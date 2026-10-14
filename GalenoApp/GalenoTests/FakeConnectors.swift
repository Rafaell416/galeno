import Foundation

@testable import Galeno

/// `MCPConnecting` con guion: estados iniciales, fallos que se acaban, y el dato real
/// que se puede retener hasta que la prueba lo suelte.
final class FakeMCP: MCPConnecting, @unchecked Sendable {
    private let lock = NSLock()
    private var statuses: [String: MCPStatus]
    private var otherServers: Set<String>
    private var registerError: MCPConnectError?
    private var removeError: MCPConnectError?
    private var loginFailures: [String: [MCPConnectError]]
    private var counts: [String: ItemCount]
    private var holdCounts: Bool
    private var holdLogin: Bool
    /// Servidores que, aun tras autorizar, no conectan: por qué (la línea `Issue:`).
    private var issues: [String: String]
    /// La dirección que «abre» `claude` al autorizar (si se le dio dónde mostrarla).
    private var authorizationURL: URL?
    private var held: [CheckedContinuation<Void, Never>] = []
    private var recorded: [String] = []
    /// Servidores que quedan conectados nada más registrarlos (entran con la sesión de Claude Code, sin OAuth).
    var connectsOnRegister: Set<String> = []

    init(
        statuses: [String: MCPStatus] = [:],
        otherServers: Set<String> = [],
        registerError: MCPConnectError? = nil,
        removeError: MCPConnectError? = nil,
        loginFailures: [String: [MCPConnectError]] = [:],
        counts: [String: ItemCount] = [:],
        holdCounts: Bool = false,
        holdLogin: Bool = false,
        issues: [String: String] = [:],
        authorizationURL: URL? = nil
    ) {
        self.issues = issues
        self.authorizationURL = authorizationURL
        self.statuses = statuses
        self.otherServers = otherServers
        self.registerError = registerError
        self.removeError = removeError
        self.loginFailures = loginFailures
        self.counts = counts
        self.holdCounts = holdCounts
        self.holdLogin = holdLogin
    }

    var calls: [String] { lock.withLock { recorded } }

    /// Cambia el estado de un servidor a mitad de una prueba (el usuario hizo algo en el navegador).
    func setStatus(_ server: String, _ status: MCPStatus) { lock.withLock { statuses[server] = status } }

    /// Cómo se registró cada servidor con su app OAuth propia (sin el secreto: solo si lo hubo).
    private var registrations: [String: (clientID: String, port: Int?, hadSecret: Bool, secretValue: String?)] = [:]
    func registration(of server: String) -> (clientID: String, port: Int?, hadSecret: Bool, secretValue: String?)? {
        lock.withLock { registrations[server] }
    }

    func status(of server: String, expectingURL: String?) async -> MCPStatus {
        lock.withLock {
            recorded.append("status \(server)")
            if otherServers.contains(server) { return .differentServer }
            return statuses[server] ?? .notRegistered
        }
    }

    func register(server: String, url: String, oauth: OAuthClientRegistration?) async throws {
        let error: MCPConnectError? = lock.withLock {
            recorded.append(oauth == nil ? "register \(server)" : "register \(server) con app propia")
            return registerError
        }
        if let error { throw error }
        // El valor del secreto se copia **solo para que la prueba pueda comprobar que llegó**; lo
        // que se anota en `calls` nunca lo lleva.
        let secretValue = oauth?.secret?.withValue { $0 }
        lock.withLock {
            statuses[server] = connectsOnRegister.contains(server) ? .connected : .needsAuthentication
            if let oauth {
                registrations[server] = (oauth.clientID, oauth.callbackPort, secretValue != nil, secretValue)
            }
        }
    }

    /// Lo que pasa con un conector de la cuenta de Claude después de abrirle el navegador: a las
    /// `connectsAfterChecks` miradas de estado, queda conectado (el usuario autorizó). `nil` = nunca.
    var connectorConnectsAfterChecks: Int?
    private var connectorChecks = 0

    /// El estado real del conector (lo que diría una sesión): el mismo guion que `status`.
    func connectorStatus(_ server: String) async -> MCPStatus {
        lock.withLock {
            recorded.append("connector-status \(server)")
            if statuses[server] != .connected, let after = connectorConnectsAfterChecks {
                connectorChecks += 1
                if connectorChecks > after { statuses[server] = .connected; connectorChecks = 0 }
            }
            return statuses[server] ?? .notRegistered
        }
    }

    func authorizeConnector(_ server: String) async throws {
        let failure: MCPConnectError? = lock.withLock {
            recorded.append("authorize \(server)")
            guard var pending = loginFailures[server], !pending.isEmpty else { return nil }
            let first = pending.removeFirst()
            loginFailures[server] = pending
            return first
        }
        if let failure { throw failure }
    }

    func remove(server: String) async throws {
        let error: MCPConnectError? = lock.withLock {
            recorded.append("remove \(server)")
            return removeError
        }
        if let error { throw error }
        lock.withLock {
            otherServers.remove(server)
            statuses[server] = nil
        }
    }

