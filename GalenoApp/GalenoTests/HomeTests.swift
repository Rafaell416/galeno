import GalenoCore
import XCTest

@testable import Galeno

/// Un opener que solo apunta lo que se le pidió.
@MainActor
private final class RecordingOpener: AgentOpening {
    var appAvailable = true
    var restartNeeded = false
    private(set) var calls: [String] = []

    /// Cuántas veces se preparó la app de Claude (abrirla y esperar) antes de mandarle un enlace.
    private(set) var prepared = 0
    func prepareClaudeApp() async { prepared += 1; calls.append("prepare") }

    var isClaudeAppAvailable: Bool { appAvailable }
    func openInClaudeApp(folder: URL, prompt: String?) -> Bool {
        calls.append("app \(folder.lastPathComponent) prompt=\(prompt ?? "nil")")
        return true
    }
    func openInTerminal(folder: URL, prompt: String?, claudePath: String) -> Bool {
        calls.append("terminal \(folder.lastPathComponent) prompt=\(prompt ?? "nil")")
        return true
    }
    func continueInClaudeApp(folder: URL) -> Bool {
        calls.append("continue \(folder.lastPathComponent)")
        return true
    }
    func claudeAppNeedsRestart(since date: Date) -> Bool { restartNeeded }
    /// Lo que devuelve el reinicio: por defecto, salió bien.
    var restartOutcome: AgentOpenOutcome = .opened
    func restartClaudeAppAndOpen(folder: URL, prompt: String?, resume: Bool) async -> AgentOpenOutcome {
        calls.append("restart \(folder.lastPathComponent) resume=\(resume)")
        return restartOutcome
    }
    func reveal(_ folder: URL) {}
}

