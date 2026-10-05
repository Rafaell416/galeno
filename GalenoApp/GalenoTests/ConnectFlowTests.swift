import Combine
import GalenoCore
import XCTest

@testable import Galeno

@MainActor
final class ConnectFlowTests: XCTestCase {
    private var recordedStatuses: [(Tool, ConnectionStatus)] = []
    private var recordedClientIDs: [(Tool, String)] = []
    /// Cuántas veces el flujo trajo Galeno al frente (tras autorizar en el navegador).
    private var returnsToApp = 0
    /// Las direcciones que el flujo abrió en el navegador (el directorio de conectores de Claude).
    private var openedURLs: [URL] = []

    private func makeFlow(
        _ tools: [Tool],
        statuses: [Tool: ConnectionStatus] = [:],
        mcp: FakeMCP = FakeMCP(),
        whatsapp: FakeWhatsApp = FakeWhatsApp(),
        slack: FakeSlackSetup = FakeSlackSetup(),
        fetchRealData: Bool = true,
        sleep: SleepLog = SleepLog(),
        timing: ConnectFlow.Timing = ConnectFlow.Timing()
    ) -> ConnectFlow {
        recordedStatuses = []
        recordedClientIDs = []
        returnsToApp = 0
        openedURLs = []
        return ConnectFlow(
            tools: tools, statuses: statuses, mcp: mcp, whatsapp: whatsapp, slack: slack,
            agentName: { "Aurora" },
            fetchRealData: fetchRealData, timing: timing, sleep: sleep.sleeper,
            onStatus: { [unowned self] tool, status in recordedStatuses.append((tool, status)) },
            onClientID: { [unowned self] tool, id in recordedClientIDs.append((tool, id)) },
            returnToApp: { [unowned self] in returnsToApp += 1 },
            openURL: { [unowned self] in openedURLs.append($0) })
    }

    private func isOn(_ flow: ConnectFlow, _ tool: Tool) -> Bool { flow.screen == .connection(tool) }

    // MARK: - La secuencia

    func testMeetHasNoScreenOfItsOwn() {
        let flow = makeFlow([.notion, .googleWorkspace, .googleMeet])

        XCTAssertEqual(flow.tools, [.notion, .googleWorkspace])
        XCTAssertEqual(flow.total, 2)
    }

    func testConnectionsFollowTheOrderGiven() {
        let flow = makeFlow([.whatsapp, .notion, .jira])

        XCTAssertEqual(flow.screen, .connection(.whatsapp))
        XCTAssertEqual(flow.tools, [.whatsapp, .notion, .jira])
    }

    func testDopamineScreensGoAfterTheFirstTwoInTheMiddleAndBeforeTheLast() {
        func shape(_ count: Int) -> [String] {
            let tools = Array(Tool.allCases.filter { $0 != .googleMeet }.prefix(count))
            return ConnectFlow.makeSequence(tools).map {
                switch $0 {
                case .connection: "c"
                case .dopamine(let kind): "d:\(kind.rawValue)"
                case .celebration: "end"
                }
            }
        }
        XCTAssertEqual(shape(1), ["c", "end"])
        XCTAssertEqual(shape(2), ["c", "c", "end"], "con 1 o 2 conexiones no hay dopamina")
        XCTAssertEqual(shape(3), ["c", "c", "d:first", "c", "end"])
        XCTAssertEqual(shape(4), ["c", "c", "d:first", "c", "c", "end"])
        XCTAssertEqual(shape(5), ["c", "c", "d:first", "c", "c", "d:last", "c", "end"])
        XCTAssertEqual(
            shape(8), ["c", "c", "d:first", "c", "c", "d:half", "c", "c", "c", "d:last", "c", "end"])
    }

    func testDopamineScreensAreNeverBackToBackOrRightAtTheStart() {
        for count in 1...9 {
            let tools = Array(Tool.allCases.filter { $0 != .googleMeet }.prefix(count))
            let screens = ConnectFlow.makeSequence(tools)
            XCTAssertEqual(screens.last, .celebration)
            for (index, screen) in screens.enumerated() {
                guard case .dopamine = screen else { continue }
                XCTAssertGreaterThan(index, 1, "count \(count)")
                if case .dopamine = screens[index - 1] { XCTFail("dos seguidas con \(count)") }
                if screens[index + 1] == .celebration { XCTFail("dopamina pegada al final con \(count)") }
            }
        }
    }

    func testReturningToTheStepResumesAtTheFirstUnresolvedConnection() {
        let flow = makeFlow(
            [.notion, .jira, .fathom],
            statuses: [.notion: .connected, .jira: .skipped, .fathom: .selected])

        XCTAssertEqual(flow.screen, .connection(.fathom))
        XCTAssertEqual(flow.connectedCount, 1)
    }

