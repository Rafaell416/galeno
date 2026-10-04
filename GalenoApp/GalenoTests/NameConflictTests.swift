import GalenoCore
import XCTest

@testable import Galeno

/// Ya hay en Claude Code otro servidor con el nombre que Galeno quería usar. Galeno nunca lo
/// borra por su cuenta: pregunta; lo predeterminado es usar otro nombre (`galeno-…`), y borrar
/// exige elegirlo y luego confirmarlo.
@MainActor
final class NameConflictTests: XCTestCase {
    private var prefixes: [(Tool, String?)] = []
    private var statuses: [(Tool, ConnectionStatus)] = []

    private func makeFlow(
        _ tools: [Tool], mcp: FakeMCP, namePrefixes: [Tool: String] = [:]
    ) -> ConnectFlow {
        prefixes = []
        statuses = []
        return ConnectFlow(
            tools: tools, mcp: mcp, whatsapp: FakeWhatsApp(), slack: FakeSlackSetup(),
            agentName: { "Aurora" }, fetchRealData: false, sleep: SleepLog.holdingSuccess.sleeper,
            onStatus: { [unowned self] tool, status in statuses.append((tool, status)) },
            namePrefixes: namePrefixes,
            onNamePrefix: { [unowned self] tool, prefix in prefixes.append((tool, prefix)) })
    }

    private func waitFor(_ flow: ConnectFlow, _ phase: ConnectFlow.Phase) async -> Bool {
        await waitUntil { flow.phase == phase }
    }

    // MARK: - Preguntar

    func testAClashingServerAsksInsteadOfFailingOrDeleting() async {
        let mcp = FakeMCP(otherServers: ["notion"])
        let flow = makeFlow([.notion], mcp: mcp)
        defer { flow.cancelAll() }

        flow.connect()
        let asking = await waitFor(flow, .nameConflict(server: "notion"))

        XCTAssertTrue(asking, "\(flow.phase)")
        XCTAssertEqual(mcp.calls, ["status notion"])
    }

    // MARK: - Otro nombre (lo predeterminado)

    func testUsingAnotherNameRegistersGalenoNotionAndLeavesTheOtherAlone() async {
        let mcp = FakeMCP(otherServers: ["notion"])
        let flow = makeFlow([.notion], mcp: mcp)
        defer { flow.cancelAll() }
        flow.connect()
        _ = await waitFor(flow, .nameConflict(server: "notion"))

        flow.useAlternateName()
        let done = await waitFor(flow, .succeeded(alreadyConnected: false))

        XCTAssertTrue(done, "\(flow.phase)")
        XCTAssertTrue(mcp.calls.contains("register galeno-notion"))
        XCTAssertTrue(mcp.calls.contains("login galeno-notion"))
        XCTAssertFalse(mcp.calls.contains { $0.hasPrefix("remove") })
        XCTAssertEqual(prefixes.count, 1)
        XCTAssertEqual(prefixes.first?.0, .notion)
        XCTAssertEqual(prefixes.first?.1, MCPServerCatalog.alternateNamePrefix)
        XCTAssertTrue(statuses.contains { $0 == (.notion, .connected) })
    }

    func testSlackWithAnotherNameGoesOnToAskForTheToken() async {
        let mcp = FakeMCP(otherServers: ["slack"])
        let flow = makeFlow([.slack], mcp: mcp)
        defer { flow.cancelAll() }
        _ = await waitFor(flow, .nameConflict(server: "slack"))

        flow.useAlternateName()
        let asking = await waitFor(flow, .slackToken)

        XCTAssertTrue(asking, "\(flow.phase)")
        XCTAssertTrue(mcp.calls.contains("status galeno-slack"))
        XCTAssertFalse(mcp.calls.contains { $0.hasPrefix("remove") })
    }

    /// Si ya se eligió el nombre alternativo en otra ocasión, no se vuelve a preguntar.
    func testAnAlreadyChosenAlternateNameIsUsedWithoutAsking() async {
        let mcp = FakeMCP(statuses: ["galeno-notion": .connected], otherServers: ["notion"])
        let flow = makeFlow([.notion], mcp: mcp, namePrefixes: [.notion: "galeno-"])
        defer { flow.cancelAll() }

        flow.connect()
        let done = await waitFor(flow, .succeeded(alreadyConnected: true))

        XCTAssertTrue(done, "\(flow.phase)")
        XCTAssertFalse(mcp.calls.contains("status notion"))
    }

