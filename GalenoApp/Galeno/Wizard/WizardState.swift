import Combine
import Foundation
import GalenoCore

/// Todo lo que el wizard va capturando. Al final, `makeConfig()` lo convierte
/// en el `AgentConfig` que se le pasa al motor.
///
/// Es la única fuente de verdad: las pantallas leen y escriben aquí, y la
/// navegación también. No contiene credenciales (igual que `AgentConfig`).
@MainActor
final class WizardState: ObservableObject {
    @Published private(set) var step: WizardStep = .welcome

    // MARK: Lo que captura el wizard

    @Published var language: Language
    @Published var agentName = ""
    @Published var projectDescription = ""
    @Published var connections: [ToolConnection] = []
    @Published var skills: [SelectedSkill] = []
    @Published var sendingRules: SendingRules = .default

    /// Lo que la pantalla 2 encontró. No va en el `AgentConfig`: es del Mac.
    @Published private(set) var claudeStatus: ClaudeCodeStatus

    private let claudeDetector: ClaudeCodeDetector
    private let connectServices: ConnectServices

    /// El sub-wizard del paso 5. Se crea al entrar en él y se recrea si cambian las
    /// herramientas elegidas.
    @Published private(set) var connectFlow: ConnectFlow?
    private var connectFlowTools: [Tool] = []
    private var connectFlowObserver: AnyCancellable?

    /// - Parameters:
    ///   - preferredLanguages: los idiomas del Mac, en orden de preferencia.
    ///   - claudeStatus: el estado inicial de la detección.
    ///   - claudeDetector: quien busca `claude`. Las tres cosas son inyectables
    ///     para las pruebas.
    init(
        preferredLanguages: [String] = Locale.preferredLanguages,
        claudeStatus: ClaudeCodeStatus = .checking,
        claudeDetector: ClaudeCodeDetector = .live,
        connectServices: ConnectServices = .live()
    ) {
        language = Self.defaultLanguage(from: preferredLanguages)
        self.claudeStatus = claudeStatus
        self.claudeDetector = claudeDetector
        self.connectServices = connectServices
    }

    /// El idioma del paso 1 viene preseleccionado según el Mac: español si el
    /// primero de sus idiomas es español, inglés en cualquier otro caso.
    nonisolated static func defaultLanguage(from preferredLanguages: [String]) -> Language {
        guard let first = preferredLanguages.first?.lowercased() else { return .english }
        return first == "es" || first.hasPrefix("es-") || first.hasPrefix("es_") ? .spanish : .english
    }

    // MARK: Navegación

    var stepCount: Int { WizardStep.allCases.count }

    /// De 1/10 en el primer paso a 1 en el último: la barra se ve desde el
    /// principio y se llena del todo en "Listo".
    var progress: Double { Double(step.number) / Double(stepCount) }

    var isFirstStep: Bool { step == WizardStep.allCases.first }
    var isLastStep: Bool { step == WizardStep.allCases.last }

    var canGoBack: Bool { step.allowsGoingBack }
    var canGoForward: Bool { !isLastStep && isCurrentStepComplete }

    /// El sub-wizard del paso 5 lleva sus propios botones (Conectar, Conectar después,
    /// Reintentar…): la barra Atrás/Siguiente se oculta hasta que llega a la celebración.
    var hidesNavigation: Bool {
        step == .connect && connectFlow?.isFinished != true
    }

    /// Si el paso actual tiene lo que necesita para seguir. Los pasos que
    /// todavía no se construyen no piden nada.
    var isCurrentStepComplete: Bool {
        switch step {
        case .detection: claudeStatus.isFound
        case .agent: agentNameIssue == nil
        case .tools: !connections.isEmpty
        // Se sale del sub-wizard cuando llega a la celebración: todas conectadas o saltadas.
        case .connect: connectFlow?.isFinished == true
        case .welcome, .sources, .skills, .rules, .generating, .done: true
        }
    }

    func next() {
        guard canGoForward, let following = WizardStep(rawValue: step.rawValue + 1) else { return }
        step = following
    }

