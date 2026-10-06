import Combine
import Foundation
import GalenoCore
import WebKit

/// A qué servidor o servidores se conecta una herramienta (sale del catálogo del motor).
struct ConnectTarget: Equatable {
    struct Server: Equatable {
        var name: String
        var url: String
    }

    /// Un conector de la cuenta de Claude del usuario (Gmail, Google Drive): no se registra con
    /// `claude mcp add`; Claude Code lo trae solo cuando el usuario lo tiene conectado en claude.ai.
    struct Connector: Equatable {
        /// Como aparece en Claude: «Google Drive».
        var name: String
        /// Su página en el directorio de conectores de Claude (`google-drive-drivemcp`).
        var directorySlug: String
        /// Como lo nombra Claude Code en una sesión y en `claude mcp login`.
        var serverName: String { "claude.ai " + name }
        /// La página del conector en Claude: ahí está su botón «Conectar».
        var directoryURL: URL { URL(string: "https://claude.ai/directory/" + directorySlug)! }
    }

    var tool: Tool
    var servers: [Server]
    /// «Google Drive, Docs y Sheets» son tres; Gmail y Google Calendar, uno.
    var connectors: [Connector]

    /// Slack, Gmail y Google Workspace exigen una app OAuth del propio cliente
    /// (`docs/03` §4e). Crearla es el paso siguiente de la fase; hasta entonces
    /// estas herramientas no se conectan aquí. **Es el punto de entrada**: cuando
    /// exista ese paso, aquí se sustituye "todavía no" por crear la app y registrar
    /// el servidor con su `client_id` (y el secreto por `MCP_CLIENT_SECRET`,
    /// nunca en los argumentos).
    var requiresOwnOAuthApp: Bool { tool.requiresUserProvidedOAuthClient }

    /// Slack ya se conecta aquí (guía + token + `apps.manifest.create`); Gmail y Google
    /// Workspace todavía no.
    var supportsOwnApp: Bool { tool == .slack }

    /// Claude Design no tiene OAuth propio: entra con la sesión de Claude Code. `claude mcp login`
    /// responde que no hay nada que autorizar, así que tras registrarlo solo se comprueba el estado.
    var usesClaudeCodeSession: Bool { tool == .claudeDesign }

    /// `nil` para las herramientas que no se conectan con `claude mcp add`: WhatsApp
    /// (su propio bridge) y Google Meet (se lee por Drive y no tiene servidor).
    ///
    /// `namePrefix`: el nombre alternativo (`galeno-`) cuando el normal ya lo ocupa otro servidor
    /// del usuario. Es el mismo que usa el motor para `.mcp.json` y los permisos.
    init?(tool: Tool, namePrefix: String? = nil) {
        let connection = ToolConnection(tool: tool, serverNamePrefix: namePrefix)
        let definitions = MCPServerCatalog.definitions(for: connection, whatsAppBridgePath: "")
        let servers = definitions.compactMap { definition -> Server? in
            guard case .http(let url) = definition.transport else { return nil }
            return Server(name: definition.serverName, url: url)
        }
        let connectors = definitions.compactMap { definition -> Connector? in
            guard case .claudeConnector(let name, let slug) = definition.transport else { return nil }
            return Connector(name: name, directorySlug: slug)
        }
        guard !servers.isEmpty || !connectors.isEmpty else { return nil }
        self.tool = tool
        self.servers = servers
        self.connectors = connectors
    }

    /// Las herramientas que tienen una pantalla de conexión, en el orden dado.
    static func connectionTools(from tools: [Tool]) -> [Tool] {
        tools.filter { $0 == .whatsapp || ConnectTarget(tool: $0) != nil }
    }
}

/// El sub-wizard del paso 5: una conexión por pantalla, con pantallas de dopamina
/// intercaladas y una celebración al final (`docs/03` §3).
///
/// Es una máquina de estados sin interfaz: las vistas solo la leen y le piden
/// `connect()`, `skip()`, `retry()`. El tiempo se inyecta (`sleep`) para que las
/// pruebas no esperen de verdad.
@MainActor
final class ConnectFlow: ObservableObject {
    // MARK: - Tipos

    enum Dopamine: String, Equatable, CaseIterable {
        case first, half, last
    }

    enum Screen: Equatable {
        case connection(Tool)
        case dopamine(Dopamine)
        case celebration
    }

    /// Qué está haciendo la app mientras el usuario espera.
    enum Step: Equatable {
        case checking
        case registering
        case waitingForBrowser
        /// El conector no está en la cuenta de Claude del usuario: se abrió el directorio para que lo conecte.
        case addingConnector
        case preparingBridge
        case checkingLink
        case installingSync
        case validatingToken
        case creatingSlackApp
        case removingServer
    }

    enum Failure: Equatable {
        case couldNotRegister
        case notAuthorizedInTime
        case loginFailed
        case stillNotConnected
        case bridgeMissing
        case bridgeFailed
        case qrExpired
        /// Slack no aceptó el token de configuración.
        case tokenRejected
        /// Slack no dejó crear la app: casi siempre falta la aprobación de un administrador.
        case slackNotAllowed
        case slackManifest
        case slackUnreachable
        /// Ni siquiera el nombre alternativo está libre: ya hay otro servidor con él.
        case nameInUse
        /// El usuario pidió borrar el servidor que estorbaba y Claude Code no pudo.
        case couldNotRemove
        /// Slack ya no conoce la app a la que apunta el registro (alguien la borró).
        case slackAppMissing
        /// Autorizó, pero Slack dice que la app no tiene activado el servidor MCP. El detalle es la
        /// página donde se activa (`api.slack.com/apps/<id>/app-assistant`).
        case slackMCPNotEnabled
        /// El `claude` de este Mac no tiene `claude mcp login`: es anterior a la versión mínima.
        case claudeOutdated
    }