    func testWhenEverythingIsResolvedItStartsAtTheCelebration() {
        let flow = makeFlow([.notion], statuses: [.notion: .connected])

        XCTAssertTrue(flow.isFinished)
    }

    // MARK: - MCP hospedados

    func testRegistersLogsInAndMarksItConnected() async {
        let mcp = FakeMCP(counts: ["notion": ItemCount(value: 10, isPartial: true)])
        let flow = makeFlow([.notion, .jira], mcp: mcp, sleep: .holdingSuccess)
        defer { flow.cancelAll() }

        flow.connect()
        let done = await waitUntil { flow.phase == .succeeded(alreadyConnected: false) }

        XCTAssertTrue(done, "\(flow.phase)")
        XCTAssertEqual(
            Array(mcp.calls.prefix(3)), ["status notion", "register notion", "login notion"])
        XCTAssertEqual(recordedStatuses.first?.0, .notion)
        XCTAssertEqual(recordedStatuses.first?.1, .connected)
        XCTAssertEqual(flow.connectedCount, 1)
    }

    func testAnAlreadyConnectedServerSkipsRegisteringAndLogin() async {
        let mcp = FakeMCP(statuses: ["notion": .connected])
        let flow = makeFlow([.notion, .jira], mcp: mcp, sleep: .holdingSuccess)
        defer { flow.cancelAll() }

        flow.connect()
        let done = await waitUntil { flow.phase == .succeeded(alreadyConnected: true) }

        XCTAssertTrue(done, "\(flow.phase)")
        XCTAssertFalse(mcp.calls.contains("register notion"))
        XCTAssertFalse(mcp.calls.contains("login notion"))
    }

    func testARegisteredServerThatNeedsAuthenticationOnlyLogsIn() async {
        let mcp = FakeMCP(statuses: ["notion": .needsAuthentication])
        let flow = makeFlow([.notion, .jira], mcp: mcp, sleep: .holdingSuccess)
        defer { flow.cancelAll() }

        flow.connect()
        _ = await waitUntil { flow.phase == .succeeded(alreadyConnected: false) }

        XCTAssertFalse(mcp.calls.contains("register notion"))
        XCTAssertTrue(mcp.calls.contains("login notion"))
    }

    func testFailingToRegisterShowsTheFailureAndRetryWorks() async {
        let mcp = FakeMCP(registerError: .registerFailed("permiso denegado"))
        let flow = makeFlow([.notion, .jira], mcp: mcp)

        flow.connect()
        let failed = await waitUntil { flow.phase == .failed(.couldNotRegister) }

        XCTAssertTrue(failed, "\(flow.phase)")
        XCTAssertEqual(flow.failureDetail, "permiso denegado")
        XCTAssertEqual(flow.connectedCount, 0)
        XCTAssertTrue(recordedStatuses.isEmpty, "un fallo no cambia el estado de la conexión")
    }

    func testAnAuthorizationThatNeverArrivesCanBeRetried() async {
        let mcp = FakeMCP(loginFailures: ["notion": [.loginTimedOut]])
        let flow = makeFlow([.notion, .jira], mcp: mcp, sleep: .holdingSuccess)
        defer { flow.cancelAll() }

        flow.connect()
        let failed = await waitUntil { flow.phase == .failed(.notAuthorizedInTime) }
        XCTAssertTrue(failed, "\(flow.phase)")

        flow.retry()
        let done = await waitUntil { flow.phase == .succeeded(alreadyConnected: false) }
        XCTAssertTrue(done, "\(flow.phase)")
    }

    func testEachLoginErrorHasItsOwnFailure() async {
        let cases: [(MCPConnectError, ConnectFlow.Failure)] = [
            (.loginTimedOut, .notAuthorizedInTime),
            (.notConnectedAfterLogin, .stillNotConnected),
            (.loginFailed("x"), .loginFailed),
        ]
        for (error, expected) in cases {
            let flow = makeFlow([.notion, .jira], mcp: FakeMCP(loginFailures: ["notion": [error]]))
            flow.connect()
            let failed = await waitUntil { flow.phase == .failed(expected) }
            XCTAssertTrue(failed, "\(error): \(flow.phase)")
        }
    }

    func testSkippingMarksTheToolSkippedAndMovesOn() {
        let flow = makeFlow([.notion, .jira])

        flow.skip()

        XCTAssertEqual(recordedStatuses.first?.0, .notion)
        XCTAssertEqual(recordedStatuses.first?.1, .skipped)
        XCTAssertEqual(flow.screen, .connection(.jira))
        XCTAssertEqual(flow.connectedCount, 0)
    }

