import GalenoCore
import XCTest

@testable import Galeno

@MainActor
final class WizardStateTests: XCTestCase {
    private func makeState(_ languages: [String] = ["es-CO"]) -> WizardState {
        WizardState(preferredLanguages: languages)
    }

    // MARK: - Los pasos

    func testThereAreTenStepsInTheOrderOfTheSpec() {
        XCTAssertEqual(
            WizardStep.allCases,
            [
                .welcome, .detection, .agent, .tools, .connect,
                .sources, .skills, .rules, .generating, .done,
            ])
        XCTAssertEqual(WizardStep.allCases.map(\.number), Array(1...10))
    }

    /// Cada título y cada línea de resumen existen en español y en inglés: una
    /// clave que falta se vería en pantalla como la clave cruda.
    func testEveryStepHasATitleAndASummaryInBothLanguages() throws {
        let app = Bundle(for: WizardState.self)

        for language in ["es", "en"] {
            let path = try XCTUnwrap(
                app.path(forResource: language, ofType: "lproj"), "falta el idioma \(language)")
            let bundle = try XCTUnwrap(Bundle(path: path))

            for step in WizardStep.allCases {
                for key in [step.titleKey, step.summaryKey] {
                    let text = bundle.localizedString(forKey: key, value: "⟂", table: nil)
                    XCTAssertNotEqual(text, "⟂", "\(key) no está en \(language)")
                    XCTAssertFalse(text.isEmpty, "\(key) está vacío en \(language)")
                }
            }
        }
    }

    func testTheNavigationStringsExistInBothLanguages() throws {
        let app = Bundle(for: WizardState.self)
        for language in ["es", "en"] {
            let bundle = try XCTUnwrap(
                Bundle(path: try XCTUnwrap(app.path(forResource: language, ofType: "lproj"))))
            for key in [
                "wizard.back", "wizard.next", "wizard.finish", "wizard.progress.label",
                "wizard.placeholder", "wizard.progress.step %lld %lld",
            ] {
                XCTAssertNotEqual(
                    bundle.localizedString(forKey: key, value: "⟂", table: nil), "⟂",
                    "\(key) no está en \(language)")
            }
        }
    }

    // MARK: - La navegación

    func testStartsAtTheWelcomeStep() {
        let state = makeState()
        XCTAssertEqual(state.step, .welcome)
        XCTAssertTrue(state.isFirstStep)
        XCTAssertFalse(state.isLastStep)
    }

    func testNextWalksEveryStepInOrderAndBackWalksThemBack() {
        let state = makeState()

        for expected in WizardStep.allCases.dropFirst() {
            state.next()
            XCTAssertEqual(state.step, expected)
        }
        XCTAssertTrue(state.isLastStep)

        // Hasta "Generando" se puede volver; ahí se corta (ver el siguiente test).
        state.back()
        XCTAssertEqual(state.step, .generating)
    }

    func testNextStopsAtTheLastStep() {
        let state = makeState()
        for _ in 0..<30 { state.next() }

        XCTAssertEqual(state.step, .done)
        XCTAssertFalse(state.canGoForward)
    }

    func testBackStopsAtTheFirstStep() {
        let state = makeState()
        XCTAssertFalse(state.canGoBack)

        state.back()

        XCTAssertEqual(state.step, .welcome)
    }

    func testThereIsNoGoingBackFromGenerating() {
        let state = makeState()
        while state.step != .generating { state.next() }

        XCTAssertFalse(state.canGoBack)
        state.back()
        XCTAssertEqual(state.step, .generating)
    }

    func testEveryOtherStepAllowsGoingBack() {
        for step in WizardStep.allCases where step != .welcome && step != .generating {
            XCTAssertTrue(step.allowsGoingBack, "\(step)")
        }
    }

    func testProgressGoesFromOneTenthToOne() {
        let state = makeState()
        XCTAssertEqual(state.progress, 0.1, accuracy: 0.0001)

        var previous = state.progress
        while state.canGoForward {
            state.next()
            XCTAssertGreaterThan(state.progress, previous)
            previous = state.progress
        }
        XCTAssertEqual(state.progress, 1.0, accuracy: 0.0001)
    }

    // MARK: - El idioma

    func testTheLanguageFollowsTheMac() {
        XCTAssertEqual(makeState(["es-CO"]).language, .spanish)
        XCTAssertEqual(makeState(["es"]).language, .spanish)
        XCTAssertEqual(makeState(["es_419", "en-US"]).language, .spanish)
        XCTAssertEqual(makeState(["en-US", "es-CO"]).language, .english)
        XCTAssertEqual(makeState(["fr-FR"]).language, .english)
        XCTAssertEqual(makeState([]).language, .english)
    }

    func testAnEnglishLanguageTagIsNotMistakenForSpanish() {
        // "es" es un prefijo de otras etiquetas que no son español.
        XCTAssertEqual(makeState(["est-EE"]).language, .english)
    }

    // MARK: - El resultado

    func testMakeConfigCarriesWhatTheWizardCaptured() {
        let state = makeState(["en-US"])
        state.agentName = "  Vesalius \n"
        state.projectDescription = "\n Scheduling app for Acme's clinic.  "
        state.connections = [ToolConnection(tool: .notion, status: .connected, sources: .everything)]
        state.skills = [SelectedSkill(id: "prd", source: .galeno)]

        let config = state.makeConfig()

        XCTAssertEqual(config.agentName, "Vesalius")
        XCTAssertEqual(config.projectDescription, "Scheduling app for Acme's clinic.")
        XCTAssertEqual(config.language, .english)
        XCTAssertEqual(config.role, .productManager)
        XCTAssertEqual(config.connections.map(\.tool), [.notion])
        XCTAssertEqual(config.skills, [SelectedSkill(id: "prd", source: .galeno)])
        XCTAssertEqual(config.sendingRules, .default)
        XCTAssertEqual(config.schemaVersion, AgentConfig.currentSchemaVersion)
    }

    /// El `AgentConfig` que arma el wizard lo acepta el motor tal cual.
    func testTheEngineAcceptsTheConfigTheWizardMakes() throws {
        let state = makeState()
        state.agentName = "Aurora"
        state.projectDescription = "App de citas para la clínica del Cliente A."
        state.connections = [ToolConnection(tool: .notion, status: .connected, sources: .everything)]

        let folder = FileManager.default.temporaryDirectory
            .appending(path: "galeno-app-tests/\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }

        let result = try ConfigGenerator().generate(
            state.makeConfig(),
            into: folder,
            options: ConfigGenerator.Options(
                skillsDirectory: folder.appending(path: "sin-skills"),
                whatsAppBridgePath: "/ruta/de/prueba/galeno-whatsapp"))

        XCTAssertTrue(result.writtenFiles.contains("AGENTS.md"))
        XCTAssertTrue(result.writtenFiles.contains("memoria/proyecto.md"))
    }

    func testAnEmptyNameIsRejectedByTheEngineNotSilentlyAccepted() {
        let state = makeState()
        state.agentName = "   "

        XCTAssertThrowsError(
            try ConfigGenerator().generate(
                state.makeConfig(),
                into: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString),
                options: ConfigGenerator.Options(
                    skillsDirectory: FileManager.default.temporaryDirectory,
                    whatsAppBridgePath: "/x")))
    }
}
