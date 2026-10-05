import Foundation

// MARK: - El contrato con el bridge

/// Lo que `galeno-whatsapp` imprime y la app reconoce.
///
/// `pair` y `status` a secas se entienden por su texto, que está en español. La vista de salud
/// usa `status --json` (desde la 0.3.0) y `chats --json`. Todo lo que depende de esos textos vive
/// aquí, en un solo lugar y con pruebas, para que un cambio en el bridge se note enseguida.
nonisolated enum BridgeText {
    /// `status`: "Vinculado como 573001234567." / "Sin vincular. Corre: galeno-whatsapp pair"
    static let linkedPrefix = "Vinculado como "
    static let notLinked = "Sin vincular"
    /// `pair`: éxito, y el caso en que ya había sesión (sale con 0 sin QR).
    static let pairSucceeded = "Vinculado correctamente."
    static let pairAlreadyLinked = "Ya hay una sesión vinculada"
}

nonisolated enum WhatsAppLinkState: Equatable, Sendable {
    case linked(number: String)
    case notLinked
}

nonisolated enum WhatsAppPairEvent: Equatable, Sendable {
    /// Un QR nuevo (PNG completo). Rota cada ~60 s.
    case qr(Data)
    case succeeded
    /// Con el final del mensaje del bridge, para quien quiera el detalle.
    case failed(String)
}

nonisolated struct ChatCounts: Equatable, Sendable {
    var total: Int
    var groups: Int
}

/// `status --json`: lo que la vista de salud sabe de la sesión de WhatsApp.
nonisolated struct WhatsAppStatus: Equatable, Sendable {
    var isLinked: Bool
    var number: String?
    /// Cuándo vinculó WhatsApp este dispositivo. `nil` si el bridge no lo pudo leer: no se inventa.
    var linkedAt: Date?
    /// La versión del bridge que contestó.
    var bridgeVersion: String
}

/// ¿Está `sync` (el servicio de fondo) corriendo? Sale de `launchctl print`.
nonisolated enum WhatsAppSyncState: Equatable, Sendable {
    case running
    /// El LaunchAgent está cargado pero el proceso no corre ahora.
    case stopped
    /// No hay LaunchAgent: nunca se instaló, o se quitó.
    case notInstalled
}

/// Cuándo avisar de que la sesión de WhatsApp puede rotar. El «~20 días» es la estimación de la guía de
/// construcción, no un dato que WhatsApp publique: el aviso lo dice con «puede». Se avisa con un margen.
nonisolated enum WhatsAppSession {
    static let estimatedRotationDays = 20
    static let warnAfterDays = 18

    /// Días enteros desde que se vinculó, o `nil` si no se sabe.
    static func ageInDays(linkedAt: Date?, now: Date = Date()) -> Int? {
        guard let linkedAt else { return nil }
        return max(0, Calendar(identifier: .gregorian).dateComponents([.day], from: linkedAt, to: now).day ?? 0)
    }

    static func shouldRelink(linkedAt: Date?, now: Date = Date()) -> Bool {
        (ageInDays(linkedAt: linkedAt, now: now) ?? 0) >= warnAfterDays
    }
}

nonisolated enum WhatsAppBridgeError: Error, Equatable, Sendable {
    case bridgeMissing
    case installFailed(String)
    case unexpectedOutput(String)
    case launchdFailed(String)
}

/// Vincula WhatsApp y cuenta lo que el bridge sincronizó. Las pruebas lo
/// reemplazan por uno falso. **No hay nada de envío**: el bridge no lo tiene.
nonisolated protocol WhatsAppLinking: Sendable {
    /// Deja el bridge instalado en su ruta estable y listo para correr.
    func prepare() async throws
    func linkState() async throws -> WhatsAppLinkState
    /// Lanza `pair` y entrega los QR conforme rotan. Cancelar la tarea que lo
    /// consume (o dejar de iterar) detiene el proceso.
    func pair() -> AsyncStream<WhatsAppPairEvent>
    /// `install-launchd`: deja `sync` corriendo y que arranque con la sesión.
    /// Idempotente: se puede correr de nuevo.
    func installLaunchd() async throws
    func chatCounts() async -> ChatCounts?
    /// `status --json`. `nil` si el bridge no contestó o su salida no se entendió.
    func status() async -> WhatsAppStatus?
    /// ¿Corre `sync`? (`launchctl print`).
    func syncState() async -> WhatsAppSyncState
    /// Cierra la sesión: detiene `sync`, le avisa a WhatsApp (`unlink`) y deja el Mac sin vincular, listo para
    /// un `pair` nuevo. **No borra** el historial ya sincronizado.
    func unlink() async throws
}