    enum Phase: Equatable {
        /// Esperando a que el usuario pulse Conectar (o acepte la advertencia de WhatsApp).
        case ready
        case working(Step)
        /// WhatsApp: el QR a escanear. `nil` hasta que el bridge lo escribe.
        case qr(Data?)
        /// WhatsApp: el historial está bajando. `chats` son los que ya aparecieron.
        case syncing(chats: Int)
        case succeeded(alreadyConnected: Bool)
        case failed(Failure)
        /// Slack: falta el token de configuración que el usuario genera y pega.
        case slackToken
        /// Necesita la app OAuth del cliente: todavía no se puede conectar aquí.
        case needsOwnApp
        /// Ya hay otro servidor con el nombre normal. Se le pregunta al usuario qué prefiere.
        case nameConflict(server: String)
        /// Eligió borrarlo: se le dice qué se borra y se confirma. Nunca se borra sin esto.
        case confirmingRemoval(server: String)
    }

    /// Lo que se cuenta de cada herramienta, para el mensaje de éxito y los totales.
    enum Noun: String, CaseIterable, Equatable {
        case channels, projects, labels, meetings, groups

        /// En inglés porque es lo que se le pide a Claude Code que cuente.
        var promptWord: String { rawValue }
    }

    struct Finding: Equatable {
        var noun: Noun
        var count: ItemCount
    }

    // MARK: - Estado

    @Published private(set) var position = 0
    @Published private(set) var phase: Phase = .ready
    @Published private(set) var findings: [Tool: Finding] = [:]
    @Published private(set) var statuses: [Tool: ConnectionStatus]
    /// Por qué falló lo último, en las palabras del programa que falló. Para el detalle.
    @Published private(set) var failureDetail = ""
    /// Las herramientas cuyo dato real todavía se está buscando.
    @Published private(set) var pendingData: Set<Tool> = []

    let tools: [Tool]
    let screens: [Screen]

    var screen: Screen { screens[min(position, screens.count - 1)] }
    var isFinished: Bool { screen == .celebration }

    /// "N de M conectadas".
    var total: Int { tools.count }
    var connectedCount: Int { tools.filter { statuses[$0] == .connected }.count }

    /// La primera conexión, con nada conectado todavía: aún se puede volver a elegir
    /// herramientas sin perder nada.
    var canReturnToToolSelection: Bool {
        guard position == 0, connectedCount == 0 else { return false }
        switch phase {
        case .ready, .failed, .needsOwnApp, .slackToken, .nameConflict, .confirmingRemoval: return true
        default: return false
        }
    }

    /// Los totales de la celebración: lo que se encontró, sumado por tipo.
    var totals: [(noun: Noun, count: ItemCount)] {
        Noun.allCases.compactMap { noun in
            let matching = findings.values.filter { $0.noun == noun }
            guard !matching.isEmpty else { return nil }
            return (noun, ItemCount(
                value: matching.reduce(0) { $0 + $1.count.value },
                isPartial: matching.contains { $0.count.isPartial }))
        }
    }

    // MARK: - Servicios y tiempos

    typealias Sleeper = @Sendable (Duration) async -> Void

    struct Timing {
        /// Lo que se ve el éxito antes de pasar a la siguiente (`docs/03` §3).
        var successHold: Double = 1.5
        /// Si el dato real sigue sin llegar, se espera hasta aquí (en total) y se avanza igual.
        var dataWaitMax: Double = 4
        var dopamineHold: Double = 3
        var syncPoll: Double = 3
        /// Lecturas seguidas sin cambio para dar la sincronización por estable.
        var syncStableReads = 3
        var syncMax: Double = 180
        /// Cada cuánto se mira si el conector de Claude ya quedó conectado, y hasta cuándo.
        var connectorPoll: Double = 3
        var connectorMax: Double = 300
        /// Cuántas veces más se mira un conector que al arrancar la sesión seguía «pendiente» antes de darlo
        /// por conectado (y las veces seguidas que debe verse así tras abrir el navegador).
        var connectorPendingLooks: Int = 3
        /// Lo que Galeno se queda al frente tras un conector, antes de abrir el navegador para el siguiente.
        var connectorPause: Double = 1.2
    }

    private let mcp: any MCPConnecting
    private let whatsapp: any WhatsAppLinking
    private let slack: any SlackAppSetting
    private let agentName: @MainActor () -> String
    private let fetchRealData: Bool
    private let sleep: Sleeper
    private let timing: Timing
    private let onStatus: @MainActor (Tool, ConnectionStatus) -> Void
    private let onClientID: @MainActor (Tool, String) -> Void
    private let onNamePrefix: @MainActor (Tool, String?) -> Void
    private let authorizer: (any SlackAuthorizationPresenting)?
    /// La hoja de autenticación del sistema, para las herramientas que se autorizan en el navegador (Notion, Jira,
    /// las de reuniones). `nil` (pruebas y conectores falsos) = se abre el navegador del sistema, como antes.
    private let systemAuthorizer: (any SystemAuthorizationPresenting)?
    private let language: @MainActor () -> Language
    /// Trae Galeno al frente cuando el usuario termina de autorizar en su navegador: la pestaña se
    /// queda allá, pero él vuelve solo al asistente.
    private let returnToApp: @MainActor () -> Void
    /// Abre una dirección en el navegador del sistema (el directorio de conectores de Claude).
    private let openURL: @MainActor (URL) -> Void
    /// La sesión efímera de Slack, compartida entre la ventana de inicio de sesión y la de
    /// autorización. Se descarta cuando termina la conexión.
    let webSession = SlackWebSession()
    /// El identificador (público) de la app de Slack que se acaba de crear, para llevar al usuario
    /// a su configuración al final. `nil` si no se creó en esta sesión.
    @Published private(set) var slackAppID: String?
    /// El conector de la cuenta de Claude que se está conectando ahora (`nil` fuera de ese proceso).
    @Published private(set) var connectorProgress: ConnectorProgress?
    /// Qué pasó con el último «Ya lo conecté, comprobar» de un conector de la cuenta de Claude.
    enum ConnectorCheck: Equatable {
        /// Se espera a que el usuario termine en el navegador.
        case waiting
        /// Pulsó «comprobar» y se está mirando.
        case checking
        /// Se miró y todavía no aparece conectado: la espera sigue.
        case notYet
    }

