import Combine
import Foundation
import GalenoCore

/// A qué servidor o servidores se conecta una herramienta (sale del catálogo del motor).
struct ConnectTarget: Equatable {
    struct Server: Equatable {
        var name: String
        var url: String
    }

    var tool: Tool
    var servers: [Server]

    /// Slack, Gmail y Google Workspace exigen una app OAuth del propio cliente
    /// (`docs/03` §4e). Crearla es el paso siguiente de la fase; hasta entonces
    /// estas herramientas no se conectan aquí. **Es el punto de entrada**: cuando
    /// exista ese paso, aquí se sustituye "todavía no" por crear la app y registrar
    /// el servidor con su `client_id` (y el secreto por `MCP_CLIENT_SECRET`,
    /// nunca en los argumentos).
    var requiresOwnOAuthApp: Bool { tool.requiresUserProvidedOAuthClient }

    /// `nil` para las herramientas que no se conectan con `claude mcp add`: WhatsApp
    /// (su propio bridge) y Google Meet (se lee por Drive y no tiene servidor).
    init?(tool: Tool) {
        let servers = MCPServerCatalog.definitions(for: tool, whatsAppBridgePath: "")
            .compactMap { definition -> Server? in
                guard case .http(let url) = definition.transport else { return nil }
                return Server(name: definition.serverName, url: url)
            }
        guard !servers.isEmpty else { return nil }
        self.tool = tool
        self.servers = servers
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
        case preparingBridge
        case checkingLink
        case installingSync
    }

    enum Failure: Equatable {
        case couldNotRegister
        case notAuthorizedInTime
        case loginFailed
        case stillNotConnected
        case bridgeMissing
        case bridgeFailed
        case qrExpired
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
        /// Necesita la app OAuth del cliente: todavía no se puede conectar aquí.
        case needsOwnApp
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
        case .ready, .failed, .needsOwnApp: return true
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
    }

    private let mcp: any MCPConnecting
    private let whatsapp: any WhatsAppLinking
    private let fetchRealData: Bool
    private let sleep: Sleeper
    private let timing: Timing
    private let onStatus: @MainActor (Tool, ConnectionStatus) -> Void

    private var workTask: Task<Void, Never>?
    private var advanceTask: Task<Void, Never>?
    private var dataTasks: [Tool: Task<Void, Never>] = [:]
    private var latestChatCounts: ChatCounts?

    init(
        tools: [Tool],
        statuses: [Tool: ConnectionStatus] = [:],
        mcp: any MCPConnecting,
        whatsapp: any WhatsAppLinking,
        fetchRealData: Bool = true,
        timing: Timing = Timing(),
        sleep: @escaping Sleeper = { _ = try? await Task.sleep(for: $0) },
        onStatus: @escaping @MainActor (Tool, ConnectionStatus) -> Void = { _, _ in }
    ) {
        let connectionTools = ConnectTarget.connectionTools(from: tools)
        self.tools = connectionTools
        self.statuses = statuses
        self.mcp = mcp
        self.whatsapp = whatsapp
        self.fetchRealData = fetchRealData
        self.timing = timing
        self.sleep = sleep
        self.onStatus = onStatus
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
            } else if let target = ConnectTarget(tool: tool), target.requiresOwnOAuthApp {
                phase = .needsOwnApp
            } else {
                phase = .ready
            }
        case .dopamine:
            phase = .ready
            scheduleAdvance(after: timing.dopamineHold, waitingFor: nil)
        case .celebration:
            phase = .ready
        }
    }

    func advance() {
        guard position < screens.count - 1 else { return }
        position += 1
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
            } else if let target = ConnectTarget(tool: tool) {
                await self?.connectHosted(target)
            }
        }
    }

    func retry() { connect() }

    /// "Conectar después" y "Saltar por ahora": la herramienta queda marcada para
    /// conectarla más tarde desde la app.
    func skip() {
        guard case .connection(let tool) = screen else { return }
        cancelWork()
        setStatus(tool, .skipped)
        advance()
    }

    func continueFromDopamine() {
        guard case .dopamine = screen else { return }
        advance()
    }

    // MARK: - Servidores MCP hospedados

    private func connectHosted(_ target: ConnectTarget) async {
        // Cada herramienta hospedada que se conecta aquí tiene un servidor; Google
        // Workspace, que tiene tres, entra con el paso de su app OAuth.
        guard let server = target.servers.first else { return }
        update(.working(.checking))

        let current = await mcp.status(of: server.name)
        if Task.isCancelled { return }

        if current == .connected {
            finishHosted(target, alreadyConnected: true)
            return
        }
        if current == .notRegistered {
            update(.working(.registering))
            do { try await mcp.register(server: server.name, url: server.url) } catch {
                if let error = error as? MCPConnectError, case .registerFailed(let detail) = error {
                    failureDetail = detail
                }
                fail(.couldNotRegister)
                return
            }
            if Task.isCancelled { return }
        }

        update(.working(.waitingForBrowser))
        do {
            try await mcp.login(server: server.name)
        } catch let error as MCPConnectError {
            if Task.isCancelled || error == .cancelled { return }
            switch error {
            case .loginTimedOut: fail(.notAuthorizedInTime)
            case .notConnectedAfterLogin: fail(.stillNotConnected)
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
        finishHosted(target, alreadyConnected: false)
    }

    private func finishHosted(_ target: ConnectTarget, alreadyConnected: Bool) {
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
        workTask?.cancel()
        workTask = nil
        advanceTask?.cancel()
        advanceTask = nil
    }

    /// Detiene todo (por ejemplo, al cerrar la app o salir del paso).
    func cancelAll() {
        cancelWork()
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
        case .gmail: .labels
        case .fireflies, .granola, .fathom: .meetings
        case .whatsapp: .groups
        case .notion, .googleWorkspace, .googleMeet: nil
        }
    }
}