extension WhatsAppLinking {
    func status() async -> WhatsAppStatus? { nil }
    func syncState() async -> WhatsAppSyncState { .notInstalled }
    func unlink() async throws { throw WhatsAppBridgeError.unexpectedOutput("unlink no disponible") }
}

// MARK: - El binario

/// Dónde está el bridge empaquetado y dónde vive la copia que se usa.
nonisolated enum BridgeLocation {
    static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Galeno", isDirectory: true)
    }

    /// La copia que corre de verdad. `install-launchd` escribe en el plist la ruta del
    /// ejecutable que lo corre: dentro de `Galeno.app` (que se mueve y se actualiza) o de
    /// DerivedData (que se borra) se rompería. Aquí no.
    static var installedBinary: URL {
        supportDirectory.appendingPathComponent("bin/galeno-whatsapp")
    }

    /// El directorio de datos del bridge (`cli.go`): sesión, historial y el PNG del QR.
    static var stateDirectory: URL {
        supportDirectory.appendingPathComponent("whatsapp", isDirectory: true)
    }

    static let qrFilename = "pair-qr.png"

    /// El binario que viene con la app. En Debug, `-galeno-bridge-path <ruta>` o
    /// `GALENO_BRIDGE_PATH` lo reemplazan para probar sin empaquetar.
    static func packagedBinary(
        bundle: Bundle = .main,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        #if DEBUG
        if let flag = arguments.firstIndex(of: "-galeno-bridge-path"), arguments.indices.contains(flag + 1) {
            return URL(fileURLWithPath: arguments[flag + 1])
        }
        if let path = environment["GALENO_BRIDGE_PATH"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        #endif
        return bundle.url(forResource: "galeno-whatsapp", withExtension: nil)
    }
}

