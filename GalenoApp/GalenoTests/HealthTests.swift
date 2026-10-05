import GalenoCore
import XCTest

@testable import Galeno

/// La vista de salud: el parser de `claude mcp list`, lo que dice el bridge (`status --json`, `launchctl`), el
/// modelo con conectores falsos, el re-vincular de WhatsApp y las carpetas que alguien borró. Todo en carpetas
/// temporales y con bridge y `claude` falsos: ninguna prueba toca el disco ni la cuenta reales.
@MainActor
final class HealthTests: XCTestCase {
    private var installer: AgentInstaller!

    override func setUp() async throws {
        installer = .sandboxed()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: installer.agentsRoot.deletingLastPathComponent())
    }

    // MARK: - Lo que se lee de `claude mcp list`

    func testParsesTheRealShapeOfClaudeMcpList() {
        let output = """
            Checking MCP server health…

            claude.ai Gmail: https://gmailmcp.googleapis.com/mcp/v1 - ✔ Connected
            claude.ai Slack: https://mcp.slack.com/mcp - ! Needs authentication
            plugin:vercel:vercel: https://mcp.vercel.com (HTTP) - ✔ Connected
            github: npx -y @modelcontextprotocol/server-github - ✘ Failed to connect
            notion: https://mcp.notion.com/mcp (HTTP) - ✔ Connected

            MCP config diagnostics ⚠

            For help configuring MCP servers, see: https://code.claude.com/docs/en/mcp

            [Contains warnings] User config (available in all your projects)
            Location: /Users/x/.claude.json
             └ [Warning] [github] mcpServers.github: Missing environment variables: TOKEN
            """

        let statuses = ClaudeMCPClient.parseList(output)

        XCTAssertEqual(statuses["claude.ai Gmail"], .connected)
        XCTAssertEqual(statuses["claude.ai Slack"], .needsAuthentication)
        XCTAssertEqual(statuses["plugin:vercel:vercel"], .connected, "el nombre puede llevar dos puntos")
        XCTAssertEqual(statuses["github"], .failed)
        XCTAssertEqual(statuses["notion"], .connected)
        XCTAssertEqual(statuses.count, 5, "los diagnósticos y el encabezado no son servidores")
    }

    func testListWithNothingRecognisableIsEmpty() {
        XCTAssertTrue(ClaudeMCPClient.parseList("").isEmpty)
        XCTAssertTrue(ClaudeMCPClient.parseList("Checking MCP server health…\n").isEmpty)
    }

    func testListingNeedsAnExitCodeOfZero() async {
        let client = ClaudeMCPClient(
            claudePath: "/c", runner: FakeRunner(["/c mcp list": CommandResult(status: 1, output: "notion: u - ✔ Connected")]))
        let listed = await client.listStatuses()
        XCTAssertNil(listed)

        let good = ClaudeMCPClient(claudePath: "/c", runner: FakeRunner(["/c mcp list": ok("notion: u - ✔ Connected\n")]))
        let result = await good.listStatuses()
        XCTAssertEqual(result, ["notion": .connected])
    }

    // MARK: - Lo que dice el bridge

    func testParsesTheBridgeStatusJSON() throws {
        let linked = try XCTUnwrap(
            WhatsAppBridge.parseStatus(
                jsonOutput: #"{"linked":true,"number":"573001234567","linked_at":1760000000,"version":"0.3.0"}"#))
        XCTAssertTrue(linked.isLinked)
        XCTAssertEqual(linked.number, "573001234567")
        XCTAssertEqual(linked.linkedAt, Date(timeIntervalSince1970: 1_760_000_000))
        XCTAssertEqual(linked.bridgeVersion, "0.3.0")

        let unlinked = try XCTUnwrap(WhatsAppBridge.parseStatus(jsonOutput: #"{"linked":false,"version":"0.3.0"}"#))
        XCTAssertFalse(unlinked.isLinked)
        XCTAssertNil(unlinked.number)
        XCTAssertNil(unlinked.linkedAt)
    }

    func testAnUnreadableLinkDateIsNotInvented() throws {
        let status = try XCTUnwrap(
            WhatsAppBridge.parseStatus(jsonOutput: #"{"linked":true,"number":"57","linked_at":0,"version":"0.3.0"}"#))
        XCTAssertNil(status.linkedAt)
    }

    func testStatusThatIsNotOurBridgeIsRejected() {
        XCTAssertNil(WhatsAppBridge.parseStatus(jsonOutput: "Vinculado como 573001234567."), "el texto viejo no es JSON")
        XCTAssertNil(WhatsAppBridge.parseStatus(jsonOutput: #"{"linked":true}"#), "sin versión no es nuestro bridge")
        XCTAssertNil(WhatsAppBridge.parseStatus(jsonOutput: ""))
    }

    func testParsesLaunchctlState() {
        let running = "gui/501/com.galeno.whatsapp-bridge = {\n\tactive count = 1\n\ttype = LaunchAgent\n\tstate = running\n\n}"
        let waiting = "gui/501/com.galeno.whatsapp-bridge = {\n\ttype = LaunchAgent\n\tstate = not running\n}"
        XCTAssertEqual(WhatsAppBridge.parseSyncState(launchctlOutput: running, exitStatus: 0), .running)
        XCTAssertEqual(WhatsAppBridge.parseSyncState(launchctlOutput: waiting, exitStatus: 0), .stopped)
        XCTAssertEqual(
            WhatsAppBridge.parseSyncState(launchctlOutput: "Could not find service", exitStatus: 113), .notInstalled)
    }

    func testTheBridgeAsksLaunchdAboutItsOwnLabel() async {
        let target = "gui/\(getuid())/com.galeno.whatsapp-bridge"
        let runner = FakeRunner(["/bin/launchctl print \(target)": ok("\tstate = running\n")])
        let bridge = WhatsAppBridge(installer: BridgeInstaller(source: nil), runner: runner)

        let state = await bridge.syncState()

        XCTAssertEqual(state, .running)
    }

    func testBridgeStatusAsksForJSON() async throws {
        let runner = FakeRunner([
            "/stable/galeno-whatsapp status --json": ok(#"{"linked":true,"number":"57","linked_at":1760000000,"version":"0.3.0"}"#)
        ])
        let bridge = WhatsAppBridge(
            installer: BridgeInstaller(source: nil, destination: URL(fileURLWithPath: "/stable/galeno-whatsapp")), runner: runner)

        let status = await bridge.status()

        XCTAssertEqual(status?.number, "57")
    }

    // MARK: - Cuándo avisar de que la sesión puede rotar

    func testRelinkWarningStartsWithMarginBeforeTheEstimatedRotation() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func linked(daysAgo: Int) -> Date { now.addingTimeInterval(-Double(daysAgo) * 86_400) }

        XCTAssertEqual(WhatsAppSession.ageInDays(linkedAt: linked(daysAgo: 5), now: now), 5)
        XCTAssertFalse(WhatsAppSession.shouldRelink(linkedAt: linked(daysAgo: 17), now: now))
        XCTAssertTrue(WhatsAppSession.shouldRelink(linkedAt: linked(daysAgo: 18), now: now))
        XCTAssertTrue(WhatsAppSession.shouldRelink(linkedAt: linked(daysAgo: 30), now: now))
        XCTAssertFalse(WhatsAppSession.shouldRelink(linkedAt: nil, now: now), "sin fecha no se avisa de lo que no se sabe")
        XCTAssertLessThan(WhatsAppSession.warnAfterDays, WhatsAppSession.estimatedRotationDays)
    }

    // MARK: - El modelo

    private func serverName(_ tool: Tool) -> String {
        ConnectTarget(tool: tool)!.servers[0].name
    }

    private func install(
        _ connections: [ToolConnection], name: String = "Hera"
    ) throws -> AgentRecord {
        try installer.install(
            AgentConfig(agentName: name, language: .spanish, projectDescription: "Proyecto", connections: connections)
        ).record
    }

    private func makeModel(
        mcp: FakeMCP = FakeMCP(), whatsapp: FakeWhatsApp = FakeWhatsApp(), claude: String? = "/ruta/claude",
        skills: any SkillUpdating = SkillUpdaterNotAvailable(), opened: OpenedURLs = OpenedURLs()
    ) -> HealthModel {
        HealthModel(
            store: installer.store, locateClaude: { claude }, makeMCP: { _ in mcp }, whatsapp: whatsapp,
            skillUpdater: skills, authorizer: nil, language: { .spanish },
            openURL: { opened.urls.append($0) }, returnToApp: {}, sleep: { _ in },
            timing: HealthModel.Timing(connectorPoll: 1, connectorMax: 3, pendingLooks: 3))
    }

    final class OpenedURLs { var urls: [URL] = [] }

    func testEachConnectedToolShowsItsOwnState() async throws {
        _ = try install([
            ToolConnection(tool: .notion, status: .connected, sources: .everything),
            ToolConnection(tool: .fathom, status: .connected, sources: .everything),
            ToolConnection(tool: .gmail, status: .connected, sources: .everything),
        ])
        let mcp = FakeMCP(statuses: [
            serverName(.notion): .connected, serverName(.fathom): .needsAuthentication,
            "claude.ai Gmail": .needsAuthentication,
        ])
        let model = makeModel(mcp: mcp)

        await model.check()

        let states = Dictionary(uniqueKeysWithValues: model.connections.map { ($0.tool, $0.state) })
        XCTAssertEqual(states[.notion], .connected)
        XCTAssertEqual(states[.fathom], .needsAuthorization)
        XCTAssertEqual(states[.gmail], .needsAuthorization, "un conector se lee de la sesión, no de `mcp list`")
        XCTAssertTrue(states[.fathom]!.canReconnect)
        XCTAssertFalse(states[.notion]!.canReconnect)
    }

    func testAToolThatWasSkippedIsNotListed() async throws {
        _ = try install([
            ToolConnection(tool: .notion, status: .connected, sources: .everything),
            ToolConnection(tool: .fathom, status: .skipped),
        ])
        let model = makeModel(mcp: FakeMCP(statuses: [serverName(.notion): .connected]))

        await model.check()

        XCTAssertEqual(model.connections.map(\.tool), [.notion])
    }

    func testAListingThatFailsClaimsNothing() async throws {
        _ = try install([ToolConnection(tool: .notion, status: .connected, sources: .everything)])
        let mcp = FakeMCP(statuses: [serverName(.notion): .connected])
        mcp.listingFails = true
        let model = makeModel(mcp: mcp)

        await model.check()

        XCTAssertEqual(model.connections.first?.state, .unknown, "sin saber, no se dice «conectada»")
        XCTAssertTrue(model.connections.first?.state.canReconnect == true)
    }

    func testWithoutClaudeNothingIsClaimed() async throws {
        _ = try install([ToolConnection(tool: .notion, status: .connected, sources: .everything)])
        let model = makeModel(claude: nil)

        await model.check()

        XCTAssertFalse(model.claudeAvailable)
        XCTAssertEqual(model.connections.first?.state, .unknown)
    }

    func testAnUnregisteredServerIsReportedAsMissing() async throws {
        _ = try install([ToolConnection(tool: .notion, status: .connected, sources: .everything)])
        let model = makeModel(mcp: FakeMCP())

        await model.check()

        XCTAssertEqual(model.connections.first?.state, .missing)
    }

    func testAPendingConnectorIsNeitherAFailureNorAskedToAuthorize() async throws {
        _ = try install([ToolConnection(tool: .gmail, status: .connected, sources: .everything)])
        let model = makeModel(mcp: FakeMCP(statuses: ["claude.ai Gmail": .pending]))

        await model.check()

        XCTAssertEqual(model.connections.first?.state, .pending)
        XCTAssertFalse(model.connections.first!.state.canReconnect)
    }

    func testTheWorstStateOfSeveralConnectorsWins() async throws {
        _ = try install([ToolConnection(tool: .googleWorkspace, status: .connected, sources: .everything)])
        let mcp = FakeMCP(statuses: [
            "claude.ai Google Drive": .connected, "claude.ai Google Docs": .needsAuthentication,
            "claude.ai Google Sheets": .connected,
        ])
        let model = makeModel(mcp: mcp)

        await model.check()

        XCTAssertEqual(model.connections.first?.state, .needsAuthorization)
    }

    // MARK: Reconectar

    func testReconnectingAHostedToolLogsInAndChecksAgain() async throws {
        _ = try install([ToolConnection(tool: .fathom, status: .connected, sources: .everything)])
        let mcp = FakeMCP(statuses: [serverName(.fathom): .needsAuthentication])
        let model = makeModel(mcp: mcp)
        await model.check()

        model.reconnect(.fathom)
        let done = await waitUntil { model.reconnecting == nil && model.connections.first?.state == .connected }

        XCTAssertTrue(done)
        XCTAssertTrue(mcp.calls.contains("login \(serverName(.fathom))"))
        XCTAssertNil(model.reconnectIssues[.fathom])
    }

    func testReconnectNeverTouchesAServerThatIsNotOurs() async throws {
        _ = try install([ToolConnection(tool: .notion, status: .connected, sources: .everything)])
        let mcp = FakeMCP(otherServers: [serverName(.notion)])
        let model = makeModel(mcp: mcp)
        await model.check()

        model.reconnect(.notion)
        let done = await waitUntil { model.reconnecting == nil && model.reconnectIssues[.notion] != nil }

        XCTAssertTrue(done)
        XCTAssertEqual(model.reconnectIssues[.notion], .nameTaken)
        XCTAssertFalse(mcp.calls.contains { $0.hasPrefix("login") || $0.hasPrefix("register") || $0.hasPrefix("remove") })
    }

    func testReconnectingAToolWithItsOwnAppThatIsGoneSendsYouToManage() async throws {
        _ = try install([
            ToolConnection(tool: .slack, status: .connected, sources: .everything, oauthClientID: "1234567890123.1234567890123")
        ])
        let mcp = FakeMCP()  // Slack ya no está registrado en Claude Code
        let model = makeModel(mcp: mcp)
        await model.check()

        model.reconnect(.slack)
        let done = await waitUntil { model.reconnecting == nil && model.reconnectIssues[.slack] != nil }

        XCTAssertTrue(done)
        XCTAssertEqual(model.reconnectIssues[.slack], .needsWizard)
        XCTAssertFalse(mcp.calls.contains { $0.hasPrefix("register") }, "sin su app y su secreto no se registra a ciegas")
    }

    func testReconnectingAConnectorAuthorizesAndWaitsUntilItIsAlive() async throws {
        _ = try install([ToolConnection(tool: .gmail, status: .connected, sources: .everything)])
        let mcp = FakeMCP(statuses: ["claude.ai Gmail": .needsAuthentication])
        mcp.connectorConnectsAfterChecks = 2
        let model = makeModel(mcp: mcp)
        await model.check()
        XCTAssertEqual(model.connections.first?.state, .needsAuthorization)

        model.reconnect(.gmail)
        let done = await waitUntil { model.reconnecting == nil && model.connections.first?.state == .connected }

        XCTAssertTrue(done)
        XCTAssertTrue(mcp.calls.contains("authorize claude.ai Gmail"))
        XCTAssertNil(model.reconnectIssues[.gmail])
    }

    func testAConnectorNoLongerInTheAccountOpensItsDirectoryPage() async throws {
        _ = try install([ToolConnection(tool: .gmail, status: .connected, sources: .everything)])
        let opened = OpenedURLs()
        let model = makeModel(mcp: FakeMCP(), opened: opened)

        model.reconnect(.gmail)
        let done = await waitUntil { model.reconnecting == nil && model.reconnectIssues[.gmail] != nil }

        XCTAssertTrue(done)
        XCTAssertEqual(opened.urls.first?.host, "claude.ai")
        XCTAssertEqual(model.reconnectIssues[.gmail], .timedOut, "si nadie lo conecta, se dice y no se queda girando")
    }

    func testOnlyOneToolReconnectsAtATime() async throws {
        _ = try install([
            ToolConnection(tool: .fathom, status: .connected, sources: .everything),
            ToolConnection(tool: .notion, status: .connected, sources: .everything),
        ])
        let mcp = FakeMCP(
            statuses: [serverName(.fathom): .needsAuthentication, serverName(.notion): .needsAuthentication], holdLogin: true)
        let model = makeModel(mcp: mcp)
        await model.check()

        model.reconnect(.fathom)
        model.reconnect(.notion)

        XCTAssertEqual(model.reconnecting, .fathom)
        model.cancelReconnect()
        XCTAssertNil(model.reconnecting)
    }

    // MARK: WhatsApp

    private func linkedStatus(daysAgo: Int) -> WhatsAppStatus {
        WhatsAppStatus(
            isLinked: true, number: "573001234567",
            linkedAt: Date().addingTimeInterval(-Double(daysAgo) * 86_400), bridgeVersion: "0.3.0")
    }

    func testWhatsAppPanelOnlyExistsIfTheAgentUsesIt() async throws {
        _ = try install([ToolConnection(tool: .notion, status: .connected, sources: .everything)])
        let model = makeModel(mcp: FakeMCP(statuses: [serverName(.notion): .connected]))

        await model.check()

        XCTAssertFalse(model.usesWhatsApp)
        XCTAssertNil(model.whatsapp)
    }

    func testWhatsAppHealthReportsSessionSyncAndAge() async throws {
        _ = try install([ToolConnection(tool: .whatsapp, status: .connected, sources: .everything)])
        let bridge = FakeWhatsApp()
        bridge.reportedStatus = linkedStatus(daysAgo: 19)
        bridge.reportedSync = .running
        let model = makeModel(whatsapp: bridge)

        await model.check()

        let health = try XCTUnwrap(model.whatsapp)
        XCTAssertTrue(health.isLinked)
        XCTAssertEqual(health.sync, .running)
        XCTAssertEqual(health.daysLinked(), 19)
        XCTAssertTrue(health.shouldRelink())
        XCTAssertEqual(health.status?.bridgeVersion, "0.3.0")
    }

    func testAFreshSessionDoesNotWarn() async throws {
        _ = try install([ToolConnection(tool: .whatsapp, status: .connected, sources: .everything)])
        let bridge = FakeWhatsApp()
        bridge.reportedStatus = linkedStatus(daysAgo: 3)
        bridge.reportedSync = .running
        let model = makeModel(whatsapp: bridge)

        await model.check()

        XCTAssertFalse(try XCTUnwrap(model.whatsapp).shouldRelink())
    }

    func testABridgeThatDoesNotAnswerIsShownAsSuch() async throws {
        _ = try install([ToolConnection(tool: .whatsapp, status: .connected, sources: .everything)])
        let model = makeModel(whatsapp: FakeWhatsApp())  // sin estado: no contesta

        await model.check()

        XCTAssertNil(model.whatsapp?.status)
        XCTAssertFalse(try XCTUnwrap(model.whatsapp).isLinked)
    }

    func testRelinkClosesTheOldSessionThenPairsThenRestartsSync() async throws {
        _ = try install([ToolConnection(tool: .whatsapp, status: .connected, sources: .everything)])
        let bridge = FakeWhatsApp(pairEvents: [.qr(Data([1, 2, 3])), .succeeded])
        bridge.reportedStatus = linkedStatus(daysAgo: 19)
        bridge.reportedSync = .running
        let model = makeModel(whatsapp: bridge)
        await model.check()

        model.askRelink()
        XCTAssertEqual(model.relink, .confirming)
        XCTAssertFalse(bridge.calls.contains("unlink"), "nada se cierra hasta confirmar")
        model.confirmRelink()
        let done = await waitUntil { model.relink == .done }

        XCTAssertTrue(done)
        let calls = bridge.calls.filter { ["prepare", "unlink", "pair", "installLaunchd"].contains($0) }
        XCTAssertEqual(calls, ["prepare", "unlink", "pair", "installLaunchd"])
        XCTAssertEqual(model.whatsapp?.sync, .running)
        XCTAssertFalse(try XCTUnwrap(model.whatsapp).shouldRelink(), "recién vinculado")
    }

    func testLinkingWithoutASessionSkipsTheUnlink() async throws {
        _ = try install([ToolConnection(tool: .whatsapp, status: .connected, sources: .everything)])
        let bridge = FakeWhatsApp()
        bridge.reportedStatus = WhatsAppStatus(isLinked: false, number: nil, linkedAt: nil, bridgeVersion: "0.3.0")
        let model = makeModel(whatsapp: bridge)
        await model.check()

        model.askRelink()
        model.confirmRelink()
        let done = await waitUntil { model.relink == .done }

        XCTAssertTrue(done)
        XCTAssertFalse(bridge.calls.contains("unlink"))
        XCTAssertTrue(bridge.calls.contains("pair"))
    }

    func testIfTheOldSessionCannotBeClosedNothingNewIsLinked() async throws {
        _ = try install([ToolConnection(tool: .whatsapp, status: .connected, sources: .everything)])
        let bridge = FakeWhatsApp()
        bridge.reportedStatus = linkedStatus(daysAgo: 19)
        bridge.failUnlink = .unexpectedOutput("x")
        let model = makeModel(whatsapp: bridge)
        await model.check()

        model.askRelink()
        model.confirmRelink()
        let done = await waitUntil { model.relink == .failed(.couldNotClose) }

        XCTAssertTrue(done)
        XCTAssertFalse(bridge.calls.contains("pair"))
        XCTAssertFalse(bridge.calls.contains("installLaunchd"))
    }

    func testAnExpiredQRIsSaidSoAndCanBeRetried() async throws {
        _ = try install([ToolConnection(tool: .whatsapp, status: .connected, sources: .everything)])
        let bridge = FakeWhatsApp(pairEvents: [.failed("se agotó el tiempo")])
        bridge.reportedStatus = WhatsAppStatus(isLinked: false, number: nil, linkedAt: nil, bridgeVersion: "0.3.0")
        let model = makeModel(whatsapp: bridge)
        await model.check()

        model.askRelink()
        model.confirmRelink()
        let failed = await waitUntil { model.relink == .failed(.qrExpired) }
        XCTAssertTrue(failed)
        XCTAssertFalse(bridge.calls.contains("installLaunchd"), "sin vincular no se deja `sync` corriendo")

        model.askRelink()
        XCTAssertEqual(model.relink, .confirming)
    }

    func testCancellingTheConfirmationDoesNothing() async throws {
        _ = try install([ToolConnection(tool: .whatsapp, status: .connected, sources: .everything)])
        let bridge = FakeWhatsApp()
        bridge.reportedStatus = linkedStatus(daysAgo: 19)
        let model = makeModel(whatsapp: bridge)
        await model.check()

        model.askRelink()
        model.cancelRelink()

        XCTAssertEqual(model.relink, .idle)
        XCTAssertFalse(bridge.calls.contains("unlink"))
        XCTAssertFalse(bridge.calls.contains("pair"))
    }

    // MARK: Skills

    func testSkillsEntryPointExistsButIsNotAvailableYet() {
        let model = makeModel()

        XCTAssertFalse(model.canUpdateSkills)
        model.updateSkills()
        XCTAssertFalse(model.isUpdatingSkills)
    }

    private struct CountingUpdater: SkillUpdating {
        let counter: Counter
        var isAvailable: Bool { true }
        func updateSkills() async throws { counter.value += 1 }
    }
    final class Counter: @unchecked Sendable { var value = 0 }

    func testASkillUpdaterPlugsIntoTheSameEntryPoint() async {
        let counter = Counter()
        let model = makeModel(skills: CountingUpdater(counter: counter))

        XCTAssertTrue(model.canUpdateSkills)
        model.updateSkills()
        let done = await waitUntil { !model.isUpdatingSkills && counter.value == 1 }

        XCTAssertTrue(done)
        XCTAssertFalse(model.skillsUpdateFailed)
    }

    // MARK: - Carpetas que alguien borró

    private func makeHome() -> HomeModel {
        HomeModel(
            store: installer.store, defaults: UserDefaults(suiteName: "health-\(UUID().uuidString)")!,
            claudePath: "/ruta/claude", installer: installer, settle: {})
    }

    func testAMissingFolderCanBeRegeneratedFromItsConfiguration() throws {
        let hera = try install([ToolConnection(tool: .notion, status: .connected, sources: .everything)], name: "Hera")
        let aurora = try install([ToolConnection(tool: .notion, status: .connected, sources: .everything)], name: "Aurora")
        try FileManager.default.removeItem(at: hera.folder)
        let home = makeHome()
        let agent = try XCTUnwrap(home.agents.first { $0.id == hera.id })
        XCTAssertFalse(agent.folderExists)

        home.askRegenerate(agent)
        XCTAssertEqual(home.dialog, .regenerate(agent))
        XCTAssertFalse(FileManager.default.fileExists(atPath: hera.folder.path), "nada se escribe hasta confirmar")
        XCTAssertTrue(home.confirmRegenerate())

        XCTAssertTrue(FileManager.default.fileExists(atPath: hera.folder.appending(path: "AGENTS.md").path))
        XCTAssertTrue(home.agents.first { $0.id == hera.id }?.folderExists == true)
        XCTAssertEqual(home.agents.count, 2)
        XCTAssertNotNil(home.agents.first { $0.id == aurora.id })
        XCTAssertEqual(try installer.store.load()?.agents.first { $0.id == hera.id }?.folderPath, hera.folderPath, "misma ruta, mismo agente")
    }

    func testRegeneratingIsNotOfferedWhileTheFolderExists() throws {
        let hera = try install([ToolConnection(tool: .notion, status: .connected, sources: .everything)])
        let home = makeHome()
        let agent = try XCTUnwrap(home.agents.first { $0.id == hera.id })

        home.askRegenerate(agent)

        XCTAssertNil(home.dialog)
    }

    func testIfTheFolderCameBackMeanwhileRegeneratingDoesNotOverwriteIt() throws {
        let hera = try install([ToolConnection(tool: .notion, status: .connected, sources: .everything)])
        try FileManager.default.removeItem(at: hera.folder)
        let home = makeHome()
        let agent = try XCTUnwrap(home.agents.first)
        home.askRegenerate(agent)
        // Alguien la devuelve a su sitio antes de confirmar.
        try FileManager.default.createDirectory(at: hera.folder, withIntermediateDirectories: true)
        try Data("MI NOTA".utf8).write(to: hera.folder.appending(path: "nota.txt"))

        XCTAssertTrue(home.confirmRegenerate())

        XCTAssertEqual(try String(contentsOf: hera.folder.appending(path: "nota.txt"), encoding: .utf8), "MI NOTA")
        XCTAssertFalse(FileManager.default.fileExists(atPath: hera.folder.appending(path: "AGENTS.md").path), "no se escribió nada encima")
    }

    func testAnAgentWhoseFolderIsGoneCanBeRemovedAndTheOthersStay() throws {
        let hera = try install([ToolConnection(tool: .notion, status: .connected, sources: .everything)], name: "Hera")
        let aurora = try install([ToolConnection(tool: .notion, status: .connected, sources: .everything)], name: "Aurora")
        try FileManager.default.removeItem(at: hera.folder)
        let home = makeHome()
        let agent = try XCTUnwrap(home.agents.first { $0.id == hera.id })

        home.askDelete(agent)
        guard case .delete(_, let plan)? = home.dialog else { return XCTFail("debería pedir confirmación") }
        XCTAssertNil(plan.folder, "no hay carpeta que mandar a la Papelera")
        XCTAssertTrue(home.confirmDelete())

        XCTAssertEqual(try installer.store.load()?.agents.map(\.id), [aurora.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: aurora.folder.path), "la otra carpeta no se toca")
    }

    func testAnUnreadableInstallationNeverCrashesTheHealthCheck() async throws {
        try FileManager.default.createDirectory(at: installer.store.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ no es json".utf8).write(to: installer.store.fileURL)
        let model = makeModel()

        await model.check()

        XCTAssertTrue(model.connections.isEmpty)
        XCTAssertFalse(model.usesWhatsApp)
    }

    // MARK: - La ventana

    private func makeApp() -> AppModel {
        let home = makeHome()
        return AppModel(
            home: home,
            makeWizard: { WizardState(preferredLanguages: $0, draftStore: MemoryDraftStore(nil)) },
            makeHealth: { [self] _ in makeModel() })
    }

    func testHealthOpensFromTheHomeAndComesBack() throws {
        _ = try install([ToolConnection(tool: .notion, status: .connected, sources: .everything)])
        let app = makeApp()
        XCTAssertEqual(app.screen, .home)

        app.openHealth()
        XCTAssertEqual(app.screen, .health)
        XCTAssertNotNil(app.health)

        app.closeHealth()
        XCTAssertEqual(app.screen, .home)
        XCTAssertNil(app.health)
    }

    func testHealthDoesNotOpenFromTheWizard() {
        let app = makeApp()  // sin agentes: abre el wizard
        XCTAssertEqual(app.screen, .wizard)

        app.openHealth()

        XCTAssertEqual(app.screen, .wizard)
        XCTAssertNil(app.health)
    }
}
