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
    /// Lo que salió mal al abrir un agente (no se pudo, o Claude no se cerró), para decirlo en su tarjeta.
    @Published private(set) var problems: [UUID: AgentOpenOutcome] = [:]
    /// La última elección de dónde abrir (app de Claude o Terminal): la que sale marcada la próxima vez.
    @Published private(set) var openTarget: OpenTarget {
        didSet { defaults.set(openTarget.rawValue, forKey: Prefs.openTarget) }
    }
    /// El agente cuyo menú «Abrir en» está desplegado.
    @Published private(set) var menuOpen: UUID?

    /// Un diálogo del home: renombrar un agente, o confirmar que se elimina (con lo que se mandaría a la Papelera).
    enum Dialog: Equatable {
        case rename(HomeAgent)
        case delete(HomeAgent, AgentRemovalPlan)

        var agent: HomeAgent {
            switch self {
            case .rename(let agent), .delete(let agent, _): agent
            }
        }
    }

    enum RenameIssue: Equatable { case empty, tooLong }

    @Published private(set) var dialog: Dialog?
    /// Mientras se guarda un nombre o se manda un agente a la Papelera.
    @Published private(set) var isWorking = false
    /// Qué salió mal en el diálogo abierto, para decirlo ahí mismo (nunca en silencio).
    @Published private(set) var dialogError: String?
    /// Un aviso tras eliminar, si algo de Claude no se pudo mandar a la Papelera.
    @Published private(set) var notice: String?
    /// El agente cuyo menú «Gestionar» está desplegado.
    @Published private(set) var manageMenu: UUID?

    private let store: InstallationStore
    private let installer: AgentInstaller
    private let remover: AgentRemover
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
        installer: AgentInstaller? = nil,
        remover: AgentRemover = AgentRemover(),
        settle: @escaping @MainActor () async -> Void = HomeModel.waitForFocusChange
    ) {
        self.store = store
        // Renombrar vuelve a escribir los archivos del agente: con la misma instalación que el home lee.
        self.installer = installer ?? {
            var live = AgentInstaller.live()
            live.store = store
            return live
        }()
        self.remover = remover
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
        problems[agent.id] = nil
        Task {
            let outcome = await AgentOpenPolicy.open(
                folder: agent.folder, tools: agent.tools, inApp: target == .app, prompt: nil, resume: true,
                opener: opener, claudePath: claudePath)
            if outcome != .opened { problems[agent.id] = outcome }
            await settle()
            opening = nil
        }
    }

    // MARK: - Gestionar un agente: renombrar y eliminar

    func toggleManageMenu(_ agent: HomeAgent) {
        guard opening == nil, agent.folderExists, !isWorking else { return }
        manageMenu = manageMenu == agent.id ? nil : agent.id
    }

    func closeManageMenu() { manageMenu = nil }

    func askRename(_ agent: HomeAgent) {
        manageMenu = nil
        dialogError = nil
        dialog = .rename(agent)
    }

    /// «Eliminar»: se calcula primero **qué** se mandaría a la Papelera y se enseña. No se toca nada hasta confirmar.
    func askDelete(_ agent: HomeAgent) {
        manageMenu = nil
        dialogError = nil
        guard let installation = try? store.load(), let record = installation.agent(id: agent.id) else {
            dialogError = nil
            return
        }
        dialog = .delete(agent, remover.plan(for: record))
    }

    func cancelDialog() {
        guard !isWorking else { return }
        dialog = nil
        dialogError = nil
    }

    func dismissNotice() { notice = nil }

    static func renameIssue(for name: String) -> RenameIssue? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return .empty }
        if name.count > WizardState.maxAgentNameLength { return .tooLong }
        return nil
    }

    /// Cambia **solo el nombre**: la carpeta no se mueve (la app de Claude ata su historial a la ruta). Vuelve a
    /// escribir los archivos del agente con el nombre nuevo; `memoria/` no se toca.
    @discardableResult
    func rename(_ agent: HomeAgent, to newName: String) -> Bool {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.renameIssue(for: name) == nil, !isWorking else { return false }
        if name == agent.name {
            cancelDialog()
            return true
        }
        isWorking = true
        defer { isWorking = false }
        do {
            guard let installation = try store.load(), var config = installation.resolvedConfig(for: agent.id) else {
                dialogError = Localized.string("home.rename.failed", locale: Locale(identifier: language.rawValue))
                return false
            }
            config.agentName = name
            _ = try installer.install(config, existingAgentID: agent.id)
            dialog = nil
            dialogError = nil
            reload()
            return true
        } catch {
            dialogError = Localized.string("home.rename.failed", locale: Locale(identifier: language.rawValue))
            return false
        }
    }

    /// Manda a la Papelera la carpeta del agente y lo que Claude guardó de ella, y lo saca de la lista.
    /// Si la carpeta no se puede mandar a la Papelera no se quita nada. Devuelve si el agente se eliminó.
    @discardableResult
    func confirmDelete() -> Bool {
        guard case .delete(let agent, let plan)? = dialog, !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        let locale = Locale(identifier: language.rawValue)
        do {
            var installation = try store.load() ?? GalenoInstallation(language: language)
            guard installation.agent(id: agent.id) != nil else {
                dialog = nil
                reload()
                return true
            }
            let outcome = try remover.execute(plan)
            try installation.removeAgent(id: agent.id)
            try store.save(installation)
            dialog = nil
            dialogError = nil
            notice = outcome.failed.isEmpty ? nil : Localized.string("home.delete.partial %lld", outcome.failed.count, locale: locale)
            reload()
            return true
        } catch {
            dialogError = Localized.string("home.delete.failed", locale: locale)
            return false
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
