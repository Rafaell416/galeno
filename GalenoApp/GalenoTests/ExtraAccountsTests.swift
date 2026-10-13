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

    func testTheDetailShowsOneRowPerAccountAndDoesNotBreak() async throws {
        let home = HomeModel(
            store: installer.store, defaults: UserDefaults(suiteName: "galeno-test-\(UUID().uuidString)")!,
            claudePath: "/ruta/claude", installer: installer, settle: {})
        let health = HealthModel(
            store: installer.store, locateClaude: { "/ruta/claude" }, makeMCP: { _ in FakeMCP() },
            whatsapp: FakeWhatsApp(), authorizer: nil, systemAuthorizer: nil, language: { .spanish }, openURL: { _ in },
            returnToApp: {}, sleep: { _ in }, playSound: { _ in })
        let model = AgentDetailModel(agentID: record.id, home: home, health: health, installer: installer)
        let notion = model.toolRows.filter { $0.tool == .notion }
        XCTAssertEqual(notion.count, 2, "una fila por cuenta")
        XCTAssertEqual(notion.filter { $0.accountID == nil }.count, 1, "la de siempre, una sola vez")
        XCTAssertEqual(Set(notion.map(\.id)).count, 2, "cada fila con su identidad")
        XCTAssertEqual(model.sharedWith.count, 0)
        await health.check()
        XCTAssertEqual(health.connections.filter { $0.tool == .notion }.count, 1)
    }

    // MARK: - «Añadir otra cuenta» en el asistente

    private func shortWizard(mcp: FakeMCP = FakeMCP()) throws -> WizardState {
        var installation = try installation()
        // Un agente nuevo parte de lo que la instalación tiene conectado; aquí, solo la cuenta de siempre de Notion.
        installation.connections.removeAll { $0.accountID != nil }
        let services = ConnectServices(
            makeMCP: { _ in mcp }, whatsapp: FakeWhatsApp(), slack: FakeSlackSetup(), installer: installer,
            fetchRealData: false, sleep: SleepLog().sleeper)
        return WizardState(
            preferredLanguages: ["es"],
            claudeStatus: .found(version: "2.1.277", path: "/ruta/claude", loggedIn: true),
            connectServices: services, startingFrom: installation)
    }

    private func waitForAccount(_ state: WizardState) async {
        for _ in 0..<400 where state.accountPhase == .working { try? await Task.sleep(for: .milliseconds(5)) }
    }

    func testTheWizardOffersAnotherAccountOnlyForConnectedToolsGalenoRegisters() throws {
        let state = try shortWizard()
        XCTAssertTrue(state.canAddAccount(to: .notion))
        XCTAssertFalse(state.canAddAccount(to: .slack), "Slack todavía no")
        XCTAssertFalse(state.canAddAccount(to: .whatsapp))
        XCTAssertFalse(state.canAddAccount(to: .jira), "no está conectada en este agente")
    }

    func testAddingAnAccountInTheWizardKeepsItWithTheAgentConfig() async throws {
        let mcp = FakeMCP()
        let state = try shortWizard(mcp: mcp)
        state.askAddAccount(.notion)
        state.accountDraft = "Personal"
        state.addAccount()
        await waitForAccount(state)

        XCTAssertNil(state.addingAccountTool)
        XCTAssertEqual(state.accountPhase, .idle)
        XCTAssertEqual(state.extraAccounts.map(\.accountID), ["personal"])
        XCTAssertEqual(mcp.calls.filter { $0.hasPrefix("register") }, ["register galeno-notion-personal"])
        XCTAssertEqual(state.connections.filter { $0.tool == .notion }.count, 1, "el asistente sigue por herramienta")

        state.agentName = "Nueva"
        let config = state.makeConfig()
        XCTAssertEqual(config.connections(for: .notion).count, 2)
        // Al crear el agente, la cuenta se guarda aparte y el motor la escribe con su servidor.
        let outcome = try installer.install(config)
        XCTAssertTrue(try String(contentsOf: outcome.record.folder.appending(path: ".mcp.json"), encoding: .utf8)
            .contains("galeno-notion-personal"))
        let saved = try installation()
        XCTAssertNotNil(saved.connection(for: ConnectionID(tool: .notion, account: "personal")))
    }

    func testAnExtraAccountThatFailsToAuthorizeIsNotKept() async throws {
        let mcp = FakeMCP(loginFailures: ["galeno-notion-personal": [.loginTimedOut]])
        let state = try shortWizard(mcp: mcp)
        state.askAddAccount(.notion)
        state.accountDraft = "Personal"
        state.addAccount()
        await waitForAccount(state)
        XCTAssertEqual(state.accountPhase, .failed(.notAuthorizedInTime))
        XCTAssertTrue(state.extraAccounts.isEmpty)
        XCTAssertEqual(state.makeConfig().connections(for: .notion).count, 1)
    }

    func testTheWizardRefusesAnAccountNameTheInstallationAlreadyHas() async throws {
        // La instalación del test ya tiene «trabajo» (setUp): un agente nuevo no puede repetir ese nombre.
        let full = WizardState(
            preferredLanguages: ["es"],
            claudeStatus: .found(version: "2.1.277", path: "/ruta/claude", loggedIn: true),
            connectServices: services(), startingFrom: try installation())
        full.askAddAccount(.notion)
        full.accountDraft = "Trabajo"
        full.addAccount()
        XCTAssertEqual(full.accountPhase, .failed(.alreadyExists))
    }

    func testRemovingAnExtraAccountInTheWizardLeavesItOutOfTheConfig() async throws {
        let state = try shortWizard()
        state.askAddAccount(.notion)
        state.accountDraft = "Personal"
        state.addAccount()
        await waitForAccount(state)
        state.removeExtraAccount(ConnectionID(tool: .notion, account: "personal"))
        XCTAssertTrue(state.extraAccounts.isEmpty)
        XCTAssertEqual(state.makeConfig().connections(for: .notion).count, 1)
    }

    func testTheDraftKeepsTheExtraAccounts() async throws {
        let state = try shortWizard()
        state.askAddAccount(.notion)
        state.accountDraft = "Personal"
        state.addAccount()
        await waitForAccount(state)
        state.agentName = "Hera"
        let draft = try XCTUnwrap(state.makeDraft())
        XCTAssertEqual(draft.extraAccounts?.map(\.accountID), ["personal"])
        // Un borrador de antes no las trae y se lee igual.
        var legacy = draft
        legacy.extraAccounts = nil
        let decoded = try JSONDecoder().decode(WizardDraft.self, from: JSONEncoder().encode(legacy))
        XCTAssertNil(decoded.extraAccounts)
    }
}
