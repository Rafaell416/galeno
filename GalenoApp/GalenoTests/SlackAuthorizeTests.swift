import GalenoCore
import WebKit
import XCTest

@testable import Galeno

/// Lo que se puede abrir en la ventana de autorización de Slack.
final class SlackAuthorizationPolicyTests: XCTestCase {
    private func url(_ text: String) -> URL? { URL(string: text) }

    func testOnlySlackPagesOverHTTPSCountAsAuthorizationPages() {
        for ok in ["https://slack.com/oauth/v2_user/authorize?client_id=1", "https://acme.slack.com/openid/connect/authorize"] {
            XCTAssertTrue(SlackAuthorization.isSlackAuthorizationURL(url(ok)), ok)
        }
        for bad in [
            "http://slack.com/oauth", "https://slack.com.evil.example/oauth", "https://evilslack.com/x",
            "https://accounts.google.com/o/oauth2", "file:///etc/passwd", "slack://open",
        ] {
            XCTAssertFalse(SlackAuthorization.isSlackAuthorizationURL(url(bad)), bad)
        }
        XCTAssertFalse(SlackAuthorization.isSlackAuthorizationURL(nil))
    }

    /// Lo único que no es `https` y se acepta: la vuelta exacta de `claude` a su puerto.
    func testTheOnlyAllowedHTTPAddressIsTheExactCallbackOnGalenosPort() {
        XCTAssertTrue(SlackAuthorization.isCallback(url("http://localhost:51820/callback?code=abc&state=xyz")))
        for bad in [
            "http://localhost:51821/callback", "http://localhost:51820/other", "http://localhost/callback",
            "http://127.0.0.1:51820/callback", "https://localhost:51820/callback", "http://evil.example:51820/callback",
            "http://localhost:51820/callback/../x",
        ] {
            XCTAssertFalse(SlackAuthorization.isCallback(url(bad)), bad)
        }
        XCTAssertEqual(SlackAuthorization.navigationDecision(for: url("http://localhost:51820/callback?code=1")), .allow)
        XCTAssertEqual(SlackAuthorization.navigationDecision(for: url("http://localhost:9999/callback")), .blocked)
        XCTAssertEqual(SlackAuthorization.navigationDecision(for: url("http://slack.com")), .blocked)
        XCTAssertEqual(
            SlackAuthorization.navigationDecision(for: url("https://accounts.google.com/signin")), .blockedGoogleSignIn)
        XCTAssertEqual(SlackAuthorization.navigationDecision(for: url("https://slack.com/signin")), .allow)
    }
}

/// `claude mcp login` abre la autorización con `$BROWSER`: Galeno le da uno que solo apunta la dirección.
final class BrowserInterceptionTests: XCTestCase {
    private let claude = "/usr/local/bin/claude"
    private let authorizeURL = "https://slack.com/oauth/v2_user/authorize?client_id=1111.2222&state=abc"

    /// Hace lo que haría `claude`: llama al programa de `$BROWSER` con la dirección.
    private func claudeOpening(_ address: String) -> @Sendable ([String: String]) async -> Void {
        { environment in
            guard let browser = environment["BROWSER"] else { return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: browser)
            process.arguments = [address]
            try? process.run()
            process.waitUntilExit()
            // Da tiempo a que Galeno la recoja (lo hace cada 100 ms).
            try? await Task.sleep(for: .milliseconds(600))
        }
    }

    private func terminal(opening address: String?) -> FakeTerminalForLogin {
        let terminal = FakeTerminalForLogin()
        if let address { terminal.whileRunning = claudeOpening(address) }
        return terminal
    }

    func testTheAuthorizationAddressGoesToGalenoInsteadOfTheSystemBrowser() async throws {
        let terminal = terminal(opening: authorizeURL)
        let client = ClaudeMCPClient(claudePath: claude, runner: FakeRunner([:]), terminal: terminal)
        let received = Received()

        try await client.login(server: "slack") { url in
            received.set(url)
            return true
        }

        XCTAssertEqual(received.value?.absoluteString, authorizeURL)
        XCTAssertNotNil(terminal.environments.first?["BROWSER"], "claude recibió un «navegador»")
    }

    func testIfGalenoDoesNotShowItTheSystemBrowserOpensIt() async throws {
        let terminal = terminal(opening: authorizeURL)
        let runner = FakeRunner(["/usr/bin/open \(authorizeURL)": ok("")])
        let client = ClaudeMCPClient(claudePath: claude, runner: runner, terminal: terminal)

        try await client.login(server: "slack") { _ in false }
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(runner.calls, ["/usr/bin/open \(authorizeURL)"])
    }

    func testWithoutAnOpenerTheBrowserIsLeftAlone() async throws {
        let terminal = terminal(opening: nil)
        let client = ClaudeMCPClient(claudePath: claude, runner: FakeRunner([:]), terminal: terminal)

        try await client.login(server: "notion")

        XCTAssertNil(terminal.environments.first?["BROWSER"])
    }