    func testSkippingWhileWaitingForTheBrowserStopsTheAttemptWithoutTouchingTheNextScreen() async {
        let mcp = FakeMCP(holdLogin: true)
        let flow = makeFlow([.notion, .jira], mcp: mcp)
        flow.connect()
        let waiting = await waitUntil { flow.phase == .working(.waitingForBrowser) }
        XCTAssertTrue(waiting, "\(flow.phase)")

        flow.skip()
        // Un momento para que la tarea cancelada termine y, si pudiera, pise la pantalla nueva.
        try? await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(flow.screen, .connection(.jira))
        XCTAssertEqual(flow.phase, .ready, "la tarea cancelada no debe escribir un fallo en la pantalla siguiente")
        XCTAssertEqual(flow.statuses[.notion], .skipped)
        XCTAssertNotEqual(flow.statuses[.notion], .connected)
    }

    // MARK: - Google: los conectores de la cuenta de Claude

    func testGoogleToolsAreClaudeAccountConnectorsNotServersToRegister() throws {
        let workspace = try XCTUnwrap(ConnectTarget(tool: .googleWorkspace))
        XCTAssertEqual(
            workspace.connectors.map(\.serverName),
            ["claude.ai Google Drive", "claude.ai Google Docs", "claude.ai Google Sheets"])
        XCTAssertEqual(
            workspace.connectors.map(\.directoryURL.absoluteString),
            [
                "https://claude.ai/directory/google-drive-drivemcp",
                "https://claude.ai/directory/google-docs-docsmcp",
                "https://claude.ai/directory/google-sheets-sheetsmcp",
            ])
        XCTAssertTrue(workspace.servers.isEmpty)
        XCTAssertFalse(workspace.requiresOwnOAuthApp)

        XCTAssertEqual(
            ConnectTarget(tool: .gmail)?.connectors.map(\.directoryURL.absoluteString),
            ["https://claude.ai/directory/gmail-gmailmcp"])
        XCTAssertEqual(
            ConnectTarget(tool: .googleCalendar)?.connectors.map(\.directoryURL.absoluteString),
            ["https://claude.ai/directory/google-calendar-calendarmcp"])
        XCTAssertEqual(makeFlow([.gmail, .notion]).phase, .ready, "ya no es «necesita su propia app»")
    }

    /// Caso 1: el conector ya está conectado en la cuenta de Claude. No se abre nada.
    func testAGoogleConnectorThatIsAlreadyConnectedNeedsNothing() async {
        let mcp = FakeMCP(statuses: ["claude.ai Gmail": .connected])
        let flow = makeFlow([.gmail, .jira], mcp: mcp, fetchRealData: false, sleep: .holdingSuccess)
        defer { flow.cancelAll() }
        flow.connect()
        let done = await waitUntil { flow.phase == .succeeded(alreadyConnected: true) }
        XCTAssertTrue(done, "\(flow.phase)")
        XCTAssertTrue(openedURLs.isEmpty)
        XCTAssertFalse(mcp.calls.contains { $0.hasPrefix("authorize") || $0.hasPrefix("register") || $0.hasPrefix("login") })
        XCTAssertEqual(returnsToApp, 0)
    }

    /// El demo de Simon: los conectores ya estaban conectados, pero al arrancar la sesión salían «pendientes».
    /// Antes se abría una página que decía «ya conectado» y la espera giraba cinco minutos. Ahora no se abre nada.
    func testAConnectorStillPendingAtStartupIsTreatedAsConnectedWithoutOpeningAnything() async {
        let mcp = FakeMCP(statuses: [
            "claude.ai Google Drive": .pending, "claude.ai Google Docs": .pending,
            "claude.ai Google Sheets": .pending,
        ])
        let flow = makeFlow([.googleWorkspace, .jira], mcp: mcp, fetchRealData: false, sleep: .holdingSuccess)
        defer { flow.cancelAll() }
        flow.connect()
        let done = await waitUntil { flow.phase == .succeeded(alreadyConnected: true) }
        XCTAssertTrue(done, "\(flow.phase)")
        XCTAssertTrue(openedURLs.isEmpty, "no abre la página del directorio")
        XCTAssertFalse(mcp.calls.contains { $0.hasPrefix("authorize") }, "ni el permiso")
        XCTAssertEqual(returnsToApp, 0)
    }

    /// Pendiente al arrancar y conectado a la siguiente mirada: es solo lento.
    func testAPendingConnectorThatConnectsOnTheNextLookIsJustSlow() async {
        let mcp = FakeMCP(statuses: ["claude.ai Gmail": .pending])
        mcp.connectorConnectsAfterChecks = 1
        let flow = makeFlow([.gmail, .jira], mcp: mcp, fetchRealData: false, sleep: .holdingSuccess)
        defer { flow.cancelAll() }
        flow.connect()
        let done = await waitUntil { flow.phase == .succeeded(alreadyConnected: true) }
        XCTAssertTrue(done, "\(flow.phase)")
        XCTAssertTrue(openedURLs.isEmpty)
    }

