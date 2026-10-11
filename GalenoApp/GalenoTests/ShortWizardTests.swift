import GalenoCore
import XCTest

@testable import Galeno

/// El wizard corto de «Nuevo agente» (`docs/03` §3b): reutiliza los pasos del completo, pero sin bienvenida ni
/// detección, parte de lo ya conectado y solo conecta lo que falta.
@MainActor
final class ShortWizardTests: XCTestCase {
    private func installation(connected: [Tool], language: Language = .spanish) -> GalenoInstallation {
        var installation = GalenoInstallation(language: language)
        for tool in connected {
            installation.setConnection(
                SharedConnection(
                    tool: tool, status: .connected, oauthClientID: tool == .slack ? "123.456" : nil,
                    // Una conexión de WhatsApp que ya pasó por la advertencia del envío.
                    sendingAccepted: tool == .whatsapp ? true : nil))
        }
        return installation
    }

    private func makeShort(connected: [Tool], language: Language = .spanish) -> WizardState {
        WizardState(
            preferredLanguages: ["en"],
            claudeStatus: .found(version: "2.1.277", path: "/ruta/claude", loggedIn: true),
            startingFrom: installation(connected: connected, language: language))
    }

    func testItStartsAtTheAgentStepWithTheInstallationLanguageAndConnections() {
        let state = makeShort(connected: [.whatsapp, .slack], language: .spanish)
        XCTAssertEqual(state.mode, .short)
        XCTAssertEqual(state.step, .role)
        XCTAssertEqual(state.language, .spanish, "el idioma no se vuelve a preguntar")
        XCTAssertEqual(state.selectedTools, [.whatsapp, .slack])
        XCTAssertTrue(state.connections.allSatisfy { $0.status == .connected })
        XCTAssertEqual(state.connection(for: .slack)?.oauthClientID, "123.456", "el client_id compartido viaja")
        XCTAssertFalse(state.hasToConnect)
    }

    /// Una instalación de antes del envío, o una vinculación que no pasó por la advertencia nueva, trae WhatsApp
    /// sin aceptar: el agente nuevo no puede salir en solo lectura sin que nadie lo diga.
    func testWhatsAppLinkedWithoutAcceptingSendingComesBackToBeConnectedWithItsWarning() {
        var old = GalenoInstallation(language: .spanish)
        old.setConnection(SharedConnection(tool: .whatsapp, status: .connected))  // sendingAccepted == nil
        old.setConnection(SharedConnection(tool: .notion, status: .connected))
        let state = WizardState(
            preferredLanguages: ["en"],
            claudeStatus: .found(version: "2.1.277", path: "/ruta/claude", loggedIn: true),
            startingFrom: old)
        XCTAssertEqual(state.connection(for: .whatsapp)?.status, .selected)
        XCTAssertEqual(state.connection(for: .notion)?.status, .connected, "lo demás sigue conectado")
        XCTAssertEqual(state.toConnect, [.whatsapp])
        XCTAssertTrue(state.stepOrder.contains(.connect), "trae el paso Conectar, con la advertencia")

        // Y aceptarlo sigue siendo por el camino de siempre: terminar la conexión en el asistente.
        state.setConnectionStatus(.whatsapp, .connected)
        XCTAssertEqual(state.connection(for: .whatsapp)?.sendingAccepted, true)
        XCTAssertFalse(state.hasToConnect)
    }

    func testWhatsAppThatAlreadyAcceptedSendingStaysConnected() {
        let state = makeShort(connected: [.whatsapp])
        XCTAssertEqual(state.connection(for: .whatsapp)?.status, .connected)
        XCTAssertEqual(state.connection(for: .whatsapp)?.sendingAccepted, true)
        XCTAssertTrue(state.toConnect.isEmpty)
    }

    func testThereIsNoWelcomeNorDetectionAndNothingToConnectSkipsThatStep() {
        let state = makeShort(connected: [.whatsapp])
        XCTAssertEqual(state.stepOrder, [.role, .agent, .context, .tools, .skills, .rules, .review, .generating, .done])
        XCTAssertEqual(state.stepCount, 6, "rol, nombre, herramientas, skills, reglas y creación")
        XCTAssertEqual(state.stepNumber, 1)
        XCTAssertTrue(state.isFirstStep)
        XCTAssertEqual(state.progress, 1.0 / 6.0, accuracy: 0.0001)
    }