    func login(server: String, openAuthorization: AuthorizationOpener?) async throws {
        let failure: MCPConnectError? = lock.withLock {
            recorded.append("login \(server)")
            if openAuthorization != nil { recorded.append("login \(server) con autorización propia") }
            guard var pending = loginFailures[server], !pending.isEmpty else { return nil }
            let first = pending.removeFirst()
            loginFailures[server] = pending
            return first
        }
        if let failure { throw failure }
        // Como `claude`: pide mostrar la dirección de autorización, si se le dio dónde.
        if let openAuthorization, let url = authorizationURL {
            let handled = await openAuthorization(url)
            lock.withLock { recorded.append("autorización \(handled ? "mostrada" : "no mostrada") \(url.host ?? "")") }
        }
        // Como el usuario que todavía no autorizó: espera hasta que lo cancelen.
        while lock.withLock({ holdLogin }) {
            if Task.isCancelled { throw MCPConnectError.cancelled }
            try? await Task.sleep(for: .milliseconds(5))
        }
        lock.withLock { statuses[server] = issues[server] == nil ? .connected : .failed }
    }

    func issue(of server: String) async -> String? {
        lock.withLock {
            recorded.append("issue \(server)")
            return issues[server]
        }
    }

    /// `claude mcp list`: lo mismo que `statuses`, salvo que se haga fallar el listado.
    var listingFails = false
    func listStatuses() async -> [String: MCPStatus]? {
        lock.withLock {
            recorded.append("list")
            return listingFails ? nil : statuses
        }
    }

    func countItems(server: String, noun: String) async -> ItemCount? {
        let mustHold: Bool = lock.withLock {
            recorded.append("count \(server) \(noun)")
            return holdCounts
        }
        if mustHold {
            await withCheckedContinuation { continuation in
                lock.withLock { held.append(continuation) }
            }
        }
        return lock.withLock { counts[server] }
    }

    /// Suelta los datos retenidos.
    func releaseCounts() {
        let toResume: [CheckedContinuation<Void, Never>] = lock.withLock {
            holdCounts = false
            defer { held = [] }
            return held
        }
        for continuation in toResume { continuation.resume() }
    }
}

