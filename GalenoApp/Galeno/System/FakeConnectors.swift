#if DEBUG
import AppKit
import Foundation
import GalenoCore

/// Conectores con guion, solo en Debug (`-galeno-fake-connect`): permiten ver todas las
/// pantallas del paso 5 —éxito, dato tardío, fallo, QR que rota, sincronización— sin
/// tocar ninguna cuenta ni lanzar `claude` ni el bridge.
///
/// El guion: `fathom` falla la primera vez (tiempo agotado) y funciona al reintentar;
/// `jira` encuentra "10+" y tarda en contarlo; `notion` no lleva dato; las demás encuentran
/// un número. Con `-galeno-fake-name-clash`, `notion` y `slack` ya están ocupados por otro
/// servidor del usuario (hasta que "se borren"), para ver la pregunta de qué hacer.
nonisolated final class ScriptedMCP: MCPConnecting, @unchecked Sendable {
    private let lock = NSLock()
    private var registered: Set<String> = []
    private var connected: Set<String> = []
    private var failedOnce: Set<String> = []
    private var occupied: Set<String>
    private var connectorChecks: [String: Int] = [:]

    init(occupiedByOthers: Set<String> = []) { occupied = occupiedByOthers }

    func status(of server: String, expectingURL: String?) async -> MCPStatus {
        try? await Task.sleep(for: .milliseconds(400))
        return lock.withLock {
            if occupied.contains(server) { return .differentServer }

            return connected.contains(server) ? .connected : (registered.contains(server) ? .needsAuthentication : .notRegistered)
        }
    }

    func register(server: String, url: String, oauth: OAuthClientRegistration?) async throws {
        try? await Task.sleep(for: .milliseconds(600))
        lock.withLock {
            _ = registered.insert(server)
            // Claude Design entra con la sesión de Claude Code: queda conectado al registrarlo, sin OAuth.
            if server.hasSuffix("claude-design") { _ = connected.insert(server) }
        }
    }

    /// Guion de los conectores de Claude: los de Google Drive, Docs y Sheets no están en la cuenta (hay que
    /// añadirlos) y los demás están pero sin autorizar; cada uno queda conectado a la tercera mirada.
    func connectorStatus(_ server: String) async -> MCPStatus {
        try? await Task.sleep(for: .milliseconds(900))
        return lock.withLock {
            let checks = (connectorChecks[server] ?? 0) + 1
            connectorChecks[server] = checks
            if checks >= 3 { return .connected }
            return server.contains("Gmail") || server.contains("Calendar") ? .needsAuthentication : .notRegistered
        }
    }

    /// El conector de la cuenta de Claude: «el usuario» tarda unos segundos en pulsar Permitir.
    func authorizeConnector(_ server: String) async throws {
        try? await Task.sleep(for: .milliseconds(400))
    }

    func remove(server: String) async throws {
        try? await Task.sleep(for: .milliseconds(500))
        lock.withLock { _ = occupied.remove(server) }
    }

    func login(server: String, openAuthorization: AuthorizationOpener?) async throws {
        try? await Task.sleep(for: .seconds(2.5))
        let shouldFail = lock.withLock { server == "fathom" && failedOnce.insert(server).inserted }
        if shouldFail { throw MCPConnectError.loginTimedOut }
        lock.withLock { _ = connected.insert(server) }
    }

    func countItems(server: String, noun: String) async -> ItemCount? {
        switch server {
        case "jira":
            try? await Task.sleep(for: .seconds(9))  // llega después de la transición
            return ItemCount(value: 10, isPartial: true)
        case "notion":
            return nil  // sin dato: solo el éxito
        default:
            try? await Task.sleep(for: .seconds(2))
            return ItemCount(value: server == "slack" ? 12 : 7, isPartial: false)
        }
    }
}

