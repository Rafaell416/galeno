import Combine
import Foundation
import GalenoCore
import SwiftUI

/// Todo lo que el wizard va capturando. Al final, `makeConfig()` lo convierte
/// en el `AgentConfig` que se le pasa al motor.
///
/// Es la única fuente de verdad: las pantallas leen y escriben aquí, y la
/// navegación también. No contiene credenciales (igual que `AgentConfig`).
@MainActor
final class WizardState: ObservableObject {
    @Published private(set) var step: WizardStep = .role {
        didSet { if step.rawValue > furthestStep.rawValue { furthestStep = step } }
    }
    /// El paso más lejano al que se ha llegado: ⌘1…⌘0 solo salta a pasos ya visitados.
    private(set) var furthestStep: WizardStep = .role

    /// El wizard completo (la primera vez) o el corto de «Nuevo agente» (`docs/03` §3b): sin idioma, detección ni
    /// conexiones ya hechas; parte de las herramientas que la instalación ya tiene conectadas.
    ///
    /// `.edit` es «Gestionar» un agente que ya existe (`docs/03` §3b): las mismas pantallas, ya con lo que el agente tiene,
    /// sin nombre ni bienvenida; al guardar se regenera **su** carpeta (no se crea otra) y `memoria/` no se toca.
    enum Mode: Equatable { case full, short, edit }
    let mode: Mode

    /// El agente que se está gestionando (solo en `.edit`).
    private(set) var editingAgent: AgentRecord?

    /// Lo que se hace al guardar los cambios de un agente: volver al home. El wizard de edición no pasa por «Listo».
    var onSaved: (@MainActor () -> Void)?

    /// Las conexiones que la instalación ya conoce (`.short` y `.edit`): una herramienta que se vuelve a marcar y ya
    /// estaba conectada entra conectada, con su `client_id`, en vez de pasar otra vez por «Conectar».
    private var knownConnections: [Tool: SharedConnection] = [:]

    // MARK: Lo que captura el wizard

    @Published var language: Language
    /// El rol del agente (paso 1): decide sus skills y el orden en que se ofrecen las herramientas.
    @Published var role: AgentRole = .productManager {
        didSet { if role != oldValue { applyRoleDefaults() } }
    }
    /// Las herramientas que el asistente marcó por el rol (y el usuario todavía no cambió).
    private var rolePreselection: [Tool] = []
    /// El rol cuyas skills de fábrica están puestas.
    private var skillsRole: AgentRole?
    @Published var agentName = ""
    @Published var projectDescription = ""
    @Published var connections: [ToolConnection] = []
    @Published var skills: [SelectedSkill] = []
    @Published var sendingRules: SendingRules = .default