/// El home (`docs/03` §3b): qué lista, a dónde se abre y qué pasa cuando `installation.json` no se puede leer.
/// Todo en carpetas temporales y en un `UserDefaults` propio: nada toca el disco ni las preferencias reales.
@MainActor
final class HomeTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("galeno-home-\(UUID().uuidString)", isDirectory: true)
        suiteName = "galeno-home-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private var store: InstallationStore { InstallationStore(directory: root.appendingPathComponent("support")) }

    /// Guarda una instalación con estos agentes (nombre, herramientas) y crea sus carpetas.
    @discardableResult
    private func install(
        _ agents: [(String, [Tool])], createFolders: Bool = true, language: Language = .spanish
    ) throws -> GalenoInstallation {
        var installation = GalenoInstallation(language: language)
        for (name, tools) in agents {
            for tool in tools { installation.setConnection(SharedConnection(tool: tool, status: .connected)) }
            let config = AgentConfig(
                agentName: name, language: language, projectDescription: "Proyecto de \(name)",
                connections: tools.map { ToolConnection(tool: $0, status: .connected, sources: .everything) })
            let record = installation.addAgent(config, agentsRoot: root.appendingPathComponent("Galeno"))
            if createFolders {
                try FileManager.default.createDirectory(at: record.folder, withIntermediateDirectories: true)
            }
        }
        try store.save(installation)
        return installation
    }

    private func makeModel(opener: RecordingOpener = RecordingOpener()) -> HomeModel {
        HomeModel(store: store, defaults: defaults, opener: opener, claudePath: "/ruta/claude", settle: {})
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    // MARK: - Qué lista

    func testWithoutAnInstallationThereIsNothingToList() {
        XCTAssertEqual(makeModel().state, .empty)
    }

    func testAnInstallationWithoutAgentsIsEmptyToo() throws {
        try install([])
        XCTAssertEqual(makeModel().state, .empty)
    }

    func testEachAgentShowsItsNameDescriptionAndTools() throws {
        try install([("Hera", [.whatsapp, .gmail]), ("Aurora", [.notion])])
        let agents = makeModel().agents
        XCTAssertEqual(agents.map(\.name), ["Hera", "Aurora"])
        XCTAssertEqual(agents[0].projectDescription, "Proyecto de Hera")
        XCTAssertEqual(agents[0].tools, [.whatsapp, .gmail])
        XCTAssertEqual(agents[1].tools, [.notion])
        XCTAssertTrue(agents.allSatisfy(\.folderExists))
    }

    /// Las herramientas salen de las conexiones compartidas: una que se desconectó ya no aparece.
    func testAToolDisconnectedInTheSharedConnectionsNoLongerAppears() throws {
        var installation = try install([("Hera", [.whatsapp, .slack])])
        installation.setConnection(SharedConnection(tool: .slack, status: .skipped))
        try store.save(installation)
        XCTAssertEqual(makeModel().agents.first?.tools, [.whatsapp])
    }

    func testAFolderDeletedByHandIsFlagged() throws {
        try install([("Hera", [.whatsapp])], createFolders: false)
        XCTAssertEqual(makeModel().agents.first?.folderExists, false)
    }

    func testTheHomeSpeaksTheInstallationLanguage() throws {
        try install([("Hera", [])], language: .english)
        XCTAssertEqual(makeModel().language, .english)
    }

    // MARK: - Si no se puede leer

    func testAnUnreadableInstallationIsAnErrorAndTheFileIsNotTouched() throws {
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        let garbage = Data("esto no es json".utf8)
        try garbage.write(to: store.fileURL)

        let model = makeModel()
        guard case .unreadable = model.state else { return XCTFail("\(model.state)") }
        XCTAssertEqual(try Data(contentsOf: store.fileURL), garbage)
    }

    func testAnInstallationFromANewerVersionIsAnErrorToo() throws {
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        let newer = Data(#"{"schemaVersion": 99}"#.utf8)
        try newer.write(to: store.fileURL)

        guard case .unreadable = makeModel().state else { return XCTFail() }
        XCTAssertEqual(try Data(contentsOf: store.fileURL), newer)
    }

    // MARK: - A dónde se abre

    private func waitForCalls(_ model: HomeModel, _ opener: RecordingOpener) async {
        await waitUntil { model.opening == nil && !opener.calls.isEmpty }
    }

    /// «Abrir» a secas abre donde se abrió la última vez, sin preguntar; la flecha despliega «Abrir en».
    func testOpenUsesTheRememberedChoiceWithoutAsking() async throws {
        try install([("Hera", [.whatsapp])])
        let opener = RecordingOpener()
        let model = makeModel(opener: opener)
        model.open(model.agents[0])
        await waitForCalls(model, opener)
        XCTAssertNil(model.menuOpen)
        XCTAssertEqual(opener.calls, ["prepare", "continue Hera"], "la primera vez, la app de Claude, ya preparada")
    }

    func testThePickedChoiceIsRememberedAndTheNextOpenUsesIt() async throws {
        try install([("Hera", [.whatsapp])])
        let opener = RecordingOpener()
        let model = makeModel(opener: opener)
        model.open(model.agents[0], in: .terminal)
        await waitForCalls(model, opener)
        XCTAssertEqual(makeModel().openTarget, .terminal, "queda guardada para la próxima vez que se abra Galeno")

        model.open(model.agents[0])
        await waitUntil { opener.calls.count == 2 && model.opening == nil }
        XCTAssertEqual(opener.calls, ["terminal Hera prompt=nil", "terminal Hera prompt=nil"])
    }

    func testTheArrowOpensAndClosesTheMenu() throws {
        try install([("Hera", [.whatsapp]), ("Aurora", [.notion])])
        let opener = RecordingOpener()
        let model = makeModel(opener: opener)
        model.toggleMenu(model.agents[0])
        XCTAssertEqual(model.menuOpen, model.agents[0].id)
        model.toggleMenu(model.agents[1])
        XCTAssertEqual(model.menuOpen, model.agents[1].id, "solo uno a la vez")
        model.closeMenu()
        XCTAssertNil(model.menuOpen)
        XCTAssertTrue(opener.calls.isEmpty, "desplegar no abre nada")
    }

    func testPickingFromTheMenuOpensAndClosesIt() async throws {
        try install([("Hera", [.whatsapp])])
        let opener = RecordingOpener()
        let model = makeModel(opener: opener)
        model.toggleMenu(model.agents[0])
        model.open(model.agents[0], in: .terminal)
        XCTAssertNil(model.menuOpen)
        await waitForCalls(model, opener)
        XCTAssertEqual(opener.calls, ["terminal Hera prompt=nil"])
    }

    func testWithoutTheClaudeAppThereIsNoMenuAndOpenGoesToTerminal() async throws {
        try install([("Hera", [.whatsapp])])
        let opener = RecordingOpener()
        opener.appAvailable = false
        let model = makeModel(opener: opener)
        XCTAssertFalse(model.canChoose)
        model.toggleMenu(model.agents[0])
        XCTAssertNil(model.menuOpen)
        model.open(model.agents[0])
        await waitForCalls(model, opener)
        XCTAssertEqual(opener.calls, ["terminal Hera prompt=nil"])
    }

    /// Volver a la conversación de siempre: en la app de Claude se continúa, no se abre una nueva.
    func testOpeningInTheAppContinuesTheLastConversationWithoutAFirstQuestion() async throws {
        try install([("Hera", [.whatsapp])])
        let opener = RecordingOpener()
        let model = makeModel(opener: opener)
        model.open(model.agents[0], in: .app)
        await waitForCalls(model, opener)
        XCTAssertEqual(opener.calls, ["prepare", "continue Hera"])
    }

    /// El agente nuevo «Aloha» acabó con su primera pregunta dentro de la carpeta de «Jarvi»: la app de Claude se había
    /// arrancado con el enlace, y un enlace que llega mientras carga puede perder su carpeta. Ahora la app se prepara
    /// —se abre y se espera— **antes** del enlace, y Terminal no necesita nada de eso.
    func testTheClaudeAppIsPreparedBeforeTheLinkAndTerminalNeedsNothing() async throws {
        try install([("Hera", [.whatsapp])])
        let opener = RecordingOpener()
        let model = makeModel(opener: opener)
        model.open(model.agents[0], in: .app)
        await waitForCalls(model, opener)
        XCTAssertEqual(opener.calls.first, "prepare")
        XCTAssertEqual(opener.calls.last, "continue Hera")

        let terminal = RecordingOpener()
        let other = makeModel(opener: terminal)
        other.open(other.agents[0], in: .terminal)
        await waitForCalls(other, terminal)
        XCTAssertEqual(terminal.prepared, 0)
    }

    func testOpeningInTerminalUsesTheTerminal() async throws {
        try install([("Hera", [.whatsapp])])
        let opener = RecordingOpener()
        let model = makeModel(opener: opener)
        model.open(model.agents[0], in: .terminal)
        await waitForCalls(model, opener)
        XCTAssertEqual(opener.calls, ["terminal Hera prompt=nil"])
    }

    /// Un agente con conectores de la cuenta y Claude abierto desde antes: se reinicia (y vuelve a su conversación).
    func testAnAgentWithConnectorsRestartsTheClaudeAppWhenItIsNeeded() async throws {
        try install([("Hera", [.gmail])])
        let opener = RecordingOpener()
        opener.restartNeeded = true
        let model = makeModel(opener: opener)
        XCTAssertTrue(model.willRestartClaude(for: model.agents[0]))

        model.open(model.agents[0], in: .app)
        await waitForCalls(model, opener)
        XCTAssertEqual(opener.calls, ["restart Hera resume=true"])
    }

    /// Claude no salió al pedírselo: no se abre nada en esa app y la tarjeta dice qué hacer. Antes se abría el
    /// agente igual, en una app que no veía sus conectores, y nadie sabía por qué.
    func testWhenClaudeDoesNotQuitTheCardSaysSoInsteadOfOpeningAnyway() async throws {
        try install([("Hera", [.gmail])])
        let opener = RecordingOpener()
        opener.restartNeeded = true
        opener.restartOutcome = .claudeDidNotQuit
        let model = makeModel(opener: opener)
        let agent = model.agents[0]

        model.open(agent, in: .app)
        await waitForCalls(model, opener)
        XCTAssertEqual(opener.calls, ["restart Hera resume=true"], "ni abre en la app ni continúa la sesión")
        XCTAssertEqual(model.problems[agent.id], .claudeDidNotQuit)

        // Al volver a intentarlo y salir bien, el aviso se quita.
        opener.restartOutcome = .opened
        model.open(agent, in: .app)
        await waitUntil { opener.calls.count == 2 && model.opening == nil }
        XCTAssertNil(model.problems[agent.id])
    }

    func testAnAgentWithoutConnectorsNeverRestartsTheClaudeApp() async throws {
        try install([("Hera", [.whatsapp, .slack])])
        let opener = RecordingOpener()
        opener.restartNeeded = true
        let model = makeModel(opener: opener)
        XCTAssertFalse(model.willRestartClaude(for: model.agents[0]))

        model.open(model.agents[0], in: .app)
        await waitForCalls(model, opener)
        XCTAssertEqual(opener.calls, ["prepare", "continue Hera"])
    }

    func testOpeningInTerminalNeverRestartsTheClaudeApp() async throws {
        try install([("Hera", [.gmail])])
        let opener = RecordingOpener()
        opener.restartNeeded = true
        let model = makeModel(opener: opener)
        model.open(model.agents[0], in: .terminal)
        await waitForCalls(model, opener)
        XCTAssertEqual(opener.calls, ["terminal Hera prompt=nil"])
    }

    func testAnAgentWhoseFolderIsGoneCannotBeOpened() async throws {
        try install([("Hera", [.whatsapp])], createFolders: false)
        let opener = RecordingOpener()
        let model = makeModel(opener: opener)
        model.toggleMenu(model.agents[0])
        model.open(model.agents[0], in: .app)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(model.menuOpen)
        XCTAssertTrue(opener.calls.isEmpty)
        XCTAssertNil(model.opening)
    }

    // MARK: - Qué muestra la ventana

    private func makeApp(draft: WizardDraft? = nil, opener: RecordingOpener = RecordingOpener()) -> AppModel {
        AppModel(
            home: makeModel(opener: opener),
            makeWizard: { WizardState(preferredLanguages: $0, draftStore: MemoryDraftStore(draft)) },
            // Con `claude` ya "encontrado": la prueba no lanza la detección de verdad.
            makeShortWizard: {
                WizardState(
                    preferredLanguages: [$0.language.rawValue],
                    claudeStatus: .found(version: "2.1.277", path: "/ruta/claude", loggedIn: true), startingFrom: $0)
            })
    }

    func testWithoutAgentsTheWindowOpensTheWizard() {
        XCTAssertEqual(makeApp().screen, .wizard)
    }

    func testWithAgentsTheWindowOpensTheHome() throws {
        try install([("Hera", [.whatsapp])])
        XCTAssertEqual(makeApp().screen, .home)
    }

    /// Mejor decir qué falló que abrir un wizard vacío que, al terminar, parecería haber perdido los agentes.
    func testAnUnreadableInstallationOpensTheHomeWhichSaysSo() throws {
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data("roto".utf8).write(to: store.fileURL)
        XCTAssertEqual(makeApp().screen, .home)
    }

    func testAnUnfinishedDraftComesFirst() throws {
        try install([("Hera", [.whatsapp])])
        let source = WizardState(
            preferredLanguages: ["es"],
            claudeStatus: .found(version: "2.1.277", path: "/ruta/claude", loggedIn: true),
            draftStore: MemoryDraftStore())
        source.agentName = "Aurora"
        source.next(); source.next(); source.next()
        let draft = try XCTUnwrap(source.makeDraft())
        XCTAssertGreaterThan(draft.step, WizardStep.welcome.rawValue)

        let app = makeApp(draft: draft)
        XCTAssertEqual(app.screen, .wizard)
        XCTAssertNotNil(app.wizard.pendingDraft)
    }

    func testNewAgentStartsTheShortWizardFromTheInstallation() throws {
        try install([("Hera", [.whatsapp, .notion])], language: .english)
        let app = makeApp()
        let before = app.wizard
        app.startNewAgent()
        XCTAssertEqual(app.screen, .wizard)
        XCTAssertFalse(app.wizard === before)
        XCTAssertEqual(app.wizard.mode, .short)
        XCTAssertEqual(app.wizard.step, .agent)
        XCTAssertEqual(app.wizard.language, .english)
        XCTAssertEqual(app.language, .english)
        XCTAssertEqual(app.wizard.selectedTools, [.whatsapp, .notion], "parte de lo ya conectado")
    }

    func testCancellingTheShortWizardGoesBackHomeWithoutCreatingAnything() throws {
        try install([("Hera", [.whatsapp])])
        let app = makeApp()
        app.startNewAgent()
        app.cancelWizard()
        XCTAssertEqual(app.screen, .home)
        XCTAssertEqual(app.home.agents.map(\.name), ["Hera"])
    }

    /// Con la instalación ilegible no se crea nada: no se trabaja sobre lo que no se vio.
    func testNewAgentDoesNothingWhenTheInstallationCannotBeRead() throws {
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data("roto".utf8).write(to: store.fileURL)
        let app = makeApp()
        app.startNewAgent()
        XCTAssertEqual(app.screen, .home)
        XCTAssertTrue(app.home.isUnreadable)
    }

    /// «Terminar» ya no cierra la app: vuelve al home, con lo que se acaba de crear.
    func testFinishingTheWizardGoesBackToTheHomeWithTheNewAgent() throws {
        let app = makeApp()
        XCTAssertEqual(app.screen, .wizard)
        try install([("Hera", [.whatsapp])])
        app.finishWizard()
        XCTAssertEqual(app.screen, .home)
        XCTAssertEqual(app.home.agents.map(\.name), ["Hera"])
    }
}