    /// Pendiente no tapa lo que sí falta: si pide autorización, sigue pidiéndola.
    func testAConnectorThatNeedsAuthorizationIsNotMistakenForPending() async {
        let mcp = FakeMCP(statuses: ["claude.ai Gmail": .needsAuthentication])
        mcp.connectorConnectsAfterChecks = 1
        let flow = makeFlow([.gmail, .jira], mcp: mcp, fetchRealData: false, sleep: .holdingSuccess)
        defer { flow.cancelAll() }
        flow.connect()
        let done = await waitUntil { flow.phase == .succeeded(alreadyConnected: false) }
        XCTAssertTrue(done, "\(flow.phase)")
        XCTAssertTrue(mcp.calls.contains("authorize claude.ai Gmail"))
    }

    /// El estado sale de una sesión real, nunca de `claude mcp get`: ese comando da por conectado un
    /// conector al que le falta la autorización de Google (así se coló un «ya estaba conectado» falso).
    func testTheConnectorStateIsNeverReadFromMCPGet() async {
        let mcp = FakeMCP(statuses: ["claude.ai Gmail": .connected])
        let flow = makeFlow([.gmail, .jira], mcp: mcp, fetchRealData: false, sleep: .holdingSuccess)
        defer { flow.cancelAll() }
        flow.connect()
        _ = await waitUntil { flow.phase == .succeeded(alreadyConnected: true) }
        XCTAssertTrue(mcp.calls.contains("connector-status claude.ai Gmail"))
        XCTAssertFalse(mcp.calls.contains("status claude.ai Gmail"))
    }

    /// Caso 2: está en la cuenta pero sin autorizar. Se abre la página de permiso y se espera.
    func testAGoogleConnectorThatNeedsAuthorizationOnlyAsksToAllow() async {
        let mcp = FakeMCP(statuses: ["claude.ai Google Calendar": .needsAuthentication])
        mcp.connectorConnectsAfterChecks = 2
        let flow = makeFlow([.googleCalendar, .jira], mcp: mcp, fetchRealData: false, sleep: .holdingSuccess)
        defer { flow.cancelAll() }
        flow.connect()
        let done = await waitUntil { flow.phase == .succeeded(alreadyConnected: false) }
        XCTAssertTrue(done, "\(flow.phase)")
        XCTAssertTrue(mcp.calls.contains("authorize claude.ai Google Calendar"))
        XCTAssertTrue(openedURLs.isEmpty, "el permiso lo abre `claude mcp login`, no el directorio")
        XCTAssertFalse(mcp.calls.contains { $0.hasPrefix("register") }, "un conector no se registra")
        XCTAssertEqual(returnsToApp, 1, "al terminar en el navegador, Galeno vuelve al frente")
        XCTAssertEqual(recordedStatuses.last?.1, .connected)
    }

    /// Caso 3: no está en la cuenta. Se abre la página del conector en Claude y se espera.
    func testAGoogleConnectorThatIsNotInTheAccountOpensItsPage() async {
        let mcp = FakeMCP()
        mcp.connectorConnectsAfterChecks = 3
        let flow = makeFlow([.gmail, .jira], mcp: mcp, fetchRealData: false, sleep: .holdingSuccess)
        defer { flow.cancelAll() }
        flow.connect()
        let done = await waitUntil { flow.phase == .succeeded(alreadyConnected: false) }
        XCTAssertTrue(done, "\(flow.phase)")
        XCTAssertEqual(openedURLs.map(\.absoluteString), ["https://claude.ai/directory/gmail-gmailmcp"])
        XCTAssertFalse(mcp.calls.contains { $0.hasPrefix("authorize") }, "no hay nada que autorizar hasta que lo añada")
        XCTAssertEqual(returnsToApp, 1)
    }

    /// «Google Drive, Docs y Sheets» son tres conectores: el que ya está se salta, y los otros se conectan
    /// uno tras otro. Galeno vuelve al frente al terminar cada uno de los que pasaron por el navegador.
    func testDriveDocsAndSheetsAreConnectedOneAfterAnother() async {
        let mcp = FakeMCP(statuses: [
            "claude.ai Google Drive": .connected, "claude.ai Google Docs": .needsAuthentication,
        ])
        mcp.connectorConnectsAfterChecks = 1
        let flow = makeFlow([.googleWorkspace, .jira], mcp: mcp, fetchRealData: false, sleep: .holdingSuccess)
        defer { flow.cancelAll() }
        flow.connect()
        let done = await waitUntil { flow.phase == .succeeded(alreadyConnected: false) }
        XCTAssertTrue(done, "\(flow.phase)")
        XCTAssertTrue(mcp.calls.contains("authorize claude.ai Google Docs"))
        XCTAssertFalse(mcp.calls.contains("authorize claude.ai Google Drive"), "Drive ya estaba")
        XCTAssertEqual(openedURLs.map(\.absoluteString), ["https://claude.ai/directory/google-sheets-sheetsmcp"])
        XCTAssertEqual(returnsToApp, 2, "Galeno vuelve al frente tras cada conector que pasó por el navegador (Docs y Sheets)")
        XCTAssertNil(flow.connectorProgress, "al terminar ya no hay conector en curso")
    }

