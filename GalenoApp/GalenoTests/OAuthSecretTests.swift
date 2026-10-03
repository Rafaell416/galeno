import GalenoCore
import XCTest

@testable import Galeno

/// El `client_secret` no debe poder escaparse por descuido (`AGENTS.md`).
final class OAuthSecretTests: XCTestCase {
    func testNothingPrintsOrDumpsTheValue() {
        let secret = OAuthSecret("SECRETO-DE-PRUEBA")
        let registration = OAuthClientRegistration(clientID: "1234.5678", callbackPort: 51820, secret: secret)

        var dumped = ""
        dump(secret, to: &dumped)
        dump(registration, to: &dumped)
        let everything = [
            "\(secret)", String(describing: secret), String(reflecting: secret),
            "\(registration)", String(reflecting: registration), dumped,
            "\(Mirror(reflecting: secret).children.map { "\($0.value)" })",
        ].joined(separator: "\n")

        XCTAssertFalse(everything.contains("SECRETO-DE-PRUEBA"))
        XCTAssertTrue(everything.contains("1234.5678"), "el client_id público sí se ve")
    }

    func testTheValueIsOnlyAvailableThroughWithValue() {
        let secret = OAuthSecret("abc123")

        XCTAssertEqual(secret.withValue { $0 }, "abc123")
        XCTAssertFalse(secret.isEmpty)
    }

    func testWipeErasesTheBytes() {
        let secret = OAuthSecret("abc123")

        secret.wipe()

        XCTAssertTrue(secret.isEmpty)
        XCTAssertEqual(secret.withValue { $0 }, "")
    }

    func testWithValueAsyncGivesTheValueToAnAsyncBody() async {
        let secret = OAuthSecret("abc123")

        let length = await secret.withValueAsync { value in
            await Task.yield()
            return value.count
        }

        XCTAssertEqual(length, 6)
    }

    /// Se puede usar desde varios hilos a la vez, también mientras se borra.
    func testConcurrentUseAndWipeIsSafe() async {
        let secret = OAuthSecret(String(repeating: "x", count: 64))

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<50 {
                group.addTask {
                    if index == 25 { secret.wipe() } else { _ = secret.withValue { $0.count } }
                }
            }
        }

        XCTAssertTrue(secret.isEmpty)
    }

    func testClientIDsThatCouldBeReadAsOptionsAreRejected() {
        for good in ["1234567890123.1234567890123", "123-abc.apps.googleusercontent.com", "abc_DEF-1.2"] {
            XCTAssertTrue(OAuthClientRegistration.isValidClientID(good), good)
        }
        for bad in ["--client-secret", "-x", "", "ab", "con espacio", "id;rm -rf", "id\nsegundo", "a$(b)c"] {
            XCTAssertFalse(OAuthClientRegistration.isValidClientID(bad), bad.debugDescription)
        }
    }
}

/// `claude mcp add` con la app propia: el secreto por el entorno, nunca en los argumentos.
final class ClaudeMCPOwnAppTests: XCTestCase {
    private let claude = "/opt/homebrew/bin/claude"

    private func client(_ runner: FakeRunner) -> ClaudeMCPClient {
        ClaudeMCPClient(claudePath: claude, runner: runner, terminal: StubTerminal())
    }

    func testRegisterWithItsOwnAppPassesTheClientAndPortAsArgumentsAndTheSecretInTheEnvironment() async throws {
        let command = "\(claude) mcp add --transport http -s user slack https://mcp.slack.com/mcp "
            + "--client-id 1111.2222 --callback-port 51820 --client-secret"
        let runner = FakeRunner([command: ok("Added")])
        let registration = OAuthClientRegistration(
            clientID: "1111.2222", callbackPort: 51820, secret: OAuthSecret("SECRETO-DE-PRUEBA"))

        try await client(runner).register(server: "slack", url: "https://mcp.slack.com/mcp", oauth: registration)

        XCTAssertEqual(runner.calls, [command])
        XCTAssertFalse(runner.calls.joined().contains("SECRETO-DE-PRUEBA"), "nunca en los argumentos")
        XCTAssertEqual(runner.environments, [["MCP_CLIENT_SECRET": "SECRETO-DE-PRUEBA"]])
    }

