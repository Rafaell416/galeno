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

    private final class Cues { var played: [Sounds.Cue] = [] }

    private func makeModel(
        mcp: FakeMCP = FakeMCP(), whatsapp: FakeWhatsApp = FakeWhatsApp(), claude: String? = "/ruta/claude",
        skills: any SkillUpdating = SkillUpdaterNotAvailable(), opened: OpenedURLs = OpenedURLs(), cues: Cues = Cues()
    ) -> HealthModel {
        HealthModel(
            store: installer.store, locateClaude: { claude }, makeMCP: { _ in mcp }, whatsapp: whatsapp,
            skillUpdater: skills, authorizer: nil, systemAuthorizer: nil, language: { .spanish },
            openURL: { opened.urls.append($0) }, returnToApp: {}, sleep: { _ in },
            timing: HealthModel.Timing(connectorPoll: 1, connectorMax: 3, pendingLooks: 3),
            playSound: { cues.played.append($0) })
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

    /// Reconectar suena como el resto de la app: el sonido de conexión lograda al quedar viva, el de fallo si no.
    func testReconnectingPlaysTheConnectedSoundWhenItWorks() async throws {
        _ = try install([ToolConnection(tool: .fathom, status: .connected, sources: .everything)])
        let cues = Cues()
        let model = makeModel(mcp: FakeMCP(statuses: [serverName(.fathom): .needsAuthentication]), cues: cues)
        await model.check()
        XCTAssertTrue(cues.played.isEmpty, "mirar el estado no suena")

        model.reconnect(.fathom)
        _ = await waitUntil { !cues.played.isEmpty }

        XCTAssertEqual(cues.played, [.connected])
    }

    func testReconnectingPlaysTheFailedSoundWhenItDoesNot() async throws {
        _ = try install([ToolConnection(tool: .notion, status: .connected, sources: .everything)])
        let cues = Cues()
        let model = makeModel(mcp: FakeMCP(otherServers: [serverName(.notion)]), cues: cues)
        await model.check()

        model.reconnect(.notion)
        _ = await waitUntil { !cues.played.isEmpty }

        XCTAssertEqual(cues.played, [.failed])
    }

    func testCancellingAReconnectionPlaysNothing() async throws {
        _ = try install([ToolConnection(tool: .fathom, status: .connected, sources: .everything)])
        let cues = Cues()
        let mcp = FakeMCP(statuses: [serverName(.fathom): .needsAuthentication], holdLogin: true)
        let model = makeModel(mcp: mcp, cues: cues)
        await model.check()

        model.reconnect(.fathom)
        model.cancelReconnect()
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertTrue(cues.played.isEmpty)
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

    /// Quien actualiza Galeno trae instalado un puente anterior a `status --json`: se pone al día antes de preguntar.
    func testTheInstalledBridgeIsBroughtUpToDateBeforeAskingItsStatus() async throws {
        _ = try install([ToolConnection(tool: .whatsapp, status: .connected, sources: .everything)])
        let bridge = FakeWhatsApp()
        bridge.reportedStatus = linkedStatus(daysAgo: 1)
        let model = makeModel(whatsapp: bridge)

        await model.check()

        let calls = bridge.calls
        let prepared = try XCTUnwrap(calls.firstIndex(of: "prepare"))
        let asked = try XCTUnwrap(calls.firstIndex(of: "status"))
        XCTAssertLessThan(prepared, asked)
    }

    func testABridgeThatDoesNotAnswerIsShownAsSuch() async throws {
        _ = try install([ToolConnection(tool: .whatsapp, status: .connected, sources: .everything)])
        let model = makeModel(whatsapp: FakeWhatsApp())  // sin estado: no contesta

        await model.check()

        XCTAssertNil(model.whatsapp?.status)
        XCTAssertFalse(try XCTUnwrap(model.whatsapp).isLinked)
    }

    // MARK: - WhatsApp: reiniciar el servicio de fondo

    /// El reinicio al abrir la app puede fallar y dejar `sync` sin cargar. Salud lo ofrece arreglar sin re-vincular: no
    /// cierra la sesión ni vincula, solo vuelve a cargar el servicio con el bridge al día.
    func testASyncThatIsNotRunningCanBeRestartedWithoutRelinking() async throws {
        _ = try install([ToolConnection(tool: .whatsapp, status: .connected, sources: .everything)])
        let bridge = FakeWhatsApp()
        bridge.reportedStatus = linkedStatus(daysAgo: 3)
        bridge.reportedSync = .stopped
        let model = makeModel(whatsapp: bridge)
        await model.check()
        XCTAssertTrue(model.canRestartSync)

        let done = await model.restartSyncNow()

        XCTAssertTrue(done)
        XCTAssertEqual(model.whatsapp?.sync, .running)
        XCTAssertFalse(model.canRestartSync, "ya corre: el botón se va")
        // Primero el bridge al día y después el servicio; luego Salud vuelve a mirar (y eso llama a `prepare` otra vez).
        let calls = bridge.calls.filter { ["prepare", "installLaunchd", "unlink", "pair"].contains($0) }
        let load = try XCTUnwrap(calls.firstIndex(of: "installLaunchd"))
        XCTAssertGreaterThan(load, 0)
        XCTAssertEqual(calls[load - 1], "prepare")
        XCTAssertEqual(calls.filter { $0 == "installLaunchd" }.count, 1)
        XCTAssertFalse(calls.contains("unlink") || calls.contains("pair"), "la sesión no se toca")
    }

    func testRestartingIsOnlyOfferedWithASessionAndASyncThatIsNotRunning() async throws {
        _ = try install([ToolConnection(tool: .whatsapp, status: .connected, sources: .everything)])
        let bridge = FakeWhatsApp()
        bridge.reportedStatus = linkedStatus(daysAgo: 3)
        bridge.reportedSync = .running
        let running = makeModel(whatsapp: bridge)
        await running.check()
        XCTAssertFalse(running.canRestartSync)

        bridge.reportedSync = .notInstalled
        await running.check()
        XCTAssertTrue(running.canRestartSync, "sin cargar también se puede arrancar")

        bridge.reportedStatus = WhatsAppStatus(isLinked: false, number: nil, linkedAt: nil, bridgeVersion: "0.4.2")
        await running.check()
        XCTAssertFalse(running.canRestartSync, "sin sesión no hay nada que arrancar: se vincula")
    }

    func testAFailedRestartIsSaidAndLeavesTheSessionAlone() async throws {
        _ = try install([ToolConnection(tool: .whatsapp, status: .connected, sources: .everything)])
        let bridge = FakeWhatsApp(installError: .launchdFailed("no pudo"))
        bridge.reportedStatus = linkedStatus(daysAgo: 3)
        bridge.reportedSync = .stopped
        let model = makeModel(whatsapp: bridge)
        await model.check()

        model.restartSync()
        let said = await waitUntil { model.syncRestartFailed && !model.isRestartingSync }

        XCTAssertTrue(said)
        XCTAssertEqual(model.whatsapp?.sync, .stopped)
        XCTAssertTrue(model.whatsapp?.isLinked == true, "la sesión sigue vinculada")
        XCTAssertTrue(model.canRestartSync, "se puede volver a intentar")
    }

    // MARK: - WhatsApp: activar los envíos

    private final class Changed { var agents: [UUID] = [] }

    private func contents(_ record: AgentRecord, _ path: String) throws -> String {
        try String(contentsOf: record.folder.appendingPathComponent(path), encoding: .utf8)
    }

    private func whatsAppIsAccepted() throws -> Bool? {
        try XCTUnwrap(try installer.store.load()).connection(for: .whatsapp)?.sendingAccepted
    }

    /// Quien vinculó WhatsApp cuando Galeno solo leía no recibe el envío al actualizar: su agente sigue leyendo
    /// y nada pregunta por la bandeja de salida.
    func testSomeoneWhoLinkedWhenGalenoOnlyReadKeepsReadingOnly() async throws {
        let agent = try install([ToolConnection(tool: .whatsapp, status: .connected, sources: .everything)])
        let bridge = FakeWhatsApp()
        bridge.reportedStatus = linkedStatus(daysAgo: 3)
        bridge.reportedOutbox = FakeWhatsApp.emptyOutbox
        let model = makeModel(whatsapp: bridge)

        await model.check()

        let health = try XCTUnwrap(model.whatsapp)
        XCTAssertFalse(health.sendingAccepted)
        XCTAssertNil(health.outbox)
        XCTAssertFalse(bridge.calls.contains("outbox"))
        XCTAssertFalse(try contents(agent, ".mcp.json").contains("--with-send"))
        XCTAssertFalse(try contents(agent, ".claude/settings.json").contains("send_message"))
        // Sin con qué volver a escribir los agentes, esta vista no ofrece activarlo.
        XCTAssertFalse(model.canActivateSending)
        model.askActivateSending()
        XCTAssertEqual(model.activation, .idle)
    }

    /// «Activar envíos»: nada cambia hasta confirmar; al confirmar, `sync` se reinicia con el bridge nuevo y se
    /// vuelve a escribir cada agente que usa WhatsApp, con la herramienta y la regla que pide aprobación a la vez.
    func testActivatingSendingRestartsSyncAndRewritesTheAgentsThatUseWhatsApp() async throws {
        let withWhatsApp = try install(
            [ToolConnection(tool: .whatsapp, status: .connected, sources: .everything)], name: "Hermes")
        let without = try install(
            [ToolConnection(tool: .notion, status: .connected, sources: .everything)], name: "Hera")
        let memory = withWhatsApp.folder.appendingPathComponent("memoria/proyecto.md")
        try Data("lo que aprendió\n".utf8).write(to: memory)
        let bridge = FakeWhatsApp()
        bridge.reportedStatus = linkedStatus(daysAgo: 3)
        bridge.reportedSync = .running
        bridge.reportedOutbox = FakeWhatsApp.emptyOutbox
        let changed = Changed()
        let model = makeModel(whatsapp: bridge)
        model.enableSendingActivation(installer: installer) { changed.agents = $0 }
        await model.check()

        model.askActivateSending()
        XCTAssertEqual(model.activation, .confirming)
        XCTAssertNil(try whatsAppIsAccepted(), "nada se guarda hasta confirmar")
        XCTAssertFalse(bridge.calls.contains("installLaunchd"))

        model.confirmActivateSending()
        let done = await waitUntil { model.activation == .idle }

        XCTAssertTrue(done)
        XCTAssertEqual(try whatsAppIsAccepted(), true)
        // Primero el bridge al día, después `sync` con él: el de antes no saca la bandeja de salida.
        let calls = bridge.calls.filter { ["prepare", "installLaunchd"].contains($0) }
        let restart = try XCTUnwrap(calls.firstIndex(of: "installLaunchd"))
        XCTAssertGreaterThan(restart, 0)
        XCTAssertEqual(calls[restart - 1], "prepare")
        XCTAssertEqual(calls.filter { $0 == "installLaunchd" }.count, 1)

        XCTAssertTrue(try contents(withWhatsApp, ".mcp.json").contains("--with-send"))
        let settings = try contents(withWhatsApp, ".claude/settings.json")
        let rules = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(settings.utf8)) as? [String: Any])["permissions"] as? [String: [String]]
        XCTAssertEqual(rules?["ask"], ["mcp__whatsapp__send_message"])
        XCTAssertFalse(rules?["allow"]?.contains { $0.contains("send_message") || $0 == "mcp__whatsapp__*" } ?? true)
        XCTAssertTrue(try contents(withWhatsApp, "AGENTS.md").contains("envías solo con aprobación"))
        XCTAssertEqual(try String(contentsOf: memory, encoding: .utf8), "lo que aprendió\n", "la memoria no se toca")

        XCTAssertFalse(try contents(without, ".mcp.json").contains("whatsapp"))
        XCTAssertEqual(changed.agents, [withWhatsApp.id], "solo el que usa WhatsApp cambió")

        let health = try XCTUnwrap(model.whatsapp)
        XCTAssertTrue(health.sendingAccepted)
        XCTAssertEqual(health.outbox, FakeWhatsApp.emptyOutbox)
    }

    func testIfTheBridgeCannotBeMadeReadyNothingIsActivated() async throws {
        let agent = try install([ToolConnection(tool: .whatsapp, status: .connected, sources: .everything)])
        let bridge = FakeWhatsApp(prepareError: .bridgeMissing)
        bridge.reportedStatus = linkedStatus(daysAgo: 3)
        let model = makeModel(whatsapp: bridge)
        model.enableSendingActivation(installer: installer) { _ in XCTFail("ningún agente cambió") }
        await model.check()

        model.askActivateSending()
        model.confirmActivateSending()
        let failed = await waitUntil { model.activation == .failed }

        XCTAssertTrue(failed)
        XCTAssertNil(try whatsAppIsAccepted())
        XCTAssertFalse(try contents(agent, ".mcp.json").contains("--with-send"))
        model.cancelActivateSending()
        XCTAssertEqual(model.activation, .idle)
    }

    /// Volver a vincular pasa por la advertencia, que es la que dice que el agente puede enviar: eso es aceptarlo.
    func testRelinkingAcceptsSending() async throws {
        let agent = try install([ToolConnection(tool: .whatsapp, status: .connected, sources: .everything)])
        let bridge = FakeWhatsApp()
        bridge.reportedStatus = linkedStatus(daysAgo: 19)
        let model = makeModel(whatsapp: bridge)
        model.enableSendingActivation(installer: installer) { _ in }
        await model.check()

        model.askRelink()
        model.confirmRelink()
        let done = await waitUntil { model.relink == .done }

        XCTAssertTrue(done)
        XCTAssertEqual(try whatsAppIsAccepted(), true)
        XCTAssertTrue(try contents(agent, ".mcp.json").contains("--with-send"))
        XCTAssertEqual(model.whatsapp?.sendingAccepted, true)
    }

    private func installWithSendingAccepted() throws -> AgentRecord {
        try install([
            ToolConnection(tool: .whatsapp, status: .connected, sources: .everything, sendingAccepted: true)
        ])
    }

    func testSentTodayComesFromTheBridge() async throws {
        _ = try installWithSendingAccepted()
        let bridge = FakeWhatsApp()
        bridge.reportedStatus = linkedStatus(daysAgo: 3)
        var outbox = FakeWhatsApp.emptyOutbox
        outbox.sentToday = 12
        outbox.pendingToday = 3
        outbox.newChatsToday = 7
        outbox.groupsToday = 2
        outbox.pendingTotal = 3
        bridge.reportedOutbox = outbox
        let model = makeModel(whatsapp: bridge)

        await model.check()

        let health = try XCTUnwrap(model.whatsapp)
        XCTAssertTrue(health.sendingAccepted)
        XCTAssertEqual(health.outbox?.usedToday, 15, "lo enviado y lo que está en cola cuentan para el tope")
        XCTAssertEqual(health.outbox?.newChatsToday, 7)
    }

    func testPausingAndResumingGoThroughTheBridge() async throws {
        _ = try installWithSendingAccepted()
        let bridge = FakeWhatsApp()
        bridge.reportedStatus = linkedStatus(daysAgo: 3)
        bridge.reportedOutbox = FakeWhatsApp.emptyOutbox
        let model = makeModel(whatsapp: bridge)
        await model.check()

        model.setSendingPaused(true)
        let paused = await waitUntil { model.whatsapp?.outbox?.isPaused == true && !model.isSavingSending }
        XCTAssertTrue(paused)

        model.setSendingPaused(false)
        let resumed = await waitUntil { model.whatsapp?.outbox?.isPaused == false && !model.isSavingSending }
        XCTAssertTrue(resumed)
        XCTAssertEqual(bridge.calls.filter { $0.hasPrefix("pause:") }, ["pause:true", "pause:false"])
        XCTAssertFalse(model.sendingSaveFailed)
    }

    /// Los topes se pueden bajar; por encima del techo que trae el bridge no sube nadie.
    func testLimitsNeverGoAboveTheCeiling() async throws {
        _ = try installWithSendingAccepted()
        let bridge = FakeWhatsApp()
        bridge.reportedStatus = linkedStatus(daysAgo: 3)
        bridge.reportedOutbox = FakeWhatsApp.emptyOutbox
        let model = makeModel(whatsapp: bridge)
        await model.check()

        model.setSendLimits(dailyTotal: 5000, dailyNewChats: 5000, dailyGroups: 5000)
        let raised = await waitUntil { bridge.calls.contains { $0.hasPrefix("limits:") } && !model.isSavingSending }
        XCTAssertTrue(raised)
        XCTAssertEqual(bridge.calls.last { $0.hasPrefix("limits:") }, "limits:80,25,20")

        model.setSendLimits(dailyTotal: 10, dailyNewChats: 3, dailyGroups: 0)
        let lowered = await waitUntil { model.whatsapp?.outbox?.limits.dailyTotal == 10 && !model.isSavingSending }
        XCTAssertTrue(lowered)
        XCTAssertEqual(bridge.calls.last { $0.hasPrefix("limits:") }, "limits:10,3,0")
    }

    func testAChangeThatCannotBeSavedIsSaid() async throws {
        _ = try installWithSendingAccepted()
        let bridge = FakeWhatsApp()
        bridge.reportedStatus = linkedStatus(daysAgo: 3)
        bridge.reportedOutbox = FakeWhatsApp.emptyOutbox
        bridge.failSendingChanges = .unexpectedOutput("disco lleno")
        let model = makeModel(whatsapp: bridge)
        await model.check()

        model.setSendingPaused(true)
        let said = await waitUntil { model.sendingSaveFailed && !model.isSavingSending }

        XCTAssertTrue(said)
        XCTAssertEqual(model.whatsapp?.outbox?.isPaused, false, "se enseña lo que hay, no lo que se quiso")
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
        let calls = bridge.calls.filter { ["unlink", "pair", "installLaunchd"].contains($0) }
        XCTAssertEqual(calls, ["unlink", "pair", "installLaunchd"])
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
