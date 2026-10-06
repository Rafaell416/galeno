import GalenoCore
import XCTest

@testable import Galeno

/// El sub-wizard dentro del wizard: navegación, estados compartidos y el texto protegido.
@MainActor
final class ConnectIntegrationTests: XCTestCase {
    private func makeState(
        _ tools: [Tool], mcp: FakeMCP = FakeMCP(), whatsapp: FakeWhatsApp = FakeWhatsApp()
    ) -> WizardState {
        let services = ConnectServices(
            makeMCP: { _ in mcp }, whatsapp: whatsapp, installer: .sandboxed(), fetchRealData: false,
            sleep: SleepLog.holdingSuccess.sleeper)
        let state = WizardState(
            preferredLanguages: ["es"],
            claudeStatus: .found(version: "2.1.277", path: "/ruta/claude", loggedIn: true),
            connectServices: services)
        state.agentName = "Aurora"
        for tool in tools { state.toggle(tool) }
        return state
    }

    private func advance(_ state: WizardState, to step: WizardStep) {
        while state.step != step, state.canGoForward { state.next() }
        XCTAssertEqual(state.step, step)
    }

    // MARK: - Navegación

    func testTheNavigationBarStaysHiddenInTheConnectStepWhichEndsWithItsOwnButton() {
        let state = makeState([.notion])
        advance(state, to: .connect)
        state.beginConnecting()

        XCTAssertTrue(state.hidesNavigation)
        XCTAssertFalse(state.canGoForward)

        state.connectFlow?.skip()

        XCTAssertTrue(state.hidesNavigation, "la celebración lleva su propio «Continuar»")
        XCTAssertTrue(state.canGoForward, "y ese botón ya puede avanzar")
        state.next()
        XCTAssertEqual(state.step, .skills)
        XCTAssertFalse(state.hidesNavigation)
    }

    func testOtherStepsNeverHideTheNavigation() {
        let state = makeState([.notion])

        for step in WizardStep.allCases where step != .connect {
            XCTAssertFalse(state.hidesNavigation, "\(step)")
        }
    }

    func testTheCurrentFlowIsKeptWhileTheToolsStayTheSame() {
        let state = makeState([.notion, .jira])
        advance(state, to: .connect)
        state.beginConnecting()
        let first = state.connectFlow

        state.beginConnecting()

        XCTAssertTrue(state.connectFlow === first)
    }

    func testChangingTheToolsBuildsANewFlowAndKeepsWhatWasAlreadyConnected() {
        let state = makeState([.notion, .jira])
        advance(state, to: .connect)
        state.beginConnecting()
        state.setConnectionStatus(.notion, .connected)
        let first = state.connectFlow

        state.back()  // "Volver a elegir herramientas"
        state.toggle(.fathom)
        advance(state, to: .connect)
        state.beginConnecting()

        XCTAssertFalse(state.connectFlow === first)
        XCTAssertEqual(state.connectFlow?.tools, [.jira, .notion, .fathom], "en el orden del rol")
        XCTAssertEqual(state.connectFlow?.statuses[.notion], .connected)
        XCTAssertEqual(state.connectFlow?.screen, .connection(.jira), "sigue por la primera sin resolver")
    }

    // MARK: - Estados

    func testConnectionStatusesReachTheConfigTheWizardMakes() {
        let state = makeState([.notion, .jira])
        advance(state, to: .connect)
        state.beginConnecting()

        state.connectFlow?.skip()  // jira, la primera de producto → skipped
        state.setConnectionStatus(.notion, .connected)

        let statuses = Dictionary(uniqueKeysWithValues: state.makeConfig().connections.map { ($0.tool, $0.status) })
        XCTAssertEqual(statuses[.jira], .skipped)
        XCTAssertEqual(statuses[.notion], .connected)
    }

    func testGoogleMeetFollowsGoogleWorkspace() {
        let state = makeState([.googleMeet])
        XCTAssertEqual(state.selectedTools, [.googleWorkspace, .googleMeet])

        state.setConnectionStatus(.googleWorkspace, .connected)
        XCTAssertEqual(state.connections.first { $0.tool == .googleMeet }?.status, .connected)

        state.setConnectionStatus(.googleWorkspace, .skipped)
        XCTAssertEqual(state.connections.first { $0.tool == .googleMeet }?.status, .skipped)
    }

    func testSkippingEverythingStillLetsTheWizardContinue() {
        let state = makeState([.slack, .notion])
        advance(state, to: .connect)
        state.beginConnecting()

        state.connectFlow?.skip()
        state.connectFlow?.skip()

        XCTAssertTrue(state.canGoForward)
        XCTAssertEqual(state.connectFlow?.connectedCount, 0)
    }