    /// Si el usuario no termina a tiempo, se dice y se puede reintentar o saltar. Nunca se da por conectado.
    func testAGoogleConnectorThatNeverGetsConnectedTimesOut() async {
        let flow = makeFlow([.googleWorkspace, .jira], mcp: FakeMCP(), fetchRealData: false)
        defer { flow.cancelAll() }
        flow.connect()
        let failed = await waitUntil { flow.phase == .failed(.notAuthorizedInTime) }
        XCTAssertTrue(failed, "\(flow.phase)")
        XCTAssertNotEqual(flow.statuses[.googleWorkspace], .connected)
        XCTAssertEqual(returnsToApp, 0)
    }

    func testSkippingAToolThatNeedsItsOwnAppLeavesItSkipped() {
        let flow = makeFlow([.gmail, .notion])

        flow.skip()

        XCTAssertEqual(recordedStatuses.first?.0, .gmail)
        XCTAssertEqual(recordedStatuses.first?.1, .skipped)
        XCTAssertEqual(flow.screen, .connection(.notion))
    }

    func testTheCatalogGivesEveryHostedToolItsServer() {
        XCTAssertEqual(ConnectTarget(tool: .notion)?.servers.first?.name, "notion")
        XCTAssertEqual(ConnectTarget(tool: .notion)?.servers.first?.url, "https://mcp.notion.com/mcp")
        XCTAssertNil(ConnectTarget(tool: .whatsapp), "WhatsApp no se conecta con `claude mcp add`")
        XCTAssertNil(ConnectTarget(tool: .googleMeet), "Meet no tiene servidor")
    }

    // MARK: - Transición, dato real y totales

    func testAfterASuccessItMovesOnAfterOneAndAHalfSeconds() async {
        let log = SleepLog()
        let flow = makeFlow([.notion, .jira], mcp: FakeMCP(), fetchRealData: false, sleep: log)

        flow.connect()
        let moved = await waitUntil { self.isOn(flow, .jira) }

        XCTAssertTrue(moved, "\(flow.screen)")
        XCTAssertEqual(log.durations.first, .milliseconds(1500))
    }

    func testTheRealFigureShowsOnTheSuccessScreen() async {
        let flow = makeFlow([.jira, .fathom], mcp: FakeMCP(counts: ["jira": ItemCount(value: 4, isPartial: false)]))

        flow.connect()
        let found = await waitUntil { flow.findings[.jira] != nil }

        XCTAssertTrue(found)
        XCTAssertEqual(flow.findings[.jira], ConnectFlow.Finding(noun: .projects, count: ItemCount(value: 4, isPartial: false)))
    }

    /// Contar páginas de Notion tardaba ~17 s y costaba ~$0,06: no se pide ningún dato.
    /// Tras autorizar en el navegador, Galeno vuelve al frente; si no se abrió ningún navegador, no.
    func testGalenoComesBackToTheFrontOnlyAfterABrowserAuthorization() async {
        let flow = makeFlow([.notion, .jira], fetchRealData: false, sleep: .holdingSuccess)
        defer { flow.cancelAll() }
        flow.connect()
        let connected = await waitUntil { flow.phase == .succeeded(alreadyConnected: false) }
        XCTAssertTrue(connected, "\(flow.phase)")
        XCTAssertEqual(returnsToApp, 1)

        let already = makeFlow([.notion, .jira], mcp: FakeMCP(statuses: ["notion": .connected]), fetchRealData: false, sleep: .holdingSuccess)
        defer { already.cancelAll() }
        already.connect()
        let found = await waitUntil { already.phase == .succeeded(alreadyConnected: true) }
        XCTAssertTrue(found, "\(already.phase)")
        XCTAssertEqual(returnsToApp, 0, "ya estaba conectado: no hubo navegador del que volver")
    }

    func testAFailedAuthorizationDoesNotStealTheFocus() async {
        let mcp = FakeMCP(loginFailures: ["notion": [.loginTimedOut]])
        let flow = makeFlow([.notion, .jira], mcp: mcp, fetchRealData: false)
        defer { flow.cancelAll() }
        flow.connect()
        let failed = await waitUntil { flow.phase == .failed(.notAuthorizedInTime) }
        XCTAssertTrue(failed, "\(flow.phase)")
        XCTAssertEqual(returnsToApp, 0)
    }

