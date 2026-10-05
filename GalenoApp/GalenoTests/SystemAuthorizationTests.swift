import GalenoCore
import XCTest

@testable import Galeno

/// Una hoja de autenticación que solo apunta lo que se le pidió.
@MainActor
private final class FakeSheet: SystemAuthorizationPresenting {
    var canPresent = true
    private(set) var presented: [URL] = []
    private(set) var dismissals = 0
    private var cancel: (@MainActor () -> Void)?

    func present(url: URL, onCancel: @escaping @MainActor () -> Void) -> Bool {
        guard canPresent else { return false }
        presented.append(url)
        cancel = onCancel
        return true
    }

    func dismiss() { dismissals += 1 }
    func userClosesTheSheet() { cancel?() }
}

/// Las herramientas que se autorizan en el navegador (Notion, Jira, las de reuniones) lo hacen en la hoja de
/// autenticación del sistema, que Galeno cierra al terminar. Slack sigue en su ventana propia.
@MainActor
final class SystemAuthorizationTests: XCTestCase {
    private let jiraURL = URL(string: "https://auth.atlassian.com/authorize?client_id=abc")!
    private let slackURL = URL(string: "https://slack.com/oauth/v2_user/authorize?client_id=1111.2222")!
    private let sheet = FakeSheet()
    private var returnsToApp = 0

    private func makeFlow(tools: [Tool], mcp: FakeMCP) -> ConnectFlow {
        returnsToApp = 0
        return ConnectFlow(
            tools: tools, mcp: mcp, whatsapp: FakeWhatsApp(), slack: FakeSlackSetup(),
            agentName: { "Aurora" }, fetchRealData: false, sleep: SleepLog.holdingSuccess.sleeper,
            systemAuthorizer: sheet, returnToApp: { [weak self] in self?.returnsToApp += 1 })
    }

    func testAHostedToolIsAuthorizedInTheSystemSheetWhichClosesWhenItEnds() async {
        let mcp = FakeMCP(authorizationURL: jiraURL)
        let flow = makeFlow(tools: [.jira], mcp: mcp)
        defer { flow.cancelAll() }

        flow.connect()
        let done = await waitUntil { flow.phase == .succeeded(alreadyConnected: false) }

        XCTAssertTrue(done, "\(flow.phase)")
        XCTAssertEqual(sheet.presented, [jiraURL])
        XCTAssertTrue(mcp.calls.contains("autorización mostrada auth.atlassian.com"))
        XCTAssertGreaterThan(sheet.dismissals, 0, "la hoja se cierra cuando termina el login")
        XCTAssertEqual(returnsToApp, 1, "y Galeno vuelve al frente")
    }

    /// Todas las que se autorizan en el navegador usan la misma hoja: Notion, Jira, Fathom, Fireflies y Granola.
    func testEveryBrowserAuthorizedToolUsesTheSheet() async {
        for tool in [Tool.notion, .jira, .fathom, .fireflies, .granola] {
            let sheet = FakeSheet()
            let mcp = FakeMCP(authorizationURL: URL(string: "https://auth.example.com/authorize")!)
            let flow = ConnectFlow(
                tools: [tool], mcp: mcp, whatsapp: FakeWhatsApp(), slack: FakeSlackSetup(),
                agentName: { "Aurora" }, fetchRealData: false, sleep: SleepLog.holdingSuccess.sleeper,
                systemAuthorizer: sheet)
            flow.connect()
            let done = await waitUntil { flow.phase == .succeeded(alreadyConnected: false) }
            flow.cancelAll()

            XCTAssertTrue(done, "\(tool): \(flow.phase)")
            XCTAssertEqual(sheet.presented.count, 1, "\(tool)")
        }
    }

    /// Si la hoja no se puede mostrar, la dirección no se pierde: `claude` la abre en el navegador, como antes.
    func testIfTheSheetCannotBeShownTheBrowserIsUsedAsBefore() async {
        sheet.canPresent = false
        let mcp = FakeMCP(authorizationURL: jiraURL)
        let flow = makeFlow(tools: [.jira], mcp: mcp)
        defer { flow.cancelAll() }

        flow.connect()
        let done = await waitUntil { flow.phase == .succeeded(alreadyConnected: false) }

        XCTAssertTrue(done, "\(flow.phase)")
        XCTAssertTrue(mcp.calls.contains("autorización no mostrada auth.atlassian.com"))
    }

