import Foundation
import GalenoCore
import OSLog

// MARK: - El contrato con el bridge

/// Lo que `galeno-whatsapp` imprime y la app reconoce.
///
/// `pair` y `status` a secas se entienden por su texto, que está en español. La vista de salud
/// usa `status --json` (desde la 0.3.0), `chats --json` y `outbox --json` (desde la 0.4.0). Todo lo que depende de esos textos vive
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

/// La bandeja de salida (`outbox --json`, bridge 0.4.0): cuánto se envió hoy, los topes y si está en pausa.
/// No trae el texto de ningún mensaje.
nonisolated struct WhatsAppOutbox: Equatable, Sendable {
    /// Los topes diarios. Los `max…` son el techo que el bridge lleva en su código: la app deja bajar un tope,
    /// nunca subirlo por encima de eso (y si lo intentara, el bridge lo ignora).
    struct Limits: Equatable, Sendable {
        var dailyTotal: Int
        var dailyNewChats: Int
        var dailyGroups: Int
        var maxDailyTotal: Int
        var maxDailyNewChats: Int
        var maxDailyGroups: Int
    }

    var isPaused: Bool
    var limits: Limits
    /// Lo que ya salió hoy y lo que está en cola para hoy: los dos cuentan para los topes.
    var sentToday: Int
    var pendingToday: Int
    var newChatsToday: Int
    var groupsToday: Int
    /// Todo lo que espera en la bandeja, sea para hoy o no.
    var pendingTotal: Int

    /// Lo que cuenta contra el tope total de hoy.
    var usedToday: Int { sentToday + pendingToday }
}

