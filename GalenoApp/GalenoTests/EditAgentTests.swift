import GalenoCore
import XCTest

@testable import Galeno

/// «Gestionar» un agente (`docs/03` §3b): las pantallas del wizard con lo que el agente ya tiene, para cambiar qué
/// lee, sus skills y sus reglas. Al guardar se regenera **su** carpeta; `memoria/` no se toca. Todo en carpetas temporales.
@MainActor
final class EditAgentTests: XCTestCase {
    private var installer: AgentInstaller!
    private var record: AgentRecord!

    override func setUp() async throws {
        installer = .sandboxed()
        var config = AgentConfig(
            agentName: "Hera", language: .spanish, projectDescription: "Lanzamiento de la app",
            connections: [
                ToolConnection(tool: .notion, status: .connected, sources: .everything),
                ToolConnection(tool: .gmail, status: .skipped),
            ])
        config.sendingRules.setPolicy(.allow, for: .notion)
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

    private func makeEditor() throws -> WizardState {
        WizardState(
            preferredLanguages: ["en"],
            claudeStatus: .found(version: "2.1.277", path: "/ruta/claude", loggedIn: true),
            connectServices: services(), startingFrom: try installation(), editing: record.id)
    }

    // MARK: - El punto de partida

    func testItStartsWithWhatTheAgentAlreadyHas() throws {
        let state = try makeEditor()
        XCTAssertEqual(state.mode, .edit)
        XCTAssertEqual(state.step, .tools)
        XCTAssertEqual(state.agentName, "Hera")
        XCTAssertEqual(state.projectDescription, "Lanzamiento de la app")
        XCTAssertEqual(state.language, .spanish, "el idioma de la instalación, no el del Mac")
        XCTAssertEqual(state.policy(for: .notion), .allow)
        XCTAssertEqual(state.generatedAgent?.id, record.id, "guarda sobre el mismo agente, no crea otro")
    }

    /// No hay bienvenida, detección ni nombre (renombrar es otra cosa), ni «Listo»: al guardar se vuelve al home.
    func testTheStepsAreToolsSkillsRulesReviewAndWriting() throws {
        let state = try makeEditor()
        state.setConnectionStatus(.gmail, .connected)  // nada por conectar
        XCTAssertEqual(state.stepOrder, [.tools, .skills, .rules, .review, .generating])
        XCTAssertTrue(state.isFirstStep)
        XCTAssertFalse(state.canGoBack, "en el primer paso se cancela, no se vuelve atrás")
    }

    /// Lo que se saltó en el wizard vuelve a estar por conectar: es la forma de recuperarlo.
    func testASkippedToolComesBackAsSomethingToConnect() throws {
        let state = try makeEditor()
        XCTAssertEqual(state.connection(for: .gmail)?.status, .selected)
        XCTAssertEqual(state.connection(for: .notion)?.status, .connected)
        XCTAssertEqual(state.toConnect, [.gmail])
        XCTAssertEqual(state.stepOrder, [.tools, .connect, .skills, .rules, .review, .generating])
    }

    func testAToolTheInstallationAlreadyHasConnectedEntersConnected() throws {
        var installation = try installation()
        installation.setConnection(SharedConnection(tool: .googleCalendar, status: .connected))
        let state = WizardState(
            preferredLanguages: ["es"],
            claudeStatus: .found(version: "2.1.277", path: "/ruta/claude", loggedIn: true),
            connectServices: services(), startingFrom: installation, editing: record.id)
        state.toggle(.googleCalendar)
        XCTAssertEqual(state.connection(for: .googleCalendar)?.status, .connected, "no vuelve a pasar por «Conectar»")
        XCTAssertEqual(state.toConnect, [.gmail], "solo lo que falta")
    }

    /// Un agente guardado antes de ocultar herramientas («Próximamente») con una de ellas sin conectar: no se
    /// puede quitar ni conectar, así que no entra a la lista de pendientes.
    func testAToolThatIsComingSoonAndWasNeverConnectedDoesNotComeBack() throws {
        var installation = try installation()
        var stale = try XCTUnwrap(installation.agent(id: record.id))
        stale.config.connections.append(ToolConnection(tool: .fireflies, status: .skipped))
        try installation.setConfig(stale.config, for: record.id)
        let state = WizardState(
            preferredLanguages: ["es"],
            claudeStatus: .found(version: "2.1.277", path: "/ruta/claude", loggedIn: true),
            startingFrom: installation, editing: record.id)
        XCTAssertNil(state.connection(for: .fireflies))
        XCTAssertEqual(state.toConnect, [.gmail])
    }

    /// El texto se adapta: al gestionar un agente que ya existe se «actualiza», al crear uno se «escribe».
    func testTheCopyUpdatesWhenManagingAndWritesWhenCreating() throws {
        let editor = try makeEditor()
        editor.setConnectionStatus(.gmail, .connected)  // nada por conectar: el camino llega a «Actualizando»
        for _ in 0..<10 where editor.step != .generating { editor.next() }
        XCTAssertEqual(editor.step, .generating)
        XCTAssertTrue("\(editor.stepTitle)".contains("step.generating.title.edit"))
        XCTAssertTrue("\(WizardStep.review.summary)".contains("step.review.summary"))

        let creator = WizardState(preferredLanguages: ["es"])
        XCTAssertFalse("\(creator.stepTitle)".contains(".edit"))
    }

    func testAnUnknownAgentFallsBackToNothingSpecial() throws {
        let state = WizardState(
            preferredLanguages: ["es"],
            claudeStatus: .found(version: "2.1.277", path: "/ruta/claude", loggedIn: true),
            startingFrom: try installation(), editing: UUID())
        XCTAssertNotEqual(state.mode, .edit)
    }

    // MARK: - Guardar

    /// Cambia una regla y guarda: se regenera la carpeta del mismo agente. Lo que alguien editó a mano en los
    /// archivos de Galeno se pierde, y la memoria sigue ahí.
    func testSavingRegeneratesTheSameFolderLosesHandEditsAndKeepsTheMemory() async throws {
        let agentsFile = record.folder.appending(path: "AGENTS.md")
        try (String(contentsOf: agentsFile, encoding: .utf8) + "\nEDITADO A MANO\n").write(to: agentsFile, atomically: true, encoding: .utf8)
        let memory = record.folder.appending(path: "memoria/proyecto.md")
        try (String(contentsOf: memory, encoding: .utf8) + "\nNOTA DE MEMORIA\n").write(to: memory, atomically: true, encoding: .utf8)

        let state = try makeEditor()
        state.setConnectionStatus(.gmail, .connected)
        state.setPolicy(.ask, for: .notion)
        var saved = 0
        state.onSaved = { saved += 1 }
        for _ in 0..<10 where state.step != .generating { state.next() }
        XCTAssertEqual(state.step, .generating)

        state.beginGeneration()
        let done = await waitUntil(timeout: 10) { state.generation?.phase != .running }
        XCTAssertTrue(done)
        XCTAssertEqual(state.generation?.phase, .succeeded)
        state.finishGeneration()
        XCTAssertEqual(saved, 1, "al guardar se vuelve al home")

        // La misma carpeta, un solo agente.
        let after = try installation()
        XCTAssertEqual(after.agents.map(\.id), [record.id])
        XCTAssertEqual(after.agents.first?.folderPath, record.folderPath)
        let siblings = try FileManager.default.contentsOfDirectory(atPath: record.folder.deletingLastPathComponent().path)
        XCTAssertEqual(siblings, [record.folder.lastPathComponent], "no apareció «Hera 2»")

        // La regla nueva quedó escrita; lo editado a mano en los archivos de Galeno se fue.
        let settings = try String(contentsOf: record.folder.appending(path: ".claude/settings.json"), encoding: .utf8)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(settings.utf8)) as? [String: Any])
        let ask = try XCTUnwrap((root["permissions"] as? [String: Any])?["ask"] as? [String])
        XCTAssertTrue(ask.contains("mcp__notion__*"), "Notion ahora pregunta")
        XCTAssertFalse(try String(contentsOf: agentsFile, encoding: .utf8).contains("EDITADO A MANO"))
        // La memoria nunca se toca.
        XCTAssertTrue(try String(contentsOf: memory, encoding: .utf8).contains("NOTA DE MEMORIA"))
        XCTAssertEqual(after.agent(id: record.id)?.config.sendingRules.policy(for: .notion), .ask)
    }

    // MARK: - Desde el home

    private func makeApp(opener: AgentOpening? = nil, defaults: UserDefaults? = nil) throws -> AppModel {
        let home = HomeModel(
            store: installer.store, defaults: defaults ?? UserDefaults(suiteName: "edit-\(UUID().uuidString)")!,
            claudePath: "/ruta/claude", settle: {})
        return AppModel(
            home: home,
            makeWizard: { WizardState(preferredLanguages: $0, draftStore: MemoryDraftStore()) },
            makeEditWizard: { installation, id in
                WizardState(
                    preferredLanguages: ["es"],
                    claudeStatus: .found(version: "2.1.277", path: "/ruta/claude", loggedIn: true),
                    connectServices: self.services(), startingFrom: installation, editing: id)
            })
    }

    func testManagingAnAgentOpensItsEditorAndSavingGoesBackHome() throws {
        let app = try makeApp()
        XCTAssertEqual(app.screen, .home)
        app.manageAgent(record.id)
        XCTAssertEqual(app.screen, .wizard)
        XCTAssertEqual(app.wizard.mode, .edit)
        app.cancelWizard()
        XCTAssertEqual(app.screen, .home, "cancelar no cambia nada")

        app.manageAgent(record.id)
        app.wizard.onSaved?()
        XCTAssertEqual(app.screen, .home)
    }

    /// Guardar con otras herramientas deja anotado el cambio (el home reinicia Claude al abrir el agente); guardar
    /// sin tocar las herramientas, no.
    func testSavingWithDifferentToolsIsNotedAndSavingTheSameToolsIsNot() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "edit-\(UUID().uuidString)"))
        let app = try makeApp(defaults: defaults)
        func noted() -> Bool { defaults.dictionary(forKey: Prefs.toolsChangedAt)?[record.id.uuidString] != nil }

        app.manageAgent(record.id)
        app.wizard.onSaved?()
        XCTAssertFalse(noted(), "las mismas herramientas: nada que recargar")

        app.manageAgent(record.id)
        var config = try XCTUnwrap(try installation().resolvedConfig(for: record.id))
        config.connections.append(ToolConnection(tool: .jira, status: .connected, sources: .everything))
        _ = try installer.install(config, existingAgentID: record.id)
        app.wizard.onSaved?()
        XCTAssertTrue(noted())
    }

    func testManagingAnAgentThatIsNotInTheInstallationDoesNothing() throws {
        let app = try makeApp()
        app.manageAgent(UUID())
        XCTAssertEqual(app.screen, .home)
    }
}
