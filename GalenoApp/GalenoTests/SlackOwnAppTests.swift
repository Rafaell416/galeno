import GalenoCore
import XCTest

@testable import Galeno

/// Slack con su propia app OAuth: del token pegado a la conexión, y que el secreto no se quede.
@MainActor
final class SlackOwnAppFlowTests: XCTestCase {
    private var clientIDs: [(Tool, String)] = []
    private var statuses: [(Tool, ConnectionStatus)] = []

    private func makeFlow(
        mcp: FakeMCP = FakeMCP(), slack: FakeSlackSetup = FakeSlackSetup(), sleep: SleepLog = .holdingSuccess
    ) -> ConnectFlow {
        clientIDs = []
        statuses = []
        return ConnectFlow(
            tools: [.slack, .notion], mcp: mcp, whatsapp: FakeWhatsApp(), slack: slack,
            agentName: { "Aurora" }, fetchRealData: false, sleep: sleep.sleeper,
            onStatus: { [unowned self] tool, status in statuses.append((tool, status)) },
            onClientID: { [unowned self] tool, id in clientIDs.append((tool, id)) })
    }

    private func waitFor(_ flow: ConnectFlow, _ phase: ConnectFlow.Phase) async -> Bool {
        await waitUntil { flow.phase == phase }
    }

    // MARK: - Al llegar a la pantalla

    func testAskForTheTokenWhenSlackIsNotRegistered() async {
        let flow = makeFlow()
        defer { flow.cancelAll() }

        let asking = await waitFor(flow, .slackToken)

        XCTAssertTrue(asking, "\(flow.phase)")
        XCTAssertTrue(flow.canReturnToToolSelection)
    }

    func testAnAlreadyConnectedSlackNeedsNoToken() async {
        let slack = FakeSlackSetup()
        let flow = makeFlow(mcp: FakeMCP(statuses: ["slack": .connected]), slack: slack)
        defer { flow.cancelAll() }

        let done = await waitFor(flow, .succeeded(alreadyConnected: true))

        XCTAssertTrue(done, "\(flow.phase)")
        XCTAssertTrue(slack.calls.isEmpty)
    }

    /// Registrado en un intento anterior con su app: solo falta autorizar, no crear **otra** app.
    func testARegisteredSlackOnlyNeedsToAuthorizeAndDoesNotCreateAnotherApp() async {
        let slack = FakeSlackSetup()
        let mcp = FakeMCP(statuses: ["slack": .needsAuthentication])
        let flow = makeFlow(mcp: mcp, slack: slack)
        defer { flow.cancelAll() }
        let ready = await waitFor(flow, .ready)
        XCTAssertTrue(ready, "\(flow.phase)")

        flow.connect()
        let done = await waitFor(flow, .succeeded(alreadyConnected: false))

        XCTAssertTrue(done, "\(flow.phase)")
        XCTAssertTrue(mcp.calls.contains("login slack"))
        XCTAssertTrue(slack.calls.isEmpty, "no se vuelve a crear la app")
    }

    /// En tu máquina ya existe un `slack` de `npx`: ni se pisa ni se da por conectado.
    func testAServerWithTheSameNameButOtherAddressIsNotOverwrittenNorTrusted() async {
        let flow = makeFlow(mcp: FakeMCP(otherServers: ["slack"]))
        defer { flow.cancelAll() }

        let failed = await waitFor(flow, .failed(.nameInUse))

        XCTAssertTrue(failed, "\(flow.phase)")
        XCTAssertEqual(flow.failureDetail, "claude mcp remove slack -s user")
        XCTAssertTrue(recordedNothingConnected)
    }

    private var recordedNothingConnected: Bool { !statuses.contains { $0.1 == .connected } }

    // MARK: - De punta a punta

    func testPastingTheTokenCreatesTheAppRegistersItWithItsOwnClientAndAuthorizes() async throws {
        let slack = FakeSlackSetup(clientID: "1111.2222", secretValue: "SECRETO-DE-PRUEBA")
        let mcp = FakeMCP()
        let flow = makeFlow(mcp: mcp, slack: slack)
        defer { flow.cancelAll() }
        _ = await waitFor(flow, .slackToken)

        flow.submitSlackToken("  xoxe.xoxp-token-de-prueba \n")
        let done = await waitFor(flow, .succeeded(alreadyConnected: false))

        XCTAssertTrue(done, "\(flow.phase)")
        XCTAssertEqual(slack.calls, ["validate", "createApp"], "primero se valida, sin crear nada")
        XCTAssertEqual(slack.tokens, ["xoxe.xoxp-token-de-prueba"], "se recorta; y es el que pegó el usuario")
        XCTAssertEqual(slack.agentNames, ["Aurora"])
        XCTAssertTrue(mcp.calls.contains("register slack con app propia"))
        XCTAssertTrue(mcp.calls.contains("login slack"))

        let registration = try XCTUnwrap(mcp.registration(of: "slack"))
        XCTAssertEqual(registration.clientID, "1111.2222")
        XCTAssertEqual(registration.port, 51820, "el puerto del callback tiene que coincidir con la app")
        XCTAssertEqual(registration.secretValue, "SECRETO-DE-PRUEBA", "el secreto llegó a quien registra")

        XCTAssertEqual(clientIDs.map(\.1), ["1111.2222"], "el client_id público se conserva")
        XCTAssertTrue(statuses.contains { $0.0 == .slack && $0.1 == .connected })
    }