    func testThereIsNoBackAtTheFirstStep() {
        let state = makeShort(connected: [.whatsapp])
        XCTAssertFalse(state.canGoBack)
        state.back()
        XCTAssertEqual(state.step, .role)
    }

    func testWhenEverythingIsAlreadyConnectedItGoesFromToolsStraightToSkills() {
        let state = makeShort(connected: [.whatsapp, .notion])
        state.next()
        state.agentName = "Aurora"
        state.next()
        XCTAssertEqual(state.step, .context)
        state.next()
        XCTAssertEqual(state.step, .tools)
        state.next()
        XCTAssertEqual(state.step, .skills, "no hay nada que conectar")
        state.back()
        XCTAssertEqual(state.step, .tools, "y al volver tampoco pasa por conectar")
    }

    /// Una herramienta que todavía no está conectada trae el paso «Conectar», y solo con ella.
    func testANewToolBringsTheConnectStepWithOnlyThatTool() {
        let state = makeShort(connected: [.whatsapp])
        state.toggle(.notion)
        XCTAssertEqual(state.toConnect, [.notion])
        XCTAssertTrue(state.hasToConnect)
        XCTAssertEqual(state.stepOrder, [.role, .agent, .context, .tools, .connect, .skills, .rules, .review, .generating, .done])

        state.next()
        state.agentName = "Aurora"
        state.next()  // contexto
        state.next()  // herramientas
        state.next()
        XCTAssertEqual(state.step, .connect)
    }

    /// Mientras se conecta, la herramienta pasa a conectada: el paso no puede desaparecer a mitad de camino.
    func testTheConnectStepStaysOnceYouAreInIt() {
        let state = makeShort(connected: [.whatsapp])
        state.toggle(.notion)
        state.next()
        state.agentName = "Aurora"
        state.next()  // contexto
        state.next()  // herramientas
        state.next()
        XCTAssertEqual(state.step, .connect)

        state.setConnectionStatus(.notion, .connected)
        XCTAssertFalse(state.hasToConnect)
        XCTAssertEqual(state.stepOrder, [.role, .agent, .context, .tools, .connect, .skills, .rules, .review, .generating, .done])
        XCTAssertEqual(state.stepNumber, 3, "conectar sigue siendo el paso de las herramientas")
    }

    func testUncheckingAConnectedToolOnlyLeavesItOutOfThisAgent() {
        let state = makeShort(connected: [.whatsapp, .notion])
        state.toggle(.notion)
        XCTAssertEqual(state.selectedTools, [.whatsapp])
        XCTAssertFalse(state.hasToConnect)
    }

    func testTheMinutesCountOnlyWhatIsLeftToConnect() {
        let state = makeShort(connected: [.whatsapp, .slack])
        XCTAssertEqual(state.estimatedSetupMinutes, 1, "nada por conectar: el mínimo")
        state.toggle(.notion)
        XCTAssertEqual(state.estimatedSetupMinutes, ToolEstimate.minutes(for: [.notion]))
    }

    func testTheShortWizardNeverWritesADraft() {
        let store = MemoryDraftStore()
        let state = WizardState(
            preferredLanguages: ["es"],
            claudeStatus: .found(version: "2.1.277", path: "/ruta/claude", loggedIn: true),
            draftStore: store, startingFrom: installation(connected: [.whatsapp]))
        state.agentName = "Aurora"
        state.saveDraft()
        XCTAssertNil(store.draft)
        XCTAssertNil(state.pendingDraft)
    }

    /// El completo: siete pasos a la vista, con el rol primero y la cuenta de Claude después.
    func testTheFullWizardShowsSevenSteps() {
        let state = WizardState(preferredLanguages: ["es"])
        XCTAssertEqual(state.mode, .full)
        XCTAssertEqual(state.stepOrder, WizardStep.allCases)
        XCTAssertEqual(state.stepCount, 7)
        XCTAssertEqual(state.stepNumber, 1)
    }
}
