import Foundation

@testable import Galeno

/// `MCPConnecting` con guion: estados iniciales, fallos que se acaban, y el dato real
/// que se puede retener hasta que la prueba lo suelte.
final class FakeMCP: MCPConnecting, @unchecked Sendable {
    private let lock = NSLock()
    private var statuses: [String: MCPStatus]
    private var registerError: MCPConnectError?
    private var loginFailures: [String: [MCPConnectError]]
    private var counts: [String: ItemCount]
    private var holdCounts: Bool
    private var holdLogin: Bool
    private var held: [CheckedContinuation<Void, Never>] = []
    private var recorded: [String] = []

    init(
        statuses: [String: MCPStatus] = [:],
        registerError: MCPConnectError? = nil,
        loginFailures: [String: [MCPConnectError]] = [:],
        counts: [String: ItemCount] = [:],
        holdCounts: Bool = false,
        holdLogin: Bool = false
    ) {
        self.statuses = statuses
        self.registerError = registerError
        self.loginFailures = loginFailures
        self.counts = counts
        self.holdCounts = holdCounts
        self.holdLogin = holdLogin
    }

    var calls: [String] { lock.withLock { recorded } }

    func status(of server: String) async -> MCPStatus {
        lock.withLock {
            recorded.append("status \(server)")
            return statuses[server] ?? .notRegistered
        }
    }

    func register(server: String, url: String) async throws {
        let error: MCPConnectError? = lock.withLock {
            recorded.append("register \(server)")
            return registerError
        }
        if let error { throw error }
        lock.withLock { statuses[server] = .needsAuthentication }
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