/// `WhatsAppLinking` con guion.
final class FakeWhatsApp: WhatsAppLinking, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    private let prepareError: WhatsAppBridgeError?
    private let state: WhatsAppLinkState
    private let pairEvents: [WhatsAppPairEvent]
    private let installError: WhatsAppBridgeError?
    private var counts: [ChatCounts]
    private var countIndex = 0

    init(
        prepareError: WhatsAppBridgeError? = nil,
        state: WhatsAppLinkState = .notLinked,
        pairEvents: [WhatsAppPairEvent] = [.succeeded],
        installError: WhatsAppBridgeError? = nil,
        counts: [ChatCounts] = [ChatCounts(total: 12, groups: 3)]
    ) {
        self.prepareError = prepareError
        self.state = state
        self.pairEvents = pairEvents
        self.installError = installError
        self.counts = counts
    }

    var calls: [String] { lock.withLock { recorded } }

    // Lo que ve la vista de salud. `pair` con éxito vincula, `unlink` desvincula, `installLaunchd` deja `sync` corriendo.
    private var statusValue: WhatsAppStatus?
    private var syncValue: WhatsAppSyncState = .notInstalled
    private var unlinkError: WhatsAppBridgeError?
    var reportedStatus: WhatsAppStatus? {
        get { lock.withLock { statusValue } }
        set { lock.withLock { statusValue = newValue } }
    }
    var reportedSync: WhatsAppSyncState {
        get { lock.withLock { syncValue } }
        set { lock.withLock { syncValue = newValue } }
    }
    var failUnlink: WhatsAppBridgeError? {
        get { lock.withLock { unlinkError } }
        set { lock.withLock { unlinkError = newValue } }
    }

    func status() async -> WhatsAppStatus? {
        lock.withLock {
            recorded.append("status")
            return statusValue
        }
    }

    func syncState() async -> WhatsAppSyncState {
        lock.withLock {
            recorded.append("syncState")
            return syncValue
        }
    }

    func unlink() async throws {
        let error: WhatsAppBridgeError? = lock.withLock {
            recorded.append("unlink")
            return unlinkError
        }
        if let error { throw error }
        lock.withLock {
            statusValue = WhatsAppStatus(isLinked: false, number: nil, linkedAt: nil, bridgeVersion: statusValue?.bridgeVersion ?? "0.3.0")
            syncValue = .notInstalled
        }
    }

    func prepare() async throws {
        lock.withLock { recorded.append("prepare") }
        if let prepareError { throw prepareError }
    }

    func linkState() async throws -> WhatsAppLinkState {
        lock.withLock { recorded.append("linkState") }
        return state
    }

    func pair() -> AsyncStream<WhatsAppPairEvent> {
        lock.withLock { recorded.append("pair") }
        if pairEvents.contains(.succeeded) {
            lock.withLock {
                statusValue = WhatsAppStatus(
                    isLinked: true, number: "573001234567", linkedAt: Date(), bridgeVersion: statusValue?.bridgeVersion ?? "0.3.0")
            }
        }
        let events = pairEvents
        return AsyncStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish()
        }
    }

    func uninstallService() async throws {
        lock.withLock {
            recorded.append("uninstallService")
            syncValue = .notInstalled
        }
    }

    func installLaunchd() async throws {
        lock.withLock { recorded.append("installLaunchd") }
        if let installError { throw installError }
        lock.withLock { syncValue = .running }
    }

    func chatCounts() async -> ChatCounts? {
        lock.withLock {
            recorded.append("chatCounts")
            let value = counts[min(countIndex, counts.count - 1)]
            countIndex += 1
            return value
        }
    }

    // La bandeja de salida. `nil` es un bridge que no contesta (o anterior a la 0.4.0).
    private var outboxValue: WhatsAppOutbox?
    private var sendingError: WhatsAppBridgeError?
    var reportedOutbox: WhatsAppOutbox? {
        get { lock.withLock { outboxValue } }
        set { lock.withLock { outboxValue = newValue } }
    }
    var failSendingChanges: WhatsAppBridgeError? {
        get { lock.withLock { sendingError } }
        set { lock.withLock { sendingError = newValue } }
    }

    /// Una bandeja con los topes de fábrica y nada enviado.
    static let emptyOutbox = WhatsAppOutbox(
        isPaused: false,
        limits: WhatsAppOutbox.Limits(
            dailyTotal: 40, dailyNewChats: 15, dailyGroups: 10, maxDailyTotal: 80, maxDailyNewChats: 25,
            maxDailyGroups: 20),
        sentToday: 0, pendingToday: 0, newChatsToday: 0, groupsToday: 0, pendingTotal: 0)

    func outbox() async -> WhatsAppOutbox? {
        lock.withLock {
            recorded.append("outbox")
            return outboxValue
        }
    }

    func setSendingPaused(_ paused: Bool) async throws {
        let error: WhatsAppBridgeError? = lock.withLock {
            recorded.append("pause:\(paused)")
            return sendingError
        }
        if let error { throw error }
        lock.withLock { outboxValue?.isPaused = paused }
    }

    func setSendLimits(dailyTotal: Int, dailyNewChats: Int, dailyGroups: Int) async throws {
        let error: WhatsAppBridgeError? = lock.withLock {
            recorded.append("limits:\(dailyTotal),\(dailyNewChats),\(dailyGroups)")
            return sendingError
        }
        if let error { throw error }
        lock.withLock {
            outboxValue?.limits.dailyTotal = dailyTotal
            outboxValue?.limits.dailyNewChats = dailyNewChats
            outboxValue?.limits.dailyGroups = dailyGroups
        }
    }
}

/// `SlackAppSetting` con guion. Guarda **solo en la prueba** copias de los valores que vio, para
/// poder afirmar que llegaron; nada de eso vive en el código de la app.
final class FakeSlackSetup: SlackAppSetting, @unchecked Sendable {
    private let lock = NSLock()
    private let validateError: SlackSetupError?
    private let createError: SlackSetupError?
    private let clientID: String
    private let secretValue: String
    private var recorded: [String] = []
    private var seenTokens: [String] = []
    private var seenNames: [String] = []
    private var issued: [OAuthSecret] = []

    init(
        validateError: SlackSetupError? = nil, createError: SlackSetupError? = nil,
        clientID: String = "1234567890123.1234567890123", secretValue: String = "SECRETO-DE-PRUEBA"
    ) {
        self.validateError = validateError
        self.createError = createError
        self.clientID = clientID
        self.secretValue = secretValue
    }

    var calls: [String] { lock.withLock { recorded } }
    var tokens: [String] { lock.withLock { seenTokens } }
    var agentNames: [String] { lock.withLock { seenNames } }
    var createCount: Int { lock.withLock { recorded.filter { $0 == "createApp" }.count } }
    /// Los secretos que se entregaron, para comprobar después que se borraron.
    var issuedSecrets: [OAuthSecret] { lock.withLock { issued } }

    func validate(token: OAuthSecret, agentName: String) async throws {
        lock.withLock {
            recorded.append("validate")
            seenTokens.append(token.withValue { $0 })
            seenNames.append(agentName)
        }
        if let validateError { throw validateError }
    }

    func createApp(token: OAuthSecret, agentName: String) async throws -> OAuthClientRegistration {
        lock.withLock { recorded.append("createApp") }
        if let createError { throw createError }
        let secret = OAuthSecret(secretValue)
        lock.withLock { issued.append(secret) }
        return OAuthClientRegistration(clientID: clientID, callbackPort: 51820, secret: secret, appID: "A0TESTAPP01")
    }
}
