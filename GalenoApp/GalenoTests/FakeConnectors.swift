import Foundation

@testable import Galeno

/// `MCPConnecting` con guion: estados iniciales, fallos que se acaban, y el dato real
/// que se puede retener hasta que la prueba lo suelte.
final class FakeMCP: MCPConnecting, @unchecked Sendable {
    private let lock = NSLock()
    private var statuses: [String: MCPStatus]
    private var otherServers: Set<String>
    private var registerError: MCPConnectError?
    private var loginFailures: [String: [MCPConnectError]]
    private var counts: [String: ItemCount]
    private var holdCounts: Bool
    private var holdLogin: Bool
    private var held: [CheckedContinuation<Void, Never>] = []
    private var recorded: [String] = []

    init(
        statuses: [String: MCPStatus] = [:],
        otherServers: Set<String> = [],
        registerError: MCPConnectError? = nil,
        loginFailures: [String: [MCPConnectError]] = [:],
        counts: [String: ItemCount] = [:],
        holdCounts: Bool = false,
        holdLogin: Bool = false
    ) {
        self.statuses = statuses
        self.otherServers = otherServers
        self.registerError = registerError
        self.loginFailures = loginFailures
        self.counts = counts
        self.holdCounts = holdCounts
        self.holdLogin = holdLogin
    }

    var calls: [String] { lock.withLock { recorded } }

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
            statuses[server] = .needsAuthentication
            if let oauth {
                registrations[server] = (oauth.clientID, oauth.callbackPort, secretValue != nil, secretValue)
            }
        }
    }

    func login(server: String) async throws {
        let failure: MCPConnectError? = lock.withLock {
            recorded.append("login \(server)")
            guard var pending = loginFailures[server], !pending.isEmpty else { return nil }
            let first = pending.removeFirst()
            loginFailures[server] = pending
            return first
        }
        if let failure { throw failure }
        // Como el usuario que todavía no autorizó: espera hasta que lo cancelen.
        while lock.withLock({ holdLogin }) {
            if Task.isCancelled { throw MCPConnectError.cancelled }
            try? await Task.sleep(for: .milliseconds(5))
        }
        lock.withLock { statuses[server] = .connected }
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
        let events = pairEvents
        return AsyncStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish()
        }
    }

    func installLaunchd() async throws {
        lock.withLock { recorded.append("installLaunchd") }
        if let installError { throw installError }
    }

    func chatCounts() async -> ChatCounts? {
        lock.withLock {
            recorded.append("chatCounts")
            let value = counts[min(countIndex, counts.count - 1)]
            countIndex += 1
            return value
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
        return OAuthClientRegistration(clientID: clientID, callbackPort: 51820, secret: secret)
    }
}