    func testIfTheAlternateNameIsAlsoTakenItFailsAndShowsWhichOne() async {
        let mcp = FakeMCP(otherServers: ["notion", "galeno-notion"])
        let flow = makeFlow([.notion], mcp: mcp)
        defer { flow.cancelAll() }
        flow.connect()
        _ = await waitFor(flow, .nameConflict(server: "notion"))

        flow.useAlternateName()
        let failed = await waitFor(flow, .failed(.nameInUse))

        XCTAssertTrue(failed, "\(flow.phase)")
        XCTAssertEqual(flow.failureDetail, "galeno-notion")
        XCTAssertFalse(mcp.calls.contains { $0.hasPrefix("remove") })
    }

    // MARK: - Borrar (solo si lo pide y lo confirma)

    func testChoosingToDeleteOnlyAsksForConfirmation() async {
        let mcp = FakeMCP(otherServers: ["notion"])
        let flow = makeFlow([.notion], mcp: mcp)
        defer { flow.cancelAll() }
        flow.connect()
        _ = await waitFor(flow, .nameConflict(server: "notion"))

        flow.askToRemoveConflictingServer()

        XCTAssertEqual(flow.phase, .confirmingRemoval(server: "notion"))
        XCTAssertFalse(mcp.calls.contains { $0.hasPrefix("remove") }, "elegirlo no borra nada")
    }

    func testBackingOutOfTheConfirmationDeletesNothing() async {
        let mcp = FakeMCP(otherServers: ["notion"])
        let flow = makeFlow([.notion], mcp: mcp)
        defer { flow.cancelAll() }
        flow.connect()
        _ = await waitFor(flow, .nameConflict(server: "notion"))
        flow.askToRemoveConflictingServer()

        flow.cancelRemoval()

        XCTAssertEqual(flow.phase, .nameConflict(server: "notion"))
        XCTAssertFalse(mcp.calls.contains { $0.hasPrefix("remove") })
    }

    func testConfirmingDeletesTheServerAndConnectsWithTheNormalName() async {
        let mcp = FakeMCP(otherServers: ["notion"])
        let flow = makeFlow([.notion], mcp: mcp)
        defer { flow.cancelAll() }
        flow.connect()
        _ = await waitFor(flow, .nameConflict(server: "notion"))
        flow.askToRemoveConflictingServer()

        flow.removeConflictingServer()
        let done = await waitFor(flow, .succeeded(alreadyConnected: false))

        XCTAssertTrue(done, "\(flow.phase)")
        XCTAssertTrue(mcp.calls.contains("remove notion"))
        XCTAssertTrue(mcp.calls.contains("register notion"))
        XCTAssertFalse(mcp.calls.contains("register galeno-notion"))
        XCTAssertEqual(prefixes.last?.1, nil)
    }

    func testCannotDeleteWithoutTheConfirmationStep() async {
        let mcp = FakeMCP(otherServers: ["notion"])
        let flow = makeFlow([.notion], mcp: mcp)
        defer { flow.cancelAll() }
        flow.connect()
        _ = await waitFor(flow, .nameConflict(server: "notion"))

        flow.removeConflictingServer()  // sin pasar por «Borrar el existente…»

        XCTAssertEqual(flow.phase, .nameConflict(server: "notion"))
        XCTAssertFalse(mcp.calls.contains { $0.hasPrefix("remove") })
    }

    func testAFailedDeletionIsReportedAndNothingIsRegistered() async {
        let mcp = FakeMCP(otherServers: ["notion"], removeError: .removeFailed("denegado"))
        let flow = makeFlow([.notion], mcp: mcp)
        defer { flow.cancelAll() }
        flow.connect()
        _ = await waitFor(flow, .nameConflict(server: "notion"))
        flow.askToRemoveConflictingServer()

        flow.removeConflictingServer()
        let failed = await waitFor(flow, .failed(.couldNotRemove))

        XCTAssertTrue(failed, "\(flow.phase)")
        XCTAssertEqual(flow.failureDetail, "denegado")
        XCTAssertFalse(mcp.calls.contains { $0.hasPrefix("register") })
    }
}

/// `claude mcp remove` real: el comando exacto, con el alcance de usuario.
final class ClaudeMCPRemoveTests: XCTestCase {
    func testRemoveRunsTheExactCommandAtUserScope() async throws {
        let runner = FakeRunner(["/bin/claude mcp remove notion -s user": ok("Removed")])
        let client = ClaudeMCPClient(claudePath: "/bin/claude", runner: runner)

        try await client.remove(server: "notion")

        XCTAssertEqual(runner.calls, ["/bin/claude mcp remove notion -s user"])
    }

    func testRemoveReportsAFailure() async {
        let runner = FakeRunner(["/bin/claude mcp remove notion -s user": CommandResult(status: 1, output: "nope")])
        let client = ClaudeMCPClient(claudePath: "/bin/claude", runner: runner)

        do {
            try await client.remove(server: "notion")
            XCTFail("debía fallar")
        } catch {
            XCTAssertEqual(error as? MCPConnectError, .removeFailed("nope"))
        }
    }
}
