import AppKit
import Combine
import Foundation
import GalenoCore

/// Quien actualiza las skills de los agentes que ya existen. **El mecanismo llega con la Fase 5** (fuente
/// remota versionada, `docs/03` §4f capa 3); hasta entonces la vista de salud solo deja el punto de entrada.
protocol SkillUpdating {
    var isAvailable: Bool { get }
    func updateSkills() async throws
}

/// El de hoy: no hay de dónde bajar skills todavía.
struct SkillUpdaterNotAvailable: SkillUpdating {
    var isAvailable: Bool { false }
    func updateSkills() async throws {}
}

/// La vista de salud (`docs/03` §3b): qué conexiones están vivas, cómo va la sesión de WhatsApp, y el punto de
/// entrada de «Actualizar skills». Lee y diagnostica; las únicas acciones son **reconectar** una herramienta
/// y **re-vincular** WhatsApp, y las dos las pide el usuario.
///
/// Nada aquí envía nada ni sale de la máquina: pregunta a `claude`, al bridge y a `launchd`.
@MainActor
final class HealthModel: ObservableObject {
    // MARK: - Conexiones

    enum ConnectionState: Equatable {
        case checking
        case connected
        /// El conector de la cuenta todavía se estaba conectando: ni falla ni pide nada (`MCPStatus.pending`).
        case pending
        case needsAuthorization
        case failed
        /// Ya no está registrada en Claude Code (o, si es un conector, ya no está en la cuenta).
        case missing
        /// No se pudo averiguar (p. ej. `claude` no respondió): no se afirma nada.
        case unknown

        /// ¿Tiene sentido ofrecer «Reconectar»?
        var canReconnect: Bool {
            switch self {
            case .needsAuthorization, .failed, .missing, .unknown: true
            case .checking, .connected, .pending: false
            }
        }

        /// Cuál es peor, para una herramienta con varios servidores (Drive, Docs y Sheets).
        fileprivate var severity: Int {
            switch self {
            case .connected: 0
            case .checking: 1
            case .pending: 2
            case .unknown: 3
            case .missing: 4
            case .needsAuthorization: 5
            case .failed: 6
            }
        }
    }

    struct ConnectionRow: Identifiable, Equatable {
        var tool: Tool
        var state: ConnectionState
        var id: Tool { tool }
    }

    /// Por qué no se pudo reconectar, para decirlo con palabras (la clave es `health.reconnect.issue.<caso>`).
    enum ReconnectIssue: Equatable {
        /// Hay que rehacer la conexión entera (la app de Slack, p. ej.): se hace desde «Gestionar».
        case needsWizard
        case notAuthorized
        case timedOut
        case stillNotConnected
        /// Otro servidor del usuario usa ese nombre: Galeno no lo toca.
        case nameTaken
        /// El `claude` de este Mac es demasiado viejo para autorizar herramientas.
        case claudeOutdated
        case failed
    }

    @Published private(set) var connections: [ConnectionRow] = []
    /// Falso hasta que se terminó de mirar todo la primera vez.
    @Published private(set) var isChecking = false
    /// La herramienta que se está reconectando ahora (solo una a la vez).
    @Published private(set) var reconnecting: Tool?
    @Published private(set) var reconnectIssues: [Tool: ReconnectIssue] = [:]
    /// `false` si `claude` no se encontró: no hay nada que consultar.
    @Published private(set) var claudeAvailable = true

    // MARK: - WhatsApp

    /// Dónde va el re-vincular. Cada fase es una pantalla del panel.
    enum RelinkPhase: Equatable {
        case idle
        /// La advertencia de WhatsApp (la misma de la vinculación) y la confirmación.
        case confirming
        /// Cerrando la sesión anterior.
        case closing
        /// El QR a escanear (`nil` hasta que el bridge lo escribe).
        case qr(Data?)
        /// Escaneado: dejando `sync` corriendo.
        case finishing
        case failed(RelinkFailure)
        case done
    }

    enum RelinkFailure: Equatable {
        case bridgeMissing
        case couldNotClose
        case qrExpired
        case failed
    }