    func testClosingTheSheetStopsWaitingAndOffersToRetry() async {
        let mcp = FakeMCP(holdLogin: true, authorizationURL: jiraURL)
        let flow = makeFlow(tools: [.jira], mcp: mcp)
        defer { flow.cancelAll() }
        flow.connect()
        _ = await waitUntil { !self.sheet.presented.isEmpty }

        sheet.userClosesTheSheet()

        XCTAssertEqual(flow.phase, .failed(.notAuthorizedInTime))
        XCTAssertEqual(returnsToApp, 0, "si no autorizó, no se roba el foco")
    }

    func testSkippingWhileWaitingClosesTheSheet() async {
        let mcp = FakeMCP(holdLogin: true, authorizationURL: jiraURL)
        let flow = makeFlow(tools: [.jira, .notion], mcp: mcp)
        defer { flow.cancelAll() }
        flow.connect()
        _ = await waitUntil { !self.sheet.presented.isEmpty }
        let before = sheet.dismissals

        flow.skip()

        XCTAssertGreaterThan(sheet.dismissals, before)
    }

    /// La hoja real solo acepta direcciones `https`; cualquier otra cosa se rechaza sin abrir nada.
    func testTheSheetOnlyTakesHttpsAddresses() {
        let real = SystemAuthorizationSheet()
        XCTAssertFalse(real.present(url: URL(string: "http://auth.atlassian.com/authorize")!) {})
        XCTAssertFalse(real.present(url: URL(string: "file:///etc/hosts")!) {})
        real.dismiss()  // sin hoja abierta no hace nada
    }

    /// El aviso de cierre de la sesión lo llama AuthenticationServices **desde su propia cola**, no desde la principal.
    /// Un cierre aislado al hilo principal aborta el proceso al entrar (`dispatch_assert_queue`): así crasheó la app el
    /// 4 de octubre de 2026 al cerrar la hoja tras reconectar Jira.
    func testTheSessionsCloseNoticeCanBeCalledFromAnyQueueAndWorkRunsOnTheMainOne() async {
        let ran = expectation(description: "el aviso llegó")
        var onMain: Bool?
        let handler = SystemAuthorizationSheet.completion {
            onMain = Thread.isMainThread
            ran.fulfill()
        }

        DispatchQueue(label: "com.apple.AuthenticationServices.test").async { handler(nil, nil) }

        await fulfillment(of: [ran], timeout: 3)
        XCTAssertEqual(onMain, true)
    }

    // MARK: - Salud: «Reconectar»

    func testReconnectingFromHealthUsesTheSameSheet() async throws {
        let installer = AgentInstaller.sandboxed()
        defer { try? FileManager.default.removeItem(at: installer.agentsRoot.deletingLastPathComponent()) }
        _ = try installer.install(
            AgentConfig(
                agentName: "Hera", language: .spanish, projectDescription: "Proyecto",
                connections: [ToolConnection(tool: .fathom, status: .connected, sources: .everything)]))
        let server = ConnectTarget(tool: .fathom)!.servers[0].name
        let mcp = FakeMCP(statuses: [server: .needsAuthentication], authorizationURL: URL(string: "https://fathom.video/oauth")!)
        let model = HealthModel(
            store: installer.store, locateClaude: { "/ruta/claude" }, makeMCP: { _ in mcp }, whatsapp: FakeWhatsApp(),
            authorizer: nil, systemAuthorizer: sheet, language: { .spanish }, openURL: { _ in }, returnToApp: {},
            sleep: { _ in })
        await model.check()

        model.reconnect(.fathom)
        let done = await waitUntil { model.reconnecting == nil && model.connections.first?.state == .connected }

        XCTAssertTrue(done)
        XCTAssertEqual(sheet.presented.map(\.host), ["fathom.video"])
        XCTAssertGreaterThan(sheet.dismissals, 0)
    }
}