    /// Solo `https`: lo que no lo sea no se muestra ni se abre.
    func testANonHTTPSAddressIsIgnored() async throws {
        let terminal = terminal(opening: "file:///etc/passwd")
        let client = ClaudeMCPClient(claudePath: claude, runner: FakeRunner([:]), terminal: terminal)
        let received = Received()

        try await client.login(server: "slack") { url in
            received.set(url)
            return true
        }

        XCTAssertNil(received.value)
    }

    func testTheInterceptorLivesInAPrivateFolderAndCleansUp() throws {
        let interceptor = try XCTUnwrap(BrowserInterceptor())
        let script = URL(fileURLWithPath: interceptor.scriptPath)
        let attributes = try FileManager.default.attributesOfItem(atPath: script.deletingLastPathComponent().path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: interceptor.scriptPath))

        interceptor.cleanUp()
        XCTAssertFalse(FileManager.default.fileExists(atPath: interceptor.scriptPath))
    }
}

private final class Received: @unchecked Sendable {
    private let lock = NSLock()
    private var url: URL?
    var value: URL? { lock.withLock { url } }
    func set(_ new: URL) { lock.withLock { url = new } }
}

/// Un terminal falso para `login`: termina bien como `claude` («Authenticated with…»).
private final class FakeTerminalForLogin: TerminalRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedEnvironments: [[String: String]] = []
    var environments: [[String: String]] { lock.withLock { recordedEnvironments } }
    var whileRunning: (@Sendable ([String: String]) async -> Void)?

    func runInTerminal(
        _ executable: String, arguments: [String], environment: [String: String], timeout: TimeInterval
    ) async -> ManagedProcess.Result? {
        lock.withLock { recordedEnvironments.append(environment) }
        await whileRunning?(environment)
        return ManagedProcess.Result(status: 0, output: "Authenticated with slack", wasStopped: false)
    }
}

// MARK: - En el flujo

@MainActor
private final class FakePresenter: SlackAuthorizationPresenting {
    private(set) var presented: [(url: URL, language: Language)] = []
    private(set) var dismissals = 0
    private var cancel: (@MainActor () -> Void)?
    private var appNotFound: (@MainActor () -> Void)?

    func presentAuthorization(
        url: URL, dataStore: WKWebsiteDataStore, language: Language,
        onCancel: @escaping @MainActor () -> Void, onAppNotFound: @escaping @MainActor () -> Void
    ) {
        presented.append((url, language))
        cancel = onCancel
        appNotFound = onAppNotFound
    }

    func slackSaysTheAppIsGone() { appNotFound?() }

    func dismissAuthorization() { dismissals += 1 }
    func userClosesTheWindow() { cancel?() }
}

@MainActor
final class SlackAuthorizationFlowTests: XCTestCase {
    private let slackURL = URL(string: "https://slack.com/oauth/v2_user/authorize?client_id=1111.2222")!
    private let presenter = FakePresenter()

    private func makeFlow(tools: [Tool] = [.slack], mcp: FakeMCP) -> ConnectFlow {
        ConnectFlow(
            tools: tools, mcp: mcp, whatsapp: FakeWhatsApp(), slack: FakeSlackSetup(),
            agentName: { "Aurora" }, fetchRealData: false, sleep: SleepLog.holdingSuccess.sleeper,
            authorizer: presenter, language: { .english })
    }

    private func finishSlack(_ flow: ConnectFlow) async {
        _ = await waitUntil { flow.phase == .slackToken }
        flow.submitSlackToken("xoxe.xoxp-token-de-prueba")
    }

    func testSlacksAuthorizationIsShownInGalenosWindowInTheWizardsLanguage() async {
        let mcp = FakeMCP(authorizationURL: slackURL)
        let flow = makeFlow(mcp: mcp)
        defer { flow.cancelAll() }

        await finishSlack(flow)
        let done = await waitUntil { flow.phase == .succeeded(alreadyConnected: false) }

        XCTAssertTrue(done, "\(flow.phase)")
        XCTAssertEqual(presenter.presented.map(\.url), [slackURL])
        XCTAssertEqual(presenter.presented.first?.language, .english)
        XCTAssertTrue(mcp.calls.contains("login slack con autorización propia"))
        XCTAssertGreaterThan(presenter.dismissals, 0, "la ventana se cierra cuando termina el login")
    }

    /// Una dirección que no es de Slack nunca se muestra en la ventana: va al navegador del sistema.
    func testAnAddressThatIsNotSlacksIsNotShownInTheWindow() async {
        let mcp = FakeMCP(authorizationURL: URL(string: "https://evil.example.com/authorize")!)
        let flow = makeFlow(mcp: mcp)
        defer { flow.cancelAll() }

        await finishSlack(flow)
        _ = await waitUntil { flow.phase == .succeeded(alreadyConnected: false) }

        XCTAssertTrue(presenter.presented.isEmpty)
        XCTAssertTrue(mcp.calls.contains("autorización no mostrada evil.example.com"))
    }

    func testOtherToolsKeepUsingTheUsersBrowser() async {
        let mcp = FakeMCP(authorizationURL: slackURL)
        let flow = makeFlow(tools: [.notion], mcp: mcp)
        defer { flow.cancelAll() }

        flow.connect()
        _ = await waitUntil { flow.phase == .succeeded(alreadyConnected: false) }

        XCTAssertFalse(mcp.calls.contains("login notion con autorización propia"))
        XCTAssertTrue(presenter.presented.isEmpty)
    }