    struct WhatsAppHealth: Equatable {
        /// `nil` si el bridge no contestó.
        var status: WhatsAppStatus?
        var sync: WhatsAppSyncState
        /// ¿Aceptó el usuario que su agente envíe por WhatsApp? Quien lo vinculó cuando solo leía, todavía no.
        var sendingAccepted = false
        /// La bandeja de salida, si el envío está aceptado y el bridge contestó.
        var outbox: WhatsAppOutbox?

        var isLinked: Bool { status?.isLinked == true }

        /// Días desde que se vinculó, si se sabe.
        func daysLinked(now: Date = Date()) -> Int? {
            guard isLinked else { return nil }
            return WhatsAppSession.ageInDays(linkedAt: status?.linkedAt, now: now)
        }

        func shouldRelink(now: Date = Date()) -> Bool {
            isLinked && WhatsAppSession.shouldRelink(linkedAt: status?.linkedAt, now: now)
        }
    }

    /// `nil` si el agente no usa WhatsApp (no se enseña el panel) o todavía no se miró.
    @Published private(set) var whatsapp: WhatsAppHealth?
    /// ¿Hay WhatsApp en la instalación? Decide si el panel existe.
    @Published private(set) var usesWhatsApp = false
    @Published private(set) var relink: RelinkPhase = .idle

    /// «Activar envíos»: para quien vinculó WhatsApp cuando Galeno solo leía. El envío no se enciende solo al
    /// actualizar la app: se le enseña la advertencia nueva y lo decide él.
    enum SendingActivation: Equatable {
        case idle
        /// Leyendo la advertencia.
        case confirming
        /// Dejando el bridge al día y volviendo a escribir los agentes.
        case working
        case failed
    }

    @Published private(set) var activation: SendingActivation = .idle
    /// Guardando la pausa o los límites.
    @Published private(set) var isSavingSending = false
    @Published private(set) var sendingSaveFailed = false

    // MARK: - Skills

    @Published private(set) var isUpdatingSkills = false
    @Published private(set) var skillsUpdateFailed = false

    var canUpdateSkills: Bool { skillUpdater.isAvailable }

    // MARK: - Dependencias

    private let store: InstallationStore
    /// Con qué se vuelven a escribir los agentes al activar el envío. `nil`: esta vista no puede activarlo.
    private var installer: AgentInstaller?
    /// Los agentes a los que se les acaba de dar el envío: quien los tenga abiertos arrancó sin él.
    private var agentsChanged: @MainActor ([UUID]) -> Void
    private var whatsappSendingAccepted = false
    private let makeMCP: @MainActor (String) -> any MCPConnecting
    private let claudePath: String?
    private let whatsappBridge: any WhatsAppLinking
    private let skillUpdater: any SkillUpdating
    private let openURL: @MainActor (URL) -> Void
    private let returnToApp: @MainActor () -> Void
    private let authorizer: (any SlackAuthorizationPresenting)?
    /// La hoja de autenticación del sistema para las herramientas que se autorizan en el navegador (`ConnectFlow`).
    private let systemAuthorizer: (any SystemAuthorizationPresenting)?
    private let webSession = SlackWebSession()
    private let language: @MainActor () -> Language
    private let sleep: @Sendable (Duration) async -> Void
    private let timing: Timing
    /// Los dos sonidos de siempre (`Sounds`): una conexión lograda y algo que falló. Las pruebas lo reemplazan.
    private let playSound: @MainActor (Sounds.Cue) -> Void

    struct Timing {
        /// Cada cuánto se mira si el usuario ya autorizó el conector, y hasta cuándo (en segundos).
        var connectorPoll: Double = 3
        var connectorMax: Double = 300
        /// Veces seguidas que `pending` cuenta como conectado tras autorizar (como en `ConnectFlow`).
        var pendingLooks = 3
    }

    private var checkTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var relinkTask: Task<Void, Never>?
    /// Las herramientas conectadas y sus nombres de servidor, tal como estaban al mirar.
    private var prefixes: [Tool: String] = [:]

