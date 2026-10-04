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
    @Published private(set) var step: WizardStep = .welcome {
        didSet { if step.rawValue > furthestStep.rawValue { furthestStep = step } }
    }
    /// El paso más lejano al que se ha llegado: ⌘1…⌘0 solo salta a pasos ya visitados.
    private(set) var furthestStep: WizardStep = .welcome

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

    /// Mientras el texto está fundido a cero durante el cambio de idioma (G8).
    @Published private(set) var languageFading = false

    /// Cambia el idioma: el texto baja a opacidad 0 (120 ms), cambia el `locale` y sube a 1 (120 ms).
    /// Sin animar (Reducir movimiento), el cambio es directo.
    func changeLanguage(_ new: Language, animated: Bool) {
        guard new != language else { return }
        guard animated else {
            language = new
            return
        }
        languageFading = true
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            language = new
            languageFading = false
        }
    }

    /// Las líneas del `AGENTS.md` que ya vio la última vez que abrió la vista previa: lo nuevo se marca.
    var previewSeen: Set<String> = []
    /// El anillo del retrato de la portada se traza solo la primera vez que se ve en la sesión.
    var hasShownPortraitTrace = false

    // MARK: Reanudar

    /// El borrador que dejó una sesión anterior, mientras el usuario decide si seguir o empezar de nuevo.
    @Published private(set) var pendingDraft: WizardDraft?
    private let draftStore: (any DraftStoring)?
    private var draftObserver: AnyCancellable?

    /// - Parameters:
    ///   - preferredLanguages: los idiomas del Mac, en orden de preferencia.
    ///   - claudeStatus: el estado inicial de la detección.
    ///   - claudeDetector: quien busca `claude`. Las tres cosas son inyectables
    ///     para las pruebas.
    init(
        preferredLanguages: [String] = Locale.preferredLanguages,
        claudeStatus: ClaudeCodeStatus = .checking,
        claudeDetector: ClaudeCodeDetector = .live,
        connectServices: ConnectServices = .live(),
        draftStore: (any DraftStoring)? = nil
    ) {
        language = Self.defaultLanguage(from: preferredLanguages)
        self.claudeStatus = claudeStatus
        self.claudeDetector = claudeDetector
        self.connectServices = connectServices
        self.draftStore = draftStore
        if let draft = draftStore?.load(), draft.step > WizardStep.welcome.rawValue {
            pendingDraft = draft
            language = draft.language  // la pantalla de «¿Seguimos?» habla en su idioma
        }
        guard draftStore != nil else { return }
        // Cada cambio se guarda poco después; mientras se decide si reanudar, no se pisa el borrador.
        draftObserver = objectWillChange
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.saveDraft() }
    }

    /// El estado de ahora como borrador. Nada si no hay nada que guardar (primer paso sin tocar,
    /// o ya terminó).
    func makeDraft() -> WizardDraft? {
        guard step != .done, step.rawValue > WizardStep.welcome.rawValue || !agentName.isEmpty else { return nil }
        let resumeStep: WizardStep = (step == .generating) ? .review : step
        return WizardDraft(
            step: resumeStep.rawValue, furthestStep: min(furthestStep.rawValue, WizardStep.review.rawValue),
            language: language, agentName: agentName, projectDescription: projectDescription,
            connections: connections, skills: skills, skillsInitialized: skillsInitialized,
            sendingRules: sendingRules)
    }

    func saveDraft() {
        guard let draftStore, pendingDraft == nil else { return }
        if let draft = makeDraft() { draftStore.save(draft) } else { draftStore.clear() }
    }

    /// «Continuar»: vuelve a donde se quedó. Las conexiones hechas en Claude Code se reconocen solas
    /// al entrar al paso 5 («ya estaba conectado»).
    func resumeDraft() {
        guard let draft = pendingDraft else { return }
        language = draft.language
        agentName = draft.agentName
        projectDescription = draft.projectDescription
        connections = draft.connections
        skills = draft.skills
        skillsInitialized = draft.skillsInitialized
        sendingRules = draft.sendingRules
        furthestStep = WizardStep(rawValue: draft.furthestStep) ?? .welcome
        step = WizardStep(rawValue: draft.step) ?? .welcome
        pendingDraft = nil
        // Pasar de largo el paso 2 no debe dejar el estado de Claude Code en «buscando».
        if !claudeStatus.isFound { Task { await detectClaudeCode() } }
    }

    /// «Empezar de nuevo»: se borra el borrador y se arranca limpio.
    func discardDraft() {
        pendingDraft = nil
        draftStore?.clear()
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
    /// Reintentar, Continuar…) hasta el final: la barra Atrás/Siguiente no aparece en ese paso.
    var hidesNavigation: Bool {
        step == .connect || step == .generating
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
        case .welcome, .skills, .rules, .review, .done: true
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
        // Desde «Listo» se vuelve a la revisión, no a la pantalla de escribir (que no se puede
        // deshacer): al avanzar se regenera el mismo agente, en la misma carpeta.
        step = step == .done ? .review : previous
    }

    /// Salta a un paso ya visitado (⌘1…⌘0). Hacia atrás siempre; hacia adelante solo hasta donde ya
    /// se llegó y con cada paso intermedio completo, para no saltarse nada.
    func goTo(_ target: WizardStep) {
        guard target != step, target.rawValue <= furthestStep.rawValue, step != .generating else { return }
        if target.rawValue < step.rawValue { jump(to: target); return }
        while step.rawValue < target.rawValue, canGoForward { next() }
    }

    /// Desde «Revisión», «Cambiar» lleva a un paso anterior. Solo hacia atrás: adelante se va
    /// con «Siguiente», que comprueba que cada paso esté completo.
    func jump(to target: WizardStep) {
        guard canGoBack, target.rawValue < step.rawValue else { return }
        step = target
    }

    /// Los minutos que faltan, para el «~17 min» de la cabecera: lo que queda por conectar más un
    /// minuto por cada paso restante. Es una estimación, como la del paso 4.
    var estimatedMinutesLeft: Int {
        let pending: Int
        switch step {
        case .welcome, .detection, .agent, .tools:
            pending = selectedTools.isEmpty ? 1 : estimatedSetupMinutes
        case .connect:
            let remaining = connectFlow.map { flow in
                flow.tools.filter { (flow.statuses[$0] ?? .selected) == .selected }
            } ?? selectedTools
            pending = remaining.reduce(0) { $0 + $1.estimatedSetupMinutes }
        default:
            pending = 0
        }
        return max(1, pending + max(0, stepCount - step.number))
    }

    // MARK: Paso 2: Claude Code

    /// Busca `claude` y actualiza `claudeStatus`. Se llama al entrar al paso y
    /// desde "Comprobar de nuevo".
    func detectClaudeCode() async {
        claudeStatus = .checking
        let started = ContinuousClock.now
        let result = await claudeDetector.detect()
        // La búsqueda se ve al menos 600 ms aunque sea instantánea: se nota que se buscó.
        let elapsed = ContinuousClock.now - started
        if elapsed < .milliseconds(600) { await connectServices.sleep(.milliseconds(600) - elapsed) }
        claudeStatus = result
    }

    // MARK: Paso 3: contexto que el usuario trae

    /// Un material que el usuario añadió (un chat de claude.ai, un documento).
    struct ContextItem: Identifiable, Equatable {
        let id = UUID()
        var file: ContextFile
    }

    /// Material que se deja en `memoria/contexto/` al crear el agente. No va al borrador ni a la config:
    /// es de una sola vez y puede ser largo.
    @Published var contextItems: [ContextItem] = []

    var contextCharacterCount: Int { contextItems.reduce(0) { $0 + $1.file.text.count } }

    enum ContextIssue: Equatable { case tooMany, tooLong, empty }

    /// Añade un material. Devuelve por qué no cupo, o `nil` si entró.
    @discardableResult
    func addContext(_ file: ContextFile) -> ContextIssue? {
        let text = file.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return .empty }
        if contextItems.count >= ContextFile.maxFiles { return .tooMany }
        if contextCharacterCount >= ContextFile.maxCharactersTotal { return .tooLong }
        contextItems.append(ContextItem(file: ContextFile(title: file.title, text: text)))
        return nil
    }

    func removeContext(_ item: ContextItem) {
        contextItems.removeAll { $0.id == item.id }
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
            language: { [weak self] in self?.language ?? .spanish },
            returnToApp: connectServices.returnToApp,
            openURL: connectServices.openURL)
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
        let context = contextItems.map(\.file)
        let flow = GenerationFlow(sleep: connectServices.sleep) {
            try installer.install(config, existingAgentID: existing, importedContext: context)
        }
        generation = flow
        generationObserver = flow.$outcome.compactMap { $0 }.sink { [weak self] outcome in
            self?.generatedAgent = outcome.record
            self?.lastGeneration = outcome.result
        }
        flow.start()
    }

    /// Terminó bien: se pasa a «Listo». El borrador ya no hace falta.
    func finishGeneration() {
        guard step == .generating, generation?.phase == .succeeded,
            let following = WizardStep(rawValue: step.rawValue + 1)
        else { return }
        step = following
        draftStore?.clear()
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
            // Ya no hay pantalla para elegir el foco: lo conectado se lee entero. Sin esto el
            // `AGENTS.md` diría que no se eligió ninguna fuente.
            connections: connections.map { connection in
                var connection = connection
                if connection.status == .connected, !connection.sources.readsEverything,
                    connection.sources.selected.isEmpty
                {
                    connection.sources = .everything
                }
                return connection
            },
            skills: skills,
            sendingRules: sendingRules
        )
    }
}
