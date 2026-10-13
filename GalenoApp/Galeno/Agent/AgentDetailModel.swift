import AppKit
import Combine
import Foundation
import GalenoCore

/// Quien desconecta de verdad la cuenta de una herramienta de Galeno: `claude mcp remove -s user` de **sus** servidores
/// (`galeno-…`). Las pruebas lo reemplazan.
nonisolated protocol AccountDisconnecting: Sendable {
    func remove(servers: [String]) async throws
}

nonisolated struct ClaudeAccountDisconnector: AccountDisconnecting {
    enum Failure: Error { case claudeNotFound }
    var claudePath: String?

    func remove(servers: [String]) async throws {
        guard let claudePath else { throw Failure.claudeNotFound }
        let client = ClaudeMCPClient(claudePath: claudePath)
        for server in servers { try await client.remove(server: server) }
    }
}

/// El detalle de un agente (`docs/03` §3b; diseño «Galeno B1 Agente»): todo lo configurado a la vista y editable en su
/// sitio, en cinco secciones. **No hay pasos ni «Siguiente»**: lo que cambia reglas, rol o herramientas se aplica al
/// momento (Galeno vuelve a escribir los archivos del agente; `memoria/` no se toca), y las skills y el contexto, al
/// guardar.
///
/// Reutiliza lo que ya existe en vez de duplicarlo: abrir, renombrar y eliminar son los del `HomeModel`; el estado de
/// las herramientas, reconectar y re-vincular WhatsApp, los del `HealthModel`; el catálogo de skills **y** la conexión de una
/// herramienta nueva, los del asistente (un `WizardState` en modo «Gestionar» que solo se usa para eso); escribir la
/// carpeta, el `AgentInstaller`.
@MainActor
final class AgentDetailModel: ObservableObject {
    enum Section: String, CaseIterable, Identifiable {
        case general, tools, skills, rules, context
        var id: String { rawValue }
        var titleKey: String { "agent.section.\(rawValue)" }
    }

    /// Una hoja sobre el detalle.
    enum Sheet: Equatable {
        /// «Quitar»: qué se quiere hacer con esa herramienta (quitarla de este agente, o desconectar la cuenta).
        case removeTool(Tool)
        /// «Añadir otra cuenta» de una herramienta: el nombre de la cuenta y la conexión.
        case addAccount(Tool)
        /// «Quitar» una cuenta extra de una herramienta (la cuenta de siempre va por `removeTool`).
        case removeAccount(ConnectionID)
    }

    typealias AccountPhase = AddAccountPhase

    /// Una herramienta del agente tal como se enseña en su lista.
    struct ToolRow: Identifiable, Equatable {
        enum Status: Equatable {
            /// Una herramienta hospedada o un conector de la cuenta de Claude: lo que dice `HealthModel`.
            case hosted(HealthModel.ConnectionState)
            case whatsappChecking
            /// Vinculado; `days` si el puente lo sabe. `rotate` si ya conviene volver a vincular (~18 días).
            case whatsappLinked(days: Int?, rotate: Bool)
            case whatsappNotLinked
            /// El puente no contestó: no se afirma nada.
            case whatsappNoAnswer
        }

        var tool: Tool
        /// `nil` es la cuenta de siempre de la herramienta; una cuenta extra lleva su identificador y su nombre.
        var accountID: String?
        var accountName: String?
        var status: Status
        /// Los otros agentes de Galeno que también la leen.
        var sharedWith: [String]
        /// ¿Se puede desconectar su cuenta desde aquí? Solo si los servidores son de Galeno (`galeno-…`).
        var canDisconnectAccount: Bool
        /// ¿Tiene algo que reconectar? Google Meet, por ejemplo, se lee por Drive y no tiene conexión propia.
        var canReconnect: Bool

        var id: ConnectionID { ConnectionID(tool: tool, account: accountID) }
        var isExtraAccount: Bool { accountID != nil }

        /// «Notion» o, en una cuenta extra, «Notion (Trabajo)».
        func displayName(in language: Language) -> String {
            let base = tool.displayName(in: language)
            guard let accountName, !accountName.isEmpty else { return base }
            return "\(base) (\(accountName))"
        }