    init(
        store: InstallationStore = InstallationStore(),
        installer: AgentInstaller? = nil,
        agentsChanged: @escaping @MainActor ([UUID]) -> Void = { _ in },
        locateClaude: @Sendable () -> String? = HealthModel.locateClaude,
        makeMCP: @escaping @MainActor (String) -> any MCPConnecting = { ClaudeMCPClient(claudePath: $0) },
        whatsapp: any WhatsAppLinking = WhatsAppBridge.live(),
        skillUpdater: any SkillUpdating = SkillUpdaterNotAvailable(),
        authorizer: (any SlackAuthorizationPresenting)? = SlackAuthorizeWindowPresenter(),
        // Navegador predeterminado, no la hoja del sistema (decisión de Rafa, 5 oct 2026; ver ConnectServices).
        systemAuthorizer: (any SystemAuthorizationPresenting)? = nil,
        language: @escaping @MainActor () -> Language = { .spanish },
        openURL: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) },
        returnToApp: @escaping @MainActor () -> Void = { AppFocus.bringToFront() },
        sleep: @escaping @Sendable (Duration) async -> Void = { _ = try? await Task.sleep(for: $0) },
        timing: Timing = Timing(),
        playSound: @escaping @MainActor (Sounds.Cue) -> Void = { Sounds.play($0) }
    ) {
        self.playSound = playSound
        self.store = store
        self.installer = installer
        self.agentsChanged = agentsChanged
        self.claudePath = locateClaude()
        self.makeMCP = makeMCP
        self.whatsappBridge = whatsapp
        self.skillUpdater = skillUpdater
        self.authorizer = authorizer
        self.systemAuthorizer = systemAuthorizer
        self.language = language
        self.openURL = openURL
        self.returnToApp = returnToApp
        self.sleep = sleep
        self.timing = timing
    }

    /// La ruta a `claude`, o `nil` si no está (la vista lo dice en vez de fallar).
    nonisolated static func locateClaude() -> String? {
        let detector = ClaudeCodeDetector()
        return detector.knownPaths.first(where: detector.isExecutable)
    }

    // MARK: - Mirar

    /// Mira todo: conexiones, WhatsApp. Lo llama la vista al abrirse y el botón «Revisar de nuevo».
    func refresh() {
        checkTask?.cancel()
        isChecking = true
        checkTask = Task { [weak self] in
            await self?.check()
            self?.isChecking = false
        }
    }

    /// Lo mismo, esperable (las pruebas).
    func check() async {
        let installation = (try? store.load()) ?? nil
        let connected = (installation?.connections ?? []).filter { $0.status == .connected }
        prefixes = Dictionary(
            uniqueKeysWithValues: connected.compactMap { shared in shared.serverNamePrefix.map { (shared.tool, $0) } })

        let tools = connected.map(\.tool).filter { $0 != .whatsapp && ConnectTarget(tool: $0, namePrefix: prefixes[$0]) != nil }
        usesWhatsApp = connected.contains { $0.tool == .whatsapp }
        whatsappSendingAccepted = connected.first { $0.tool == .whatsapp }?.sendingAccepted == true
        connections = tools.map { ConnectionRow(tool: $0, state: .checking) }

        // WhatsApp contesta en un instante; `claude mcp list` puede tardar: no se hace esperar a uno por el otro.
        let whatsappCheck = Task { await self.checkWhatsApp() }
        await checkConnections(tools)
        await whatsappCheck.value
    }

    private func checkConnections(_ tools: [Tool]) async {
        guard let claudePath else {
            claudeAvailable = false
            connections = tools.map { ConnectionRow(tool: $0, state: .unknown) }
            return
        }
        claudeAvailable = true
        let mcp = makeMCP(claudePath)

        // Los servidores propios, de una vez con `claude mcp list`. Si no contesta, ninguno se afirma.
        let hostedTools = tools.filter { !(ConnectTarget(tool: $0, namePrefix: prefixes[$0])?.servers.isEmpty ?? true) }
        let listed = hostedTools.isEmpty ? [:] : await mcp.listStatuses()

        for tool in tools {
            if Task.isCancelled { return }
            guard let target = ConnectTarget(tool: tool, namePrefix: prefixes[tool]) else { continue }
            var states: [ConnectionState] = []
            for server in target.servers {
                states.append(listed.map { Self.state(from: $0[server.name]) } ?? .unknown)
            }
            // Un conector de la cuenta no se lee de `mcp list` (lo da por conectado sin estarlo): sale del
            // arranque de una sesión real.
            for connector in target.connectors {
                states.append(Self.state(from: await mcp.connectorStatus(connector.serverName)))
            }
            setState(states.max { $0.severity < $1.severity } ?? .unknown, for: tool)
        }
    }

    private func setState(_ state: ConnectionState, for tool: Tool) {
        guard let index = connections.firstIndex(where: { $0.tool == tool }) else { return }
        connections[index].state = state
    }

    static func state(from status: MCPStatus?) -> ConnectionState {
        switch status {
        case .connected?: .connected
        case .pending?: .pending
        case .needsAuthentication?: .needsAuthorization
        case .failed?: .failed
        case .notRegistered?, nil: .missing
        // Otro servidor con ese nombre: el nuestro no está.
        case .differentServer?: .missing
        }
    }

    private func checkWhatsApp() async {
        guard usesWhatsApp else {
            whatsapp = nil
            return
        }
        // La copia instalada puede ser de una versión anterior a `status --json` (0.2.x): antes de preguntarle se
        // deja al día con la que trae la app. Si no se puede, se pregunta igual y la vista dice que no contestó.
        try? await whatsappBridge.prepare()
        async let status = whatsappBridge.status()
        async let sync = whatsappBridge.syncState()
        let (found, state) = await (status, sync)
        let outbox = whatsappSendingAccepted && found?.isLinked == true ? await whatsappBridge.outbox() : nil
        whatsapp = WhatsAppHealth(
            status: found, sync: state, sendingAccepted: whatsappSendingAccepted, outbox: outbox)
    }

    // MARK: - WhatsApp: envíos

    /// ¿Puede esta vista activar el envío? Hace falta con qué volver a escribir los agentes.
    var canActivateSending: Bool { installer != nil }

    /// Le da a esta vista con qué activar el envío: el instalador que comparte la instalación del home, y a quién
    /// avisar de los agentes que cambiaron (para que «Abrir» reinicie la conversación que arrancó sin el envío).
    func enableSendingActivation(installer: AgentInstaller, agentsChanged: @escaping @MainActor ([UUID]) -> Void) {
        self.installer = installer
        self.agentsChanged = agentsChanged
    }

    /// «Activar envíos…»: enseña la advertencia y pide confirmar.
    func askActivateSending() {
        guard canActivateSending, activation == .idle || activation == .failed else { return }
        activation = .confirming
    }

    func cancelActivateSending() {
        guard activation == .confirming || activation == .failed else { return }
        activation = .idle
    }

    /// «Entiendo, activar». El bridge se deja al día y `sync` se reinicia con él (el de antes no saca la bandeja
    /// de salida); el envío queda aceptado en la instalación y se vuelve a escribir cada agente que usa WhatsApp,
    /// para que le lleguen a la vez la herramienta y la regla que pide aprobación. `memoria/` no se toca.
    func confirmActivateSending() {
        guard activation == .confirming else { return }
        activation = .working
        Task { [weak self] in
            guard let self else { return }
            let done = await self.activateSending()
            self.activation = done ? .idle : .failed
        }
    }

    /// Lo mismo, esperable (las pruebas).
    func activateSending() async -> Bool {
        do {
            try await whatsappBridge.prepare()
            if whatsapp?.isLinked == true { try await whatsappBridge.installLaunchd() }
            try recordSendingAccepted()
        } catch {
            return false
        }
        await checkWhatsApp()
        return true
    }

    /// Anota en la instalación que el usuario aceptó el envío y vuelve a escribir los agentes que usan WhatsApp.
    private func recordSendingAccepted() throws {
        guard let installer, var installation = try installer.store.load(),
            var shared = installation.connection(for: .whatsapp)
        else { throw WhatsAppBridgeError.unexpectedOutput("no hay WhatsApp en la instalación") }
        shared.sendingAccepted = true
        installation.setConnection(shared)
        try installer.store.save(installation)

        let users = installation.agents.filter {
            installation.resolvedConfig(for: $0.id)?.connectedTools.contains(.whatsapp) == true
        }
        for user in users {
            if let resolved = installation.resolvedConfig(for: user.id) {
                _ = try installer.install(resolved, existingAgentID: user.id)
            }
        }
        whatsappSendingAccepted = true
        agentsChanged(users.map(\.id))
    }

    /// «Pausar envíos» / «Reanudar envíos».
    func setSendingPaused(_ paused: Bool) {
        saveSending { try await $0.setSendingPaused(paused) }
    }

    /// «Límites»: baja los topes del día. Nunca por encima del techo que trae el bridge.
    func setSendLimits(dailyTotal: Int, dailyNewChats: Int, dailyGroups: Int) {
        guard let limits = whatsapp?.outbox?.limits else { return }
        let total = min(max(1, dailyTotal), limits.maxDailyTotal)
        let newChats = min(max(1, dailyNewChats), limits.maxDailyNewChats)
        let groups = min(max(0, dailyGroups), limits.maxDailyGroups)
        saveSending { try await $0.setSendLimits(dailyTotal: total, dailyNewChats: newChats, dailyGroups: groups) }
    }

    private func saveSending(_ change: @escaping @Sendable (any WhatsAppLinking) async throws -> Void) {
        guard !isSavingSending else { return }
        isSavingSending = true
        sendingSaveFailed = false
        Task { [weak self] in
            guard let self else { return }
            do { try await change(self.whatsappBridge) } catch { self.sendingSaveFailed = true }
            await self.checkWhatsApp()
            self.isSavingSending = false
        }
    }

    // MARK: - Reconectar una herramienta

    /// «Reconectar»: vuelve a pasar por la autorización de **esa** herramienta. Una a la vez.
    func reconnect(_ tool: Tool) {
        guard reconnecting == nil, let claudePath else { return }
        reconnecting = tool
        reconnectIssues[tool] = nil
        setState(.checking, for: tool)
        let mcp = makeMCP(claudePath)
        reconnectTask = Task { [weak self] in
            guard let self else { return }
            let issue = await self.performReconnect(tool, mcp: mcp)
            guard !Task.isCancelled else { return }
            if let issue { self.reconnectIssues[tool] = issue }
            self.authorizer?.dismissAuthorization()
            self.systemAuthorizer?.dismiss()
            self.reconnecting = nil
            await self.recheck(tool, mcp: mcp)
            guard !Task.isCancelled else { return }
            // Suena al terminar: lograda (quedó viva) o fallida (no pudo, o sigue sin responder). Si el usuario
            // cancela no suena nada. Es igual para la hoja de autenticación, el navegador y la ventana de Slack.
            let alive = self.connections.first { $0.tool == tool }?.state
            let worked = issue == nil && (alive == .connected || alive == .pending)
            self.playSound(worked ? .connected : .failed)
        }
    }

    /// Cierra una reconexión en curso (la ventana de Slack se cerró, o el usuario se fue de la vista).
    func cancelReconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        authorizer?.dismissAuthorization()
        systemAuthorizer?.dismiss()
        if let tool = reconnecting {
            reconnecting = nil
            Task { [weak self] in
                guard let self, let claudePath = self.claudePath else { return }
                await self.recheck(tool, mcp: self.makeMCP(claudePath))
            }
        }
    }

    private func recheck(_ tool: Tool, mcp: any MCPConnecting) async {
        guard let target = ConnectTarget(tool: tool, namePrefix: prefixes[tool]) else { return }
        var states: [ConnectionState] = []
        for server in target.servers {
            states.append(Self.state(from: await mcp.status(of: server.name, expectingURL: server.url)))
        }
        for connector in target.connectors {
            states.append(Self.state(from: await mcp.connectorStatus(connector.serverName)))
        }
        setState(states.max { $0.severity < $1.severity } ?? .unknown, for: tool)
    }

    /// `nil` = quedó reconectada (o ya lo estaba).
    private func performReconnect(_ tool: Tool, mcp: any MCPConnecting) async -> ReconnectIssue? {
        guard let target = ConnectTarget(tool: tool, namePrefix: prefixes[tool]) else { return .failed }
        if !target.connectors.isEmpty { return await reconnectConnectors(target, mcp: mcp) }
        guard let server = target.servers.first else { return .failed }

        switch await mcp.status(of: server.name, expectingURL: server.url) {
        case .connected:
            return nil
        case .differentServer:
            // Galeno nunca pisa un servidor del usuario.
            return .nameTaken
        case .notRegistered:
            // Con app OAuth propia (Slack) no se registra a ciegas: falta su `client_id` y su secreto, que
            // solo existen mientras se crea la app. Eso se rehace desde «Gestionar».
            if target.requiresOwnOAuthApp { return .needsWizard }
            do { try await mcp.register(server: server.name, url: server.url) } catch { return .failed }
        case .needsAuthentication, .failed, .pending:
            break
        }
        if Task.isCancelled { return nil }

        // Claude Design entra con la sesión de Claude Code: no hay nada que autorizar aquí.
        if target.usesClaudeCodeSession {
            return await mcp.status(of: server.name, expectingURL: server.url) == .connected ? nil : .stillNotConnected
        }

        // Como al conectarla: Slack, con su app propia, en la ventana de Galeno; las demás, en la hoja de
        // autenticación del sistema (y si no se puede mostrar, en el navegador).
        let usesOwnWindow = target.requiresOwnOAuthApp && authorizer != nil
        let opener: AuthorizationOpener?
        if usesOwnWindow {
            opener = { @MainActor [weak self] url in self?.showAuthorization(url) ?? false }
        } else if let systemAuthorizer {
            opener = { @MainActor [weak self] url in
                systemAuthorizer.present(url: url) { self?.cancelReconnect() }
            }
        } else {
            opener = nil
        }
        do {
            try await mcp.login(server: server.name, openAuthorization: opener)
        } catch let error as MCPConnectError {
            if Task.isCancelled || error == .cancelled { return nil }
            switch error {
            case .loginTimedOut: return .timedOut
            case .notConnectedAfterLogin: return .stillNotConnected
            case .claudeOutdated: return .claudeOutdated
            default: return .failed
            }
        } catch {
            return .failed
        }
        if Task.isCancelled { return nil }
        if !usesOwnWindow {
            systemAuthorizer?.dismiss()
            returnToApp()
        }
        let after = await mcp.status(of: server.name, expectingURL: server.url)
        return after == .connected ? nil : .stillNotConnected
    }

    /// Los conectores de la cuenta de Claude (Gmail, Drive…): `needs-auth` → `claude mcp login`, que abre la
    /// página de permiso y termina; si no está en la cuenta o no se sabe cómo está → se abre su página en Claude.
    /// Después se espera a verlo **conectado de verdad**: `pending` no cuenta, ni antes ni después de abrir el
    /// navegador (así se marcó uno sin estarlo en el demo de Aquiles, 5 oct 2026).
    private func reconnectConnectors(_ target: ConnectTarget, mcp: any MCPConnecting) async -> ReconnectIssue? {
        for connector in target.connectors {
            var current = await mcp.connectorStatus(connector.serverName)
            if Task.isCancelled { return nil }
            // Un conector lento sale «pendiente» al arrancar: se le dan unas miradas antes de abrir nada.
            var looks = 0
            while current == .pending, looks < timing.pendingLooks {
                await sleep(.seconds(timing.connectorPoll))
                current = await mcp.freshConnectorStatus(connector.serverName)
                if Task.isCancelled { return nil }
                looks += 1
            }
            if current == .connected { continue }

            if current == .needsAuthentication {
                do { try await mcp.authorizeConnector(connector.serverName) } catch {
                    return (error as? MCPConnectError) == .claudeOutdated ? .claudeOutdated : .failed
                }
            } else {
                openURL(connector.directoryURL)
            }

            var waited = 0.0
            while waited < timing.connectorMax, current != .connected {
                await sleep(.seconds(timing.connectorPoll))
                waited += timing.connectorPoll
                if Task.isCancelled { return nil }
                current = await mcp.connectorStatus(connector.serverName)
            }
            if current != .connected { return .timedOut }
            returnToApp()
        }
        return nil
    }

    private func showAuthorization(_ url: URL) -> Bool {
        guard let authorizer, SlackAuthorization.isSlackAuthorizationURL(url) else { return false }
        authorizer.presentAuthorization(
            url: url, dataStore: webSession.dataStore, language: language(),
            onCancel: { [weak self] in self?.cancelReconnect() },
            onAppNotFound: { [weak self] in
                self?.reconnectIssues[.slack] = .needsWizard
                self?.cancelReconnect()
            })
        return true
    }

    // MARK: - WhatsApp: re-vincular

    /// «Re-vincular» (o «Vincular», si no había sesión): enseña la advertencia y pide confirmar.
    func askRelink() {
        guard relink == .idle || relink == .done || isRelinkFailed else { return }
        relink = .confirming
    }

    /// «Cancelar» en cualquier punto: detiene `pair` (si corría) y mira cómo quedó todo.
    func cancelRelink() {
        guard relink != .closing, relink != .finishing else { return }
        relinkTask?.cancel()
        relinkTask = nil
        relink = .idle
        Task { [weak self] in await self?.checkWhatsApp() }
    }

    func dismissRelink() {
        guard relink == .done || isRelinkFailed else { return }
        relink = .idle
    }

    private var isRelinkFailed: Bool {
        if case .failed = relink { true } else { false }
    }

    /// Confirmado. Si había sesión, se cierra primero (`unlink`); luego el QR; al escanearlo, `sync` vuelve a quedar
    /// corriendo. El historial ya sincronizado no se toca.
    func confirmRelink() {
        guard relink == .confirming else { return }
        let wasLinked = whatsapp?.isLinked == true
        relinkTask = Task { [weak self] in
            guard let self else { return }
            do { try await self.whatsappBridge.prepare() } catch {
                self.relink = .failed(error as? WhatsAppBridgeError == .bridgeMissing ? .bridgeMissing : .failed)
                return
            }
            if wasLinked {
                self.relink = .closing
                do { try await self.whatsappBridge.unlink() } catch {
                    if !Task.isCancelled { self.relink = .failed(.couldNotClose) }
                    return
                }
                if Task.isCancelled { return }
            }
            await self.pairAndFinish()
        }
    }

    private func pairAndFinish() async {
        relink = .qr(nil)
        var linked = false
        var detail = ""
        for await event in whatsappBridge.pair() {
            switch event {
            case .qr(let image): relink = .qr(image)
            case .succeeded: linked = true
            case .failed(let text): detail = text
            }
        }
        if Task.isCancelled { return }
        guard linked else {
            relink = .failed(detail.lowercased().contains("tiempo") ? .qrExpired : .failed)
            await checkWhatsApp()
            return
        }
        relink = .finishing
        do { try await whatsappBridge.installLaunchd() } catch {
            relink = .failed(.failed)
            await checkWhatsApp()
            return
        }
        // Volvió a pasar por la advertencia, que es la que dice que el agente puede enviar: eso es aceptarlo.
        if installer != nil, !whatsappSendingAccepted { try? recordSendingAccepted() }
        await checkWhatsApp()
        relink = .done
    }

    // MARK: - Skills

    /// «Actualizar skills». Hoy no hay de dónde (Fase 5): la vista ni ofrece el botón.
    func updateSkills() {
        guard canUpdateSkills, !isUpdatingSkills else { return }
        isUpdatingSkills = true
        skillsUpdateFailed = false
        Task { [weak self] in
            guard let self else { return }
            do { try await self.skillUpdater.updateSkills() } catch { self.skillsUpdateFailed = true }
            self.isUpdatingSkills = false
        }
    }

    /// La vista se fue: nada se queda corriendo (un `pair` huérfano seguiría escuchando).
    func stop() {
        checkTask?.cancel()
        cancelReconnect()
        if relink != .closing, relink != .finishing {
            relinkTask?.cancel()
            relinkTask = nil
            relink = .idle
        }
    }
}