/// Copia el bridge a su ruta estable, y lo vuelve a copiar si cambió de versión.
nonisolated struct BridgeInstaller: Sendable {
    var source: URL?
    var destination: URL = BridgeLocation.installedBinary
    var runner: any CommandRunning = ProcessRunner()

    func ensureInstalled() async throws {
        let installedVersion = await version(of: destination.path)

        guard let source else {
            // Sin binario empaquetado, sirve el que ya estaba si funciona.
            if installedVersion != nil { return }
            throw WhatsAppBridgeError.bridgeMissing
        }
        let packagedVersion = await version(of: source.path)
        if let installedVersion, installedVersion == packagedVersion { return }

        do {
            let directory = destination.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // Se copia a un archivo temporal y se reemplaza: un `sync` que ya corra con la
            // copia vieja sigue con ella, y nunca queda un binario a medias.
            let temporary = directory.appendingPathComponent(".galeno-whatsapp-\(UUID().uuidString)")
            try FileManager.default.copyItem(at: source, to: temporary)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temporary.path)
            // La copia hereda la marca de cuarentena de una app recién descargada, y fuera del paquete
            // macOS puede negarse a ejecutarla aunque el usuario ya haya aprobado Galeno. Es nuestro
            // propio binario, el que venía dentro de la app: se le quita solo a esta copia.
            removexattr(temporary.path, "com.apple.quarantine", 0)
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: destination)
            }
        } catch {
            throw WhatsAppBridgeError.installFailed(error.localizedDescription)
        }
    }

    /// `galeno-whatsapp version` imprime solo la versión ("0.2.0").
    private func version(of path: String) async -> String? {
        guard FileManager.default.isExecutableFile(atPath: path),
            let result = await runner.run(path, arguments: ["version"], timeout: 10),
            result.status == 0
        else { return nil }
        let text = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

// MARK: - El bridge real

nonisolated struct WhatsAppBridge: WhatsAppLinking {
    var installer: BridgeInstaller
    var runner: any CommandRunning = ProcessRunner()
    var stateDirectory: URL = BridgeLocation.stateDirectory
    var pollInterval: Duration = .milliseconds(700)
    /// El bridge corta `pair` a los 3 minutos; esto es el tope propio de la app.
    var pairTimeout: TimeInterval = 200

    var binaryPath: String { installer.destination.path }

    static func live() -> WhatsAppBridge {
        WhatsAppBridge(installer: BridgeInstaller(source: BridgeLocation.packagedBinary()))
    }

    func prepare() async throws {
        try await installer.ensureInstalled()
    }

    func linkState() async throws -> WhatsAppLinkState {
        let result = await runCapturing(["status"], timeout: 15)
        guard let result, result.status == 0 else {
            throw WhatsAppBridgeError.unexpectedOutput(result?.output ?? "")
        }
        return try Self.parseLinkState(result.output)
    }

    func pair() -> AsyncStream<WhatsAppPairEvent> {
        let qrURL = stateDirectory.appendingPathComponent(BridgeLocation.qrFilename)
        let binary = binaryPath
        let interval = pollInterval
        let timeout = pairTimeout

        return AsyncStream { continuation in
            let process = ManagedProcess(executable: binary, arguments: ["pair"])
            do { try process.start() } catch {
                continuation.yield(.failed("no se pudo lanzar el bridge"))
                continuation.finish()
                return
            }

            let task = Task {
                // El QR se lee del PNG que el bridge reescribe cada ~60 s (no hay evento).
                let poller = Task {
                    var last: Data?
                    while !Task.isCancelled {
                        if let data = try? Data(contentsOf: qrURL), Self.isCompletePNG(data), data != last {
                            last = data
                            continuation.yield(.qr(data))
                        }
                        try? await Task.sleep(for: interval)
                    }
                }
                let result = await process.wait(timeout: timeout)
                poller.cancel()
                continuation.yield(Self.pairOutcome(result))
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
                process.stop()
            }
        }
    }

    func installLaunchd() async throws {
        guard let result = await runCapturing(["install-launchd"], timeout: 30), result.status == 0 else {
            throw WhatsAppBridgeError.launchdFailed("launchctl no pudo activarlo")
        }
    }

    func status() async -> WhatsAppStatus? {
        // Solo stdout: stderr lleva los logs y rompería el JSON.
        guard let result = await runner.run(binaryPath, arguments: ["status", "--json"], timeout: 15),
            result.status == 0
        else { return nil }
        return Self.parseStatus(jsonOutput: result.output)
    }

    func syncState() async -> WhatsAppSyncState {
        let target = "gui/\(getuid())/\(Self.launchAgentLabel)"
        guard let result = await runner.run("/bin/launchctl", arguments: ["print", target], timeout: 10) else {
            return .notInstalled
        }
        return Self.parseSyncState(launchctlOutput: result.output, exitStatus: result.status)
    }

    func unlink() async throws {
        // `sync` y `unlink` usan la misma sesión: con los dos conectados WhatsApp expulsa a uno. Se detiene
        // `sync` primero (si no estaba, `bootout` falla y no importa); quien vuelva a vincular lo reinstala.
        _ = await runner.run(
            "/bin/launchctl", arguments: ["bootout", "gui/\(getuid())/\(Self.launchAgentLabel)"], timeout: 15)
        guard let result = await runCapturing(["unlink"], timeout: 45), result.status == 0 else {
            throw WhatsAppBridgeError.unexpectedOutput("no se pudo cerrar la sesión")
        }
    }

    /// El LaunchAgent de `launchd.go` (`launchAgentLabel`).
    static let launchAgentLabel = "com.galeno.whatsapp-bridge"

    func chatCounts() async -> ChatCounts? {
        // Solo stdout: stderr lleva los logs y rompería el JSON.
        guard let result = await runner.run(binaryPath, arguments: ["chats", "--json"], timeout: 30),
            result.status == 0
        else { return nil }
        return Self.parseChatCounts(jsonOutput: result.output)
    }

    // MARK: Lectura de la salida del bridge

    static func parseLinkState(_ output: String) throws -> WhatsAppLinkState {
        let lines = output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        if let linked = lines.first(where: { $0.hasPrefix(BridgeText.linkedPrefix) }) {
            let number = linked.dropFirst(BridgeText.linkedPrefix.count)
                .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            return .linked(number: number)
        }
        if lines.contains(where: { $0.hasPrefix(BridgeText.notLinked) }) { return .notLinked }
        throw WhatsAppBridgeError.unexpectedOutput(lines.suffix(2).joined(separator: " "))
    }

    /// El resultado final de `pair`. Sale con 0 tanto al vincular como si ya había
    /// sesión, y con 1 si falla o se agota el tiempo.
    static func pairOutcome(_ result: ManagedProcess.Result) -> WhatsAppPairEvent {
        let output = result.output
        if result.succeeded,
            output.contains(BridgeText.pairSucceeded) || output.contains(BridgeText.pairAlreadyLinked)
        {
            return .succeeded
        }
        let detail = output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .suffix(2).joined(separator: " ")
        return .failed(result.wasStopped ? "se agotó el tiempo" : detail)
    }

    /// `{"linked":true,"number":"573001234567","linked_at":1760000000,"version":"0.3.0"}`. Sin `version` no se
    /// da por entendido: sería otro programa.
    static func parseStatus(jsonOutput: String) -> WhatsAppStatus? {
        struct Report: Decodable {
            var linked: Bool
            var number: String?
            var linked_at: Double?
            var version: String
        }
        guard let data = jsonOutput.data(using: .utf8),
            let report = try? JSONDecoder().decode(Report.self, from: data)
        else { return nil }
        return WhatsAppStatus(
            isLinked: report.linked,
            number: report.number,
            linkedAt: report.linked_at.flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil },
            bridgeVersion: report.version)
    }

    /// `launchctl print gui/<uid>/<label>`: sale con 0 y `state = running` si corre; con 0 y otro estado, cargado
    /// pero parado; con otro código, no existe.
    static func parseSyncState(launchctlOutput: String, exitStatus: Int32) -> WhatsAppSyncState {
        guard exitStatus == 0 else { return .notInstalled }
        let running = launchctlOutput.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .contains { $0 == "state = running" }
        return running ? .running : .stopped
    }

    static func parseChatCounts(jsonOutput: String) -> ChatCounts? {
        struct Chat: Decodable { var is_group: Bool? }
        guard let data = jsonOutput.data(using: .utf8),
            let chats = try? JSONDecoder().decode([Chat].self, from: data)
        else { return nil }
        return ChatCounts(total: chats.count, groups: chats.filter { $0.is_group == true }.count)
    }

    /// Un PNG entero: firma al principio y el trozo IEND al final. El bridge reescribe el
    /// archivo sin atomicidad, así que una lectura puede pillarlo a medias.
    static func isCompletePNG(_ data: Data) -> Bool {
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        let end: [UInt8] = [0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82]
        return data.count > signature.count + end.count
            && data.prefix(signature.count).elementsEqual(signature)
            && data.suffix(end.count).elementsEqual(end)
    }

    // MARK: Interno

    /// Corre un subcomando y devuelve stdout y stderr juntos (para poder explicar un fallo).
    private func runCapturing(_ arguments: [String], timeout: TimeInterval) async -> ManagedProcess.Result? {
        let process = ManagedProcess(executable: binaryPath, arguments: arguments)
        do { try process.start() } catch { return nil }
        let result = await process.wait(timeout: timeout)
        return result.wasStopped ? nil : result
    }
}