        /// ¿Pide que alguien la mire? (alimenta el «2 !» de la navegación.)
        var needsReview: Bool {
            switch status {
            case .hosted(let state): state.canReconnect && canReconnect
            case .whatsappNotLinked, .whatsappNoAnswer: true
            case .whatsappLinked(_, let rotate): rotate
            case .whatsappChecking: false
            }
        }
    }

    /// Por qué no se pudo traer un material a «Contexto».
    enum ContextProblem: Equatable {
        case unsupported, tooLarge, unreadable, tooMany, tooLong, empty
    }

    // MARK: Lo que se ve

    let agentID: UUID
    let home: HomeModel
    let health: HealthModel

    @Published var section: Section
    @Published private(set) var config: AgentConfig?
    @Published private(set) var record: AgentRecord?
    @Published private(set) var sharedWith: [Tool: [String]] = [:]
    /// Los otros agentes que leen **esa cuenta extra** (`sharedWith` es por herramienta, la de siempre).
    @Published private(set) var sharedAccounts: [ConnectionID: [String]] = [:]
    /// Las herramientas cuya cuenta es de Galeno (sus servidores se llaman `galeno-…`) y con qué prefijo.
    private var ownedPrefixes: [Tool: String] = [:]
    @Published var sheet: Sheet?
    /// Mientras se vuelven a escribir los archivos del agente o se desconecta una cuenta.
    @Published private(set) var isWorking = false
    /// Qué salió mal, a la vista en la sección (nunca en silencio).
    @Published private(set) var error: String?
    /// Las skills como cards, editables en su sitio: un `WizardState` en modo «Gestionar» que solo se usa para elegir. Se
    /// crea al entrar a la sección y guarda lo marcado hasta «Guardar skills» o «Descartar».
    @Published private(set) var picker: WizardState? {
        didSet {
            pickerObserver = picker?.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        }
    }
    private var pickerObserver: AnyCancellable?

    /// Una herramienta que se está conectando **aquí mismo** (otro `WizardState` en modo «Gestionar», solo por su flujo de
    /// conexión) y cuál. Mientras no es `nil`, el detalle muestra la conexión encima.
    @Published private(set) var connecting: WizardState?
    @Published private(set) var connectingTool: Tool?
    /// Mientras se busca `claude` antes de abrir la conexión.
    @Published private(set) var isPreparingConnection = false
    /// La última herramienta que quedó conectada: su fila entra a la lista con un destello.
    @Published private(set) var justAdded: Tool?
    /// La última cuenta extra que quedó conectada.
    @Published private(set) var justAddedAccount: ConnectionID?

    // «Añadir otra cuenta»
    @Published var accountDraft = ""
    @Published private(set) var accountPhase: AccountPhase = .idle
    /// La cuenta extra que se está reconectando ahora.
    @Published private(set) var reconnectingAccount: ConnectionID?
    private var accountTask: Task<Void, Never>?
    private var connectionObserver: AnyCancellable?
    private var isFinishingConnection = false

    // Contexto: lo editado, hasta que se guarda.
    @Published var projectDraft = ""
    @Published private(set) var contextEntries: [ContextEntry] = []
    @Published private(set) var pendingContext: [ContextFile] = []
    @Published private(set) var removedContext: Set<String> = []
    @Published private(set) var contextProblem: ContextProblem?

    // MARK: Dependencias

    private let installer: AgentInstaller
    /// Cuánto se deja ver el éxito de la conexión antes de volver a la lista.
    private let connectedHold: Duration
    private let makePicker: @MainActor (GalenoInstallation, UUID) -> WizardState
    private let disconnector: any AccountDisconnecting
    private let makeMCP: @MainActor (String) -> any MCPConnecting
    private let locateClaude: @MainActor () -> String?
    private let trashContext: (URL) throws -> Void
    private let importContext: (URL) throws -> ContextFile
    private let reveal: @MainActor (URL) -> Void
    private var cancellables: Set<AnyCancellable> = []