    func testClaudeDesignConnectsWithTheClaudeCodeSessionAndNeverOpensALogin() async {
        let mcp = FakeMCP()
        mcp.connectsOnRegister = ["claude-design"]
        let flow = makeFlow([.claudeDesign, .jira], mcp: mcp, fetchRealData: false, sleep: .holdingSuccess)
        defer { flow.cancelAll() }
        flow.connect()
        let connected = await waitUntil { flow.phase == .succeeded(alreadyConnected: false) }
        XCTAssertTrue(connected, "\(flow.phase)")
        XCTAssertTrue(mcp.calls.contains("register claude-design"))
        XCTAssertFalse(mcp.calls.contains { $0.hasPrefix("login") }, "no hay OAuth que abrir: \(mcp.calls)")
    }

    func testClaudeDesignSaysSoWhenClaudeCodeHasNoSession() async {
        let mcp = FakeMCP(issues: ["claude-design": "Run `claude login`"])
        let flow = makeFlow([.claudeDesign, .jira], mcp: mcp, fetchRealData: false)
        defer { flow.cancelAll() }
        flow.connect()
        let failed = await waitUntil { flow.phase == .failed(.stillNotConnected) }
        XCTAssertTrue(failed, "\(flow.phase)")
        XCTAssertFalse(mcp.calls.contains { $0.hasPrefix("login") })
    }

    func testNotionIsConnectedWithoutAskingForAnyFigure() async {
        let mcp = FakeMCP(counts: ["notion": ItemCount(value: 10, isPartial: true)])
        let flow = makeFlow([.notion, .jira], mcp: mcp, sleep: .holdingSuccess)
        defer { flow.cancelAll() }

        flow.connect()
        let done = await waitUntil { flow.phase == .succeeded(alreadyConnected: false) }

        XCTAssertTrue(done, "\(flow.phase)")
        XCTAssertFalse(mcp.calls.contains { $0.hasPrefix("count") }, "no se le pregunta nada a Claude")
        XCTAssertTrue(flow.pendingData.isEmpty, "no hay 'Mirando qué encontré…'")
        XCTAssertTrue(flow.findings.isEmpty)
    }

    func testOnlyToolsWithAReliableFigureAskForOne() {
        XCTAssertNil(ConnectFlow.noun(for: .notion))
        XCTAssertNil(ConnectFlow.noun(for: .googleMeet))
        XCTAssertEqual(ConnectFlow.noun(for: .jira), .projects)
        XCTAssertEqual(ConnectFlow.noun(for: .whatsapp), .groups)
    }

    func testAFigureThatNeverArrivesDoesNotHoldTheFlowBeyondFourSeconds() async {
        let log = SleepLog()
        let mcp = FakeMCP(counts: ["jira": ItemCount(value: 10, isPartial: true)], holdCounts: true)
        let flow = makeFlow([.jira, .fathom], mcp: mcp, sleep: log)

        flow.connect()
        let moved = await waitUntil { self.isOn(flow, .fathom) }

        XCTAssertTrue(moved, "debe avanzar aunque el dato no haya llegado")
        XCTAssertLessThanOrEqual(log.seconds, 4.01)
        XCTAssertGreaterThanOrEqual(log.seconds, 4.0 - 0.01)
        XCTAssertNil(flow.findings[.jira])
        XCTAssertTrue(flow.pendingData.contains(.jira))

        // Lo que llega tarde no se pierde: suma a los totales.
        mcp.releaseCounts()
        let late = await waitUntil { flow.findings[.jira] != nil }
        XCTAssertTrue(late)
        XCTAssertFalse(flow.pendingData.contains(.jira))
        XCTAssertEqual(flow.totals.first?.noun, .projects)
        XCTAssertEqual(flow.totals.first?.count, ItemCount(value: 10, isPartial: true))
    }

    func testWithoutRealDataNothingIsAskedOfClaude() async {
        let mcp = FakeMCP()
        let flow = makeFlow([.notion, .jira], mcp: mcp, fetchRealData: false)

        flow.connect()
        _ = await waitUntil { self.isOn(flow, .jira) }

        XCTAssertFalse(mcp.calls.contains { $0.hasPrefix("count") })
    }

    func testAMissingFigureLeavesJustTheSuccess() async {
        let flow = makeFlow([.notion, .jira], mcp: FakeMCP(counts: [:]))

        flow.connect()
        _ = await waitUntil { self.isOn(flow, .jira) }

        XCTAssertTrue(flow.findings.isEmpty)
        XCTAssertEqual(flow.connectedCount, 1)
    }