    @Published private(set) var connectorCheck: ConnectorCheck = .waiting
    /// El conector cuya página está abierta en el navegador, para poder abrirla otra vez.
    private var openConnector: ConnectTarget.Connector?
    /// El usuario dijo «ya lo conecté»: la próxima mirada es inmediata y con una lectura nueva.
    private var connectorConfirmRequested = false
    /// Lo que se conectó o se saltó en esta pasada: al avanzar no se vuelve a enseñar.
    private var resolvedHere: Set<Tool> = []
    private var seenDopamine: Set<Dopamine> = []
    /// Las herramientas que se registran con el nombre alternativo (`galeno-slack`).
    private var namePrefixes: [Tool: String]

    /// Slack rechazó el último token: la próxima vez hay que generar uno nuevo, no reusar el que
    /// siga a la vista en la página.
    @Published private(set) var slackNeedsFreshToken = false

    /// La app de Slack ya se creó y se registró en Claude Code: si falla después, reintentar
    /// no debe crear **otra** app (el secreto no se guarda), solo volver a autorizar.
    private var slackAppRegistered = false

    private var workTask: Task<Void, Never>?
    private var advanceTask: Task<Void, Never>?
    private var dataTasks: [Tool: Task<Void, Never>] = [:]
    private var latestChatCounts: ChatCounts?

    init(
        tools: [Tool],
        statuses: [Tool: ConnectionStatus] = [:],
        mcp: any MCPConnecting,
        whatsapp: any WhatsAppLinking,
        slack: any SlackAppSetting = SlackAppSetupService(),
        agentName: @escaping @MainActor () -> String = { "" },
        fetchRealData: Bool = true,
        timing: Timing = Timing(),
        sleep: @escaping Sleeper = { _ = try? await Task.sleep(for: $0) },
        onStatus: @escaping @MainActor (Tool, ConnectionStatus) -> Void = { _, _ in },
        onClientID: @escaping @MainActor (Tool, String) -> Void = { _, _ in },
        namePrefixes: [Tool: String] = [:],
        onNamePrefix: @escaping @MainActor (Tool, String?) -> Void = { _, _ in },
        authorizer: (any SlackAuthorizationPresenting)? = nil,
        systemAuthorizer: (any SystemAuthorizationPresenting)? = nil,
        language: @escaping @MainActor () -> Language = { .spanish },
        returnToApp: @escaping @MainActor () -> Void = {},
        openURL: @escaping @MainActor (URL) -> Void = { _ in }
    ) {
        self.openURL = openURL
        self.authorizer = authorizer
        self.systemAuthorizer = systemAuthorizer
        self.language = language
        self.returnToApp = returnToApp
        let connectionTools = ConnectTarget.connectionTools(from: tools)
        self.tools = connectionTools
        self.statuses = statuses
        self.mcp = mcp
        self.whatsapp = whatsapp
        self.slack = slack
        self.agentName = agentName
        self.fetchRealData = fetchRealData
        self.timing = timing
        self.sleep = sleep
        self.onStatus = onStatus
        self.onClientID = onClientID
        self.namePrefixes = namePrefixes
        self.onNamePrefix = onNamePrefix
        self.screens = Self.makeSequence(connectionTools)

        // Si se vuelve a este paso, se sigue por la primera sin resolver.
        position = screens.firstIndex { screen in
            if case .connection(let tool) = screen { return statuses[tool] ?? .selected == .selected }
            return false
        } ?? screens.count - 1
        enter(screen)
    }

    // MARK: - La secuencia

    /// Las pantallas del sub-wizard: una por conexión, las de dopamina intercaladas y la
    /// celebración al final. Las de dopamina van tras las 2 primeras, a la mitad y antes de
    /// la última, nunca pegadas una a otra ni justo antes de la celebración sin motivo
    /// (`docs/03` §3: "cada 2–3 conexiones").
    nonisolated static func makeSequence(_ tools: [Tool]) -> [Screen] {
        let count = tools.count
        var slots: [Int: Dopamine] = [:]
        var lastSlot = -10
        // Con 1 o 2 conexiones no hay nada que romper: el proceso es corto.
        for (slot, kind) in [(2, Dopamine.first), ((count + 1) / 2, .half), (count - 1, .last)]
        where count >= 3 && slot >= 1 && slot <= count - 1 && slot - lastSlot >= 2 {
            slots[slot] = kind
            lastSlot = slot
        }

        var screens: [Screen] = []
        for (index, tool) in tools.enumerated() {
            screens.append(.connection(tool))
            if let kind = slots[index + 1] { screens.append(.dopamine(kind)) }
        }
        screens.append(.celebration)
        return screens
    }

    private func enter(_ screen: Screen) {
        cancelWork()
        failureDetail = ""
        switch screen {
        case .connection(let tool):
            if statuses[tool] == .connected {
                phase = .succeeded(alreadyConnected: true)
                scheduleAdvance(after: timing.successHold, waitingFor: nil)
            } else if let target = target(for: tool), target.requiresOwnOAuthApp {
                if target.supportsOwnApp {
                    // Puede que la app ya exista de una vez anterior: se mira antes de pedir
                    // un token nuevo (y de crear una segunda app).
                    phase = .working(.checking)
                    workTask = Task { [weak self] in await self?.resolveSlackStart(target) }
                } else {
                    phase = .needsOwnApp
                }
            } else {
                phase = .ready
            }
        case .dopamine(let kind):
            seenDopamine.insert(kind)
            phase = .ready
            scheduleAdvance(after: timing.dopamineHold, waitingFor: nil)
        case .celebration:
            phase = .ready
        }
    }

    func advance() {
        guard position < screens.count - 1 else { return }
        let last = screens.count - 1
        var next = position + 1
        // Con la tira se puede ir de una conexión a otra en cualquier orden: lo que ya se resolvió en esta
        // pasada (y la pausa que ya se vio) no se vuelve a enseñar…
        while next < last, isBehindUs(screens[next]) { next += 1 }
        // …y antes de celebrar se vuelve por lo que quedó sin resolver.
        if next == last, let pending = screens.firstIndex(where: isUnresolved) { next = pending }
        position = next
        enter(screen)
    }