    init(
        agentID: UUID, section: Section = .general, home: HomeModel, health: HealthModel,
        installer: AgentInstaller? = nil, connectedHold: Duration = .milliseconds(1200),
        makePicker: @escaping @MainActor (GalenoInstallation, UUID) -> WizardState = {
            WizardState(preferredLanguages: [$0.language.rawValue], startingFrom: $0, editing: $1)
        },
        disconnector: (any AccountDisconnecting)? = nil,
        makeMCP: @escaping @MainActor (String) -> any MCPConnecting = { ClaudeMCPClient(claudePath: $0) },
        locateClaude: @escaping @MainActor () -> String? = { HealthModel.locateClaude() },
        trashContext: @escaping (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) },
        importContext: @escaping (URL) throws -> ContextFile = { try ContextImporter.load($0) },
        reveal: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
    ) {
        self.agentID = agentID
        self.section = section
        self.home = home
        self.health = health
        self.installer = installer ?? AgentInstaller.live()
        self.connectedHold = connectedHold
        self.makePicker = makePicker
        self.disconnector = disconnector ?? ClaudeAccountDisconnector(claudePath: HealthModel.locateClaude())
        self.makeMCP = makeMCP
        self.locateClaude = locateClaude
        self.trashContext = trashContext
        self.importContext = importContext
        self.reveal = reveal
        // Lo que cambia en la salud o en el home (renombrar, el estado de una herramienta) vuelve a pintar el detalle.
        health.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        home.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        // Renombrar (un diálogo del home) o cualquier cambio de la lista vuelve a leer el agente.
        home.$state.dropFirst().sink { [weak self] _ in self?.reload() }.store(in: &cancellables)
        reload()
    }

    /// Al salir del detalle: deja de mirar las conexiones y cierra una conexión a medias.
    func stop() {
        cancelConnecting()
        health.cancelReconnect()
        health.stop()
    }

    /// Al entrar (y con «Revisar de nuevo»): mira las conexiones.
    func refreshHealth() {
        healthStarted = true
        health.refresh()
    }
    private var healthStarted = false

    // MARK: Leer

    /// Vuelve a leer el agente de la instalación. Si ya no está (o no se puede leer), `config` queda en `nil` y la
    /// vista lo dice.
    func reload() {
        guard let installation = (try? installer.store.load()) ?? nil, let found = installation.agent(id: agentID),
            let resolved = installation.resolvedConfig(for: agentID)
        else {
            config = nil
            record = nil
            return
        }
        // Si la línea del proyecto no se había tocado, sigue a lo guardado; si se estaba editando, no se pisa.
        let draftWasClean = projectDraft.trimmingCharacters(in: .whitespacesAndNewlines) == (config?.projectDescription ?? "")
        record = found
        config = resolved
        var shared: [Tool: [String]] = [:]
        for other in installation.agents where other.id != agentID {
            let otherConfig = installation.resolvedConfig(for: other.id) ?? other.config
            for tool in otherConfig.connectedTools { shared[tool, default: []].append(otherConfig.agentName) }
        }
        sharedWith = shared
        var sharedAccounts: [ConnectionID: [String]] = [:]
        for other in installation.agents where other.id != agentID {
            let otherConfig = installation.resolvedConfig(for: other.id) ?? other.config
            for connection in otherConfig.connectedConnections where connection.accountID != nil {
                sharedAccounts[connection.id, default: []].append(otherConfig.agentName)
            }
        }
        self.sharedAccounts = sharedAccounts
        ownedPrefixes = Dictionary(
            installation.connections.compactMap { connection -> (Tool, String)? in
                guard connection.status == .connected, connection.accountID == nil, connection.galenoOwnsServers,
                    let prefix = connection.serverNamePrefix
                else { return nil }
                return (connection.tool, prefix)
            },
            uniquingKeysWith: { first, _ in first })
        contextEntries = ContextFolder.list(in: found.folder)
        if draftWasClean { projectDraft = resolved.projectDescription }
    }

    var agent: HomeAgent? { home.agents.first { $0.id == agentID } }
    var name: String { config?.agentName ?? "" }
    var role: AgentRole { config?.role ?? .productManager }
    var language: Language { config?.language ?? home.language }
    var folder: URL? { record?.folder }
    private var locale: Locale { Locale(identifier: language.rawValue) }

    /// «Creado el …»: se lee de la carpeta del agente (la instalación no guarda la fecha). `nil` si no se sabe.
    var createdAt: Date? {
        guard let folder else { return nil }
        return (try? folder.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? nil
    }

    // MARK: Herramientas

    var toolRows: [ToolRow] {
        guard let config else { return [] }
        return config.connections.filter { $0.status == .connected }.map { connection in
            guard connection.accountID != nil else {
                return ToolRow(
                    tool: connection.tool, accountID: nil, accountName: nil, status: status(of: connection.tool),
                    sharedWith: sharedWith[connection.tool] ?? [],
                    canDisconnectAccount: canDisconnectAccount(connection.tool),
                    canReconnect: ConnectTarget(tool: connection.tool, namePrefix: connection.serverNamePrefix) != nil)
            }
            // Una cuenta extra: su estado sale del servidor con su nombre; sin lectura, no se afirma nada.
            let server = AccountConnector.server(of: connection)?.name
            let state: HealthModel.ConnectionState =
                server.flatMap { health.serverStates[$0] } ?? (health.isChecking || !healthStarted ? .checking : .unknown)
            return ToolRow(
                tool: connection.tool, accountID: connection.accountID, accountName: connection.accountName,
                status: .hosted(state), sharedWith: sharedAccounts[connection.id] ?? [],
                canDisconnectAccount: connection.galenoOwnsServers, canReconnect: server != nil)
        }
    }

    private func status(of tool: Tool) -> ToolRow.Status {
        if tool == .whatsapp {
            guard let whatsapp = health.whatsapp else { return health.isChecking ? .whatsappChecking : .whatsappNoAnswer }
            guard whatsapp.status != nil else { return .whatsappNoAnswer }
            guard whatsapp.isLinked else { return .whatsappNotLinked }
            return .whatsappLinked(days: whatsapp.daysLinked(), rotate: whatsapp.shouldRelink())
        }
        if let row = health.connections.first(where: { $0.tool == tool }) { return .hosted(row.state) }
        // Todavía no se miró (o se está mirando): «Revisando». Mirada ya, y esa herramienta no está entre las que se
        // pueden comprobar: no se afirma nada.
        return .hosted(health.isChecking || !healthStarted ? .checking : .unknown)
    }

    /// Los servidores de esa herramienta son de Galeno (`galeno-…`): solo esos se desconectan desde aquí. Los de un
    /// conector de la cuenta de Claude (Gmail, Drive) y los que llevan el nombre genérico de otro proyecto del usuario
    /// no son de Galeno: se quitan **de este agente**, nunca de la cuenta.
    func canDisconnectAccount(_ tool: Tool) -> Bool {
        guard tool != .whatsapp, let prefix = ownedPrefixes[tool], let target = ConnectTarget(tool: tool, namePrefix: prefix)
        else { return false }
        // Un conector de la cuenta de Claude no tiene servidores de Galeno que quitar.
        return !target.servers.isEmpty
    }

    var reviewCount: Int { toolRows.filter(\.needsReview).count }

    /// Las herramientas que se pueden añadir: las que se conectan desde Galeno y este agente todavía no lee.
    var addableTools: [Tool] {
        let have = Set(config?.connectedTools ?? [])
        return ConnectTarget.connectionTools(from: Tool.allCases.filter { !$0.isComingSoon && $0 != .googleMeet })
            .filter { !have.contains($0) }
    }

    // MARK: Conectar una herramienta nueva, aquí mismo

    /// «Añadir herramienta» → elegir una: se abre **su conexión** encima del detalle (ficha, navegador, autorizar), sin pasar por
    /// el asistente ni por «Elige tus herramientas». Al quedar conectada se guarda en el agente y su fila entra a la lista.
    /// Es el flujo de conexión de siempre (`ConnectFlow`): todas las herramientas, con sus casos (QR de WhatsApp, la app
    /// de Slack, el nombre ocupado…).
    func startConnecting(_ tool: Tool) async {
        guard connecting == nil, !isPreparingConnection, !isWorking, addableTools.contains(tool),
            let installation = (try? installer.store.load()) ?? nil, installation.agent(id: agentID) != nil
        else { return }
        isPreparingConnection = true
        error = nil
        defer { isPreparingConnection = false }
        let wizard = makePicker(installation, agentID)
        // Solo esta herramienta: lo que el agente tenía saltado (y el modo «Gestionar» vuelve a poner por conectar) no entra.
        if !wizard.isSelected(tool) { wizard.toggle(tool) }
        wizard.connections.removeAll { $0.status != .connected && $0.tool != tool }
        // Con `claude` ya buscado, la conexión no parpadea con «Antes de conectar».
        await wizard.detectClaudeCodeIfNeeded()
        // Lista la conexión antes de mostrarla (si `claude` no está listo, la pantalla lo arregla y la arma después).
        if wizard.claudeStatus.isReady { wizard.beginConnecting() }
        isFinishingConnection = false
        connectingTool = tool
        connecting = wizard
        connectionObserver = wizard.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.connectionChanged() }
        }
    }

    /// Cierra la conexión sin guardar nada (el usuario canceló o saltó la herramienta).
    func cancelConnecting() {
        connectionObserver = nil
        connecting?.stopWorking()
        connecting = nil
        connectingTool = nil
        isFinishingConnection = false
    }

    private func connectionChanged() {
        guard let wizard = connecting, let tool = connectingTool, let flow = wizard.connectFlow else { return }
        if flow.statuses[tool] == .skipped {
            cancelConnecting()
            return
        }
        guard !isFinishingConnection, flow.statuses[tool] == .connected else { return }
        // «Conectada» llega antes que el final (WhatsApp sigue sincronizando): se espera a que la conexión **termine**.
        if case .succeeded = flow.phase {
            isFinishingConnection = true
            Task { [connectedHold] in
                try? await Task.sleep(for: connectedHold)
                await finishConnecting()
            }
        } else if flow.isFinished {
            isFinishingConnection = true
            Task { await finishConnecting() }
        }
    }

    /// Guarda la herramienta ya conectada en el agente (la conexión compartida y su carpeta), anota que cambiaron sus
    /// herramientas y deja que su fila entre a la lista.
    private func finishConnecting() async {
        guard let wizard = connecting, let tool = connectingTool, wizard.connectedTools.contains(tool) else {
            isFinishingConnection = false
            return
        }
        var config = wizard.makeConfig()
        // El asistente ordena las herramientas por rol: aquí las de antes conservan su sitio y la nueva entra al final de la lista.
        let order = (self.config?.connections ?? []).map(\.tool)
        config.connections.sort { (order.firstIndex(of: $0.tool) ?? .max) < (order.firstIndex(of: $1.tool) ?? .max) }
        connectionObserver = nil
        wizard.stopWorking()
        do {
            _ = try installer.install(config, existingAgentID: agentID)
        } catch {
            connecting = nil
            connectingTool = nil
            isFinishingConnection = false
            self.error = Localized.string("agent.error.save", locale: locale)
            return
        }
        connecting = nil
        connectingTool = nil
        isFinishingConnection = false
        home.noteToolsChanged(agentID)
        home.reload()
        reload()
        section = .tools
        justAdded = tool
        health.refresh()
        // El destello dura un momento.
        Task {
            try? await Task.sleep(for: .seconds(2.4))
            if justAdded == tool { justAdded = nil }
        }
    }

    func reconnect(_ tool: Tool) { health.reconnect(tool) }
    func relinkWhatsApp() { health.askRelink() }
    func askRemove(_ tool: Tool) { sheet = .removeTool(tool) }
    func closeSheet() { if !isWorking { sheet = nil } }

    /// «Quitar de este agente»: deja de leerla. La cuenta sigue conectada (otro agente puede estar usándola).
    @discardableResult
    func removeFromAgent(_ tool: Tool) -> Bool {
        let done = apply { $0.connections.removeAll { $0.tool == tool } }
        if done {
            home.noteToolsChanged(agentID)
            sheet = nil
        }
        return done
    }

    /// «Desconectar la cuenta»: quita los servidores `galeno-…` de Claude Code (los de **todos** los agentes de Galeno
    /// que la usan), la deja «por conectar» y vuelve a escribir cada agente que la tenía. Solo si la cuenta es de Galeno
    /// (`canDisconnectAccount`); nunca toca un servidor del usuario ni un conector de su cuenta de Claude.
    @discardableResult
    func disconnectAccount(_ tool: Tool) async -> Bool {
        guard canDisconnectAccount(tool), !isWorking else { return false }
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            guard var installation = try installer.store.load(), let shared = installation.connection(for: tool),
                shared.galenoOwnsServers, let target = ConnectTarget(tool: tool, namePrefix: shared.serverNamePrefix),
                !target.servers.isEmpty
            else {
                error = Localized.string("agent.error.save", locale: locale)
                return false
            }
            let users = installation.agents.filter { installation.resolvedConfig(for: $0.id)?.connectedTools.contains(tool) == true }
            try await disconnector.remove(servers: target.servers.map(\.name))
            installation.setConnection(
                SharedConnection(
                    tool: tool, status: .selected, oauthClientID: shared.oauthClientID,
                    serverNamePrefix: shared.serverNamePrefix))
            try installer.store.save(installation)
            for user in users {
                if let resolved = installation.resolvedConfig(for: user.id) {
                    _ = try installer.install(resolved, existingAgentID: user.id)
                }
                home.noteToolsChanged(user.id)
            }
            sheet = nil
            home.reload()
            reload()
            return true
        } catch {
            self.error = Localized.string("agent.error.disconnect", locale: locale)
            return false
        }
    }

    // MARK: Otra cuenta de una herramienta

    /// «Añadir otra cuenta»: abre la hoja con el nombre de la cuenta. Solo en las herramientas que Galeno registra.
    func askAddAccount(_ tool: Tool) {
        guard AccountConnector.canAdd(tool), !isWorking, sheet == nil else { return }
        accountDraft = ""
        accountPhase = .idle
        error = nil
        sheet = .addAccount(tool)
    }

    /// «Conectar»: registra la cuenta como otro servidor, espera a que el usuario autorice en su navegador y la suma
    /// a este agente (el motor le escribe sus propias reglas de permiso y su hook). Si algo falla no se guarda nada.
    func addAccount() {
        guard case .addAccount(let tool)? = sheet, accountPhase != .working else { return }
        guard let claudePath = locateClaude() else {
            accountPhase = .failed(.claudeOutdated)
            return
        }
        guard let installation = (try? installer.store.load()) ?? nil, installation.agent(id: agentID) != nil else {
            error = Localized.string("agent.error.unreadable", locale: locale)
            return
        }
        let existing = installation.connections(for: tool).map(\.id) + (config?.connections(for: tool).map(\.id) ?? [])
        let connection: ToolConnection
        switch AccountConnector.prepare(tool: tool, name: accountDraft, existing: existing) {
        case .failure(let issue):
            accountPhase = .failed(issue)
            return
        case .success(let prepared):
            connection = prepared
        }
        accountPhase = .working
        let connector = AccountConnector(mcp: makeMCP(claudePath))
        accountTask = Task { [weak self] in
            let issue = await connector.connect(connection, openAuthorization: nil)
            guard let self, !Task.isCancelled else { return }
            if let issue {
                self.accountPhase = .failed(issue)
                return
            }
            AppFocus.bringToFront()
            self.finishAddingAccount(connection)
        }
    }

    private func finishAddingAccount(_ connection: ToolConnection) {
        let saved = apply { config in
            config.connections.removeAll { $0.id == connection.id }
            config.connections.append(connection)
        }
        accountTask = nil
        guard saved else {
            accountPhase = .failed(.stillNotConnected)
            return
        }
        accountPhase = .idle
        sheet = nil
        home.noteToolsChanged(agentID)
        section = .tools
        justAddedAccount = connection.id
        health.refresh()
        Task {
            try? await Task.sleep(for: .seconds(2.4))
            if justAddedAccount == connection.id { justAddedAccount = nil }
        }
    }

    /// Cierra la hoja de «Añadir otra cuenta» (también si estaba esperando la autorización).
    func cancelAddingAccount() {
        accountTask?.cancel()
        accountTask = nil
        accountPhase = .idle
        if case .addAccount? = sheet { sheet = nil }
    }

    /// «Reconectar» una cuenta extra: la misma conexión de siempre (idempotente), con su servidor.
    func reconnectAccount(_ id: ConnectionID) {
        guard reconnectingAccount == nil, !isWorking, let claudePath = locateClaude(),
            let connection = config?.connection(for: id), connection.accountID != nil
        else { return }
        reconnectingAccount = id
        let connector = AccountConnector(mcp: makeMCP(claudePath))
        Task { [weak self] in
            _ = await connector.connect(connection, openAuthorization: nil)
            guard let self else { return }
            AppFocus.bringToFront()
            self.reconnectingAccount = nil
            self.health.refresh()
        }
    }

    func askRemoveAccount(_ id: ConnectionID) { sheet = .removeAccount(id) }

    /// «Quitar de este agente» una cuenta extra: deja de leerla. La cuenta sigue conectada.
    @discardableResult
    func removeAccountFromAgent(_ id: ConnectionID) -> Bool {
        let done = apply { $0.connections.removeAll { $0.id == id } }
        if done {
            home.noteToolsChanged(agentID)
            sheet = nil
        }
        return done
    }

    /// «Desconectar la cuenta» extra: quita **ese** servidor de Claude Code (nunca el de otra cuenta ni uno del
    /// usuario) y la saca de todos los agentes que la leían.
    @discardableResult
    func disconnectExtraAccount(_ id: ConnectionID) async -> Bool {
        guard id.account != nil, !isWorking else { return false }
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            guard var installation = try installer.store.load(), let shared = installation.connection(for: id),
                shared.galenoOwnsServers,
                let server = AccountConnector.server(
                    of: ToolConnection(
                        tool: id.tool, serverNamePrefix: shared.serverNamePrefix, accountID: id.account,
                        accountName: shared.accountName))
            else {
                error = Localized.string("agent.error.save", locale: locale)
                return false
            }
            let users = installation.agents.filter { installation.resolvedConfig(for: $0.id)?.connection(for: id) != nil }
            try await disconnector.remove(servers: [server.name])
            installation.connections.removeAll { $0.id == id }
            for user in users {
                guard var record = installation.agent(id: user.id) else { continue }
                record.config.connections.removeAll { $0.id == id }
                try installation.setConfig(record.config, for: user.id)
            }
            try installer.store.save(installation)
            for user in users {
                if let resolved = installation.resolvedConfig(for: user.id) {
                    _ = try installer.install(resolved, existingAgentID: user.id)
                }
                home.noteToolsChanged(user.id)
            }
            sheet = nil
            home.reload()
            reload()
            return true
        } catch {
            self.error = Localized.string("agent.error.disconnect", locale: locale)
            return false
        }
    }

    // MARK: General

    func setRole(_ newRole: AgentRole) {
        guard newRole != role else { return }
        apply { $0.role = newRole }
    }

    func revealFolder() {
        if let folder { reveal(folder) }
    }

    // MARK: Reglas

    /// Las escrituras que se pueden decidir: las de las herramientas que el agente lee.
    var configurableWrites: [InternalWrite] {
        let tools = config?.connectedTools ?? []
        return InternalWrite.allCases.filter { write in tools.contains { $0.internalWrites.contains(write) } }
    }

    func policy(for write: InternalWrite) -> ApprovalPolicy { config?.sendingRules.policy(for: write) ?? .ask }

    func setPolicy(_ policy: ApprovalPolicy, for write: InternalWrite) {
        guard policy != self.policy(for: write) else { return }
        apply { $0.sendingRules.setPolicy(policy, for: write) }
    }

    // MARK: Skills

    var skillCount: Int { config?.skills.count ?? 0 }

    /// Prepara las cards de skills de este agente (idempotente). La vista lo llama al entrar a la sección.
    func prepareSkillsEditor() {
        guard picker == nil, let installation = (try? installer.store.load()) ?? nil,
            installation.agent(id: agentID) != nil
        else { return }
        let wizard = makePicker(installation, agentID)
        wizard.loadSkillCatalog()
        picker = wizard
    }

    /// ¿Hay algo marcado, quitado o traído que todavía no se guardó?
    var skillsDirty: Bool {
        guard let picker, let config else { return false }
        return Set(picker.skills) != Set(config.skills) || !picker.pendingOwnSkillImports.isEmpty
            || !picker.pendingOwnSkillTrash.isEmpty
    }

    /// «Descartar»: vuelve a lo guardado.
    func discardSkillChanges() {
        picker = nil
        prepareSkillsEditor()
    }

    func saveSkills() {
        guard let picker, skillsDirty else { return }
        let skills = picker.skills
        if apply(
            ownSkills: picker.pendingOwnSkillImports, ownSkillsToTrash: picker.pendingOwnSkillTrash,
            { $0.skills = skills })
        {
            // Ya está guardado: se arma de nuevo desde lo guardado (lo traído ya vive en `skills-propias/`).
            self.picker = nil
            prepareSkillsEditor()
        }
    }

    // MARK: Contexto

    var hasUnsavedContext: Bool {
        let description = projectDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return description != (config?.projectDescription ?? "") || !pendingContext.isEmpty || !removedContext.isEmpty
    }

    /// Cuántos materiales caben todavía, contando lo que se quitó y lo que está por añadir.
    var contextSlotsLeft: Int {
        max(0, ContextFile.maxFiles - (contextEntries.count - removedContext.count) - pendingContext.count)
    }

    private var contextCharacters: Int {
        guard let folder else { return pendingContext.reduce(0) { $0 + $1.text.count } }
        let kept = contextEntries.filter { !removedContext.contains($0.fileName) }.reduce(0) { total, entry in
            let url = ContextFolder.directory(in: folder).appending(path: entry.fileName)
            return total + ((try? String(contentsOf: url, encoding: .utf8).count) ?? 0)
        }
        return kept + pendingContext.reduce(0) { $0 + $1.text.count }
    }

    /// Trae un material de un archivo del Mac. Queda por añadir hasta «Guardar contexto».
    func addContext(from url: URL) {
        do {
            let file = try importContext(url)
            let text = file.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { contextProblem = .empty; return }
            if contextSlotsLeft == 0 { contextProblem = .tooMany; return }
            if contextCharacters >= ContextFile.maxCharactersTotal { contextProblem = .tooLong; return }
            pendingContext.append(ContextFile(title: file.title, text: text))
            contextProblem = nil
        } catch ContextImporter.Failure.unsupported {
            contextProblem = .unsupported
        } catch ContextImporter.Failure.tooLarge {
            contextProblem = .tooLarge
        } catch {
            contextProblem = .unreadable
        }
    }

    func removePendingContext(_ file: ContextFile) { pendingContext.removeAll { $0 == file } }

    /// «Quitar» un material que ya está: se marca, y va a la Papelera al guardar. Otra vez lo devuelve.
    func toggleRemoveContext(_ entry: ContextEntry) {
        if removedContext.contains(entry.fileName) { removedContext.remove(entry.fileName) } else { removedContext.insert(entry.fileName) }
    }

    /// «Guardar contexto»: la línea del proyecto (se vuelve a escribir el `AGENTS.md`) y los materiales (los nuevos a
    /// `memoria/contexto/`, sin pisar ninguno; los quitados, a la Papelera).
    @discardableResult
    func saveContext() -> Bool {
        guard let record, !isWorking else { return false }
        let description = String(
            projectDraft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(WizardState.maxProjectDescriptionLength))
        if description != (config?.projectDescription ?? "") {
            guard apply({ $0.projectDescription = description }) else { return false }
        }
        do {
            for fileName in removedContext {
                try ContextFolder.trash(fileName: fileName, in: record.folder, trasher: trashContext)
            }
            if !pendingContext.isEmpty {
                try ContextFolder.add(pendingContext, to: record.folder, language: language)
            }
        } catch {
            self.error = Localized.string("agent.error.context", locale: locale)
            reload()
            return false
        }
        pendingContext = []
        removedContext = []
        contextProblem = nil
        reload()
        return true
    }

    // MARK: Eliminar y renombrar (los del home)

    func askRename() { if let agent { home.askRename(agent) } }
    func askDelete() { if let agent { home.askDelete(agent) } }

    // MARK: Escribir la carpeta

    /// Cambia la configuración del agente y vuelve a escribir su carpeta (`memoria/` no se toca). Devuelve si quedó hecho;
    /// si no, `error` lo dice y no se cambió nada.
    @discardableResult
    private func apply(
        ownSkills: [AgentInstaller.OwnSkillImport] = [], ownSkillsToTrash: [String] = [],
        _ mutate: (inout AgentConfig) -> Void
    ) -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            guard let installation = try installer.store.load(), var resolved = installation.resolvedConfig(for: agentID)
            else {
                error = Localized.string("agent.error.unreadable", locale: locale)
                return false
            }
            mutate(&resolved)
            _ = try installer.install(
                resolved, existingAgentID: agentID, ownSkills: ownSkills, ownSkillsToTrash: ownSkillsToTrash)
            home.reload()
            reload()
            return true
        } catch {
            self.error = Localized.string("agent.error.save", locale: locale)
            return false
        }
    }
}
