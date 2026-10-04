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

    // MARK: Pantallas 6 a 10

    /// Las listas de la pantalla 6. Se crea al entrar y se recrea si cambian las conexiones.
    @Published private(set) var sourcesFlow: SourcesFlow?
    private var sourcesFlowKey: [String] = []
    private var sourcesObserver: AnyCancellable?

    enum SkillCatalogState: Equatable {
        case notLoaded
        case loaded(SkillCatalog)
        case failed(String)
    }
    /// El catálogo de la pantalla 7.
    @Published private(set) var skillCatalog: SkillCatalogState = .notLoaded
    private var skillsInitialized = false

    /// La generación de la pantalla 9, y el agente que dejó (para la 10 y para regenerar sin crear otro).
    @Published private(set) var generation: GenerationFlow?
    @Published private(set) var generatedAgent: AgentRecord?
    @Published private(set) var lastGeneration: GenerationResult?
    private var generationObserver: AnyCancellable?

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
        (step == .connect && connectFlow?.isFinished != true) || step == .generating
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
        case .generating: generation?.phase == .succeeded
        case .welcome, .sources, .skills, .rules, .done: true
        }
    }

    func next() {
        guard canGoForward, let following = WizardStep(rawValue: step.rawValue + 1) else { return }
        // Cada vez que se entra a «Generando» es una generación nueva: la de antes ya no cuenta.
        if following == .generating {
            generation?.cancel()
            generation = nil
        }
        step = following
    }

    func back() {
        guard canGoBack, let previous = WizardStep(rawValue: step.rawValue - 1) else { return }
        // Desde «Listo» se vuelve a las reglas, no a la pantalla de generar: al avanzar se
        // regenera el mismo agente, en la misma carpeta.
        step = step == .done ? .rules : previous
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
            slack: connectServices.slack,
            agentName: { [weak self] in self?.agentName.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" },
            fetchRealData: connectServices.fetchRealData,
            timing: connectServices.timing,
            sleep: connectServices.sleep,
            onStatus: { [weak self] tool, status in self?.setConnectionStatus(tool, status) },
            onClientID: { [weak self] tool, clientID in self?.setOAuthClientID(tool, clientID) },
            namePrefixes: Dictionary(
                uniqueKeysWithValues: connections.compactMap { connection in
                    connection.serverNamePrefix.map { (connection.tool, $0) }
                }),
            onNamePrefix: { [weak self] tool, prefix in self?.setServerNamePrefix(tool, prefix) },
            authorizer: connectServices.authorizer,
            language: { [weak self] in self?.language ?? .spanish })
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

    /// El `client_id` de la app OAuth propia (Slack, Google): público, va al `.mcp.json`.
    /// El `client_secret` **nunca** llega aquí.
    func setOAuthClientID(_ tool: Tool, _ clientID: String) {
        for index in connections.indices where connections[index].tool == tool {
            connections[index].oauthClientID = clientID
        }
    }

    /// El prefijo con el que quedó registrada una herramienta cuando el nombre normal estaba
    /// ocupado (`nil` = el normal). El motor lo usa para `.mcp.json`, permisos y subagentes.
    func setServerNamePrefix(_ tool: Tool, _ prefix: String?) {
        for index in connections.indices where connections[index].tool == tool {
            connections[index].serverNamePrefix = prefix
        }
    }

    /// Al cerrar la app: nada de procesos huérfanos.
    func stopConnecting() {
        connectFlow?.cancelAll()
    }

    // MARK: Paso 6: qué leer

    /// Pide las listas de lo que se puede elegir (canales, chats, carpetas, proyectos). Se llama al
    /// entrar al paso; es idempotente mientras no cambien las conexiones.
    func beginSources() {
        // Las herramientas sin nada que elegir (reuniones transcritas) leen todo.
        for index in connections.indices
        where connections[index].status == .connected && connections[index].tool.selectableSourceKinds.isEmpty {
            connections[index].sources = .everything
        }

        let connected = connections.filter { $0.status == .connected }
        let key = connected.map { "\($0.tool.rawValue):\($0.serverNamePrefix ?? "")" }
        if sourcesFlow == nil || key != sourcesFlowKey {
            sourcesFlow?.cancelAll()
            let claudePath: String
            if case .found(_, let path, _) = claudeStatus { claudePath = path } else { claudePath = "claude" }
            let flow = SourcesFlow(connections: connected, lister: connectServices.makeLister(claudePath))
            sourcesFlow = flow
            sourcesFlowKey = key
            sourcesObserver = flow.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        }
        sourcesFlow?.start()
    }

    func sourceSelection(for tool: Tool) -> SourceSelection {
        connection(for: tool)?.sources ?? .nothing
    }

    func isSourceSelected(_ source: Source, in tool: Tool) -> Bool {
        let selection = sourceSelection(for: tool)
        return !selection.readsEverything && selection.selected.contains { $0.id == source.id }
    }

    /// Marca o desmarca una fuente. Elegir una la vuelve el foco del agente; sin ninguna, el agente
    /// no tiene un foco concreto (y sigue pudiendo leer lo que tenga a la vista).
    func toggleSource(_ source: Source, in tool: Tool) {
        let current = sourceSelection(for: tool)
        var chosen = current.readsEverything ? [] : current.selected
        if let index = chosen.firstIndex(where: { $0.id == source.id }) {
            chosen.remove(at: index)
        } else {
            chosen.append(source)
        }
        setSelection(chosen.isEmpty ? .nothing : .only(chosen), for: tool)
    }

    /// «Que lea todo»: lo que se ofrece cuando no se pudo listar. Desactivarlo vuelve a «sin elegir».
    func setReadsEverything(_ on: Bool, for tool: Tool) {
        setSelection(on ? .everything : .nothing, for: tool)
    }

    private func setSelection(_ selection: SourceSelection, for tool: Tool) {
        for index in connections.indices where connections[index].tool == tool {
            connections[index].sources = selection
        }
    }

    func connection(for tool: Tool) -> ToolConnection? {
        connections.first { $0.tool == tool }
    }

    /// Las herramientas que quedaron conectadas, en el orden de las conexiones.
    var connectedTools: [Tool] { connections.filter { $0.status == .connected }.map(\.tool) }

    // MARK: Paso 7: skills

    /// Lee `skills/catalog.json`. Las nuestras vienen marcadas la primera vez; lo que el usuario
    /// desmarque se respeta si vuelve a esta pantalla.
    func loadSkillCatalog() {
        guard let directory = connectServices.skillsDirectory else {
            skillCatalog = .failed("no hay carpeta de skills")
            return
        }
        do {
            let catalog = try SkillCatalog.load(from: directory)
            skillCatalog = .loaded(catalog)
            if !skillsInitialized {
                skillsInitialized = true
                skills = catalog.defaultSelection
            }
        } catch {
            skillCatalog = .failed(String(describing: error))
        }
    }

    func isSkillSelected(_ id: String, source: SkillSource) -> Bool {
        skills.contains { $0.id == id && $0.source == source }
    }

    func toggleSkill(_ id: String, source: SkillSource) {
        // Una curada sin su contenido todavía no se instala: marcarla haría fallar la generación.
        if source == .curated, !isSkillSelected(id, source: .curated) {
            guard case .loaded(let catalog) = skillCatalog,
                catalog.curated.contains(where: { $0.id == id && $0.available })
            else { return }
        }
        if let index = skills.firstIndex(where: { $0.id == id && $0.source == source }) {
            skills.remove(at: index)
        } else {
            skills.append(SelectedSkill(id: id, source: source))
        }
    }

    // MARK: Paso 8: reglas

    /// Las escrituras internas que aplican a lo que el usuario conectó. Los envíos externos
    /// (Slack, email) no se configuran: siempre piden aprobación.
    var configurableWrites: [InternalWrite] {
        let tools = connectedTools
        return InternalWrite.allCases.filter { write in tools.contains { $0.internalWrites.contains(write) } }
    }

    func policy(for write: InternalWrite) -> ApprovalPolicy { sendingRules.policy(for: write) }

    func setPolicy(_ policy: ApprovalPolicy, for write: InternalWrite) {
        sendingRules.setPolicy(policy, for: write)
    }

    /// Las herramientas conectadas por las que el agente puede hablarle a otras personas.
    var externalSendTools: [Tool] { connectedTools.filter { $0.externalSend != nil } }

    // MARK: Paso 9: generar

    /// Escribe la carpeta del agente y lo registra. Se llama al entrar al paso.
    func beginGeneration() {
        generation?.cancel()
        let config = makeConfig()
        let installer = connectServices.installer
        let existing = generatedAgent?.id
        let flow = GenerationFlow(sleep: connectServices.sleep) {
            try installer.install(config, existingAgentID: existing)
        }
        generation = flow
        generationObserver = flow.$outcome.compactMap { $0 }.sink { [weak self] outcome in
            self?.generatedAgent = outcome.record
            self?.lastGeneration = outcome.result
        }
        flow.start()
    }

    /// Terminó bien: se pasa a «Listo».
    func finishGeneration() {
        guard step == .generating, generation?.phase == .succeeded,
            let following = WizardStep(rawValue: step.rawValue + 1)
        else { return }
        step = following
    }

    /// Falló: se vuelve a las reglas para que el usuario pueda cambiar algo o reintentar.
    func leaveFailedGeneration() {
        guard step == .generating, case .failed? = generation?.phase else { return }
        generation?.cancel()
        step = .rules
    }

    /// Para abrir el agente y mostrar su carpeta (pantalla 10).
    var opener: any AgentOpening { connectServices.opener }

    /// La ruta de `claude` que encontró el paso 2.
    var claudePath: String {
        if case .found(_, let path, _) = claudeStatus { return path }
        return "claude"
    }

    /// Se llama al cerrar la app.
    func stopWorking() {
        stopConnecting()
        sourcesFlow?.cancelAll()
        generation?.cancel()
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
