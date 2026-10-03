import Foundation

/// Lo que la pantalla 2 sabe de Claude Code (`docs/03` §3).
nonisolated enum ClaudeCodeStatus: Equatable, Sendable {
    /// Todavía no se ha mirado, o se está mirando.
    case checking
    /// Instalado. `loggedIn` es `nil` si no se pudo saber (una versión sin
    /// `claude auth status`): en ese caso no se avisa de nada.
    case found(version: String, path: String, loggedIn: Bool?)
    case notFound

    var isFound: Bool {
        if case .found = self { return true }
        return false
    }
}

/// El resultado de un comando que terminó a tiempo.
nonisolated struct CommandResult: Sendable, Equatable {
    var status: Int32
    var output: String
}

/// Lanza un comando. Es lo único del detector que toca el sistema, así que las
/// pruebas lo reemplazan por uno falso.
nonisolated protocol CommandRunning: Sendable {
    /// `nil` si no se pudo lanzar o no terminó dentro de `timeout` segundos.
    func run(_ executable: String, arguments: [String], timeout: TimeInterval) async -> CommandResult?
}

/// Busca `claude` y pregunta su versión y si hay sesión iniciada.
///
/// Una app que se abre desde Finder hereda un PATH mínimo (sin Homebrew ni
/// `~/.local/bin`), así que no sirve preguntar solo "¿está en el PATH?". Se
/// miran primero las rutas donde lo dejan los instaladores y, si no está ahí,
/// se le pregunta a un shell de login, que sí ve el PATH del usuario (npm, nvm).
///
/// Galeno nunca instala Claude Code: instalarlo es descargar y ejecutar un
/// script remoto, y eso lo hace el usuario en su terminal (`docs/03` §3).
nonisolated struct ClaudeCodeDetector: Sendable {
    var runner: any CommandRunning = ProcessRunner()
    var homeDirectory: String = NSHomeDirectory()
    var isExecutable: @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }

    /// Dónde dejan `claude` el instalador nativo, Homebrew y la instalación local.
    var knownPaths: [String] {
        [
            "\(homeDirectory)/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(homeDirectory)/.claude/local/claude",
        ]
    }

    func detect() async -> ClaudeCodeStatus {
        var tried: Set<String> = []

        // Primero las rutas conocidas: son instantáneas. El shell de login es lo
        // lento (puede cargar un `.zshrc` pesado), así que solo se le pregunta si
        // ninguna de ellas dio un `claude` que funcione.
        for path in knownPaths.filter(isExecutable) where tried.insert(path).inserted {
            if let found = await probe(path) { return found }
        }
        if let path = await pathFromLoginShell(), tried.insert(path).inserted {
            if let found = await probe(path) { return found }
        }
        return .notFound
    }

    // MARK: Pasos

    /// Versión y sesión de un `claude` concreto, o `nil` si no funciona.
    private func probe(_ path: String) async -> ClaudeCodeStatus? {
        guard let version = await version(at: path) else { return nil }
        return .found(version: version, path: path, loggedIn: await loginState(at: path))
    }

    private func pathFromLoginShell() async -> String? {
        // `-i` además de `-l`: el PATH de nvm y de npm suele ponerse en `.zshrc`.
        guard
            let result = await runner.run(
                "/bin/zsh", arguments: ["-lic", "command -v claude"], timeout: 5),
            result.status == 0
        else { return nil }
        // Un `.zshrc` puede imprimir cosas: nos quedamos con la última línea que sea una ruta.
        return result.output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { $0.hasPrefix("/") && isExecutable($0) }
    }

    /// "2.1.277 (Claude Code)" → "2.1.277".
    private func version(at path: String) async -> String? {
        guard let result = await runner.run(path, arguments: ["--version"], timeout: 10),
            result.status == 0
        else { return nil }
        return Self.parseVersion(result.output)
    }

    /// Solo se lee si hay sesión. `claude auth status` también devuelve el
    /// correo de la cuenta: ese dato no se guarda, ni se muestra, ni se registra.
    private func loginState(at path: String) async -> Bool? {
        guard let result = await runner.run(path, arguments: ["auth", "status"], timeout: 10),
            let data = result.output.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let loggedIn = json["loggedIn"] as? Bool
        else { return nil }
        return loggedIn
    }

    static func parseVersion(_ output: String) -> String? {
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = text.range(of: #"^\d+\.\d+\.\d+[0-9A-Za-z.+-]*"#, options: .regularExpression)
        else { return nil }
        return String(text[range])
    }
}

extension ClaudeCodeDetector {
    /// El detector real. En Debug, el argumento de arranque `-galeno-claude-missing`
    /// finge que `claude` no está, para ver esa pantalla en un Mac que sí lo tiene.
    static var live: ClaudeCodeDetector {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-galeno-claude-missing") {
            return ClaudeCodeDetector(runner: NothingRunner(), isExecutable: { _ in false })
        }
        #endif
        return ClaudeCodeDetector()
    }
}

#if DEBUG
    private nonisolated struct NothingRunner: CommandRunning {
        func run(_ executable: String, arguments: [String], timeout: TimeInterval) async -> CommandResult? { nil }
    }
#endif

// MARK: - Lanzar procesos

/// Corre un comando de verdad, con tiempo máximo.
///
/// La salida va a un archivo temporal y no a un `Pipe`: un `.zshrc` puede dejar
/// un proceso vivo que mantenga el pipe abierto, y leer hasta el final no
/// terminaría nunca. Con un archivo, basta con esperar a que muera el proceso.
nonisolated struct ProcessRunner: CommandRunning {
    func run(_ executable: String, arguments: [String], timeout: TimeInterval) async -> CommandResult? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: Self.runBlocking(executable, arguments, timeout))
            }
        }
    }

    private static func runBlocking(
        _ executable: String, _ arguments: [String], _ timeout: TimeInterval
    ) -> CommandResult? {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("galeno-\(UUID().uuidString).out")
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil),
            let sink = try? FileHandle(forWritingTo: outputURL)
        else { return nil }
        defer {
            try? sink.close()
            try? FileManager.default.removeItem(at: outputURL)
        }

        let job = Job()
        job.process.executableURL = URL(fileURLWithPath: executable)
        job.process.arguments = arguments
        // Un directorio neutro: así `claude` no carga el `CLAUDE.md` ni los ajustes
        // de la carpeta desde la que se haya abierto la app.
        job.process.currentDirectoryURL = FileManager.default.temporaryDirectory
        job.process.standardInput = FileHandle.nullDevice
        job.process.standardOutput = sink
        job.process.standardError = FileHandle.nullDevice

        do { try job.process.run() } catch { return nil }

        let watchdog = DispatchWorkItem { job.timeOut() }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        job.process.waitUntilExit()
        watchdog.cancel()

        guard !job.timedOut else { return nil }
        let data = (try? Data(contentsOf: outputURL)) ?? Data()
        return CommandResult(
            status: job.process.terminationStatus,
            output: String(decoding: data, as: UTF8.self))
    }

    /// El proceso y si se agotó el tiempo. Se comparte con el temporizador, que
    /// corre en otro hilo.
    private final class Job: @unchecked Sendable {
        let process = Process()
        private let lock = NSLock()
        private var expired = false

        var timedOut: Bool { lock.withLock { expired } }

        func timeOut() {
            lock.withLock { expired = true }
            // SIGKILL y no `terminate()`: un shell interactivo ignora SIGTERM.
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }
}
