import GalenoCore
import XCTest

@testable import Galeno

/// Lo que cambió con el rediseño B1 en el recorrido: sin la pantalla «El foco», con «Revisión»
/// antes de escribir y con el tiempo restante en la cabecera.
@MainActor
final class RedesignFlowTests: XCTestCase {
    private func makeState() -> WizardState {
        let state = WizardState(
            preferredLanguages: ["es"],
            claudeStatus: .found(version: "2.1.277", path: "/ruta/claude", loggedIn: true))
        state.agentName = "Hera"
        return state
    }

    func testTheReviewStepComesRightBeforeWriting() {
        let steps = WizardStep.allCases
        XCTAssertEqual(steps.firstIndex(of: .review), steps.firstIndex(of: .generating).map { $0 - 1 })
        XCTAssertEqual(steps.count, 10)
    }

    func testJumpOnlyGoesBackwards() {
        let state = makeState()
        state.toggle(.notion)
        state.next()  // detección
        state.next()  // agente
        state.next()  // herramientas
        XCTAssertEqual(state.step, .tools)

        state.jump(to: .review)
        XCTAssertEqual(state.step, .tools, "«Cambiar» nunca salta hacia adelante")

        state.jump(to: .detection)
        XCTAssertEqual(state.step, .detection)
    }

    /// Sin pantalla para elegir el foco, lo conectado se lee entero: el `AGENTS.md` no debe decir
    /// que no se eligió ninguna fuente.
    func testConnectedToolsReadEverythingInTheConfig() throws {
        let state = makeState()
        state.toggle(.notion)
        state.toggle(.jira)
        state.setConnectionStatus(.notion, .connected)

        let config = state.makeConfig()
        let notion = try XCTUnwrap(config.connections.first { $0.tool == .notion })
        let jira = try XCTUnwrap(config.connections.first { $0.tool == .jira })
        XCTAssertTrue(notion.sources.readsEverything)
        XCTAssertFalse(jira.sources.readsEverything, "lo que no se conectó no cambia")
    }

    func testTheTimeLeftShrinksAsTheWizardAdvances() {
        let state = makeState()
        state.toggle(.whatsapp)  // 3 min
        state.toggle(.notion)  // 1 min
        XCTAssertEqual(state.estimatedMinutesLeft, 4 + 9, "lo que falta conectar más un minuto por paso restante")

        state.next()
        XCTAssertEqual(state.estimatedMinutesLeft, 4 + 8)
    }

    /// Tras un éxito, «Continuar» pasa a la siguiente sin esperar a que la pantalla avance sola.
    func testContinueAfterASuccessMovesOnRightAway() async {
        let frozen: ConnectFlow.Sleeper = { _ in try? await Task.sleep(for: .seconds(120)) }
        let flow = ConnectFlow(
            tools: [.notion, .jira], statuses: [:], mcp: FakeMCP(), whatsapp: FakeWhatsApp(),
            slack: FakeSlackSetup(), agentName: { "Hera" }, fetchRealData: false,
            timing: ConnectFlow.Timing(), sleep: frozen, onStatus: { _, _ in }, onClientID: { _, _ in })
        defer { flow.cancelAll() }

        flow.continueFromSuccess()
        XCTAssertEqual(flow.screen, .connection(.notion), "sin éxito no hace nada")

        flow.connect()
        let succeeded = await waitUntil {
            if case .succeeded = flow.phase { return true }
            return false
        }
        XCTAssertTrue(succeeded)

        flow.continueFromSuccess()
        XCTAssertEqual(flow.screen, .connection(.jira))
    }
}