    /// Lo que la pantalla 2 encontró. No va en el `AgentConfig`: es del Mac.
    @Published private(set) var claudeStatus: ClaudeCodeStatus
    /// Lo que Galeno está haciendo por el usuario en el paso 2 (instalar, actualizar, iniciar sesión).
    @Published private(set) var claudeSetup: ClaudeSetupPhase = .idle
    private var claudeSetupTask: Task<Void, Never>?

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
    /// Paso «Skills»: la skill cuya vista previa está abierta (la hoja va sobre toda la ventana).
    @Published var previewedSkill: CatalogSkill?
    /// Paso «Skills»: una card tiene el foco del teclado. Ahí ↩ abre su vista previa en vez de avanzar.
    @Published var skillCardHasFocus = false
    /// ¿↩ es del paso y no de «Siguiente»? Con una card enfocada o la vista previa abierta, avanzar es ⌘↩.
    var returnBelongsToStep: Bool { step == .skills && (skillCardHasFocus || previewedSkill != nil) }
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
    private var connectFlowClaudePath = ""
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
        draftStore: (any DraftStoring)? = nil,
        startingFrom installation: GalenoInstallation? = nil,
        editing agentID: UUID? = nil
    ) {
        language = Self.defaultLanguage(from: preferredLanguages)
        self.claudeStatus = claudeStatus
        self.claudeDetector = claudeDetector
        self.connectServices = connectServices
        // El corto se hace de una vez: nunca guarda ni pisa el borrador del wizard completo.
        self.draftStore = installation == nil ? draftStore : nil
        if let installation, let agentID, let record = installation.agent(id: agentID),
            let config = installation.resolvedConfig(for: agentID)
        {
            // «Gestionar»: el agente tal como está guardado. Lo que se saltó (`skipped`) vuelve a estar por conectar:
            // si no, «Conectar» lo daría por resuelto y no habría forma de recuperarlo.
            mode = .edit
            editingAgent = record
            generatedAgent = record
            knownConnections = Dictionary(uniqueKeysWithValues: installation.connections.map { ($0.tool, $0) })
            language = installation.language
            agentName = config.agentName
            projectDescription = config.projectDescription
            // Lo que no se puede conectar hoy («Próximamente») y no estaba conectado no entra: no se podría ni
            // quitar de la lista ni conectar, y contaría como pendiente para siempre.
            connections = config.connections
                .filter { !$0.tool.isComingSoon || $0.status == .connected }
                .map { connection in
                    var connection = connection
                    if connection.status == .skipped { connection.status = .selected }
                    return connection
                }
            role = config.role
            skills = config.skills
            skillsInitialized = true  // lo que tiene el agente manda, no la selección de fábrica
            sendingRules = config.sendingRules
            step = .tools
            furthestStep = .tools
            if !claudeStatus.isFound { Task { await detectClaudeCode() } }
            return
        }
        if let installation {
            // «Nuevo agente»: el idioma y las conexiones ya hechas son los de la instalación (la función de
            // la Fase 3b), y se empieza en el nombre. No hay borrador: es corto y se hace de una vez.
            mode = .short
            language = installation.language
            connections = installation.startingPoint(agentName: "").connections
            knownConnections = Dictionary(uniqueKeysWithValues: installation.connections.map { ($0.tool, $0) })
            step = .role
            furthestStep = .role
            // Conectar una herramienta nueva necesita saber dónde está `claude`; el paso 2 no existe aquí.
            if !claudeStatus.isFound { Task { await detectClaudeCode() } }
            return
        }
        mode = .full
        if let draft = draftStore?.load(), draft.step > WizardStep.role.rawValue {
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
        guard step != .done, step.rawValue > WizardStep.role.rawValue || !agentName.isEmpty else { return nil }
        let resumeStep: WizardStep = (step == .generating) ? .review : step
        return WizardDraft(
            step: resumeStep.rawValue, furthestStep: min(furthestStep.rawValue, WizardStep.review.rawValue),
            language: language, role: role, agentName: agentName, projectDescription: projectDescription,
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
        role = draft.role
        agentName = draft.agentName
        projectDescription = draft.projectDescription
        connections = draft.connections
        skills = draft.skills
        skillsInitialized = draft.skillsInitialized
        if draft.skillsInitialized { skillsRole = role }
        sendingRules = draft.sendingRules
        furthestStep = WizardStep(rawValue: draft.furthestStep) ?? .role
        let resumed = WizardStep(rawValue: draft.step) ?? .role
        // Un paso que este asistente no tiene (p. ej. «Skills») no se reanuda: se va al siguiente que sí.
        step = stepOrder.contains(resumed) ? resumed : (stepOrder.first { $0.rawValue > resumed.rawValue } ?? .role)
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

    /// Los pasos de este asistente, en orden. «Skills» llega con las del rol ya marcadas (el boceto la quitaba
    /// al crear un agente; Rafa la pidió de vuelta, 5 oct 2026). El corto («Nuevo agente») no tiene el paso de
    /// Claude Code, y solo tiene «Conectar» si alguna herramienta elegida todavía no está conectada.
    var stepOrder: [WizardStep] {
        switch mode {
        case .full:
            return [.role, .detection, .agent, .context, .tools, .connect, .skills, .rules, .review, .generating, .done]
        case .short:
            let connecting = step.rawValue <= WizardStep.tools.rawValue ? hasToConnect : connectStepLocked
            return [.role, .agent, .context, .tools] + (connecting ? [.connect] : []) + [.skills, .rules, .review, .generating, .done]
        case .edit:
            // Sin rol ni nombre (cambiarlos es otra cosa) ni «Listo»: al guardar se vuelve al home.
            let connecting = step.rawValue <= WizardStep.tools.rawValue ? hasToConnect : connectStepLocked
            return [.tools] + (connecting ? [.connect] : []) + [.skills, .rules, .review, .generating]
        }
    }

    /// Si «Conectar» entra en el wizard corto, decidido al salir de «Tus herramientas»: mientras se conecta,
    /// las herramientas pasan a conectadas y el paso no puede desaparecer a mitad de camino.
    private var connectStepLocked = false

    /// El título del paso. «Escribiendo» al crear un agente es «Actualizando» al gestionar uno que ya existe.
    var stepTitle: LocalizedStringKey {
        mode == .edit && step == .generating ? "step.generating.title.edit" : step.title
    }

    /// Los pasos que el usuario ve, sin repetir los que son momentos de uno mismo (`WizardStep.phase`).
    private var phases: [Int] {
        var seen: [Int] = []
        for phase in stepOrder.map(\.phase) where !seen.contains(phase) { seen.append(phase) }
        return seen
    }

    /// «Paso N de 7»: siete en el asistente completo, seis en «Nuevo agente», cuatro en «Gestionar».
    var stepCount: Int { phases.count }

    /// 1 en el primer paso del asistente (no el número fijo del paso: el corto tiene menos).
    var stepNumber: Int { stepNumber(of: step) }

    /// El número que el usuario ve para un paso cualquiera («Ibas por el paso 4»).
    func stepNumber(of step: WizardStep) -> Int { (phases.firstIndex(of: step.phase) ?? 0) + 1 }

    /// De 1/N en el primer paso a 1 en el último: la barra se ve desde el
    /// principio y se llena del todo en "Listo".
    var progress: Double { Double(stepNumber) / Double(stepCount) }

    var isFirstStep: Bool { step == stepOrder.first }
    var isLastStep: Bool { step == stepOrder.last }

    private func step(after current: WizardStep) -> WizardStep? {
        let order = stepOrder
        guard let index = order.firstIndex(of: current), index + 1 < order.count else { return nil }
        return order[index + 1]
    }

    private func step(before current: WizardStep) -> WizardStep? {
        let order = stepOrder
        guard let index = order.firstIndex(of: current), index > 0 else { return nil }
        return order[index - 1]
    }

    /// En el primer paso no hay atrás: en el wizard corto se cancela (vuelve al home).
    var canGoBack: Bool { step.allowsGoingBack && !isFirstStep }
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
        case .detection: claudeStatus.isReady && claudeSetup == .idle
        case .agent: agentNameIssue == nil
        case .tools: !connections.isEmpty
        // Se sale del sub-wizard cuando llega a la celebración: todas conectadas o saltadas.
        case .connect: connectFlow?.isFinished == true
        case .generating: generation?.phase == .succeeded
        case .role, .context, .skills, .rules, .review, .done: true
        }
    }

    func next() {
        if mode != .full, step == .tools { connectStepLocked = hasToConnect }
        guard canGoForward, let following = step(after: step) else { return }
        // Al salir del rol ya se sabe qué skills trae y qué herramientas se le proponen primero.
        if step == .role { applyRoleDefaults() }
        // Cada vez que se entra a «Generando» es una generación nueva: la de antes ya no cuenta.
        if following == .generating {
            generation?.cancel()
            generation = nil
        }
        step = following
    }

    func back() {
        guard canGoBack, let previous = step(before: step) else { return }
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

    // MARK: Paso 2: Claude Code

    /// Hay una búsqueda en curso. `claudeStatus == .checking` no sirve para saberlo: también es el valor de
    /// antes de haber mirado nunca, y tomarlo por «ya se está buscando» dejaba el paso girando para siempre
    /// en un Mac sin instalación previa (prueba de arranque limpio, 5 oct 2026).
    private var isDetectingClaude = false

    /// Al entrar al paso: mira si todavía no está listo. Si ya lo está, volver atrás y adelante no lo
    /// vuelve a buscar; si ya se está buscando, no se lanza otra búsqueda.
    func detectClaudeCodeIfNeeded() async {
        guard !claudeStatus.isReady, !claudeSetup.isWorking else { return }
        await detectClaudeCode()
    }

    /// Busca `claude` y actualiza `claudeStatus`. Se llama al entrar al paso y
    /// desde "Comprobar de nuevo".
    func detectClaudeCode() async {
        guard !isDetectingClaude else { return }
        isDetectingClaude = true
        defer { isDetectingClaude = false }
        claudeStatus = .checking
        let started = ContinuousClock.now
        let result = await claudeDetector.detect()
        // La búsqueda se ve al menos 600 ms aunque sea instantánea: se nota que se buscó.
        let elapsed = ContinuousClock.now - started
        if elapsed < .milliseconds(600) { await connectServices.sleep(.milliseconds(600) - elapsed) }
        claudeStatus = result
    }

    /// «Instalar» y «Actualizar»: Galeno corre el instalador oficial y vuelve a mirar. Si al terminar sigue
    /// sin haber un Claude Code que sirva, es un fallo aunque el instalador dijera que todo fue bien.
    func installClaudeCode() {
        guard !claudeSetup.isWorking else { return }
        claudeSetup = .installing
        claudeSetupTask = Task { [weak self] in
            guard let self else { return }
            let outcome = await connectServices.claudeSetup.install()
            if Task.isCancelled { return }
            switch outcome {
            case .done:
                let status = await claudeDetector.detect()
                if Task.isCancelled { return }
                claudeStatus = status
                claudeSetup = status.isFound ? .idle : .failed(.installFailed(detail: ""))
            case .offline: claudeSetup = .failed(.offline)
            case .timedOut: claudeSetup = .failed(.installTimedOut)
            case .cancelled: claudeSetup = .idle
            case .failed(let detail): claudeSetup = .failed(.installFailed(detail: detail))
            }
        }
    }

    /// «Iniciar sesión»: `claude auth login` abre el navegador; al terminar se vuelve a mirar.
    func signInToClaude() {
        guard !claudeSetup.isWorking, let path = claudeStatus.path else { return }
        claudeSetup = .signingIn
        claudeSetupTask = Task { [weak self] in
            guard let self else { return }
            let outcome = await connectServices.claudeSetup.signIn(claudePath: path)
            if Task.isCancelled { return }
            connectServices.returnToApp()
            switch outcome {
            case .done:
                let status = await claudeDetector.detect()
                if Task.isCancelled { return }
                claudeStatus = status
                claudeSetup = status.isReady ? .idle : .failed(.signInFailed(detail: ""))
            case .offline, .timedOut: claudeSetup = .failed(.signInTimedOut)
            case .cancelled: claudeSetup = .idle
            case .failed(let detail): claudeSetup = .failed(.signInFailed(detail: detail))
            }
        }
    }

    /// «Ya inicié sesión, comprobar»: se mira ya, sin esperar a que `claude auth login` se entere. Si hay
    /// sesión, se sigue; si no, la espera continúa como estaba.
    func confirmClaudeSignIn() async {
        guard claudeSetup == .signingIn else { return }
        let status = await claudeDetector.detect()
        guard claudeSetup == .signingIn, status.isReady else { return }
        claudeSetupTask?.cancel()
        claudeSetupTask = nil
        claudeStatus = status
        claudeSetup = .idle
    }

    /// «Cancelar» mientras se espera el navegador, y «Entendido» tras un fallo.
    func cancelClaudeSetup() {
        claudeSetupTask?.cancel()
        claudeSetupTask = nil
        claudeSetup = .idle
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

    /// Si el usuario dio algo en «Darle contexto»: una línea del proyecto o algún archivo.
    var hasContext: Bool {
        !projectDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !contextItems.isEmpty
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

    /// Lo que el rol trae de fábrica: sus skills y, si el usuario todavía no eligió herramientas por su cuenta,
    /// las tres primeras de su orden. Al crear un agente; en «Gestionar» manda lo que el agente ya tiene.
    private func applyRoleDefaults() {
        guard mode != .edit else { return }
        if case .loaded(let catalog) = skillCatalog {
            // Solo si el rol cambió: al volver a pasar por aquí con el mismo, lo que el usuario marcó en «Skills» se queda.
            if skillsRole != role || !skillsInitialized {
                skills = catalog.defaultSelection(for: role)
                skillsInitialized = true
                skillsRole = role
            }
        } else {
            loadSkillCatalog()
        }
        let chosen = connections.map(\.tool)
        guard chosen.isEmpty || Set(chosen) == Set(rolePreselection) else {
            // Lo que el usuario ya eligió se queda; solo cambia el orden, que es el del rol.
            let order = toolsInRoleOrder
            connections.sort { order.firstIndex(of: $0.tool)! < order.firstIndex(of: $1.tool)! }
            return
        }
        let preselected = role.preselectedTools.filter { !$0.isComingSoon }
        connections = []
        for tool in preselected where !isSelected(tool) { toggle(tool) }
        rolePreselection = connections.map(\.tool)
    }

    /// Las herramientas que se ofrecen, en el orden del rol: es también el orden en que se conectan.
    var toolsInRoleOrder: [Tool] { role.ordered(Tool.allCases) }

    /// Marca o desmarca. Al marcar una herramienta se marcan también las que
    /// necesita; las que otra necesita no se desmarcan.
    func toggle(_ tool: Tool) {
        if isSelected(tool) {
            guard !isRequiredBySelection(tool) else { return }
            connections.removeAll { $0.tool == tool }
        } else {
            for needed in tool.requires + [tool] where !isSelected(needed) {
                if let known = knownConnections[needed], known.status == .connected {
                    connections.append(
                        ToolConnection(
                            tool: needed, status: .connected,
                            sources: needed.selectableSourceKinds.isEmpty ? .everything : .nothing,
                            oauthClientID: known.oauthClientID, serverNamePrefix: known.serverNamePrefix))
                } else {
                    // Una conexión nueva se registra con el nombre propio de Galeno (`galeno-notion`): así lo que
                    // Galeno cierra o quita nunca es de otro proyecto del usuario.
                    connections.append(
                        ToolConnection(tool: needed, serverNamePrefix: MCPServerCatalog.defaultNamePrefix(for: needed)))
                }
            }
            // El orden de la grilla (el del rol), no el de los clics: es el de las conexiones del paso 4.
            let order = toolsInRoleOrder
            connections.sort { order.firstIndex(of: $0.tool)! < order.firstIndex(of: $1.tool)! }
        }
    }

    /// Las elegidas que todavía no están conectadas: lo que el paso 5 tiene que hacer. En el wizard completo son
    /// todas; en el corto, solo las que la instalación aún no tenía.
    var toConnect: [Tool] { connections.filter { $0.status != .connected }.map(\.tool) }
    var hasToConnect: Bool { !toConnect.isEmpty }

    /// "~X min" del pie de la grilla: solo lo que falta por conectar.
    var estimatedSetupMinutes: Int { ToolEstimate.minutes(for: toConnect) }

    // MARK: Paso 5: conectar

    /// Crea el sub-wizard (o conserva el que ya hay, si las herramientas son las mismas).
    func beginConnecting() {
        let pending = connections.filter { mode == .full || $0.status != .connected }.map(\.tool)
        let tools = ConnectTarget.connectionTools(from: pending)
        let claudePath = claudeStatus.path ?? "claude"
        // Si entre tanto se instaló o actualizó Claude Code, el sub-wizard viejo apunta a otro `claude`.
        let samePath = claudeStatus.path == nil || connectFlowClaudePath == claudePath
        if connectFlow != nil, connectFlowTools == tools, samePath { return }

        connectFlow?.cancelAll()
        connectFlowTools = tools
        connectFlowClaudePath = claudePath

        let flow = ConnectFlow(
            tools: pending,
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
            systemAuthorizer: connectServices.systemAuthorizer,
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
            claudePath = claudeStatus.path ?? "claude"
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
                skills = catalog.defaultSelection(for: role)
                skillsRole = role
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
        guard step == .generating, generation?.phase == .succeeded else { return }
        guard let following = step(after: step) else {
            // «Gestionar»: no hay «Listo»; se guardó y se vuelve al home.
            onSaved?()
            return
        }
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
    var claudePath: String { claudeStatus.path ?? "claude" }

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
            role: role,
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