    private func isBehindUs(_ screen: Screen) -> Bool {
        switch screen {
        case .connection(let tool): resolvedHere.contains(tool)
        case .dopamine(let kind): seenDopamine.contains(kind)
        case .celebration: false
        }
    }

    private func isUnresolved(_ screen: Screen) -> Bool {
        if case .connection(let tool) = screen { return (statuses[tool] ?? .selected) == .selected }
        return false
    }

    /// ¿Se puede ir a esa conexión pulsando su icono en la tira? A cualquiera que no esté ya conectada,
    /// desde los mismos momentos en que se puede «Conectar después» (demo de Aquiles, 5 oct 2026: quiso
    /// pasar de una a otra pulsando los iconos).
    func canJump(to tool: Tool) -> Bool {
        guard case .connection(let current) = screen, current != tool, tools.contains(tool),
            statuses[tool] != .connected
        else { return false }
        switch phase {
        case .ready, .working, .qr, .slackToken, .failed, .needsOwnApp, .nameConflict: return true
        case .syncing, .succeeded, .confirmingRemoval: return false
        }
    }

    /// Va a la conexión de esa herramienta. La que se deja a medias no se marca como saltada: sigue por
    /// conectar, y se vuelve a ella antes de terminar.
    func jump(to tool: Tool) {
        guard canJump(to: tool), let index = screens.firstIndex(of: .connection(tool)) else { return }
        cancelWork()
        authorizer?.dismissAuthorization()
        systemAuthorizer?.dismiss()
        webSession.reset()
        position = index
        enter(screen)
    }

    // MARK: - Acciones del usuario

    /// "Conectar" (o "Continuar", tras la advertencia de WhatsApp).
    func connect() {
        guard case .connection(let tool) = screen else { return }
        cancelWork()
        failureDetail = ""
        workTask = Task { [weak self] in
            if tool == .whatsapp {
                await self?.linkWhatsApp()
            } else if let target = self?.target(for: tool) {
                if !target.connectors.isEmpty {
                    await self?.connectClaudeConnectors(target)
                } else {
                    await self?.connectHosted(target)
                }
            }
        }
    }

    func retry() {
        // Si la app de Slack aún no se creó, reintentar es volver a pedir el token (el anterior
        // pudo vencer). Si ya se creó y registró, solo falta autorizar.
        if case .connection(.slack) = screen, !slackAppRegistered {
            cancelWork()
            failureDetail = ""
            phase = .slackToken
            return
        }
        connect()
    }

    /// "Conectar después" y "Saltar por ahora": la herramienta queda marcada para
    /// conectarla más tarde desde la app.
    func skip() {
        guard case .connection(let tool) = screen else { return }
        cancelWork()
        authorizer?.dismissAuthorization()
        systemAuthorizer?.dismiss()
        webSession.reset()
        setStatus(tool, .skipped)
        advance()
    }

    /// «Continuar» tras un éxito: no hace falta esperar a que la pantalla avance sola.
    func continueFromSuccess() {
        guard case .succeeded = phase else { return }
        advance()
    }

    func continueFromDopamine() {
        guard case .dopamine = screen else { return }
        advance()
    }

    // MARK: - Conectores de la cuenta de Claude (Gmail, Google Drive, Docs, Sheets, Calendar)

    /// Qué conector se está conectando ahora, para decírselo al usuario («Google Docs · 2 de 3»).
    struct ConnectorProgress: Equatable {
        var name: String
        var index: Int
        var total: Int
    }

    /// Google no se conecta con una app propia: sus servidores siguen en Developer Preview (inscripción con
    /// aprobación de días, solo cuentas de Workspace). Se usan los conectores de la cuenta de Claude del
    /// usuario, que Claude Code trae solos. Para cada uno, tres casos:
    ///
    /// 1. Ya está conectado: no hay nada que hacer.
    /// 2. Está en su cuenta pero sin autorizar: `claude mcp login` abre la página de permiso.
    /// 3. No está en su cuenta, o no se pudo saber cómo está: se abre la página del conector en Claude, que
    ///    dice su estado de verdad, y el usuario pulsa «Conectar» y «Permitir».
    ///
    /// El estado se lee de una sesión real (`connectorStatus`): `claude mcp get` da por conectado un
    /// conector al que le falta la autorización. En 2 y 3 Claude Code no avisa cuando el usuario termina:
    /// se vuelve a mirar cada pocos segundos. Galeno vuelve al frente al terminar **cada** conector.
    ///
    /// **Solo cuenta un «conectado» de verdad.** El tiempo que pase nunca marca nada: en el demo de Aquiles
    /// (5 oct 2026) un conector se dio por conectado mientras él seguía eligiendo cuenta de Google, porque
    /// tres lecturas `pending` seguidas contaban. La única otra salida la da el usuario: «Ya lo conecté,
    /// comprobar» (`confirmConnector`), y ahí `pending` sí vale, porque es él quien lo afirma.
    private func connectClaudeConnectors(_ target: ConnectTarget) async {
        defer {
            connectorProgress = nil
            openConnector = nil
        }
        var usedBrowser = false

        for (index, connector) in target.connectors.enumerated() {
            connectorProgress = ConnectorProgress(name: connector.name, index: index + 1, total: target.connectors.count)
            connectorConfirmRequested = false
            connectorCheck = .waiting
            update(.working(.checking))
            var current = await mcp.connectorStatus(connector.serverName)
            if Task.isCancelled { return }
            // «Pendiente» es que el conector aún se estaba conectando al arrancar la sesión: se le dan unas
            // miradas más antes de abrir nada (así un conector lento que ya estaba bien no abre el navegador).
            var looks = 0
            while current == .pending || current == .failed, looks < timing.connectorPendingLooks {
                await sleep(.seconds(timing.connectorPoll))
                current = await mcp.connectorStatus(connector.serverName)
                if Task.isCancelled { return }
                looks += 1
            }
            if current == .connected { continue }

            usedBrowser = true
            openConnector = connector
            if current == .needsAuthentication {
                update(.working(.waitingForBrowser))
                do {
                    try await mcp.authorizeConnector(connector.serverName)
                } catch {
                    if Task.isCancelled { return }
                    if let error = error as? MCPConnectError {
                        if error == .claudeOutdated { return fail(.claudeOutdated) }
                        if case .loginFailed(let detail) = error { failureDetail = detail }
                    }
                    fail(.loginFailed)
                    return
                }
            } else {
                // No está en la cuenta, o sigue sin saberse: su página en Claude lo dice y tiene el botón.
                update(.working(.addingConnector))
                openURL(connector.directoryURL)
            }

            var connected = false
            var waited = 0.0
            while waited < timing.connectorMax {
                waited += await waitForNextLook()
                if Task.isCancelled { return }
                let confirmed = connectorConfirmRequested
                let status =
                    confirmed
                    ? await mcp.freshConnectorStatus(connector.serverName)
                    : await mcp.connectorStatus(connector.serverName)
                if Task.isCancelled { return }
                if status == .connected || (confirmed && status == .pending) {
                    connected = true
                    break
                }
                if confirmed {
                    connectorConfirmRequested = false
                    connectorCheck = .notYet
                }
            }
            if Task.isCancelled { return }
            openConnector = nil
            connectorCheck = .waiting
            guard connected else {
                fail(.notAuthorizedInTime)
                return
            }
            // Cada conector que termina en el navegador trae a Galeno al frente (decisión de Rafa, 4 oct
            // 2026): con tres seguidos (Drive, Docs, Sheets) el usuario ve que uno quedó antes de que se
            // abra el siguiente, en vez de quedarse en el navegador sin saber si ya puede volver.
            returnToApp()
            if index < target.connectors.count - 1 {
                update(.working(.checking))
                await sleep(.seconds(timing.connectorPause))
                if Task.isCancelled { return }
            }
        }

        finishHosted(target, alreadyConnected: !usedBrowser)
    }