    /// El usuario ya tiene su propio `notion` conectado (lo usan otros proyectos suyos). Galeno registra y autoriza el
    /// suyo, `galeno-notion`, y **no toca** el del usuario: ni lo mira, ni lo registra, ni inicia o cierra su sesión.
    /// (Incidente del 5 oct 2026: limpiar `notion` desconectó el agente de MediClub.)
    func testGalenoConnectsItsOwnNameAndNeverTouchesTheUsersServer() async {
        let mcp = FakeMCP(statuses: ["notion": .connected])
        let state = makeState([.notion], mcp: mcp)
        advance(state, to: .connect)
        state.beginConnecting()

        state.connectFlow?.connect()
        let connected = await waitUntil { state.connections.first { $0.tool == .notion }?.status == .connected }

        XCTAssertTrue(connected, "etapa: \(String(describing: state.connectFlow?.phase))")
        XCTAssertEqual(
            Array(mcp.calls.prefix(3)), ["status galeno-notion", "register galeno-notion", "login galeno-notion"])
        for call in mcp.calls {
            let server = call.split(separator: " ").dropFirst().first.map(String.init) ?? ""
            XCTAssertNotEqual(server, "notion", "tocó el servidor del usuario: \(call)")
        }
        XCTAssertEqual(state.connections.first { $0.tool == .notion }?.serverNamePrefix, "galeno-")
        // Lo que se genera (`.mcp.json`, permisos) usa ese mismo nombre.
        let connection = try? XCTUnwrap(state.makeConfig().connections.first { $0.tool == .notion })
        let names = connection.map { MCPServerCatalog.definitions(for: $0, whatsAppBridgePath: "").map(\.serverName) }
        XCTAssertEqual(names, ["galeno-notion"])
    }

    func testItUsesTheClaudePathFoundInStep2() async {
        let mcp = FakeMCP(statuses: ["notion": .connected])
        var receivedPath: String?
        let services = ConnectServices(
            makeMCP: { path in
                receivedPath = path
                return mcp
            }, whatsapp: FakeWhatsApp(), installer: .sandboxed(), fetchRealData: false,
            sleep: SleepLog.holdingSuccess.sleeper)
        let state = WizardState(
            preferredLanguages: ["es"],
            claudeStatus: .found(version: "2.1.277", path: "/opt/homebrew/bin/claude", loggedIn: true),
            connectServices: services)
        state.toggle(.notion)

        state.beginConnecting()

        XCTAssertEqual(receivedPath, "/opt/homebrew/bin/claude")
    }

    // MARK: - El texto protegido de WhatsApp

    /// `AGENTS.md`: no se toca el texto de advertencia sin que Rafa lo apruebe. Esta prueba
    /// compara el español de la app con el de la spec, palabra por palabra.
    func testTheWhatsAppWarningIsTheOneInTheSpecVerbatim() throws {
        let spec = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "docs/03-especificacion-v0.0.1.md")
        let text = String(decoding: try readRepoFile(spec), as: UTF8.self)
        let line = try XCTUnwrap(text.split(separator: "\n").first { $0.contains("Transparencia total") })
        let quoted = try XCTUnwrap(line.split(separator: "\"").dropFirst().first, "la spec ya no cita el texto entre comillas")

        let app = Bundle(for: WizardState.self)
        let bundle = try XCTUnwrap(Bundle(path: try XCTUnwrap(app.path(forResource: "es", ofType: "lproj"))))
        let shown = bundle.localizedString(forKey: "connect.whatsapp.warning.body", value: "⟂", table: nil)

        XCTAssertEqual(shown, String(quoted))
    }

    func testTheWhatsAppWarningDoesNotPromiseSafetyOrOfficialStatus() throws {
        let app = Bundle(for: WizardState.self)
        for language in ["es", "en"] {
            let bundle = try XCTUnwrap(Bundle(path: try XCTUnwrap(app.path(forResource: language, ofType: "lproj"))))
            let text = bundle.localizedString(forKey: "connect.whatsapp.warning.body", value: "⟂", table: nil).lowercased()

            XCTAssertFalse(text.contains("seguro") && !text.contains("no "), language)
            XCTAssertFalse(text.contains("100%"), language)
            // Dice que es no oficial y que hay riesgo: eso es lo que debe decir.
            XCTAssertTrue(text.contains("no oficial") || text.contains("unofficial"), language)
            XCTAssertTrue(text.contains("riesgo") || text.contains("risk"), language)
        }
    }
}