    func testTheSecretsAreWipedAndNothingKeepsThem() async throws {
        let slack = FakeSlackSetup(secretValue: "SECRETO-DE-PRUEBA")
        let flow = makeFlow(slack: slack)
        defer { flow.cancelAll() }
        _ = await waitFor(flow, .slackToken)

        flow.submitSlackToken("xoxe.xoxp-TOKEN-MUY-SECRETO")
        let done = await waitFor(flow, .succeeded(alreadyConnected: false))
        XCTAssertTrue(done, "\(flow.phase)")

        // El secreto de la app que entregó Slack se borró de memoria al terminar.
        let secret = try XCTUnwrap(slack.issuedSecrets.first)
        XCTAssertTrue(secret.isEmpty, "el client_secret se borra tras registrarlo")

        // Y nada de lo que el flujo retiene —ni lo que muestra— lo contiene.
        // Se vuelca lo que el flujo retiene por sí mismo. Los servicios inyectados se saltan: el
        // `FakeSlackSetup` guarda copias a propósito para poder afirmar que los valores llegaron.
        var dumped = ""
        for child in Mirror(reflecting: flow).children where !["slack", "mcp", "whatsapp"].contains(child.label ?? "") {
            dump(child.value, to: &dumped)
        }
        XCTAssertFalse(dumped.isEmpty, "el volcado no debe quedar vacío")
        let visible = [
            dumped, "\(flow.phase)", flow.failureDetail, "\(flow.findings)", "\(flow.statuses)",
            "\(clientIDs)", "\(statuses)",
        ].joined(separator: "\n")
        XCTAssertFalse(visible.contains("TOKEN-MUY-SECRETO"))
        XCTAssertFalse(visible.contains("SECRETO-DE-PRUEBA"))
    }

    func testTheSecretNeverTravelsInTheArgumentsOrTheCallLog() async {
        let mcp = FakeMCP()
        let flow = makeFlow(mcp: mcp, slack: FakeSlackSetup(secretValue: "SECRETO-DE-PRUEBA"))
        defer { flow.cancelAll() }
        _ = await waitFor(flow, .slackToken)

        flow.submitSlackToken("xoxe.xoxp-token")
        _ = await waitFor(flow, .succeeded(alreadyConnected: false))

        XCTAssertFalse(mcp.calls.joined(separator: " ").contains("SECRETO-DE-PRUEBA"))
    }

    // MARK: - Cuando algo falla

    func testARejectedTokenAsksForAnotherOneAndNeverCreatesTheApp() async {
        let slack = FakeSlackSetup(validateError: .tokenRejected("token_expired"))
        let flow = makeFlow(slack: slack)
        defer { flow.cancelAll() }
        _ = await waitFor(flow, .slackToken)

        flow.submitSlackToken("xoxe.xoxp-vencido")
        let failed = await waitFor(flow, .failed(.tokenRejected))

        XCTAssertTrue(failed, "\(flow.phase)")
        XCTAssertEqual(flow.failureDetail, "token_expired")
        XCTAssertEqual(slack.createCount, 0, "con un token inválido no se crea nada")

        flow.retry()
        XCTAssertEqual(flow.phase, .slackToken, "reintentar es pegar otro token, no repetir el mismo")
    }

    func testASlackThatRefusesToCreateTheAppPointsToTheAdmin() async {
        let flow = makeFlow(slack: FakeSlackSetup(createError: .notAllowed("restricted_action")))
        defer { flow.cancelAll() }
        _ = await waitFor(flow, .slackToken)

        flow.submitSlackToken("xoxe.xoxp-token")
        let failed = await waitFor(flow, .failed(.slackNotAllowed))

        XCTAssertTrue(failed, "\(flow.phase)")
        XCTAssertEqual(flow.failureDetail, "restricted_action")
        XCTAssertEqual(flow.connectedCount, 0)
    }

    func testNetworkAndManifestFailuresAreTold() async {
        let cases: [(SlackSetupError, ConnectFlow.Failure)] = [
            (.unreachable("sin internet"), .slackUnreachable),
            (.invalidManifest(["nombre muy largo"]), .slackManifest),
            (.unexpected, .slackManifest),
        ]
        for (error, expected) in cases {
            let flow = makeFlow(slack: FakeSlackSetup(validateError: error))
            _ = await waitFor(flow, .slackToken)
            flow.submitSlackToken("xoxe.xoxp-token")
            let failed = await waitFor(flow, .failed(expected))
            XCTAssertTrue(failed, "\(error): \(flow.phase)")
            flow.cancelAll()
        }
    }