    /// Espera hasta la próxima mirada, en tramos cortos: si el usuario pulsa «Ya lo conecté», no espera más.
    /// Devuelve lo que esperó.
    private func waitForNextLook() async -> Double {
        let slice = 0.5
        var waited = 0.0
        while waited < timing.connectorPoll, !connectorConfirmRequested, !Task.isCancelled {
            await sleep(.seconds(slice))
            waited += slice
        }
        return waited
    }

    /// ¿Se está esperando a que el usuario termine un conector en el navegador?
    var isWaitingForConnector: Bool {
        guard openConnector != nil else { return false }
        return phase == .working(.addingConnector) || phase == .working(.waitingForBrowser)
    }

    /// «Ya lo conecté, comprobar»: se mira ahora mismo, con una lectura nueva.
    func confirmConnector() {
        guard isWaitingForConnector, connectorCheck != .checking else { return }
        connectorCheck = .checking
        connectorConfirmRequested = true
    }

    /// «Abrir la página otra vez»: la del conector en Claude, por si se cerró o nunca se abrió.
    func reopenConnectorPage() {
        guard isWaitingForConnector, let openConnector else { return }
        openURL(openConnector.directoryURL)
    }

    // MARK: - Servidores MCP hospedados

    private func connectHosted(_ target: ConnectTarget, oauth: OAuthClientRegistration? = nil) async {
        // Cada herramienta hospedada que se conecta aquí tiene un servidor; Google
        // Workspace, que tiene tres, entra con el paso de su app OAuth.
        guard let server = target.servers.first else { return }
        update(.working(.checking))

        let current = await mcp.status(of: server.name, expectingURL: server.url)
        if Task.isCancelled { return }

        switch current {
        case .connected:
            finishHosted(target, alreadyConnected: true)
            return
        case .differentServer:
            // Ya hay un servidor con ese nombre que no es el nuestro (por ejemplo uno local de
            // `npx`): ni se pisa, ni se borra, ni se da por conectado.
            resolveNameConflict(target, server: server)
            return
        case .notRegistered:
            // Una herramienta con app OAuth propia no se registra a ciegas: sin su app no hay
            // `client_id` y el OAuth fallaría.
            if target.requiresOwnOAuthApp && oauth == nil {
                update(target.supportsOwnApp ? .slackToken : .needsOwnApp)
                return
            }
            update(.working(.registering))
            do { try await mcp.register(server: server.name, url: server.url, oauth: oauth) } catch {
                if let error = error as? MCPConnectError, case .registerFailed(let detail) = error {
                    failureDetail = detail
                }
                fail(.couldNotRegister)
                return
            }
            if Task.isCancelled { return }
            if oauth != nil { slackAppRegistered = true }
        case .needsAuthentication, .failed, .pending:
            break
        }

        // Un servidor que entra con la sesión de Claude Code (Claude Design) no abre ningún navegador:
        // si ya responde, está conectado; si no, falta iniciar sesión en Claude Code.
        if target.usesClaudeCodeSession {
            update(.working(.checking))
            let status = await mcp.status(of: server.name, expectingURL: server.url)
            if Task.isCancelled { return }
            if status == .connected {
                finishHosted(target, alreadyConnected: false)
            } else {
                failureDetail = await mcp.issue(of: server.name) ?? ""
                fail(.stillNotConnected)
            }
            return
        }

        update(.working(.waitingForBrowser))
        // Con la app propia de Slack, la autorización se muestra en la ventana de Galeno (con la
        // sesión que ya tiene) y se cierra sola. Las demás herramientas van al **navegador predeterminado**
        // del usuario (decisión de Rafa, 5 oct 2026: la hoja del sistema usa la sesión de Safari y las
        // cuentas de verdad pueden vivir en otro navegador; a Aquiles lo conectó al workspace equivocado).
        // `systemAuthorizer` queda como gancho para las pruebas; en producción llega `nil` y `claude mcp
        // login` abre el navegador él mismo. La pestaña queda abierta; Galeno vuelve al frente al terminar.
        let usesOwnWindow = target.requiresOwnOAuthApp && authorizer != nil
        let opener: AuthorizationOpener?
        if usesOwnWindow {
            opener = { @MainActor [weak self] url in self?.showAuthorization(url) ?? false }
        } else if let systemAuthorizer {
            opener = { @MainActor [weak self] url in
                systemAuthorizer.present(url: url) { self?.authorizationWindowClosedByUser() }
            }
        } else {
            opener = nil
        }
        defer {
            authorizer?.dismissAuthorization()
            systemAuthorizer?.dismiss()
        }
        do {
            try await mcp.login(server: server.name, openAuthorization: opener)
        } catch let error as MCPConnectError {
            if Task.isCancelled || error == .cancelled { return }
            switch error {
            case .loginTimedOut: fail(.notAuthorizedInTime)
            case .notConnectedAfterLogin: fail(.stillNotConnected)
            case .claudeOutdated: fail(.claudeOutdated)
            case .loginFailed(let detail):
                failureDetail = detail
                fail(.loginFailed)
            default: fail(.loginFailed)
            }
            return
        } catch {
            fail(.loginFailed)  // si se canceló, `fail` no escribe nada
            return
        }
        if Task.isCancelled { return }
        // Autorizó en su navegador: se cierra la hoja y se le trae de vuelta. (Con la ventana propia de Slack
        // nunca salió de Galeno.)
        if !usesOwnWindow {
            systemAuthorizer?.dismiss()
            returnToApp()
        }

        // Con una app propia, «autorizado» no basta: Slack puede aceptar el inicio de sesión y
        // rechazar luego la conexión (la app sin el MCP activado). Se comprueba antes de decir
        // que está conectado.
        if target.requiresOwnOAuthApp {
            update(.working(.checking))
            if await mcp.status(of: server.name) != .connected {
                if Task.isCancelled { return }
                let issue = await mcp.issue(of: server.name)
                if let url = Self.slackMCPSettingsURL(fromIssue: issue) {
                    failureDetail = url.absoluteString
                    fail(.slackMCPNotEnabled)
                } else {
                    failureDetail = issue ?? ""
                    fail(.stillNotConnected)
                }
                return
            }
            if Task.isCancelled { return }
        }
        finishHosted(target, alreadyConnected: false)
    }

