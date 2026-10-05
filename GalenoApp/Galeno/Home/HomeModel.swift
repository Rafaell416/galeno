import AppKit
import Combine
import Foundation
import GalenoCore

/// Dónde se abre un agente desde el home.
enum OpenTarget: String, CaseIterable, Identifiable {
    case app, terminal
    var id: String { rawValue }
}

/// Un agente tal como lo ve el home: lo que hay que leer de un vistazo y dónde está su carpeta.
struct HomeAgent: Identifiable, Equatable {
    let id: UUID
    var name: String
    var projectDescription: String
    /// Las herramientas que lee **hoy**: salen de las conexiones compartidas, así que una que se
    /// desconectó ya no aparece (`GalenoInstallation.resolvedConfig`).
    var tools: [Tool]
    var folder: URL
    /// Falso si alguien borró o movió la carpeta a mano.
    var folderExists: Bool
}

/// El home (`docs/03` §3b): la lista de agentes de la instalación y «Abrir».
///
/// **Si `installation.json` no se puede leer, no se toca ni se vuelve al wizard en silencio**: puede ser
/// lo único que recuerda los agentes. Se muestra el error y se deja reintentar.
@MainActor
final class HomeModel: ObservableObject {
    enum State: Equatable {
        /// No hay instalación o no tiene agentes: se abre el wizard.
        case empty
        case agents([HomeAgent])
        case unreadable(String)
    }

    @Published private(set) var state: State = .empty
    /// El idioma de la instalación (el del paso 1 del primer agente).
    @Published private(set) var language: Language
    /// El agente que se está abriendo (el botón gira) y los que no se pudieron abrir.
    @Published private(set) var opening: UUID?
    @Published private(set) var failed: Set<UUID> = []
    /// La última elección de dónde abrir (app de Claude o Terminal): la que sale marcada la próxima vez.
    @Published private(set) var openTarget: OpenTarget {
        didSet { defaults.set(openTarget.rawValue, forKey: Prefs.openTarget) }
    }
    /// El agente cuyo menú «Abrir en» está desplegado.
    @Published private(set) var menuOpen: UUID?

    private let store: InstallationStore
    private let defaults: UserDefaults
    let opener: any AgentOpening
    private let claudePath: String
    /// Cuánto se queda girando el botón tras abrir: hasta que otra app toma el foco (2 s como mucho).
    /// Las pruebas lo reemplazan.
    private let settle: @MainActor () async -> Void

    init(
        store: InstallationStore = InstallationStore(),
        defaults: UserDefaults = .standard,
        opener: any AgentOpening = SystemAgentOpener(),
        claudePath: String? = nil,
        settle: @escaping @MainActor () async -> Void = HomeModel.waitForFocusChange
    ) {
        self.store = store
        self.defaults = defaults
        self.opener = opener
        self.claudePath = claudePath ?? Self.findClaude()
        self.settle = settle
        language = WizardState.defaultLanguage(from: Locale.preferredLanguages)
        let stored = defaults.string(forKey: Prefs.openTarget).flatMap(OpenTarget.init(rawValue:))
        openTarget = stored ?? (opener.isClaudeAppAvailable ? .app : .terminal)
        reload()
    }

    /// Dónde abre «Abrir» a secas: la última elección. Sin la app de Claude en el Mac solo puede ser Terminal.
    var effectiveTarget: OpenTarget { opener.isClaudeAppAvailable ? openTarget : .terminal }

    /// ¿Hay algo que elegir? Sin la app de Claude no hay menú.
    var canChoose: Bool { opener.isClaudeAppAvailable }

    var agents: [HomeAgent] {
        if case .agents(let agents) = state { return agents }
        return []
    }

    func reload() {
        do {
            guard let installation = try store.load() else {
                state = .empty
                return
            }
            language = installation.language
            let rows = installation.agents.map { record -> HomeAgent in
                let config = installation.resolvedConfig(for: record.id) ?? record.config
                return HomeAgent(
                    id: record.id,
                    name: config.agentName,
                    projectDescription: config.projectDescription,
                    tools: config.connections.filter { $0.status == .connected }.map(\.tool),
                    folder: record.folder,
                    folderExists: FileManager.default.fileExists(atPath: record.folderPath))
            }
            state = rows.isEmpty ? .empty : .agents(rows)
        } catch {
            state = .unreadable(String(describing: error))
        }
    }

    /// ¿Abrir este agente en la app de Claude la va a cerrar y reabrir? Se avisa antes de elegir.
    func willRestartClaude(for agent: HomeAgent) -> Bool {
        AgentOpenPolicy.needsClaudeRestart(tools: agent.tools, folder: agent.folder, opener: opener)
    }

    /// La instalación tal como está en disco, para armar el punto de partida de un agente nuevo. `nil` si no se
    /// puede leer: ahí no se crea nada, para no trabajar sobre algo que no se vio.
    func loadInstallation() -> GalenoInstallation? {
        (try? store.load()) ?? nil
    }

    var isUnreadable: Bool {
        if case .unreadable = state { return true } else { return false }
    }

    /// El botón principal: abre donde se abrió la última vez, sin preguntar.
    func open(_ agent: HomeAgent) { open(agent, in: effectiveTarget) }

    /// La flecha del botón: despliega o cierra «Abrir en».
    func toggleMenu(_ agent: HomeAgent) {
        guard canChoose, opening == nil, agent.folderExists else { return }
        menuOpen = menuOpen == agent.id ? nil : agent.id
    }

    func closeMenu() { menuOpen = nil }

    /// Abre el agente donde se pidió y lo deja como la elección de ahí en adelante. **Vuelve a la última
    /// conversación** de la carpeta si la hay (en la app de Claude); sin primera pregunta: el usuario ya
    /// conoce a su agente.
    func open(_ agent: HomeAgent, in target: OpenTarget) {
        guard opening == nil, agent.folderExists else { return }
        menuOpen = nil
        openTarget = target
        opening = agent.id
        failed.remove(agent.id)
        Task {
            let opened = await AgentOpenPolicy.open(
                folder: agent.folder, tools: agent.tools, inApp: target == .app, prompt: nil, resume: true,
                opener: opener, claudePath: claudePath)
            if !opened { failed.insert(agent.id) }
            await settle()
            opening = nil
        }
    }

    // MARK: - Ayudas

    /// Hasta que otra app toma el foco, o 2 s: el botón no vuelve a su sitio antes de que se vea el cambio.
    static func waitForFocusChange() async {
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(100))
            if !NSApp.isActive { break }
        }
    }

    /// Dónde dejan `claude` sus instaladores. Solo lo usa el respaldo de Terminal.
    static func findClaude() -> String {
        let detector = ClaudeCodeDetector()
        return detector.knownPaths.first(where: detector.isExecutable) ?? "claude"
    }
}
