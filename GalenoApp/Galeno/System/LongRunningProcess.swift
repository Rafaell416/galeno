import Darwin
import Foundation

/// Un proceso hijo que puede tardar minutos y que hay que poder cancelar:
/// `claude mcp login` (espera a que el usuario autorice en el navegador) y
/// `galeno-whatsapp pair` (espera a que escanee el QR).
///
/// `ProcessRunner` corre-hasta-terminar con un tiempo máximo y sirve para los
/// comandos cortos. Este expone además la salida **mientras corre** (`output`),
/// se detiene a pedido (`stop()`), y muere con la app (`ProcessRegistry`).
///
/// - Con `usesTerminal`, el hijo ve un terminal de verdad en stdin/stdout/stderr.
///   `claude mcp login` lo exige y se niega a correr sin él ("stdin isn't a
///   terminal"), aunque el OAuth se complete solo por el navegador.
/// - Sin él, stdout y stderr van a un archivo temporal y no a un `Pipe`: un
///   proceso que deje un nieto vivo mantendría el pipe abierto y leerlo no
///   terminaría.
nonisolated final class ManagedProcess: @unchecked Sendable {
    struct Result: Equatable, Sendable {
        var status: Int32
        var output: String
        /// `true` si lo detuvimos nosotros (`stop()`, tiempo máximo o cancelación)
        /// y no terminó por su cuenta.
        var wasStopped: Bool

        /// Terminó solo y con éxito.
        var succeeded: Bool { status == 0 && !wasStopped }
    }

    private let process = Process()
    /// Se señala cuando el proceso termina. Se usa el `terminationHandler` y no
    /// `waitUntilExit()`: éste gira el run loop del hilo desde el que se espera, y
    /// `Process` entrega la terminación por el del hilo que lo lanzó. Si son hilos
    /// distintos (aquí lo son), puede no enterarse nunca de que un hijo veloz ya terminó.
    private let exited = DispatchSemaphore(value: 0)
    private let usesTerminal: Bool
    private let lock = NSLock()
    private var stopRequested = false
    private var started = false
    private var finished = false

    // Salida con terminal
    private var terminalBuffer = Data()
    private var masterFD: Int32 = -1
    private var readerDone: DispatchSemaphore?
    private var readerShouldStop = false

    // Salida sin terminal
    private var outputURL: URL?
    private var sink: FileHandle?

    private static let maxCapturedBytes = 256 * 1024

    init(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil,
        usesTerminal: Bool = false
    ) {
        self.usesTerminal = usesTerminal
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.terminationHandler = { [exited] _ in exited.signal() }
        if let environment {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }
    }

    struct LaunchError: Error, Equatable { var reason: String }

    /// Lanza el proceso. Lanza un error si no se pudo.
    func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !started else { return }

        process.standardInput = FileHandle.nullDevice
        var slaveToClose: FileHandle?

        if usesTerminal {
            guard let (master, slave) = Self.openPseudoTerminal() else {
                throw LaunchError(reason: "no se pudo abrir un terminal")
            }
            masterFD = master
            process.standardInput = slave
            process.standardOutput = slave
            process.standardError = slave
            slaveToClose = slave
        } else {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("galeno-\(UUID().uuidString).out")
            guard FileManager.default.createFile(atPath: url.path, contents: nil),
                let handle = try? FileHandle(forWritingTo: url)
            else { throw LaunchError(reason: "no se pudo crear el archivo de salida") }
            outputURL = url
            sink = handle
            process.standardOutput = handle
            // stderr va al mismo archivo: es donde los programas dicen por qué fallaron.
            process.standardError = handle
        }

        do {
            try process.run()
        } catch {
            // Ya se tiene el candado: no se puede volver a tomar (`NSLock` no es reentrante).
            discardOutputFile()
            if masterFD >= 0 {
                close(masterFD)
                masterFD = -1
            }
            throw LaunchError(reason: error.localizedDescription)
        }
        started = true
        // El hijo ya tiene su copia. Sin cerrar la nuestra, el lado maestro
        // nunca vería el final de la salida.
        try? slaveToClose?.close()
        if usesTerminal { startReadingTerminal() }
        ProcessRegistry.shared.add(self)
    }

    var isRunning: Bool { lock.withLock { started && process.isRunning } }

    /// Lo que el proceso lleva escrito hasta ahora (sin códigos de terminal).
    var output: String {
        lock.lock()
        defer { lock.unlock() }
        let data: Data
        if usesTerminal {
            data = terminalBuffer
        } else if let outputURL, let read = try? Data(contentsOf: outputURL) {
            data = read
        } else {
            data = Data()
        }
        return Self.stripTerminalCodes(String(decoding: data, as: UTF8.self))
    }

    /// Pide que termine: SIGTERM y, si sigue vivo 2 s después, SIGKILL.
    func stop() {
        let shouldSignal: Bool = lock.withLock {
            stopRequested = true
            return started && process.isRunning
        }
        guard shouldSignal else { return }
        process.terminate()
        let pid = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.isRunning else { return }
            kill(pid, SIGKILL)
        }
    }

    /// Lo mata de inmediato. Es lo que se usa al cerrar la app, cuando no hay tiempo.
    func killNow() {
        lock.withLock { stopRequested = true }
        if isRunning { kill(process.processIdentifier, SIGKILL) }
    }

    /// Espera a que termine. Si pasan `timeout` segundos, o se cancela la tarea,
    /// lo detiene. Se espera una sola vez.
    func wait(timeout: TimeInterval? = nil) async -> Result {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    var watchdog: DispatchWorkItem?
                    if let timeout {
                        let item = DispatchWorkItem { [weak self] in self?.stop() }
                        watchdog = item
                        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: item)
                    }
                    self.exited.wait()
                    watchdog?.cancel()
                    continuation.resume(returning: self.finish())
                }
            }
        } onCancel: {
            self.stop()
        }
    }

    // MARK: - Interno

    private func finish() -> Result {
        // El lector del terminal necesita un momento para vaciar lo último.
        if usesTerminal { stopReadingTerminal() }
        let text = output
        let (status, stopped): (Int32, Bool) = lock.withLock {
            finished = true
            return (process.terminationStatus, stopRequested)
        }
        cleanUpOutput()
        ProcessRegistry.shared.remove(self)
        return Result(status: status, output: text, wasStopped: stopped)
    }

    private func cleanUpOutput() {
        lock.lock()
        defer { lock.unlock() }
        discardOutputFile()
    }

    /// Cierra y borra el archivo de salida. **Hay que tener el candado.** `output` ya se
    /// leyó antes de limpiar; después queda vacío para el que pregunte tarde.
    private func discardOutputFile() {
        try? sink?.close()
        sink = nil
        if let outputURL { try? FileManager.default.removeItem(at: outputURL) }
        outputURL = nil
    }

    private func startReadingTerminal() {
        let fd = masterFD
        let done = DispatchSemaphore(value: 0)
        readerDone = done
        Thread.detachNewThread { [weak self] in
            var chunk = [UInt8](repeating: 0, count: 4096)
            while true {
                guard let self, !self.lock.withLock({ self.readerShouldStop }) else { break }
                var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                // Con tiempo máximo corto para poder notar `readerShouldStop`.
                let ready = poll(&descriptor, 1, 200)
                if ready < 0 { break }
                if ready == 0 { continue }
                let count = read(fd, &chunk, chunk.count)
                if count <= 0 { break }  // el hijo cerró el terminal (EIO) o hubo un error
                self.lock.withLock {
                    if self.terminalBuffer.count < Self.maxCapturedBytes {
                        self.terminalBuffer.append(contentsOf: chunk[0..<count])
                    }
                }
            }
            done.signal()
        }
    }

    private func stopReadingTerminal() {
        // Si el hijo ya murió, el lector termina solo en cuanto vacía lo pendiente;
        // se le da un instante antes de pedirle que pare.
        let finishedOnItsOwn = readerDone?.wait(timeout: .now() + 0.4) == .success
        if !finishedOnItsOwn {
            lock.withLock { readerShouldStop = true }
            _ = readerDone?.wait(timeout: .now() + 1)
        }
        lock.withLock {
            if masterFD >= 0 {
                close(masterFD)
                masterFD = -1
            }
        }
    }

    /// Un par maestro/esclavo de pseudo-terminal. El maestro lo lee la app; el
    /// esclavo es el stdin/stdout/stderr del hijo.
    private static func openPseudoTerminal() -> (Int32, FileHandle)? {
        let master = posix_openpt(O_RDWR | O_NOCTTY)
        guard master >= 0 else { return nil }
        guard grantpt(master) == 0, unlockpt(master) == 0, let name = ptsname(master) else {
            close(master)
            return nil
        }
        let slave = open(name, O_RDWR | O_NOCTTY)
        guard slave >= 0 else {
            close(master)
            return nil
        }
        return (master, FileHandle(fileDescriptor: slave, closeOnDealloc: true))
    }

    /// Quita los códigos de escape (colores, hipervínculos OSC 8, movimiento del
    /// cursor) y los retornos de carro de lo que escribió un programa de terminal.
    static func stripTerminalCodes(_ text: String) -> String {
        var result = text
        // OSC: ESC ] … (BEL | ESC \)
        result = result.replacingOccurrences(
            of: "\u{1B}\\][^\u{07}\u{1B}]*(\u{07}|\u{1B}\\\\)", with: "", options: .regularExpression)
        // CSI: ESC [ … letra (con los parámetros privados `<`, `>`, `=` que usan los programas de pantalla completa)
        result = result.replacingOccurrences(
            of: "\u{1B}\\[[0-9;?<>=]*[A-Za-z]", with: "", options: .regularExpression)
        // Juego de caracteres (ESC ( B) y guardar/restaurar cursor o teclado (ESC 7, ESC 8, ESC =, ESC >)
        result = result.replacingOccurrences(
            of: "\u{1B}([()][A-Za-z0-9]|[78=>])", with: "", options: .regularExpression)
        return result.replacingOccurrences(of: "\r", with: "")
    }
}

/// Los procesos hijo vivos. Al cerrar la app se matan: un `pair` huérfano
/// seguiría escuchando por su cuenta hasta agotar sus 3 minutos.
///
/// No cubre un cierre brusco (`kill -9`, un fallo de la app): ahí los procesos
/// siguen hasta que terminen solos.
nonisolated final class ProcessRegistry: @unchecked Sendable {
    static let shared = ProcessRegistry()

    private let lock = NSLock()
    private var live: [ObjectIdentifier: ManagedProcess] = [:]

    var count: Int { lock.withLock { live.count } }

    func add(_ process: ManagedProcess) {
        lock.withLock { live[ObjectIdentifier(process)] = process }
    }

    func remove(_ process: ManagedProcess) {
        _ = lock.withLock { live.removeValue(forKey: ObjectIdentifier(process)) }
    }

    /// Síncrono y sin esperas: `applicationWillTerminate` tiene poco tiempo.
    func killAll() {
        let snapshot = lock.withLock { Array(live.values) }
        for process in snapshot { process.killNow() }
    }
}