    func testRegisterWithoutASecretDoesNotAskForOne() async throws {
        let command = "\(claude) mcp add --transport http -s user x https://x.example/mcp --client-id abc.123"
        let runner = FakeRunner([command: ok("Added")])

        try await client(runner).register(
            server: "x", url: "https://x.example/mcp",
            oauth: OAuthClientRegistration(clientID: "abc.123", callbackPort: nil, secret: nil))

        XCTAssertEqual(runner.calls, [command])
        XCTAssertEqual(runner.environments, [[:]])
    }

    func testRegisterWithoutAnOwnAppIsTheSameAsBefore() async throws {
        let command = "\(claude) mcp add --transport http -s user notion https://mcp.notion.com/mcp"
        let runner = FakeRunner([command: ok("Added")])

        try await client(runner).register(server: "notion", url: "https://mcp.notion.com/mcp")

        XCTAssertEqual(runner.calls, [command])
        XCTAssertEqual(runner.environments, [[:]])
    }

    func testAnInvalidClientIDNeverReachesTheCommandLine() async {
        let runner = FakeRunner([:])
        let hostile = OAuthClientRegistration(clientID: "--client-secret", callbackPort: nil, secret: nil)

        do {
            try await client(runner).register(server: "slack", url: "https://mcp.slack.com/mcp", oauth: hostile)
            XCTFail("debía rechazarlo")
        } catch {
            XCTAssertEqual(error as? MCPConnectError, .invalidClientID)
        }
        XCTAssertTrue(runner.calls.isEmpty)
    }

    // MARK: - Un servidor homónimo

    func testALocalServerWithTheSameNameIsNotTakenForOurs() async {
        // Lo que imprime `claude mcp get` de un servidor local de `npx`: sin línea URL.
        let output = "slack:\n  Scope: User config\n  Status: ✔ Connected\n  Type: stdio\n  Command: npx\n"
        let runner = FakeRunner(["\(claude) mcp get slack": ok(output)])

        let status = await client(runner).status(of: "slack", expectingURL: "https://mcp.slack.com/mcp")

        XCTAssertEqual(status, .differentServer)
    }

    func testAnHTTPServerOnAnotherAddressIsNotTakenForOurs() async {
        let output = "slack:\n  Status: ✔ Connected\n  Type: http\n  URL: https://otro.example.com/mcp\n"
        let runner = FakeRunner(["\(claude) mcp get slack": ok(output)])

        let status = await client(runner).status(of: "slack", expectingURL: "https://mcp.slack.com/mcp")

        XCTAssertEqual(status, .differentServer)
    }

    func testTheSameAddressIsOursEvenWithATrailingSlash() async {
        let output = "slack:\n  Status: ! Needs authentication\n  Type: http\n  URL: https://mcp.slack.com/mcp/\n"
        let runner = FakeRunner(["\(claude) mcp get slack": ok(output)])

        let status = await client(runner).status(of: "slack", expectingURL: "https://mcp.slack.com/mcp")

        XCTAssertEqual(status, .needsAuthentication)
    }

    func testWithoutAnExpectedAddressNothingIsCompared() async {
        let output = "slack:\n  Status: ✔ Connected\n  Type: stdio\n"
        let runner = FakeRunner(["\(claude) mcp get slack": ok(output)])

        let status = await client(runner).status(of: "slack")

        XCTAssertEqual(status, .connected)
    }

    func testAServerThatDoesNotExistIsNotADifferentServer() async {
        let runner = FakeRunner(["\(claude) mcp get slack": CommandResult(status: 1, output: "")])

        let status = await client(runner).status(of: "slack", expectingURL: "https://mcp.slack.com/mcp")

        XCTAssertEqual(status, .notRegistered)
    }
}

private struct StubTerminal: TerminalRunning {
    func runInTerminal(_ executable: String, arguments: [String], timeout: TimeInterval) async -> ManagedProcess.Result? { nil }
}

