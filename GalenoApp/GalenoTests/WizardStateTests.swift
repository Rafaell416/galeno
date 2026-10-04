import GalenoCore
import XCTest

@testable import Galeno

@MainActor
final class WizardStateTests: XCTestCase {
    private func makeState(_ languages: [String] = ["es-CO"]) -> WizardState {
        WizardState(preferredLanguages: languages)
    }

    /// Un wizard con lo mínimo para que "Siguiente" no se bloquee en ningún paso:
    /// Claude Code encontrado, un nombre y una herramienta.
    private func makeReadyState() -> WizardState {
        let state = WizardState(
            preferredLanguages: ["es-CO"],
            claudeStatus: .found(version: "2.1.277", path: "/ruta/claude", loggedIn: true),
            connectServices: ConnectServices(
                makeMCP: { _ in FakeMCP() }, whatsapp: FakeWhatsApp(), installer: .sandboxed(),
                fetchRealData: false, sleep: SleepLog().sleeper))
        state.agentName = "Aurora"
        state.toggle(.notion)
        return state
    }

    /// Un paso adelante. El paso 5 es un sub-wizard que no deja avanzar hasta que cada
    /// conexión se resuelve: aquí se salta cada una para poder seguir.
    private func stepForward(_ state: WizardState) {
        if state.step == .connect {
            state.beginConnecting()
            for _ in 0..<20 where state.connectFlow?.isFinished != true { state.connectFlow?.skip() }
        }
        if state.step == .generating {
            // La pantalla 9 genera sola al aparecer y pasa a «Listo» al terminar: aquí se hace a mano.
            state.beginGeneration()
            let deadline = Date().addingTimeInterval(5)
            while state.generation?.phase == .running, Date() < deadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            }
            state.finishGeneration()
            return
        }
        state.next()
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

    /// Toda cadena del catálogo está en español y en inglés, y compilada en los dos
    /// `.lproj`. Recorre el catálogo entero, así que una clave nueva sin traducir
    /// rompe esta prueba sin que haya que acordarse de añadirla a una lista.
    func testEveryCatalogStringIsTranslatedAndCompiledInBothLanguages() throws {
        let catalogURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Galeno/Localizable.xcstrings")
        let catalog = try JSONSerialization.jsonObject(with: readRepoFile(catalogURL)) as? [String: Any]
        let strings = try XCTUnwrap(catalog?["strings"] as? [String: [String: Any]])
        XCTAssertGreaterThan(strings.count, 50)

        let app = Bundle(for: WizardState.self)
        for language in ["es", "en"] {
            let bundle = try XCTUnwrap(
                Bundle(path: try XCTUnwrap(app.path(forResource: language, ofType: "lproj"))))
            for (key, entry) in strings {
                // Las claves que Xcode extrae solas (el nombre de la app) no se traducen.
                guard let localizations = entry["localizations"] as? [String: Any],
                    let localization = localizations[language] as? [String: Any]
                else { continue }

                if let plural = (localization["variations"] as? [String: Any])?["plural"] as? [String: Any] {
                    // Un plural lleva una versión por categoría ("one", "other"…), todas con texto.
                    XCTAssertNotNil(plural["other"], "\(key) no tiene 'other' en \(language)")
                    for (category, form) in plural {
                        let value = ((form as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String
                        XCTAssertFalse(value?.isEmpty ?? true, "\(key) [\(category)] está vacío en \(language)")
                    }
                    continue  // las claves de plural se compilan a un .stringsdict, no al .strings
                }

                let value = (localization["stringUnit"] as? [String: Any])?["value"] as? String
                XCTAssertFalse(value?.isEmpty ?? true, "\(key) no tiene texto en \(language)")

                XCTAssertNotEqual(
                    bundle.localizedString(forKey: key, value: "⟂", table: nil), "⟂",
                    "\(key) no está compilada en \(language)")
            }
        }
    }

    /// Cada idioma que ofrece el selector tiene su `.lproj`: si se añade un
    /// `Language` en el motor sin traducir la app, esta prueba lo avisa.
    func testEveryLanguageOfTheEngineHasALocalizationInTheApp() {
        let app = Bundle(for: WizardState.self)
        for language in Language.allCases {
            XCTAssertNotNil(
                app.path(forResource: language.rawValue, ofType: "lproj"),
                "la app no tiene \(language.rawValue).lproj")
        }
    }

    /// Los textos de dopamina los escribe Rafa; mientras tanto deben seguir
    /// marcados para que no se cuelen a una versión.
    func testTheDopamineSlotsAreStillMarkedTODO() throws {
        let app = Bundle(for: WizardState.self)
        let bundle = try XCTUnwrap(
            Bundle(path: try XCTUnwrap(app.path(forResource: "es", ofType: "lproj"))))
        for key in [
            "dopamine.welcome", "dopamine.detection", "dopamine.agent", "dopamine.tools",
            "dopamine.connect.first", "dopamine.connect.half", "dopamine.connect.last",
        ] {
            let text = bundle.localizedString(forKey: key, value: "⟂", table: nil)
            XCTAssertTrue(text.hasPrefix("TODO(dopamina)"), "\(key): \(text)")
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
        let state = makeReadyState()

        for expected in WizardStep.allCases.dropFirst() {
            stepForward(state)
            XCTAssertEqual(state.step, expected)
        }
        XCTAssertTrue(state.isLastStep)

        // Desde «Listo» se vuelve a las reglas, no a «Generando» (que no se puede deshacer):
        // al avanzar otra vez se regenera el mismo agente.
        state.back()
        XCTAssertEqual(state.step, .rules)
    }

    func testNextStopsAtTheLastStep() {
        let state = makeReadyState()
        for _ in 0..<30 { stepForward(state) }

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
        let state = makeReadyState()
        for _ in 0..<20 where state.step != .generating { stepForward(state) }
        XCTAssertEqual(state.step, .generating)

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
        let state = makeReadyState()
        XCTAssertEqual(state.progress, 0.1, accuracy: 0.0001)

        var previous = state.progress
        for _ in 0..<20 where !state.isLastStep {
            stepForward(state)
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
