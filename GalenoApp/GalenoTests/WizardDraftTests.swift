import GalenoCore
import XCTest

@testable import Galeno

/// «Reanudar donde quedaste»: el borrador se guarda sin credenciales, se ofrece al abrir y se borra al
/// terminar. Todas las pruebas usan un almacén en memoria: ninguna toca el disco real.
@MainActor
final class WizardDraftTests: XCTestCase {
    private func makeState(_ store: MemoryDraftStore) -> WizardState {
        let state = WizardState(
            preferredLanguages: ["es"],
            claudeStatus: .found(version: "2.1.277", path: "/ruta/claude", loggedIn: true),
            draftStore: store)
        state.agentName = "Hera"
        return state
    }

    func testNothingIsSavedBeforeAnythingIsChosen() {
        let store = MemoryDraftStore()
        let state = WizardState(preferredLanguages: ["es"], draftStore: store)
        state.saveDraft()
        XCTAssertNil(store.draft)
    }

    func testTheDraftHoldsTheChoicesButNoSecrets() throws {
        let store = MemoryDraftStore()
        let state = makeState(store)
        state.toggle(.notion)
        state.toggle(.slack)
        state.setOAuthClientID(.slack, "1234567890123.1234567890123")
        for _ in 0..<5 { state.next() }  // hasta «Conectar»
        state.saveDraft()

        let draft = try XCTUnwrap(store.draft)
        XCTAssertEqual(draft.step, WizardStep.connect.rawValue)
        XCTAssertEqual(draft.agentName, "Hera")
        XCTAssertEqual(Set(draft.connections.map(\.tool)), [.notion, .slack])

        let json = String(decoding: try JSONEncoder().encode(draft), as: UTF8.self).lowercased()
        for forbidden in ["secret", "token", "password", "contraseña"] {
            XCTAssertFalse(json.contains(forbidden), "el borrador no debe llevar «\(forbidden)»")
        }
    }

    func testAFreshLaunchOffersToResumeAndContinueRestoresEverything() throws {
        let store = MemoryDraftStore()
        let first = makeState(store)
        first.projectDescription = "App de citas"
        first.toggle(.notion)
        first.setConnectionStatus(.notion, .connected)
        for _ in 0..<5 { first.next() }  // hasta «Conectar»
        first.saveDraft()

        let second = WizardState(preferredLanguages: ["en"], draftStore: store)
        let pending = try XCTUnwrap(second.pendingDraft)
        XCTAssertEqual(pending.agentName, "Hera")
        XCTAssertEqual(second.language, .spanish, "la pantalla de reanudar habla el idioma de la sesión")
        XCTAssertEqual(second.step, .role, "hasta decidir, no se mueve nada")

        second.resumeDraft()

        XCTAssertNil(second.pendingDraft)
        XCTAssertEqual(second.step, .connect)
        XCTAssertEqual(second.agentName, "Hera")
        XCTAssertEqual(second.projectDescription, "App de citas")
        XCTAssertEqual(second.connection(for: .notion)?.status, .connected)
        XCTAssertEqual(second.furthestStep, .connect)
    }

    func testStartingOverClearsTheDraft() {
        let store = MemoryDraftStore()
        let first = makeState(store)
        first.toggle(.notion)
        first.next(); first.next()
        first.saveDraft()
        XCTAssertNotNil(store.draft)

        let second = WizardState(preferredLanguages: ["es"], draftStore: store)
        second.discardDraft()

        XCTAssertNil(second.pendingDraft)
        XCTAssertNil(store.draft)
        XCTAssertEqual(second.step, .role)
        XCTAssertEqual(second.agentName, "")
    }

    func testWhileTheUserDecidesTheOldDraftIsNotOverwritten() throws {
        let store = MemoryDraftStore()
        let first = makeState(store)
        first.toggle(.notion)
        first.next(); first.next(); first.next()
        first.saveDraft()
        let saved = try XCTUnwrap(store.draft)

        let second = WizardState(preferredLanguages: ["es"], draftStore: store)
        second.saveDraft()

        XCTAssertEqual(store.draft, saved)
    }

    func testAnInterruptedWritingResumesAtTheReview() throws {
        let store = MemoryDraftStore()
        let state = makeState(store)
        state.toggle(.notion)
        state.setConnectionStatus(.notion, .connected)
        for _ in 0..<8 where state.step != .generating { state.next() }
        // Llega hasta «Escribiendo» como pueda; si no, el borrador se queda en el paso más lejano.
        state.saveDraft()
        let draft = try XCTUnwrap(store.draft)
        XCTAssertLessThanOrEqual(draft.step, WizardStep.review.rawValue, "nunca se reanuda dentro de «Escribiendo»")
    }

    func testGoToOnlyReachesVisitedSteps() {
        let state = makeState(MemoryDraftStore())
        state.toggle(.notion)
        for _ in 0..<3 { state.next() }  // herramientas
        XCTAssertEqual(state.step, .tools)

        state.goTo(.skills)
        XCTAssertEqual(state.step, .tools, "aún no ha llegado a «Skills»")

        state.goTo(.detection)
        XCTAssertEqual(state.step, .detection)

        state.goTo(.tools)
        XCTAssertEqual(state.step, .tools, "puede volver hasta donde ya había llegado")
    }
}