/// El servicio que crea la app de Slack, con una sesión HTTP falsa: nada habla con Slack.
final class SlackAppSetupServiceTests: XCTestCase {
    private actor Session: SlackAPISession {
        private let body: String
        private let failure: (any Error)?
        private(set) var requests: [URLRequest] = []

        init(body: String = #"{"ok": true}"#, failure: (any Error)? = nil) {
            self.body = body
            self.failure = failure
        }

        func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
            requests.append(request)
            if let failure { throw failure }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        }
    }

    func testClassifiesTheTokenProblemsSeparatelyFromThePermissionOnes() {
        for code in ["invalid_auth", "token_expired", "token_revoked", "not_allowed_token_type", "not_authed"] {
            XCTAssertEqual(
                SlackAppSetupService.classify(SlackAppProvisioner.ProvisioningError.slackRejected(error: code)),
                .tokenRejected(code), code)
        }
        for code in ["restricted_action", "no_permission", "app_creation_disabled", "cualquier_otro"] {
            XCTAssertEqual(
                SlackAppSetupService.classify(SlackAppProvisioner.ProvisioningError.slackRejected(error: code)),
                .notAllowed(code), code)
        }
        XCTAssertEqual(
            SlackAppSetupService.classify(SlackAppProvisioner.ProvisioningError.invalidManifest(messages: ["x"])),
            .invalidManifest(["x"]))
        XCTAssertEqual(
            SlackAppSetupService.classify(SlackAppProvisioner.ProvisioningError.transport(description: "sin red")),
            .unreachable("sin red"))
        XCTAssertEqual(
            SlackAppSetupService.classify(SlackAppProvisioner.ProvisioningError.unexpectedResponse), .unexpected)
    }

    func testValidateSendsTheTokenToSlackAndPassesWhenSlackAcceptsIt() async throws {
        let session = Session()
        let service = SlackAppSetupService(session: session)

        try await service.validate(token: OAuthSecret("xoxe.xoxp-prueba"), agentName: "Aurora")

        let requests = await session.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.url?.lastPathComponent, "apps.manifest.validate")
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer xoxe.xoxp-prueba")
    }

    func testValidateReportsABadToken() async {
        let service = SlackAppSetupService(session: Session(body: #"{"ok": false, "error": "invalid_auth"}"#))

        do {
            try await service.validate(token: OAuthSecret("mal"), agentName: "Aurora")
            XCTFail("debía fallar")
        } catch {
            XCTAssertEqual(error as? SlackSetupError, .tokenRejected("invalid_auth"))
        }
    }

    func testCreateAppReturnsOnlyWhatIsNeededToRegisterIt() async throws {
        let body = """
            {"ok": true, "app_id": "A012", "credentials": {
              "client_id": "1234.5678", "client_secret": "SECRETO-DE-PRUEBA",
              "verification_token": "SECRETO-V", "signing_secret": "SECRETO-F"}}
            """
        let service = SlackAppSetupService(session: Session(body: body))

        let registration = try await service.createApp(token: OAuthSecret("xoxe.xoxp-prueba"), agentName: "Aurora")

        XCTAssertEqual(registration.clientID, "1234.5678")
        XCTAssertEqual(registration.callbackPort, 51820, "el mismo puerto que la URL de redirección del manifiesto")
        XCTAssertEqual(registration.secret?.withValue { $0 }, "SECRETO-DE-PRUEBA")
        var dumped = ""
        dump(registration, to: &dumped)
        XCTAssertFalse(dumped.contains("SECRETO"), "ni el client_secret ni los demás secretos se ven")
    }

    func testNetworkFailureIsReportedAsUnreachable() async {
        let service = SlackAppSetupService(session: Session(failure: URLError(.notConnectedToInternet)))

        do {
            try await service.validate(token: OAuthSecret("xoxe.xoxp-prueba"), agentName: "Aurora")
            XCTFail("debía fallar")
        } catch {
            guard case .unreachable = error as? SlackSetupError else { return XCTFail("\(error)") }
        }
    }
}