    /// La app ya se creó y se registró; si el usuario no autoriza a tiempo, reintentar NO debe
    /// crear una segunda app (el secreto no se guarda, no se podría reusar).
    func testIfAuthorizationFailsAfterCreatingTheAppRetryDoesNotCreateAnother() async {
        let slack = FakeSlackSetup()
        let mcp = FakeMCP(loginFailures: ["slack": [.loginTimedOut]])
        let flow = makeFlow(mcp: mcp, slack: slack)
        defer { flow.cancelAll() }
        _ = await waitFor(flow, .slackToken)

        flow.submitSlackToken("xoxe.xoxp-token")
        let failed = await waitFor(flow, .failed(.notAuthorizedInTime))
        XCTAssertTrue(failed, "\(flow.phase)")

        flow.retry()
        let done = await waitFor(flow, .succeeded(alreadyConnected: false))

        XCTAssertTrue(done, "\(flow.phase)")
        XCTAssertEqual(slack.createCount, 1, "una sola app")
        XCTAssertEqual(mcp.calls.filter { $0.hasPrefix("register") }.count, 1)
    }

    func testSkippingWhileAskingForTheTokenLeavesSlackSkipped() async {
        let slack = FakeSlackSetup()
        let flow = makeFlow(slack: slack)
        defer { flow.cancelAll() }
        _ = await waitFor(flow, .slackToken)

        flow.skip()

        XCTAssertEqual(statuses.first?.1, .skipped)
        XCTAssertTrue(slack.calls.isEmpty)
        XCTAssertEqual(flow.screen, .connection(.notion))
    }

    func testSubmittingOutsideTheSlackScreenDoesNothing() {
        let slack = FakeSlackSetup()
        let flow = ConnectFlow(
            tools: [.notion, .slack], mcp: FakeMCP(), whatsapp: FakeWhatsApp(), slack: slack)
        defer { flow.cancelAll() }

        flow.submitSlackToken("xoxe.xoxp-token")  // la pantalla actual es la de Notion

        XCTAssertTrue(slack.calls.isEmpty)
    }

    // MARK: - El token que captura la ventana de inicio de sesión

    func testATokenCapturedByTheSignInWindowFollowsTheSamePathAndIsWiped() async {
        let slack = FakeSlackSetup()
        let flow = makeFlow(slack: slack)
        defer { flow.cancelAll() }
        _ = await waitFor(flow, .slackToken)
        let secret = OAuthSecret("xoxe.xoxp-capturado-por-la-ventana")

        flow.submitSlackSecret(secret)
        let done = await waitFor(flow, .succeeded(alreadyConnected: false))

        XCTAssertTrue(done, "\(flow.phase)")
        XCTAssertEqual(slack.tokens, ["xoxe.xoxp-capturado-por-la-ventana"])
        XCTAssertEqual(slack.calls, ["validate", "createApp"])
        XCTAssertTrue(secret.isEmpty, "el token se borra en cuanto se usó")
    }

    func testAfterARejectedTokenTheWindowIsAskedForAFreshOne() async {
        let flow = makeFlow(slack: FakeSlackSetup(validateError: .tokenRejected("token_expired")))
        defer { flow.cancelAll() }
        _ = await waitFor(flow, .slackToken)
        XCTAssertFalse(flow.slackNeedsFreshToken)

        flow.submitSlackSecret(OAuthSecret("xoxe.xoxp-vencido"))
        _ = await waitFor(flow, .failed(.tokenRejected))

        XCTAssertTrue(flow.slackNeedsFreshToken, "el mismo token sigue en la página: hay que generar otro")
    }

    func testASecretThatArrivesOutsideTheSlackScreenIsWipedAndIgnored() {
        let slack = FakeSlackSetup()
        let flow = ConnectFlow(tools: [.notion, .slack], mcp: FakeMCP(), whatsapp: FakeWhatsApp(), slack: slack)
        defer { flow.cancelAll() }
        let secret = OAuthSecret("xoxe.xoxp-token")

        flow.submitSlackSecret(secret)  // la pantalla actual es la de Notion

        XCTAssertTrue(slack.calls.isEmpty)
        XCTAssertTrue(secret.isEmpty, "no se deja un token suelto en memoria")
    }

    // MARK: - El token que se pega

    func testRecognisesTheAccessTokenAndNotTheRefreshToken() {
        XCTAssertTrue(ConnectFlow.looksLikeSlackAccessToken("xoxe.xoxp-1-abc"))
        XCTAssertTrue(ConnectFlow.looksLikeSlackAccessToken("  xoxe.xoxp-1-abc \n"))
        XCTAssertFalse(ConnectFlow.looksLikeSlackAccessToken("xoxe-1-abc"))
        XCTAssertFalse(ConnectFlow.looksLikeSlackAccessToken("xoxb-1-abc"))
        XCTAssertFalse(ConnectFlow.looksLikeSlackAccessToken(""))
        XCTAssertTrue(ConnectFlow.looksLikeSlackRefreshToken("xoxe-1-abc"))
        XCTAssertFalse(ConnectFlow.looksLikeSlackRefreshToken("xoxe.xoxp-1-abc"))
    }
}