    func back() {
        guard canGoBack, let previous = WizardStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    // MARK: Paso 2: Claude Code

    /// Busca `claude` y actualiza `claudeStatus`. Se llama al entrar al paso y
    /// desde "Comprobar de nuevo".
    func detectClaudeCode() async {
        claudeStatus = .checking
        claudeStatus = await claudeDetector.detect()
    }

    // MARK: Paso 3: el agente

    /// Los mismos topes que usa el motor para la carpeta (`AgentFolder`: 60) y
    /// una línea corta para la descripción (`docs/03` §3).
    static let maxAgentNameLength = 60
    static let maxProjectDescriptionLength = 140

    enum AgentNameIssue: Equatable {
        case empty
        case tooLong
    }

    /// Por qué el nombre no vale, o `nil` si vale. El motor rechaza el vacío
    /// (`GenerationError.emptyAgentName`); aquí se avisa antes de llegar a él.
    var agentNameIssue: AgentNameIssue? {
        let name = agentName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return .empty }
        if name.count > Self.maxAgentNameLength { return .tooLong }
        return nil
    }

    // MARK: Paso 4: las herramientas

    /// Las herramientas marcadas, en el orden de la grilla.
    var selectedTools: [Tool] { connections.map(\.tool) }

    func isSelected(_ tool: Tool) -> Bool {
        connections.contains { $0.tool == tool }
    }

    /// Una herramienta marcada que otra necesita no se puede desmarcar: Google
    /// Meet se lee con el MCP de Google Workspace (`Tool.requires`).
    func isRequiredBySelection(_ tool: Tool) -> Bool {
        selectedTools.contains { $0.requires.contains(tool) }
    }

    /// Marca o desmarca. Al marcar una herramienta se marcan también las que
    /// necesita; las que otra necesita no se desmarcan.
    func toggle(_ tool: Tool) {
        if isSelected(tool) {
            guard !isRequiredBySelection(tool) else { return }
            connections.removeAll { $0.tool == tool }
        } else {
            for needed in tool.requires + [tool] where !isSelected(needed) {
                connections.append(ToolConnection(tool: needed))
            }
            // El orden de la grilla, no el de los clics: es el de las conexiones del paso 5.
            let order = Tool.allCases
            connections.sort { order.firstIndex(of: $0.tool)! < order.firstIndex(of: $1.tool)! }
        }
    }

    /// "~X min" del pie de la grilla.
    var estimatedSetupMinutes: Int { ToolEstimate.minutes(for: selectedTools) }

    // MARK: Paso 5: conectar

    /// Crea el sub-wizard (o conserva el que ya hay, si las herramientas son las mismas).
    func beginConnecting() {
        let tools = ConnectTarget.connectionTools(from: selectedTools)
        if connectFlow != nil, connectFlowTools == tools { return }

        connectFlow?.cancelAll()
        connectFlowTools = tools
        let claudePath: String
        if case .found(_, let path, _) = claudeStatus { claudePath = path } else { claudePath = "claude" }

        let flow = ConnectFlow(
            tools: selectedTools,
            statuses: Dictionary(uniqueKeysWithValues: connections.map { ($0.tool, $0.status) }),
            mcp: connectServices.makeMCP(claudePath),
            whatsapp: connectServices.whatsapp,
            fetchRealData: connectServices.fetchRealData,
            timing: connectServices.timing,
            sleep: connectServices.sleep,
            onStatus: { [weak self] tool, status in self?.setConnectionStatus(tool, status) })
        connectFlow = flow
        // Que `canGoForward` y la barra de navegación se enteren de lo que hace el sub-wizard.
        connectFlowObserver = flow.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    /// Marca el estado de una conexión. Google Meet no tiene servidor: queda como
    /// Google Workspace, que es con lo que se lee.
    func setConnectionStatus(_ tool: Tool, _ status: ConnectionStatus) {
        for index in connections.indices where connections[index].tool == tool {
            connections[index].status = status
        }
        if tool == .googleWorkspace {
            for index in connections.indices where connections[index].tool == .googleMeet {
                connections[index].status = status
            }
        }
    }

    /// Al cerrar la app: nada de procesos huérfanos.
    func stopConnecting() {
        connectFlow?.cancelAll()
    }

    // MARK: El resultado

    /// El `AgentConfig` con el que se genera la carpeta del agente.
    func makeConfig() -> AgentConfig {
        AgentConfig(
            agentName: agentName.trimmingCharacters(in: .whitespacesAndNewlines),
            language: language,
            role: .productManager,
            projectDescription: projectDescription.trimmingCharacters(in: .whitespacesAndNewlines),
            connections: connections,
            skills: skills,
            sendingRules: sendingRules
        )
    }
}
