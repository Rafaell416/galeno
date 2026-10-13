import GalenoCore
import XCTest

@testable import Galeno

/// Una cuenta extra de una herramienta (`ToolConnection.accountID`, GAL-13) no puede tumbar la app ni perderse al guardar.
///
/// Todavía no hay interfaz que la cree, pero el motor y la instalación ya la admiten: cualquier pantalla que arme un
/// diccionario por herramienta con las conexiones de la instalación se caería con dos de la misma. Todo en carpetas temporales.
@MainActor
final class ExtraAccountsTests: XCTestCase {
    private var installer: AgentInstaller!
    private var record: AgentRecord!

    private let prefix = MCPServerCatalog.ownedNamePrefix

    override func setUp() async throws {
        installer = .sandboxed()
        let config = AgentConfig(
            agentName: "Hera", language: .spanish,
            connections: [
                ToolConnection(tool: .notion, status: .connected, sources: .everything, serverNamePrefix: prefix),
                ToolConnection(
                    tool: .notion, status: .connected, sources: .everything, serverNamePrefix: prefix,
                    accountID: "trabajo", accountName: "Trabajo"),
            ])
        record = try installer.install(config).record
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: record.folder.deletingLastPathComponent().deletingLastPathComponent())
    }

    private func installation() throws -> GalenoInstallation {
        try XCTUnwrap(try installer.store.load())
    }

    private func services() -> ConnectServices {
        ConnectServices(
            makeMCP: { _ in FakeMCP() }, whatsapp: FakeWhatsApp(), slack: FakeSlackSetup(), installer: installer,
            fetchRealData: false, sleep: SleepLog().sleeper)
    }

    // MARK: - La instalación

    func testEachAccountIsSavedAsItsOwnSharedConnection() throws {
        let saved = try installation()
        XCTAssertEqual(saved.connections(for: .notion).count, 2)
        XCTAssertEqual(saved.connection(for: ConnectionID(tool: .notion))?.accountID, nil)
        XCTAssertEqual(saved.connection(for: ConnectionID(tool: .notion, account: "trabajo"))?.accountName, "Trabajo")
    }

    /// Guardar de nuevo la cuenta extra no toca la de siempre (antes se pisaban: las dos eran «Notion»).
    func testSavingAnExtraAccountNeverOverwritesTheDefaultOne() throws {
        var config = try XCTUnwrap(try installation().agent(id: record.id)).config
        config.connections[1].status = .skipped
        config.connections[1].oauthClientID = "otro"
        _ = try installer.install(config, existingAgentID: record.id)

        let saved = try installation()
        XCTAssertEqual(saved.connection(for: ConnectionID(tool: .notion))?.status, .connected)
        XCTAssertNil(saved.connection(for: ConnectionID(tool: .notion))?.oauthClientID)
    }

    func testTheGeneratedFilesHaveBothAccountsServers() throws {
        let mcp = try String(contentsOf: record.folder.appending(path: ".mcp.json"), encoding: .utf8)
        XCTAssertTrue(mcp.contains("\"galeno-notion\""))
        XCTAssertTrue(mcp.contains("\"galeno-notion-trabajo\""))
    }

    // MARK: - El asistente («Gestionar»)

    func testTheEditorOpensWithoutBreakingAndLeavesTheExtraAccountAlone() throws {
        let state = WizardState(
            preferredLanguages: ["es"],
            claudeStatus: .found(version: "2.1.277", path: "/ruta/claude", loggedIn: true),
            connectServices: services(), startingFrom: try installation(), editing: record.id)
        XCTAssertEqual(state.connections.filter { $0.tool == .notion }.count, 1, "el asistente solo maneja la de siempre")
        XCTAssertNil(state.connection(for: .notion)?.accountID)
    }

    func testSavingFromTheEditorKeepsTheExtraAccount() throws {
        let state = WizardState(
            preferredLanguages: ["es"],
            claudeStatus: .found(version: "2.1.277", path: "/ruta/claude", loggedIn: true),
            connectServices: services(), startingFrom: try installation(), editing: record.id)
        let config = state.makeConfig()
        XCTAssertEqual(config.connections(for: .notion).count, 2)
        XCTAssertEqual(config.connection(for: ConnectionID(tool: .notion, account: "trabajo"))?.accountName, "Trabajo")
    }

    func testANewAgentStartsWithoutTheExtraAccount() throws {
        let state = WizardState(
            preferredLanguages: ["es"],
            claudeStatus: .found(version: "2.1.277", path: "/ruta/claude", loggedIn: true),
            connectServices: services(), startingFrom: try installation())
        XCTAssertEqual(state.mode, .short)
        XCTAssertEqual(state.connections.filter { $0.tool == .notion }.count, 1)
        XCTAssertNil(state.connection(for: .notion)?.accountID)
    }

    // MARK: - El detalle y la salud

    func testTheDetailShowsOneRowPerToolAndDoesNotBreak() async throws {
        let home = HomeModel(
            store: installer.store, defaults: UserDefaults(suiteName: "galeno-test-\(UUID().uuidString)")!,
            claudePath: "/ruta/claude", installer: installer, settle: {})
        let health = HealthModel(
            store: installer.store, locateClaude: { "/ruta/claude" }, makeMCP: { _ in FakeMCP() },
            whatsapp: FakeWhatsApp(), authorizer: nil, systemAuthorizer: nil, language: { .spanish }, openURL: { _ in },
            returnToApp: {}, sleep: { _ in }, playSound: { _ in })
        let model = AgentDetailModel(agentID: record.id, home: home, health: health, installer: installer)
        XCTAssertEqual(model.toolRows.filter { $0.tool == .notion }.count, 1)
        XCTAssertEqual(model.sharedWith.count, 0)
        await health.check()
        XCTAssertEqual(health.connections.filter { $0.tool == .notion }.count, 1)
    }
}