    func testTotalsAddUpByKindAndMarkPartialOnes() async {
        let mcp = FakeMCP(counts: [
            "fireflies": ItemCount(value: 5, isPartial: false),
            "granola": ItemCount(value: 7, isPartial: true),
            "fathom": ItemCount(value: 2, isPartial: false),
        ])
        let flow = makeFlow([.fireflies, .granola, .fathom], mcp: mcp)

        for tool in [Tool.fireflies, .granola, .fathom] {
            flow.connect()
            _ = await waitUntil { flow.statuses[tool] == .connected && flow.findings[tool] != nil }
            _ = await waitUntil { flow.screen != .connection(tool) }
        }
        let finished = await waitUntil { flow.isFinished }

        XCTAssertTrue(finished, "\(flow.screen)")
        XCTAssertEqual(flow.totals.count, 1)
        XCTAssertEqual(flow.totals.first?.noun, .meetings)
        XCTAssertEqual(flow.totals.first?.count, ItemCount(value: 14, isPartial: true))
    }

    func testDopamineScreensAdvanceByThemselvesAndByButton() async {
        let log = SleepLog()
        let flow = makeFlow([.notion, .jira, .fathom], statuses: [:], sleep: log)
        flow.skip()
        flow.skip()
        XCTAssertEqual(flow.screen, .dopamine(.first))

        let moved = await waitUntil { self.isOn(flow, .fathom) }

        XCTAssertTrue(moved, "\(flow.screen)")
        XCTAssertTrue(log.durations.contains(.milliseconds(3000)))

        let again = makeFlow([.notion, .jira, .fathom])
        again.skip()
        again.skip()
        again.continueFromDopamine()
        XCTAssertEqual(again.screen, .connection(.fathom))
    }

    func testTheFlowEndsAtTheCelebrationAndStaysThere() {
        let flow = makeFlow([.notion])

        flow.skip()

        XCTAssertTrue(flow.isFinished)
        flow.advance()
        XCTAssertTrue(flow.isFinished)
    }

    func testReturningToToolSelectionIsOnlyPossibleBeforeConnectingAnything() async {
        let flow = makeFlow([.notion, .jira])
        XCTAssertTrue(flow.canReturnToToolSelection)

        flow.connect()
        _ = await waitUntil { flow.phase == .working(.waitingForBrowser) || flow.connectedCount == 1 }
        XCTAssertFalse(flow.canReturnToToolSelection, "mientras trabaja no")
    }

    // MARK: - WhatsApp

    func testWhatsAppFirstPairsThenInstallsSyncAndWaitsForTheHistory() async {
        let whatsapp = FakeWhatsApp(
            pairEvents: [.qr(Data([1])), .qr(Data([2])), .succeeded],
            counts: [
                ChatCounts(total: 0, groups: 0), ChatCounts(total: 8, groups: 2),
                ChatCounts(total: 20, groups: 5), ChatCounts(total: 20, groups: 5),
                ChatCounts(total: 20, groups: 5), ChatCounts(total: 20, groups: 5),
            ])
        let flow = makeFlow([.whatsapp, .notion], whatsapp: whatsapp, sleep: .holdingSuccess)
        defer { flow.cancelAll() }
        var phases: [ConnectFlow.Phase] = []
        let observer = flow.$phase.sink { phases.append($0) }
        defer { observer.cancel() }

        flow.connect()
        let done = await waitUntil { flow.phase == .succeeded(alreadyConnected: false) }

        XCTAssertTrue(done, "\(flow.phase)")
        XCTAssertTrue(phases.contains(.qr(Data([1]))))
        XCTAssertTrue(phases.contains(.qr(Data([2]))), "el QR se refresca cuando cambia")
        XCTAssertTrue(phases.contains(.syncing(chats: 8)))
        XCTAssertEqual(flow.findings[.whatsapp], ConnectFlow.Finding(noun: .groups, count: ItemCount(value: 5, isPartial: false)))
        XCTAssertEqual(flow.statuses[.whatsapp], .connected)

        // El orden: preparar, mirar si ya hay sesión, vincular y solo entonces `install-launchd`.
        let calls = whatsapp.calls
        let pair = calls.firstIndex(of: "pair"), install = calls.firstIndex(of: "installLaunchd")
        XCTAssertNotNil(pair)
        XCTAssertNotNil(install)
        XCTAssertLessThan(pair!, install!)
        XCTAssertEqual(Array(calls.prefix(2)), ["prepare", "linkState"])
    }