nonisolated final class ScriptedWhatsApp: WhatsAppLinking, @unchecked Sendable {
    private let lock = NSLock()
    private var reads = 0

    func prepare() async throws { try? await Task.sleep(for: .milliseconds(500)) }
    func linkState() async throws -> WhatsAppLinkState {
        try? await Task.sleep(for: .milliseconds(500))
        return .notLinked
    }

    func pair() -> AsyncStream<WhatsAppPairEvent> {
        AsyncStream { continuation in
            let task = Task {
                try? await Task.sleep(for: .seconds(1))
                for seed in 1...3 {
                    continuation.yield(.qr(Self.fakeQR(seed: seed)))
                    try? await Task.sleep(for: .seconds(3))
                }
                continuation.yield(.succeeded)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func installLaunchd() async throws { try? await Task.sleep(for: .seconds(1)) }

    func chatCounts() async -> ChatCounts? {
        let count = lock.withLock { () -> Int in reads += 1; return reads }
        let total = [0, 8, 24, 40, 40, 40, 40, 40][min(count - 1, 7)]
        return ChatCounts(total: total, groups: total / 4)
    }

    /// Un PNG de cuadros que cambia con `seed`: no es un QR de verdad.
    static func fakeQR(seed: Int) -> Data {
        let image = NSImage(size: NSSize(width: 160, height: 160), flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            NSColor.black.setFill()
            for row in 0..<16 {
                for column in 0..<16 where (row * 7 + column * 13 + seed * 5) % 3 == 0 {
                    NSRect(x: column * 10, y: row * 10, width: 10, height: 10).fill()
                }
            }
            return true
        }
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:])
        else { return Data() }
        return png
    }
}

/// Slack con guion: acepta cualquier token que empiece por `xoxe.xoxp-`, rechaza el resto
/// (para ver la pantalla de "token rechazado") y "crea" una app con un `client_id` falso.
nonisolated struct ScriptedSlackSetup: SlackAppSetting {
    func validate(token: OAuthSecret, agentName: String) async throws {
        try? await Task.sleep(for: .milliseconds(700))
        let accepted = token.withValue { $0.hasPrefix("xoxe.xoxp-") }
        if !accepted { throw SlackSetupError.tokenRejected("invalid_auth") }
    }

    func createApp(token: OAuthSecret, agentName: String) async throws -> OAuthClientRegistration {
        try? await Task.sleep(for: .milliseconds(900))
        return OAuthClientRegistration(
            clientID: "1111111111111.2222222222222", callbackPort: SlackOAuth.callbackPort,
            secret: OAuthSecret("secreto-falso-de-depuracion"), appID: "A0DEBUG0001")
    }
}

/// Las listas de la pantalla 6 con guion: unas aparecen enseguida, otras tardan, y las de Notion
/// fallan la primera vez (para ver el aviso y el reintento).
nonisolated final class ScriptedSourceLister: SourceListing, @unchecked Sendable {
    private let lock = NSLock()
    private var failedOnce: Set<Tool> = []

    func list(_ connection: ToolConnection) async -> SourceListResult {
        switch connection.tool {
        case .whatsapp:
            try? await Task.sleep(for: .milliseconds(300))
            let groups = (1...12).map {
                Source(id: "1203630\($0)@g.us", name: "Grupo de prueba \($0)", kind: .group)
            }
            return .loaded(groups + [Source(id: "5731000001@s.whatsapp.net", name: "Ana (prueba)", kind: .chat)], isPartial: false)
        case .slack:
            try? await Task.sleep(for: .seconds(2))
            return .loaded(
                ["producto", "ingenieria", "clientes", "lanzamiento", "soporte"].map {
                    Source(id: "C0\($0.count)", name: "#\($0)", kind: .channel)
                }, isPartial: false)
        case .notion:
            try? await Task.sleep(for: .seconds(3))
            let first = lock.withLock { failedOnce.insert(.notion).inserted }
            if first { return .failed("simulado") }
            return .loaded(
                [Source(id: "p1", name: "Roadmap", kind: .page), Source(id: "d1", name: "Tareas", kind: .database)],
                isPartial: true)
        default:
            try? await Task.sleep(for: .seconds(1))
            return .loaded([Source(id: "x1", name: "Ejemplo", kind: connection.tool.selectableSourceKinds.first ?? .page)], isPartial: false)
        }
    }
}

/// Abrir el agente sin abrir nada de verdad (la prueba visual no debe lanzar tu app de Claude).
@MainActor
struct ScriptedOpener: AgentOpening {
    var isClaudeAppAvailable: Bool { true }
    func openInClaudeApp(folder: URL, prompt: String?) -> Bool { true }
    func continueInClaudeApp(folder: URL) -> Bool { true }
    func claudeAppNeedsRestart(since date: Date) -> Bool { false }
    func restartClaudeAppAndOpen(folder: URL, prompt: String?, resume: Bool) async -> AgentOpenOutcome { .opened }
    func openInTerminal(folder: URL, prompt: String?, claudePath: String) -> Bool { true }
    func reveal(_ folder: URL) {}
}

/// Un Mac de mentira para el paso 2, solo con `-galeno-fake-connect`: deja ver «Falta Claude Code», «necesita
/// actualizarse» y «Falta iniciar sesión» —y lo que pasa al pulsar cada botón— sin instalar ni abrir nada.
/// Cómo arranca: `-galeno-claude-missing` (sin Claude Code), `-galeno-claude-outdated` (uno viejo),
/// `-galeno-claude-signedout` (sin sesión); sin ninguno, todo listo.
nonisolated final class ScriptedClaudeMac: CommandRunning, @unchecked Sendable {
    static let shared = ScriptedClaudeMac(arguments: ProcessInfo.processInfo.arguments)
    static let path = "/Users/demo/.local/bin/claude"

    private let lock = NSLock()
    private var version: String?
    private var loggedIn: Bool

    init(arguments: [String]) {
        if arguments.contains("-galeno-claude-missing") {
            version = nil
            loggedIn = false
        } else if arguments.contains("-galeno-claude-outdated") {
            version = "2.1.150"
            loggedIn = true
        } else {
            version = "2.1.289"
            loggedIn = !arguments.contains("-galeno-claude-signedout")
        }
    }

    var detector: ClaudeCodeDetector {
        ClaudeCodeDetector(
            runner: self, homeDirectory: "/Users/demo",
            isExecutable: { [self] in $0 == Self.path && lock.withLock { version != nil } })
    }

    func install() { lock.withLock { version = "2.1.289" } }
    func signIn() { lock.withLock { loggedIn = true } }

    func run(
        _ executable: String, arguments: [String], environment: [String: String], timeout: TimeInterval
    ) async -> CommandResult? {
        lock.withLock {
            guard executable == Self.path, let version else { return nil }
            if arguments == ["--version"] { return CommandResult(status: 0, output: "\(version) (Claude Code)") }
            if arguments == ["auth", "status"] {
                return CommandResult(status: 0, output: #"{"loggedIn": \#(loggedIn)}"#)
            }
            return nil
        }
    }
}

/// «Instalar» e «Iniciar sesión» de mentira: esperan un momento y cambian el Mac de mentira.
nonisolated struct ScriptedClaudeSetup: ClaudeCodeSettingUp {
    func install() async -> ClaudeSetupOutcome {
        try? await Task.sleep(for: .seconds(3))
        if Task.isCancelled { return .cancelled }
        ScriptedClaudeMac.shared.install()
        return .done
    }

    func signIn(claudePath: String) async -> ClaudeSetupOutcome {
        try? await Task.sleep(for: .seconds(4))
        if Task.isCancelled { return .cancelled }
        ScriptedClaudeMac.shared.signIn()
        return .done
    }
}

extension ConnectServices {
    static func scripted() -> ConnectServices {
        // Con conectores falsos, el agente se genera en una carpeta temporal: probar la
        // interfaz nunca toca tu `~/Galeno` ni tu `installation.json`.
        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("galeno-fake-\(UUID().uuidString)", isDirectory: true)
        let skills = SkillsLocation.bundled()
        return ConnectServices(
            makeMCP: { _ in
                ScriptedMCP(
                    occupiedByOthers: ProcessInfo.processInfo.arguments.contains("-galeno-fake-name-clash")
                        ? ["galeno-notion", "galeno-slack"] : [])
            }, whatsapp: ScriptedWhatsApp(), slack: ScriptedSlackSetup(),
            makeLister: { _ in ScriptedSourceLister() },
            installer: AgentInstaller(
                store: InstallationStore(directory: sandbox.appendingPathComponent("support")),
                agentsRoot: sandbox.appendingPathComponent("Galeno"),
                options: ConfigGenerator.Options(
                    skillsDirectory: skills ?? URL(fileURLWithPath: "/nonexistent/skills"),
                    whatsAppBridgePath: "/usr/bin/true")),
            opener: ScriptedOpener(), skillsDirectory: skills, claudeSetup: ScriptedClaudeSetup())
    }
}
#endif
