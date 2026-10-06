import GalenoCore
import XCTest

@testable import Galeno

private actor InstantLister: SourceListing {
    func list(_ connection: ToolConnection) async -> SourceListResult {
        .loaded([Source(id: "a", name: "A", kind: .channel), Source(id: "b", name: "B", kind: .channel)], isPartial: false)
    }
}

/// La lógica de las pantallas 6 a 10, con todo en carpetas temporales.
@MainActor
final class WizardScreens6to10Tests: XCTestCase {
    /// Ninguna app arrancó antes del principio de los tiempos: con un agente más viejo que la app de
    /// Claude que está abierta, «Abrir en la app de Claude» no la reinicia.
    func testClaudeIsNeverRestartedForAnAgentOlderThanTheRunningApp() {
        XCTAssertFalse(SystemAgentOpener().claudeAppNeedsRestart(since: .distantPast))
    }

    private var sandbox: URL!

    override func setUp() async throws {
        sandbox = FileManager.default.temporaryDirectory
            .appending(path: "galeno-screens/\(UUID().uuidString)", directoryHint: .isDirectory)
        try writeSkills()
    }

    override func tearDown() async throws {
        if let sandbox { try? FileManager.default.removeItem(at: sandbox) }
    }

    private var skillsDirectory: URL { sandbox.appending(path: "skills", directoryHint: .isDirectory) }