    func testAnAlreadyLinkedWhatsAppSkipsTheQRButStillInstallsSync() async {
        let whatsapp = FakeWhatsApp(state: .linked(number: "573001234567"))
        let flow = makeFlow([.whatsapp, .notion], whatsapp: whatsapp, sleep: .holdingSuccess)
        defer { flow.cancelAll() }
        var phases: [ConnectFlow.Phase] = []
        let observer = flow.$phase.sink { phases.append($0) }
        defer { observer.cancel() }

        flow.connect()
        let done = await waitUntil { flow.phase == .succeeded(alreadyConnected: false) }

        XCTAssertTrue(done, "\(flow.phase)")
        XCTAssertFalse(whatsapp.calls.contains("pair"), "`pair` con sesión solo diría 'Ya hay una sesión vinculada'")
        XCTAssertTrue(whatsapp.calls.contains("installLaunchd"))
        XCTAssertFalse(phases.contains { if case .qr = $0 { true } else { false } })
    }

    func testAPairThatFailsDoesNotInstallSyncAndOffersRetry() async {
        let whatsapp = FakeWhatsApp(pairEvents: [.qr(Data([1])), .failed("se agotó el tiempo esperando que escanearas el QR")])
        let flow = makeFlow([.whatsapp, .notion], whatsapp: whatsapp)

        flow.connect()
        let failed = await waitUntil { flow.phase == .failed(.qrExpired) }

        XCTAssertTrue(failed, "\(flow.phase)")
        XCTAssertFalse(whatsapp.calls.contains("installLaunchd"))
        XCTAssertEqual(flow.statuses[.whatsapp] ?? .selected, .selected)
    }

    func testAPairThatEndsWithoutSuccessIsABridgeFailure() async {
        let whatsapp = FakeWhatsApp(pairEvents: [.failed("no se pudo conectar")])
        let flow = makeFlow([.whatsapp, .notion], whatsapp: whatsapp)

        flow.connect()
        let failed = await waitUntil { flow.phase == .failed(.bridgeFailed) }

        XCTAssertTrue(failed, "\(flow.phase)")
        XCTAssertEqual(flow.failureDetail, "no se pudo conectar")
    }

    func testAMissingBridgeIsReportedAsSuch() async {
        let flow = makeFlow([.whatsapp, .notion], whatsapp: FakeWhatsApp(prepareError: .bridgeMissing))

        flow.connect()
        let failed = await waitUntil { flow.phase == .failed(.bridgeMissing) }

        XCTAssertTrue(failed, "\(flow.phase)")
    }

    func testSyncingForeverStopsAtTheLimitAndStaysPartial() async {
        // Los chats siguen creciendo: nunca se estabiliza.
        let growing = (1...200).map { ChatCounts(total: $0 * 3, groups: $0) }
        let flow = makeFlow(
            [.whatsapp, .notion], whatsapp: FakeWhatsApp(state: .linked(number: "1"), counts: growing),
            sleep: .holdingSuccess)
        defer { flow.cancelAll() }

        flow.connect()
        let done = await waitUntil { flow.phase == .succeeded(alreadyConnected: false) }

        XCTAssertTrue(done, "\(flow.phase)")
        XCTAssertEqual(flow.findings[.whatsapp]?.count.isPartial, true)
        XCTAssertGreaterThan(flow.findings[.whatsapp]?.count.value ?? 0, 0)
    }

    func testAnEmptyHistoryIsNeverConsideredStable() async {
        let flow = makeFlow(
            [.whatsapp, .notion],
            whatsapp: FakeWhatsApp(state: .linked(number: "1"), counts: [ChatCounts(total: 0, groups: 0)]),
            sleep: .holdingSuccess)
        defer { flow.cancelAll() }

        flow.connect()
        let done = await waitUntil { flow.phase == .succeeded(alreadyConnected: false) }

        XCTAssertTrue(done)
        XCTAssertEqual(flow.findings[.whatsapp]?.count, ItemCount(value: 0, isPartial: true))
    }

    func testContinuingWhileItSyncsKeepsWhatsAppConnectedAndPartial() async {
        let growing = (1...500).map { ChatCounts(total: $0, groups: $0 / 4) }
        let flow = makeFlow(
            [.whatsapp, .notion], whatsapp: FakeWhatsApp(state: .linked(number: "1"), counts: growing),
            sleep: SleepLog(stalling: [.milliseconds(3000)]))
        defer { flow.cancelAll() }
        flow.connect()
        let syncing = await waitUntil { if case .syncing = flow.phase { true } else { false } }
        XCTAssertTrue(syncing, "\(flow.phase)")

        flow.continueWhileSyncing()

        XCTAssertEqual(flow.statuses[.whatsapp], .connected)
        XCTAssertEqual(flow.findings[.whatsapp]?.count.isPartial, true)
    }

    func testSkippingWhatsAppDoesNotInstallAnything() {
        let whatsapp = FakeWhatsApp()
        let flow = makeFlow([.whatsapp, .notion], whatsapp: whatsapp)

        flow.skip()

        XCTAssertTrue(whatsapp.calls.isEmpty)
        XCTAssertEqual(recordedStatuses.first?.1, .skipped)
    }
}