    func testClosingTheAuthorizationWindowStopsWaitingAndOffersToRetry() async {
        let mcp = FakeMCP(holdLogin: true, authorizationURL: slackURL)
        let flow = makeFlow(mcp: mcp)
        defer { flow.cancelAll() }
        await finishSlack(flow)
        _ = await waitUntil { !self.presenter.presented.isEmpty }

        presenter.userClosesTheWindow()

        XCTAssertEqual(flow.phase, .failed(.notAuthorizedInTime))
    }

    /// Slack contesta «Invalid client_id» porque alguien borró la app: se explica, y solo si el
    /// usuario lo pide se quita el registro viejo y se vuelve a empezar por el token.
    func testWhenSlackNoLongerKnowsTheAppItOffersToCreateItAgain() async {
        let mcp = FakeMCP(holdLogin: true, authorizationURL: slackURL)
        let flow = makeFlow(mcp: mcp)
        defer { flow.cancelAll() }
        await finishSlack(flow)
        _ = await waitUntil { !self.presenter.presented.isEmpty }

        presenter.slackSaysTheAppIsGone()
        XCTAssertEqual(flow.phase, .failed(.slackAppMissing))
        XCTAssertFalse(mcp.calls.contains { $0.hasPrefix("remove") }, "no se borra nada por su cuenta")

        flow.recreateSlackApp()
        let asking = await waitUntil { flow.phase == .slackToken }

        XCTAssertTrue(asking, "\(flow.phase)")
        XCTAssertTrue(mcp.calls.contains("remove slack"))
    }

    /// Una sola sesión efímera para las dos ventanas, que se descarta al terminar.
    func testTheSessionIsSharedWhileConnectingAndDiscardedAfterwards() async {
        let flow = makeFlow(mcp: FakeMCP(authorizationURL: slackURL))
        defer { flow.cancelAll() }
        let first = flow.webSession.dataStore
        XCTAssertTrue(first === flow.webSession.dataStore, "la misma sesión para inicio de sesión y autorización")
        XCTAssertFalse(first.isPersistent)

        await finishSlack(flow)
        _ = await waitUntil { flow.phase == .succeeded(alreadyConnected: false) }

        XCTAssertFalse(first === flow.webSession.dataStore, "al terminar se descartó")
    }
}

// MARK: - La ventana

@MainActor
final class SlackAuthorizeModelTests: XCTestCase {
    func testTheWindowClosesByItselfOnceClaudeReceivesTheCode() async {
        var finished = 0
        let model = SlackAuthorizeModel(
            url: URL(string: "https://slack.com/oauth/v2_user/authorize")!, dataStore: .nonPersistent()
        ) { finished += 1 }
        model.closeDelay = .milliseconds(20)

        model.pageFinished(URL(string: "https://slack.com/oauth/v2_user/authorize"))
        XCTAssertEqual(model.stage, .userTurn, "espera a que el usuario pulse «Permitir»")
        XCTAssertEqual(finished, 0)

        model.pageFinished(URL(string: "http://localhost:51820/callback?code=abc&state=xyz"))
        XCTAssertEqual(model.stage, .done)
        let closed = await waitUntil { finished == 1 }
        XCTAssertTrue(closed)

        model.pageFinished(URL(string: "http://localhost:51820/callback?code=abc&state=xyz"))
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(finished, 1, "se cierra una sola vez")
    }

    func testAnotherLocalAddressDoesNotCloseTheWindow() async {
        var finished = 0
        let model = SlackAuthorizeModel(
            url: URL(string: "https://slack.com/x")!, dataStore: .nonPersistent()
        ) { finished += 1 }
        model.closeDelay = .milliseconds(10)

        model.pageFinished(URL(string: "http://localhost:9999/callback?code=abc"))
        try? await Task.sleep(for: .milliseconds(60))

        XCTAssertEqual(finished, 0)
        XCTAssertNotEqual(model.stage, .done)
    }

    func testItNoticesWhenSlackSaysTheClientIDIsInvalid() async throws {
        var missing = 0
        let model = SlackAuthorizeModel(
            url: URL(string: "https://slack.com/oauth/v2_user/authorize")!, dataStore: .nonPersistent(),
            onAppNotFound: { missing += 1 }, onFinished: {})
        model.webView.loadHTMLString(
            "<html><body><p>Something went wrong when authorizing this app.</p><pre>Invalid client_id parameter</pre></body></html>",
            baseURL: URL(string: "https://slack.com/oauth/v2_user/authorize")!)

        let noticed = await waitUntil(timeout: 10) { missing == 1 }

        XCTAssertTrue(noticed)
        XCTAssertEqual(model.stage, .appNotFound)
    }

    func testTheWindowIsEphemeral() {
        let model = SlackAuthorizeModel(url: URL(string: "https://slack.com/x")!, dataStore: .nonPersistent()) {}
        XCTAssertFalse(model.webView.configuration.websiteDataStore.isPersistent)
    }
}