/// Lo que pasó al poner al día el bridge instalado cuando la app arranca (`WhatsAppBridge.refreshAfterAppUpdate`).
nonisolated enum BridgeRefresh: Equatable, Sendable {
    /// No hay copia instalada: WhatsApp nunca se usó en este Mac. No se toca nada.
    case notInstalled
    /// La copia ya es la que trae la app.
    case upToDate
    /// La copia se reemplazó por la de la app.
    case updated(sync: SyncRestart)
    /// No se pudo: la app no trae un bridge que conteste, o la copia no se dejó reemplazar. Queda lo que había.
    case failed

    enum SyncRestart: Equatable, Sendable {
        /// El LaunchAgent no estaba cargado: no hay servicio que reiniciar.
        case notLoaded
        case restarted
        /// `install-launchd` no lo consiguió. La vista de salud lo enseña como lo encuentre.
        case failed
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
    /// `uninstall-launchd`: quita el servicio de fondo de este número. **No toca** la sesión ni el historial.
    func uninstallService() async throws
    /// El estado de la bandeja de salida. `nil` si el bridge no contestó o es anterior a la 0.4.0.
    func outbox() async -> WhatsAppOutbox?
    /// «Pausar envíos»: mientras esté en pausa no sale nada, y lo que estaba en cola se cancela.
    func setSendingPaused(_ paused: Bool) async throws
    /// Baja (o devuelve a su valor) los topes diarios. Nunca por encima del techo del bridge.
    func setSendLimits(dailyTotal: Int, dailyNewChats: Int, dailyGroups: Int) async throws
}

extension WhatsAppLinking {
    func uninstallService() async throws {}
    func status() async -> WhatsAppStatus? { nil }
    func syncState() async -> WhatsAppSyncState { .notInstalled }
    func unlink() async throws { throw WhatsAppBridgeError.unexpectedOutput("unlink no disponible") }
    func outbox() async -> WhatsAppOutbox? { nil }
    func setSendingPaused(_ paused: Bool) async throws {
        throw WhatsAppBridgeError.unexpectedOutput("pausa no disponible")
    }
    func setSendLimits(dailyTotal: Int, dailyNewChats: Int, dailyGroups: Int) async throws {
        throw WhatsAppBridgeError.unexpectedOutput("límites no disponibles")
    }
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

    /// El de un número extra (`--account <id>`): `whatsapp/cuentas/<id>/`, aparte del de siempre (`stateDirectoryPath`).
    static func stateDirectory(account: String?) -> URL {
        guard let account else { return stateDirectory }
        return stateDirectory.appendingPathComponent("cuentas", isDirectory: true)
            .appendingPathComponent(account, isDirectory: true)
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

    /// ¿Hay algo en la ruta estable? Sin copia, WhatsApp nunca se instaló en este Mac.
    var hasInstalledCopy: Bool { FileManager.default.fileExists(atPath: destination.path) }

    /// La versión de la copia instalada. `nil` si no hay o no contesta.
    func installedVersion() async -> String? { await version(of: destination.path) }

    /// La versión del bridge que trae la app. `nil` si no trae o no contesta.
    func packagedVersion() async -> String? {
        guard let source else { return nil }
        return await version(of: source.path)
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
    /// Cuánto se espera antes de volver a intentar `install-launchd` al reiniciar `sync`.
    var syncRestartRetryDelay: Duration = .seconds(2)
    /// De qué número habla: `nil` es el de siempre; un identificador es un número extra (`--account`, `AccountID`).
    var account: String?

    var binaryPath: String { installer.destination.path }

    static func live(account: String? = nil) -> WhatsAppBridge {
        WhatsAppBridge(
            installer: BridgeInstaller(source: BridgeLocation.packagedBinary()),
            stateDirectory: BridgeLocation.stateDirectory(account: account), account: account)
    }

    /// Los argumentos de un subcomando, con la cuenta si es un número extra. El bridge la quita antes de leer los suyos.
    private func arguments(_ base: [String]) -> [String] {
        guard let account else { return base }
        return base + ["--account", account]
    }

    /// El servicio de fondo de este número (`launchd.go`, `launchAgentLabelFor`).
    var serviceLabel: String {
        guard let account else { return Self.launchAgentLabel }
        return Self.launchAgentLabel + "." + account
    }

    func prepare() async throws {
        try await installer.ensureInstalled()
    }

    /// Al arrancar la app: si la copia instalada no es de la versión que trae la app, se reemplaza y, si `sync`
    /// estaba cargado en launchd, se reinicia para que corra el binario nuevo. Es como le llega un parche del
    /// bridge a quien ya tiene WhatsApp vinculado, sin esperar a que abra Salud (`docs/03` §4f, capa 2).
    ///
    /// Sin copia instalada no hace nada: no instala ni vincula. Nunca toca la sesión ni `messages.db`: solo
    /// corre `version` e `install-launchd`. No lanza errores; lo que quede mal lo sigue diagnosticando Salud.
    ///
    /// `extraAccounts`: los otros números de la instalación (`--account`). Cada uno tiene su propio servicio, y todos
    /// los que estaban cargados se reinician con el binario nuevo (si no, quedarían corriendo el viejo).
    func refreshAfterAppUpdate(extraAccounts: [String] = []) async -> BridgeRefresh {
        guard installer.hasInstalledCopy else { return .notInstalled }
        // Sin un bridge empaquetado que conteste no hay con qué comparar: se deja la copia que había.
        guard let packaged = await installer.packagedVersion() else { return .failed }
        if await installer.installedVersion() == packaged { return .upToDate }

        // Se mira antes de tocar nada: solo se reinicia un servicio que ya estaba cargado.
        let numbers: [WhatsAppBridge] = [self] + extraAccounts.map { number in
            var other = self
            other.account = number
            other.stateDirectory = BridgeLocation.stateDirectory(account: number)
            return other
        }
        var loaded: [WhatsAppBridge] = []
        for number in numbers where await number.syncState() != .notInstalled { loaded.append(number) }
        do { try await installer.ensureInstalled() } catch { return .failed }
        guard !loaded.isEmpty else { return .updated(sync: .notLoaded) }
        var allRestarted = true
        for number in loaded where !(await number.restartSync()) { allRestarted = false }
        return .updated(sync: allRestarted ? .restarted : .failed)
    }

    /// `install-launchd` desactiva el servicio y lo vuelve a activar, ya con la copia nueva. Activarlo justo después
    /// de desactivarlo puede fallar si el proceso viejo aún no terminó, y un fallo dejaría `sync` sin cargar: se reintenta.
    func restartSync() async -> Bool {
        for attempt in 0..<3 {
            if attempt > 0 { try? await Task.sleep(for: syncRestartRetryDelay) }
            if (try? await installLaunchd()) != nil { return true }
        }
        return false
    }

    /// Falso cuando la app es la anfitriona de las pruebas: tocaría la copia y el servicio reales.
    static func refreshesAtLaunch(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment["XCTestConfigurationFilePath"] == nil
    }

    private static let refreshLog = Logger(subsystem: "com.galeno.Galeno", category: "bridge")

    /// Lanza `refreshAfterAppUpdate` en segundo plano, sin esperar ni avisar.
    static func refreshAtLaunch() {
        guard refreshesAtLaunch() else { return }
        Task.detached(priority: .utility) {
            // Los demás números de WhatsApp de la instalación (si los hay): cada uno con su servicio.
            let installation = (try? InstallationStore().load()) ?? nil
            let extras = (installation?.connections(for: .whatsapp) ?? []).compactMap(\.accountID)
            let outcome = await WhatsAppBridge.live().refreshAfterAppUpdate(extraAccounts: extras)
            refreshLog.info("bridge al arrancar: \(String(describing: outcome), privacy: .public)")
        }
    }

    func linkState() async throws -> WhatsAppLinkState {
        let result = await runCapturing(arguments(["status"]), timeout: 15)
        guard let result, result.status == 0 else {
            throw WhatsAppBridgeError.unexpectedOutput(result?.output ?? "")
        }
        return try Self.parseLinkState(result.output)
    }

    func pair() -> AsyncStream<WhatsAppPairEvent> {
        let qrURL = stateDirectory.appendingPathComponent(BridgeLocation.qrFilename)
        let binary = binaryPath
        let pairArguments = arguments(["pair"])
        let interval = pollInterval
        let timeout = pairTimeout

        return AsyncStream { continuation in
            let process = ManagedProcess(executable: binary, arguments: pairArguments)
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
        guard let result = await runCapturing(arguments(["install-launchd"]), timeout: 30), result.status == 0 else {
            throw WhatsAppBridgeError.launchdFailed("launchctl no pudo activarlo")
        }
    }

    func uninstallService() async throws {
        guard let result = await runCapturing(arguments(["uninstall-launchd"]), timeout: 30), result.status == 0 else {
            throw WhatsAppBridgeError.launchdFailed("no se pudo quitar el servicio")
        }
    }

    func status() async -> WhatsAppStatus? {
        // Solo stdout: stderr lleva los logs y rompería el JSON.
        guard let result = await runner.run(binaryPath, arguments: arguments(["status", "--json"]), timeout: 15),
            result.status == 0
        else { return nil }
        return Self.parseStatus(jsonOutput: result.output)
    }

    func syncState() async -> WhatsAppSyncState {
        let target = "gui/\(getuid())/\(serviceLabel)"
        guard let result = await runner.run("/bin/launchctl", arguments: ["print", target], timeout: 10) else {
            return .notInstalled
        }
        return Self.parseSyncState(launchctlOutput: result.output, exitStatus: result.status)
    }

    func unlink() async throws {
        // `sync` y `unlink` usan la misma sesión: con los dos conectados WhatsApp expulsa a uno. Se detiene
        // `sync` primero (si no estaba, `bootout` falla y no importa); quien vuelva a vincular lo reinstala.
        _ = await runner.run(
            "/bin/launchctl", arguments: ["bootout", "gui/\(getuid())/\(serviceLabel)"], timeout: 15)
        guard let result = await runCapturing(arguments(["unlink"]), timeout: 45), result.status == 0 else {
            throw WhatsAppBridgeError.unexpectedOutput("no se pudo cerrar la sesión")
        }
    }

    // MARK: La bandeja de salida

    /// Los dos archivos que el bridge mira en su directorio de estado (`outbox_guards.go`). Los escribe la app;
    /// el agente no puede: solo escribe en `memoria/` de su carpeta.
    static let pauseFilename = "send-paused"
    static let limitsFilename = "send-limits.json"

    func outbox() async -> WhatsAppOutbox? {
        // Solo stdout: stderr lleva los logs y rompería el JSON.
        guard let result = await runner.run(binaryPath, arguments: arguments(["outbox", "--json"]), timeout: 15),
            result.status == 0
        else { return nil }
        return Self.parseOutbox(jsonOutput: result.output)
    }

    func setSendingPaused(_ paused: Bool) async throws {
        let file = stateDirectory.appendingPathComponent(Self.pauseFilename)
        do {
            if paused {
                try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
                try Data().write(to: file, options: .atomic)
            } else if FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.removeItem(at: file)
            }
        } catch {
            throw WhatsAppBridgeError.unexpectedOutput("no se pudo \(paused ? "pausar" : "reanudar") los envíos")
        }
    }

    func setSendLimits(dailyTotal: Int, dailyNewChats: Int, dailyGroups: Int) async throws {
        // Los nombres son los de `send-limits.json` en el bridge.
        let limits = ["daily_total": max(0, dailyTotal), "daily_new_chats": max(0, dailyNewChats),
            "daily_groups": max(0, dailyGroups)]
        do {
            try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: limits, options: [.sortedKeys])
            try data.write(to: stateDirectory.appendingPathComponent(Self.limitsFilename), options: .atomic)
        } catch {
            throw WhatsAppBridgeError.unexpectedOutput("no se pudieron guardar los límites")
        }
    }

    /// El LaunchAgent de `launchd.go` (`launchAgentLabel`).
    static let launchAgentLabel = "com.galeno.whatsapp-bridge"

    func chatCounts() async -> ChatCounts? {
        // Solo stdout: stderr lleva los logs y rompería el JSON.
        guard let result = await runner.run(binaryPath, arguments: arguments(["chats", "--json"]), timeout: 30),
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

    /// `{"paused":false,"limits":{…},"today":{"sent":12,"pending":3,"new_chats":7,"groups":2},"pending_total":3,…}`.
    /// Sin `limits` o sin `today` no se da por entendido: sería otro programa o un bridge viejo.
    static func parseOutbox(jsonOutput: String) -> WhatsAppOutbox? {
        struct Report: Decodable {
            struct Limits: Decodable {
                var daily_total: Int
                var daily_new_chats: Int
                var daily_groups: Int
                var max_daily_total: Int
                var max_daily_new_chats: Int
                var max_daily_groups: Int
            }
            struct Today: Decodable {
                var sent: Int
                var pending: Int
                var new_chats: Int
                var groups: Int
            }
            var paused: Bool
            var limits: Limits
            var today: Today
            var pending_total: Int
        }
        guard let data = jsonOutput.data(using: .utf8),
            let report = try? JSONDecoder().decode(Report.self, from: data)
        else { return nil }
        return WhatsAppOutbox(
            isPaused: report.paused,
            limits: WhatsAppOutbox.Limits(
                dailyTotal: report.limits.daily_total, dailyNewChats: report.limits.daily_new_chats,
                dailyGroups: report.limits.daily_groups, maxDailyTotal: report.limits.max_daily_total,
                maxDailyNewChats: report.limits.max_daily_new_chats, maxDailyGroups: report.limits.max_daily_groups),
            sentToday: report.today.sent, pendingToday: report.today.pending,
            newChatsToday: report.today.new_chats, groupsToday: report.today.groups,
            pendingTotal: report.pending_total)
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