    /// Slack dice, en el error, dónde activar el MCP: `…/apps/A0123ABCD/app-assistant`. Se
    /// reconstruye la dirección solo con el identificador de la app: nunca se abre una dirección
    /// que venga tal cual del texto.
    nonisolated static func slackMCPSettingsURL(fromIssue issue: String?) -> URL? {
        guard let issue, issue.lowercased().contains("not enabled for slack mcp") else { return nil }
        let cleaned = issue.replacingOccurrences(of: "\\", with: "")
        guard let range = cleaned.range(of: #"api\.slack\.com/apps/(A[A-Z0-9]{5,})/app-assistant"#, options: .regularExpression)
        else { return nil }
        let path = cleaned[range]
        guard let id = path.split(separator: "/").dropFirst(2).first else { return nil }
        return URL(string: "https://api.slack.com/apps/\(id)/app-assistant")
    }

    // MARK: - La autorización de Slack en la ventana de Galeno

    /// `claude` quiere abrir la página de autorización: se muestra aquí, solo si es de Slack.
    /// `false` = no se mostró, y se abre en el navegador del sistema como siempre.
    private func showAuthorization(_ url: URL) -> Bool {
        guard let authorizer, SlackAuthorization.isSlackAuthorizationURL(url) else { return false }
        authorizer.presentAuthorization(
            url: url, dataStore: webSession.dataStore, language: language(),
            onCancel: { [weak self] in self?.authorizationWindowClosedByUser() },
            onAppNotFound: { [weak self] in self?.slackAppIsGone() })
        return true
    }

    /// Slack contestó «Invalid client_id»: la app ya no existe. Se deja de esperar la autorización
    /// y se le explica al usuario, con la opción de rehacerla.
    private func slackAppIsGone() {
        guard case .working(.waitingForBrowser) = phase else { return }
        cancelWork()
        failureDetail = ""
        slackAppRegistered = false
        phase = .failed(.slackAppMissing)
    }

    /// «Crear la app de nuevo»: el usuario lo pidió desde el aviso. Quita de Claude Code el
    /// registro que apunta a la app borrada (el que Galeno creó) y vuelve a empezar por el token.
    func recreateSlackApp() {
        guard case .failed(.slackAppMissing) = phase, let target = target(for: .slack),
            let server = target.servers.first
        else { return }
        cancelWork()
        failureDetail = ""
        phase = .working(.removingServer)
        workTask = Task { [weak self] in
            guard let self else { return }
            do { try await self.mcp.remove(server: server.name) } catch {
                if Task.isCancelled { return }
                if let error = error as? MCPConnectError, case .removeFailed(let detail) = error {
                    self.failureDetail = detail
                }
                self.fail(.couldNotRemove)
                return
            }
            if Task.isCancelled { return }
            self.slackAppID = nil
            self.restartCurrentConnection(.slack)
        }
    }

    /// El usuario cerró la ventana de autorización sin terminar: no se espera a que venza el tiempo.
    private func authorizationWindowClosedByUser() {
        guard case .working(.waitingForBrowser) = phase else { return }
        cancelWork()
        failureDetail = ""
        phase = .failed(.notAuthorizedInTime)
    }

    // MARK: - Un servidor con el mismo nombre

    /// El destino de una herramienta, con el nombre alternativo si ya se eligió.
    private func target(for tool: Tool) -> ConnectTarget? {
        ConnectTarget(tool: tool, namePrefix: namePrefixes[tool])
    }

    /// Hay otro servidor con ese nombre: se le pregunta al usuario. Si ya se estaba usando el nombre
    /// alternativo y también está ocupado, no se vuelve a preguntar: es un fallo.
    private func resolveNameConflict(_ target: ConnectTarget, server: ConnectTarget.Server) {
        if namePrefixes[target.tool] != nil {
            failureDetail = server.name
            fail(.nameInUse)
        } else {
            update(.nameConflict(server: server.name))
        }
    }

    /// "Usar otro nombre": el predeterminado. Nada se borra; Galeno registra el suyo como
    /// `galeno-<nombre>` y el motor genera todo con ese nombre.
    func useAlternateName() {
        guard case .connection(let tool) = screen, case .nameConflict = phase else { return }
        namePrefixes[tool] = MCPServerCatalog.ownedNamePrefix
        onNamePrefix(tool, MCPServerCatalog.ownedNamePrefix)
        restartCurrentConnection(tool)
    }

    /// "Borrar el existente…": todavía no borra nada, pide confirmación.
    func askToRemoveConflictingServer() {
        guard case .nameConflict(let server) = phase else { return }
        phase = .confirmingRemoval(server: server)
    }

    /// "Mejor no": vuelve a la pregunta.
    func cancelRemoval() {
        guard case .confirmingRemoval(let server) = phase else { return }
        phase = .nameConflict(server: server)
    }

    /// El usuario confirmó: se borra ese servidor de Claude Code y se conecta con el nombre normal.
    func removeConflictingServer() {
        guard case .connection(let tool) = screen, case .confirmingRemoval(let server) = phase else { return }
        cancelWork()
        failureDetail = ""
        phase = .working(.removingServer)
        workTask = Task { [weak self] in
            guard let self else { return }
            do { try await self.mcp.remove(server: server) } catch {
                if Task.isCancelled { return }
                if let error = error as? MCPConnectError, case .removeFailed(let detail) = error {
                    self.failureDetail = detail
                }
                self.fail(.couldNotRemove)
                return
            }
            if Task.isCancelled { return }
            self.namePrefixes[tool] = nil
            self.onNamePrefix(tool, nil)
            self.restartCurrentConnection(tool)
        }
    }

    /// Vuelve a empezar la conexión de esta pantalla (Slack revisa primero si ya hay app).
    private func restartCurrentConnection(_ tool: Tool) {
        if tool == .slack {
            enter(screen)
        } else {
            connect()
        }
    }

    // MARK: - Slack: la app OAuth del cliente

    /// ¿Un token de configuración de Slack, y no el refresh token? (`xoxe.xoxp-…` vs `xoxe-…`).
    nonisolated static func looksLikeSlackAccessToken(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("xoxe.xoxp-")
    }

    nonisolated static func looksLikeSlackRefreshToken(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("xoxe-") && !trimmed.hasPrefix("xoxe.xoxp-")
    }

    /// Al llegar a la pantalla de Slack: si ya está conectado (o registrado), no se pide nada.
    private func resolveSlackStart(_ target: ConnectTarget) async {
        guard let server = target.servers.first else { return }
        let current = await mcp.status(of: server.name, expectingURL: server.url)
        if Task.isCancelled { return }
        switch current {
        case .connected:
            finishHosted(target, alreadyConnected: true)
        case .differentServer:
            resolveNameConflict(target, server: server)
        case .needsAuthentication, .failed, .pending:
            // Registrado antes con su app: solo falta autorizar.
            slackAppRegistered = true
            update(.ready)
        case .notRegistered:
            update(.slackToken)
        }
    }

    /// El usuario pegó el token de configuración. Se envuelve en un `OAuthSecret` al instante, se
    /// usa una vez y se descarta: no se guarda en ninguna parte.
    func submitSlackToken(_ pasted: String) {
        submitSlackSecret(OAuthSecret(pasted.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    /// El token que capturó la ventana de inicio de sesión, ya envuelto: nunca fue un `String`
    /// en manos del flujo.
    func submitSlackSecret(_ token: OAuthSecret) {
        guard case .connection(.slack) = screen, let target = target(for: .slack) else {
            token.wipe()
            return
        }
        cancelWork()
        failureDetail = ""
        workTask = Task { [weak self] in await self?.setUpSlack(target, token: token) }
    }

    private func setUpSlack(_ target: ConnectTarget, token: OAuthSecret) async {
        defer { token.wipe() }
        let name = agentName()

        update(.working(.validatingToken))
        do { try await slack.validate(token: token, agentName: name) } catch {
            failSlack(error)
            return
        }
        if Task.isCancelled { return }

        update(.working(.creatingSlackApp))
        let registration: OAuthClientRegistration
        do { registration = try await slack.createApp(token: token, agentName: name) } catch {
            failSlack(error)
            return
        }
        token.wipe()  // ya no hace falta
        defer { registration.secret?.wipe() }
        if Task.isCancelled { return }

        // El `client_id` es público: es lo único que se conserva (va al `.mcp.json`).
        onClientID(.slack, registration.clientID)
        slackAppID = registration.appID
        await connectHosted(target, oauth: registration)
    }

    private func failSlack(_ error: any Error) {
        if Task.isCancelled { return }
        switch error as? SlackSetupError {
        case .tokenRejected(let code):
            failureDetail = code
            slackNeedsFreshToken = true
            fail(.tokenRejected)
        case .notAllowed(let code):
            failureDetail = code
            fail(.slackNotAllowed)
        case .invalidManifest(let messages):
            failureDetail = messages.joined(separator: "; ")
            fail(.slackManifest)
        case .unreachable(let description):
            failureDetail = description
            fail(.slackUnreachable)
        case .unexpected, .none:
            fail(.slackManifest)
        }
    }

    private func finishHosted(_ target: ConnectTarget, alreadyConnected: Bool) {
        if target.requiresOwnOAuthApp { webSession.reset() }  // la sesión de Slack no se guarda
        setStatus(target.tool, .connected)
        if fetchRealData, let server = target.servers.first, let noun = Self.noun(for: target.tool) {
            startDataFetch(for: target.tool, server: server.name, noun: noun)
        }
        update(.succeeded(alreadyConnected: alreadyConnected))
        scheduleAdvance(after: timing.successHold, waitingFor: target.tool)
    }

    /// El dato real corre en segundo plano: no frena el flujo. Lo que llegue tarde
    /// suma a los totales de la celebración.
    private func startDataFetch(for tool: Tool, server: String, noun: Noun) {
        pendingData.insert(tool)
        dataTasks[tool] = Task { [weak self] in
            guard let self else { return }
            let count = await self.mcp.countItems(server: server, noun: noun.promptWord)
            if Task.isCancelled { return }
            if let count { self.findings[tool] = Finding(noun: noun, count: count) }
            self.pendingData.remove(tool)
        }
    }

    // MARK: - WhatsApp

    private func linkWhatsApp() async {
        update(.working(.preparingBridge))
        do {
            try await whatsapp.prepare()
        } catch WhatsAppBridgeError.bridgeMissing {
            fail(.bridgeMissing)
            return
        } catch {
            failureDetail = String(describing: error)
            fail(.bridgeFailed)
            return
        }
        if Task.isCancelled { return }

        update(.working(.checkingLink))
        let state: WhatsAppLinkState
        do { state = try await whatsapp.linkState() } catch {
            fail(.bridgeFailed)
            return
        }
        if Task.isCancelled { return }

        if case .notLinked = state {
            update(.qr(nil))
            var linked = false
            for await event in whatsapp.pair() {
                switch event {
                case .qr(let image): update(.qr(image))
                case .succeeded: linked = true
                case .failed(let detail): failureDetail = detail
                }
            }
            if Task.isCancelled { return }
            guard linked else {
                fail(failureDetail.lowercased().contains("tiempo") ? .qrExpired : .bridgeFailed)
                return
            }
        }

        // Ya vinculado, sea ahora o antes: `sync` tiene que estar corriendo para que
        // lleguen los mensajes, y `install-launchd` es idempotente.
        update(.working(.installingSync))
        do { try await whatsapp.installLaunchd() } catch {
            fail(.bridgeFailed)
            return
        }
        if Task.isCancelled { return }

        setStatus(.whatsapp, .connected)
        await waitForInitialSync()
    }

    /// El bridge no dice cuándo terminó la sincronización inicial ni da progreso: se mira
    /// cuántos chats aparecen y se da por estable cuando deja de cambiar. Es una heurística.
    private func waitForInitialSync() async {
        var lastTotal = -1
        var stableReads = 0
        var elapsed = 0.0
        latestChatCounts = nil
        update(.syncing(chats: 0))

        while elapsed < timing.syncMax {
            if let counts = await whatsapp.chatCounts() {
                update(.syncing(chats: counts.total))
                stableReads = (counts.total > 0 && counts.total == lastTotal) ? stableReads + 1 : 0
                lastTotal = counts.total
                latestChatCounts = counts
                if stableReads >= timing.syncStableReads { break }
            }
            await sleep(.milliseconds(Int(timing.syncPoll * 1000)))
            elapsed += timing.syncPoll
            if Task.isCancelled { return }
        }

        if Task.isCancelled { return }
        finishWhatsApp(settled: stableReads >= timing.syncStableReads)
    }

    /// "Seguir mientras sincroniza": WhatsApp ya está vinculado y `sync` sigue en segundo
    /// plano; lo que falte llegará solo.
    func continueWhileSyncing() {
        guard case .syncing = phase else { return }
        cancelWork()
        finishWhatsApp(settled: false)
    }

    private func finishWhatsApp(settled: Bool) {
        findings[.whatsapp] = Finding(
            noun: .groups,
            count: ItemCount(value: latestChatCounts?.groups ?? 0, isPartial: !settled))
        phase = .succeeded(alreadyConnected: false)
        scheduleAdvance(after: timing.successHold, waitingFor: nil)
    }

    // MARK: - Interno

    private func fail(_ failure: Failure) {
        update(.failed(failure))
    }

    /// Cambia la fase desde una tarea de trabajo. Si esa tarea ya fue cancelada (el usuario
    /// saltó la conexión o salió del paso), no escribe nada: la pantalla ya es otra.
    private func update(_ newPhase: Phase) {
        guard !Task.isCancelled else { return }
        phase = newPhase
    }

    private func setStatus(_ tool: Tool, _ status: ConnectionStatus) {
        statuses[tool] = status
        if status == .selected { resolvedHere.remove(tool) } else { resolvedHere.insert(tool) }
        onStatus(tool, status)
    }

    /// Pasa a la siguiente pantalla tras `seconds`; si el dato real de `tool` sigue sin
    /// llegar, espera hasta `dataWaitMax` en total.
    private func scheduleAdvance(after seconds: Double, waitingFor tool: Tool?) {
        advanceTask?.cancel()
        advanceTask = Task { [weak self] in
            guard let self else { return }
            await self.sleep(.milliseconds(Int(seconds * 1000)))
            if Task.isCancelled { return }
            if let tool {
                var waited = seconds
                while self.pendingData.contains(tool), waited < self.timing.dataWaitMax {
                    await self.sleep(.milliseconds(250))
                    waited += 0.25
                    if Task.isCancelled { return }
                }
            }
            self.advance()
        }
    }

    /// Cancela lo que esté corriendo en la pantalla actual. El dato real de una
    /// herramienta ya conectada **no** se cancela: sigue y suma a los totales.
    private func cancelWork() {
        connectorConfirmRequested = false
        connectorCheck = .waiting
        openConnector = nil
        workTask?.cancel()
        workTask = nil
        advanceTask?.cancel()
        advanceTask = nil
    }

    /// Detiene todo (por ejemplo, al cerrar la app o salir del paso).
    func cancelAll() {
        cancelWork()
        authorizer?.dismissAuthorization()
        systemAuthorizer?.dismiss()
        webSession.reset()
        for task in dataTasks.values { task.cancel() }
        dataTasks = [:]
        pendingData = []
    }

    /// Qué se cuenta de cada herramienta, o `nil` si no se pide ningún dato real.
    ///
    /// **Notion no lleva dato**: contar sus páginas con `claude -p` tardaba ~17 s y costaba
    /// ~$0,06 por consulta, y la búsqueda devuelve una primera página, no un total fiable.
    /// Conectar es lo que importa; el éxito se muestra sin esperar nada.
    static func noun(for tool: Tool) -> Noun? {
        switch tool {
        case .slack: .channels
        case .jira: .projects
        // Gmail va por el conector de la cuenta de Claude, y los nombres de sus herramientas no están
        // verificados: no se pide ningún dato.
        case .gmail: nil
        case .fireflies, .granola, .fathom: .meetings
        case .whatsapp: .groups
        case .notion, .googleWorkspace, .googleMeet, .claudeDesign, .googleCalendar: nil
        }
    }
}