    /// Un catálogo chico y las carpetas de las skills que dice tener.
    private func writeSkills() throws {
        func skill(_ id: String, _ group: String, needs: [String] = []) -> String {
            let needsJSON = needs.map { "\"\($0)\"" }.joined(separator: ",")
            return """
                {"id":"\(id)","group":"\(group)","name":{"es":"\(id)","en":"\(id)"},"summary":{"es":"s","en":"s"},
                 "writes":["notion"],"needsAny":[\(needsJSON)]}
                """
        }
        let catalog = """
            {"schemaVersion":1,"groups":[{"id":"documents","name":{"es":"G","en":"G"}}],
             "galeno":[\(skill("prd", "documents")),\(skill("acta", "documents", needs: ["fireflies"])),\(skill("informe-slack", "documents", needs: ["slack"]))],
             "curated":[
               {"id":"c-ready","name":{"es":"C","en":"C"},"summary":{"es":"s","en":"s"},"author":"someone","repository":"https://github.com/someone/x","path":"skills/c","license":"MIT","available":true},
               {"id":"c-soon","name":{"es":"C","en":"C"},"summary":{"es":"s","en":"s"},"author":"someone","repository":"https://github.com/someone/x","path":"skills/d","license":"MIT","available":false}]}
            """
        try FileManager.default.createDirectory(at: skillsDirectory, withIntermediateDirectories: true)
        try catalog.write(to: skillsDirectory.appending(path: "catalog.json"), atomically: true, encoding: .utf8)
        for (kind, id) in [("galeno", "prd"), ("galeno", "acta"), ("galeno", "informe-slack"), ("curated", "c-ready")] {
            let folder = skillsDirectory.appending(path: "\(kind)/\(id)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try "---\nname: \(id)\ndescription: \"x\"\n---\nbody\n".write(
                to: folder.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
        }
    }

    private func makeState(skills: URL? = nil, tools: [Tool] = [.slack, .notion]) -> WizardState {
        let directory = skills ?? skillsDirectory
        let services = ConnectServices(
            makeMCP: { _ in FakeMCP() }, whatsapp: FakeWhatsApp(), slack: FakeSlackSetup(),
            makeLister: { _ in InstantLister() }, installer: .sandboxed(skills: directory),
            skillsDirectory: directory, fetchRealData: false, sleep: SleepLog().sleeper)
        let state = WizardState(
            preferredLanguages: ["es-CO"],
            claudeStatus: .found(version: "2.1.277", path: "/ruta/claude", loggedIn: true),
            connectServices: services)
        state.agentName = "Hera"
        for tool in tools {
            state.toggle(tool)
            state.setConnectionStatus(tool, .connected)
        }
        return state
    }

    // MARK: Pantalla 6

    func testToolsWithNothingToChooseReadEverythingWithoutAsking() {
        let state = makeState(tools: [.fireflies, .slack])
        state.beginSources()
        defer { state.sourcesFlow?.cancelAll() }

        XCTAssertEqual(state.sourceSelection(for: .fireflies), .everything)
        XCTAssertEqual(state.sourceSelection(for: .slack), .nothing, "lo que sí se elige no se decide solo")
    }

    func testBeginningTheSourcesStepTwiceKeepsTheSameLists() async {
        let state = makeState()
        state.beginSources()
        let first = state.sourcesFlow
        state.beginSources()
        XCTAssertTrue(first === state.sourcesFlow)
        _ = await waitUntil { state.sourcesFlow?.sources(of: .slack).count == 2 }

        state.setConnectionStatus(.notion, .skipped)
        state.beginSources()
        XCTAssertFalse(first === state.sourcesFlow, "si cambian las conexiones, se piden de nuevo")
        state.sourcesFlow?.cancelAll()
    }

    func testChoosingSourcesMakesThemTheFocusAndUnchoosingEverythingGoesBackToNone() {
        let state = makeState()
        let a = Source(id: "a", name: "A", kind: .channel), b = Source(id: "b", name: "B", kind: .channel)

        state.toggleSource(a, in: .slack)
        state.toggleSource(b, in: .slack)
        XCTAssertEqual(state.sourceSelection(for: .slack), .only([a, b]))
        XCTAssertTrue(state.isSourceSelected(a, in: .slack))

        state.toggleSource(a, in: .slack)
        state.toggleSource(b, in: .slack)
        XCTAssertEqual(state.sourceSelection(for: .slack), .nothing)
        XCTAssertFalse(state.isSourceSelected(a, in: .slack))
    }

    func testReadingEverythingReplacesTheChosenAndChoosingOneLeavesIt() {
        let state = makeState()
        let a = Source(id: "a", name: "A", kind: .channel)
        state.toggleSource(a, in: .slack)

        state.setReadsEverything(true, for: .slack)
        XCTAssertEqual(state.sourceSelection(for: .slack), .everything)
        XCTAssertFalse(state.isSourceSelected(a, in: .slack))

        state.toggleSource(a, in: .slack)
        XCTAssertEqual(state.sourceSelection(for: .slack), .only([a]))
        state.setReadsEverything(false, for: .slack)
        XCTAssertEqual(state.sourceSelection(for: .slack), .nothing)
    }

    func testChoosingInOneToolDoesNotTouchAnother() {
        let state = makeState()
        state.toggleSource(Source(id: "a", name: "A", kind: .channel), in: .slack)
        XCTAssertEqual(state.sourceSelection(for: .notion), .nothing)
    }

    // MARK: Pantalla 7

    func testOurSkillsComeTickedAndTheUsersChoiceSurvivesComingBack() {
        let state = makeState()
        state.loadSkillCatalog()
        XCTAssertEqual(Set(state.skills.map(\.id)), ["prd", "acta", "informe-slack"])
        XCTAssertTrue(state.skills.allSatisfy { $0.source == .galeno })

        state.toggleSkill("acta", source: .galeno)
        state.loadSkillCatalog()  // vuelve a la pantalla

        XCTAssertFalse(state.isSkillSelected("acta", source: .galeno), "no se vuelve a marcar sola")
        XCTAssertEqual(state.skills.count, 2)
    }

    /// Marcar una curada sin contenido haría fallar la generación: no se deja.
    func testACuratedSkillWithoutContentCannotBeTicked() {
        let state = makeState()
        state.loadSkillCatalog()

        state.toggleSkill("c-soon", source: .curated)
        XCTAssertFalse(state.isSkillSelected("c-soon", source: .curated))
        state.toggleSkill("c-ready", source: .curated)
        XCTAssertTrue(state.isSkillSelected("c-ready", source: .curated))
        state.toggleSkill("c-ready", source: .curated)
        XCTAssertFalse(state.isSkillSelected("c-ready", source: .curated))
    }

    func testAMissingSkillsFolderIsReportedAndCanBeRetried() throws {
        let missing = sandbox.appending(path: "no-hay", directoryHint: .isDirectory)
        let state = makeState(skills: missing)
        state.loadSkillCatalog()
        guard case .failed = state.skillCatalog else { return XCTFail("\(state.skillCatalog)") }
        XCTAssertTrue(state.skills.isEmpty)

        try FileManager.default.copyItem(at: skillsDirectory, to: missing)
        state.loadSkillCatalog()
        guard case .loaded = state.skillCatalog else { return XCTFail("\(state.skillCatalog)") }
    }

    // MARK: Pantalla 8

    func testOnlyTheWritesOfConnectedToolsAreConfigurable() {
        XCTAssertEqual(makeState(tools: [.slack]).configurableWrites, [])
        XCTAssertEqual(makeState(tools: [.notion, .jira]).configurableWrites, [.notion, .jira])
        XCTAssertEqual(makeState(tools: [.googleWorkspace]).configurableWrites, [.googleDocs, .googleSheets])
    }

    func testExternalSendingToolsAreListedAndCannotBeConfigured() {
        let state = makeState(tools: [.slack, .gmail, .whatsapp, .notion])
        XCTAssertEqual(state.externalSendTools, [.slack, .gmail])
        // El tipo no tiene forma de expresar «enviar sin preguntar».
        for send in ExternalSend.allCases { XCTAssertEqual(state.sendingRules.policy(for: send), .ask) }
    }

    func testRulesStartPermissiveInsideTheUsersToolsAndCanBeChanged() {
        let state = makeState(tools: [.notion])
        XCTAssertEqual(state.policy(for: .notion), .allow)

        state.setPolicy(.ask, for: .notion)

        XCTAssertEqual(state.policy(for: .notion), .ask)
        XCTAssertEqual(state.makeConfig().sendingRules.policy(for: .notion), .ask)
    }

    // MARK: Pantallas 9 y 10

    private func stepForward(_ state: WizardState) {
        if state.step == .connect {
            state.beginConnecting()
            for _ in 0..<20 where state.connectFlow?.isFinished != true { state.connectFlow?.skip() }
        }
        state.next()
    }

    private func walkToGenerating(_ state: WizardState) {
        for _ in 0..<20 where state.step != .generating { stepForward(state) }
    }

    private func generate(_ state: WizardState) async -> Bool {
        state.beginGeneration()
        return await waitUntil(timeout: 10) { state.generation?.phase != .running }
    }

    func testContextTheUserBroughtLandsInTheAgentsMemoryFolder() async throws {
        let state = makeState()
        state.loadSkillCatalog()
        state.setOAuthClientID(.slack, "1234567890123.1234567890123")
        XCTAssertNil(state.addContext(ContextFile(title: "Resumen.md", text: "Ana lleva diseño.")))
        walkToGenerating(state)
        let done = await generate(state)
        XCTAssertTrue(done)
        let agent = try XCTUnwrap(state.generatedAgent)
        let imported = try String(
            contentsOf: agent.folder.appending(path: "memoria/contexto/01-resumen.md"), encoding: .utf8)
        XCTAssertTrue(imported.contains("Ana lleva diseño."))
    }

    func testClaudeDesignAsksBeforeWritingUntilTheUserSaysOtherwise() {
        let state = makeState(tools: [.claudeDesign])
        XCTAssertEqual(state.configurableWrites, [.claudeDesign])
        XCTAssertEqual(state.policy(for: .claudeDesign), .ask, "puede borrar archivos: de fábrica pregunta")
        state.setPolicy(.allow, for: .claudeDesign)
        XCTAssertEqual(state.makeConfig().sendingRules.policy(for: .claudeDesign), .allow)
    }

    func testTheFirstCommandInvitesToPasteADesignLinkWhenThatIsAllThereIs() {
        let suggestion = FirstCommand.suggestion(for: [.claudeDesign], language: .spanish)
        XCTAssertTrue(suggestion.contains("enlace de Claude Design"))
        XCTAssertEqual(
            FirstCommand.suggestion(for: [.claudeDesign, .slack], language: .spanish),
            "¿Cuáles son los 3 mensajes más recientes de Slack donde me mencionan?", "con otras herramientas manda la de siempre")
    }

    func testContextLimitsAndEmptyTextAreRefused() {
        let state = makeState()
        XCTAssertEqual(state.addContext(ContextFile(title: "x", text: "  \n")), .empty)
        for index in 0..<ContextFile.maxFiles {
            XCTAssertNil(state.addContext(ContextFile(title: "n\(index)", text: "texto")))
        }
        XCTAssertEqual(state.addContext(ContextFile(title: "otro", text: "texto")), .tooMany)
        state.removeContext(state.contextItems[0])
        XCTAssertEqual(state.contextItems.count, ContextFile.maxFiles - 1)
    }

    func testContextIsNotPartOfTheConfigNorTheDraft() throws {
        let state = makeState()
        state.addContext(ContextFile(title: "Secreto?", text: "contenido largo del usuario"))
        let config = try String(data: AgentConfig.jsonEncoder.encode(state.makeConfig()), encoding: .utf8)
        XCTAssertFalse(try XCTUnwrap(config).contains("contenido largo del usuario"))
        let draft = try String(data: JSONEncoder().encode(state.makeDraft()), encoding: .utf8)
        XCTAssertFalse(try XCTUnwrap(draft).contains("contenido largo del usuario"))
    }

    func testGeneratingWritesTheAgentAndLeavesItReadyForTheLastScreen() async throws {
        let state = makeState()
        state.loadSkillCatalog()
        state.toggleSource(Source(id: "a", name: "#producto", kind: .channel), in: .slack)

        // Con las conexiones ya resueltas (las del paso 5 se dan por hechas), se avanza.
        state.setConnectionStatus(.slack, .connected)
        state.setOAuthClientID(.slack, "1234567890123.1234567890123")
        walkToGenerating(state)
        XCTAssertEqual(state.step, .generating)
        XCTAssertTrue(state.hidesNavigation, "mientras escribe no hay Atrás ni Siguiente")

        let done = await generate(state)
        XCTAssertTrue(done)
        XCTAssertEqual(state.generation?.phase, .succeeded)
        let agent = try XCTUnwrap(state.generatedAgent)
        XCTAssertTrue(FileManager.default.fileExists(atPath: agent.folder.appending(path: "AGENTS.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: agent.folder.appending(path: ".claude/skills/prd/SKILL.md").path))
        XCTAssertNotNil(state.lastGeneration)

        state.finishGeneration()
        XCTAssertEqual(state.step, .done)
        // «Listo» lleva su propio botón de abrir y su salida (6 oct 2026): sin la barra Atrás/Terminar. Atrás sigue
        // existiendo por teclado (⌘←, Esc), hacia la revisión.
        XCTAssertTrue(state.hidesNavigation)
        XCTAssertTrue(state.canGoBack)
    }

    func testGoingBackFromDoneAndAdvancingAgainRegeneratesTheSameAgent() async throws {
        let state = makeState()
        state.loadSkillCatalog()
        state.setOAuthClientID(.slack, "1234567890123.1234567890123")
        walkToGenerating(state)
        _ = await generate(state)
        let first = try XCTUnwrap(state.generatedAgent)
        state.finishGeneration()

        state.back()
        XCTAssertEqual(state.step, .review)
        state.setPolicy(.ask, for: .notion)
        state.next()
        XCTAssertEqual(state.step, .generating)
        XCTAssertNil(state.generation, "la generación anterior no cuenta: no se puede saltar «Generando»")
        state.next()
        XCTAssertEqual(state.step, .generating)
        _ = await generate(state)

        let again = try XCTUnwrap(state.generatedAgent)
        XCTAssertEqual(again.id, first.id)
        XCTAssertEqual(again.folderPath, first.folderPath, "no crea «Hera 2»")
        XCTAssertEqual(again.config.sendingRules.policy(for: .notion), .ask, "usa lo último que eligió")
    }

    func testAFailedGenerationOffersToGoBackToTheRulesAndNeverMovesOn() async {
        // Una skill marcada cuya carpeta no existe: el motor falla sin escribir nada.
        let state = makeState()
        state.loadSkillCatalog()
        state.setOAuthClientID(.slack, "1234567890123.1234567890123")
        try? FileManager.default.removeItem(at: skillsDirectory.appending(path: "galeno/prd"))
        walkToGenerating(state)

        let finished = await generate(state)
        XCTAssertTrue(finished)
        guard case .failed(let detail)? = state.generation?.phase else { return XCTFail("\(String(describing: state.generation?.phase))") }
        XCTAssertTrue(detail.contains("prd"), detail)
        XCTAssertNil(state.generatedAgent)

        state.finishGeneration()
        XCTAssertEqual(state.step, .generating, "no pasa a «Listo» si falló")
        state.leaveFailedGeneration()
        XCTAssertEqual(state.step, .rules)
    }

    func testTheClaudePathFromStep2IsWhatTheTerminalWillRun() {
        XCTAssertEqual(makeState().claudePath, "/ruta/claude")
        XCTAssertEqual(WizardState(preferredLanguages: ["es"]).claudePath, "claude")
    }
}
