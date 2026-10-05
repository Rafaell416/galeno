import GalenoCore
import XCTest

@testable import Galeno

/// Renombrar y eliminar un agente desde el home. Todo en carpetas temporales y con una «Papelera» falsa que solo
/// anota: ninguna prueba mueve ni borra nada real.
@MainActor
final class ManageAgentTests: XCTestCase {
    private final class Trashed: @unchecked Sendable {
        private let lock = NSLock()
        private var list: [URL] = []
        var failing: Set<String> = []
        var urls: [URL] { lock.withLock { list } }
        func add(_ url: URL) throws {
            struct Boom: Error {}
            if lock.withLock({ failing.contains(url.lastPathComponent) || failing.contains(url.pathExtension) }) { throw Boom() }
            lock.withLock { list.append(url) }
        }
    }

    private var installer: AgentInstaller!
    private var claudeRoot: URL!
    private var trash: Trashed!
    private var hera: AgentRecord!
    private var aurora: AgentRecord!

    override func setUp() async throws {
        installer = .sandboxed()
        claudeRoot = FileManager.default.temporaryDirectory.appendingPathComponent("galeno-claude-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeRoot.appendingPathComponent("projects"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: claudeRoot.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        trash = Trashed()
        func config(_ name: String) -> AgentConfig {
            AgentConfig(
                agentName: name, language: .spanish, projectDescription: "Proyecto de \(name)",
                connections: [ToolConnection(tool: .notion, status: .connected, sources: .everything)])
        }
        hera = try installer.install(config("Hera")).record
        aurora = try installer.install(config("Aurora")).record
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: claudeRoot)
        try? FileManager.default.removeItem(at: installer.agentsRoot.deletingLastPathComponent())
    }

    private func makeModel() -> HomeModel {
        let log = trash!
        let remover = AgentRemover(
            agentsRoot: installer.agentsRoot, claudeProjects: claudeRoot.appendingPathComponent("projects"),
            desktopSessions: ClaudeSessionStore(root: claudeRoot.appendingPathComponent("sessions")),
            trash: { try log.add($0) })
        return HomeModel(
            store: installer.store, defaults: UserDefaults(suiteName: "manage-\(UUID().uuidString)")!,
            claudePath: "/ruta/claude", installer: installer, remover: remover, settle: {})
    }

    private func claudeData(for record: AgentRecord, sessions: Int = 1) throws {
        let project = claudeRoot.appendingPathComponent("projects/\(AgentRemover.projectFolderName(for: record.folder))")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: project.appendingPathComponent("a.jsonl"))
        let dir = claudeRoot.appendingPathComponent("sessions/org/user")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for index in 0..<sessions {
            let id = "local_\(record.config.agentName)-\(index)"
            let json: [String: Any] = ["sessionId": id, "cwd": record.folder.path]
            try JSONSerialization.data(withJSONObject: json).write(to: dir.appendingPathComponent("\(id).json"))
        }
    }

    // MARK: - Renombrar

    /// Solo cambia el nombre: la misma carpeta, el mismo agente, la memoria intacta; los archivos de Galeno se reescriben.
    func testRenamingChangesOnlyTheNameAndKeepsTheFolderAndTheMemory() throws {
        let agentsFile = hera.folder.appending(path: "AGENTS.md")
        try (String(contentsOf: agentsFile, encoding: .utf8) + "\nEDITADO A MANO\n").write(to: agentsFile, atomically: true, encoding: .utf8)
        let memory = hera.folder.appending(path: "memoria/proyecto.md")
        try (String(contentsOf: memory, encoding: .utf8) + "\nNOTA DE MEMORIA\n").write(to: memory, atomically: true, encoding: .utf8)
        let model = makeModel()
        let agent = try XCTUnwrap(model.agents.first { $0.id == hera.id })
        model.askRename(agent)
        XCTAssertEqual(model.dialog, .rename(agent))

        XCTAssertTrue(model.rename(agent, to: "  Hera Pro  "))

        XCTAssertNil(model.dialog)
        let installation = try XCTUnwrap(try installer.store.load())
        let renamed = try XCTUnwrap(installation.agent(id: hera.id))
        XCTAssertEqual(renamed.config.agentName, "Hera Pro")
        XCTAssertEqual(renamed.folderPath, hera.folderPath, "la carpeta no se mueve")
        XCTAssertEqual(installation.agents.count, 2)
        XCTAssertEqual(model.agents.first { $0.id == hera.id }?.name, "Hera Pro")
        let text = try String(contentsOf: agentsFile, encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("# Hera Pro"))
        XCTAssertFalse(text.contains("EDITADO A MANO"), "Galeno es el dueño de esos archivos")
        XCTAssertTrue(try String(contentsOf: memory, encoding: .utf8).contains("NOTA DE MEMORIA"))
        XCTAssertTrue(trash.urls.isEmpty, "renombrar no manda nada a la Papelera")
    }

    func testANameThatIsEmptyOrTooLongIsRefused() throws {
        XCTAssertEqual(HomeModel.renameIssue(for: "   "), .empty)
        XCTAssertEqual(HomeModel.renameIssue(for: String(repeating: "a", count: WizardState.maxAgentNameLength + 1)), .tooLong)
        XCTAssertNil(HomeModel.renameIssue(for: "Hera Pro"))
        let model = makeModel()
        let agent = try XCTUnwrap(model.agents.first)
        XCTAssertFalse(model.rename(agent, to: " "))
        XCTAssertEqual(try installer.store.load()?.agent(id: agent.id)?.config.agentName, agent.name)
    }

    func testRenamingToTheSameNameJustClosesTheDialog() throws {
        let model = makeModel()
        let agent = try XCTUnwrap(model.agents.first)
        model.askRename(agent)
        XCTAssertTrue(model.rename(agent, to: agent.name))
        XCTAssertNil(model.dialog)
    }

    // MARK: - Eliminar

    func testAskingToDeleteShowsWhatWouldGoToTheTrashAndTouchesNothing() throws {
        try claudeData(for: hera, sessions: 2)
        let model = makeModel()
        let agent = try XCTUnwrap(model.agents.first { $0.id == hera.id })

        model.askDelete(agent)

        guard case .delete(_, let plan)? = model.dialog else { return XCTFail("\(String(describing: model.dialog))") }
        XCTAssertEqual(plan.folder?.lastPathComponent, hera.folder.lastPathComponent)
        XCTAssertNotNil(plan.claudeCodeData)
        XCTAssertEqual(plan.desktopSessions.count, 2)
        XCTAssertEqual(plan.conversationCount, 1)
        XCTAssertTrue(trash.urls.isEmpty, "preguntar no manda nada")
        XCTAssertEqual(try installer.store.load()?.agents.count, 2)

        model.cancelDialog()
        XCTAssertNil(model.dialog)
        XCTAssertTrue(trash.urls.isEmpty)
    }

    func testConfirmingSendsThatAgentToTheTrashAndRemovesItFromTheList() throws {
        try claudeData(for: hera)
        let model = makeModel()
        let agent = try XCTUnwrap(model.agents.first { $0.id == hera.id })
        model.askDelete(agent)

        XCTAssertTrue(model.confirmDelete())

        XCTAssertEqual(trash.urls.count, 3)  // carpeta, datos de Claude Code y su sesión
        XCTAssertTrue(trash.urls.contains { $0.lastPathComponent == hera.folder.lastPathComponent })
        XCTAssertFalse(trash.urls.contains { $0.path.contains(aurora.folder.lastPathComponent) }, "el otro agente no")
        let installation = try XCTUnwrap(try installer.store.load())
        XCTAssertEqual(installation.agents.map(\.id), [aurora.id])
        XCTAssertEqual(installation.connection(for: .notion)?.status, .connected, "las conexiones son de todos")
        XCTAssertEqual(model.agents.map(\.id), [aurora.id])
        XCTAssertNil(model.dialog)
        XCTAssertNil(model.notice)
    }

    /// Si la carpeta no se puede mandar a la Papelera no se quita nada: el agente sigue en la lista y se dice.
    func testIfTheFolderCannotGoToTheTrashTheAgentStaysAndTheDialogSaysSo() throws {
        let model = makeModel()
        let agent = try XCTUnwrap(model.agents.first { $0.id == hera.id })
        trash.failing = [hera.folder.lastPathComponent]
        model.askDelete(agent)

        XCTAssertFalse(model.confirmDelete())

        XCTAssertNotNil(model.dialogError)
        XCTAssertNotNil(model.dialog, "el diálogo sigue abierto")
        XCTAssertEqual(try installer.store.load()?.agents.count, 2)
        XCTAssertTrue(trash.urls.isEmpty)
    }

    /// Lo de Claude que no se pudo mandar a la Papelera se avisa; el agente sí se elimina.
    func testWhatClaudeKeepsThatCouldNotBeTrashedIsReported() throws {
        try claudeData(for: hera)
        let model = makeModel()
        let agent = try XCTUnwrap(model.agents.first { $0.id == hera.id })
        trash.failing = ["json"]
        model.askDelete(agent)

        XCTAssertTrue(model.confirmDelete())

        XCTAssertEqual(try installer.store.load()?.agents.map(\.id), [aurora.id])
        XCTAssertNotNil(model.notice)
    }

    /// Una carpeta que ya no está: se quita de Galeno y no hay nada que mandar a la Papelera.
    func testAnAgentWhoseFolderIsGoneIsJustRemovedFromGaleno() throws {
        try FileManager.default.removeItem(at: hera.folder)
        let model = makeModel()
        let agent = try XCTUnwrap(model.agents.first { $0.id == hera.id })
        model.askDelete(agent)
        guard case .delete(_, let plan)? = model.dialog else { return XCTFail() }
        XCTAssertNil(plan.folder)

        XCTAssertTrue(model.confirmDelete())
        XCTAssertEqual(try installer.store.load()?.agents.map(\.id), [aurora.id])
        XCTAssertTrue(trash.urls.isEmpty)
    }

    // MARK: - Desde la ventana

    func testDeletingTheLastAgentOpensTheShortWizard() throws {
        let log = trash!
        let remover = AgentRemover(
            agentsRoot: installer.agentsRoot, claudeProjects: claudeRoot.appendingPathComponent("projects"),
            desktopSessions: ClaudeSessionStore(root: claudeRoot.appendingPathComponent("sessions")),
            trash: { try log.add($0) })
        let home = HomeModel(
            store: installer.store, defaults: UserDefaults(suiteName: "manage-\(UUID().uuidString)")!,
            claudePath: "/ruta/claude", installer: installer, remover: remover, settle: {})
        let app = AppModel(
            home: home,
            makeWizard: { WizardState(preferredLanguages: $0, draftStore: MemoryDraftStore()) },
            makeShortWizard: {
                WizardState(
                    preferredLanguages: ["es"],
                    claudeStatus: .found(version: "2.1.277", path: "/ruta/claude", loggedIn: true), startingFrom: $0)
            })
        for id in [hera.id, aurora.id] {
            let agent = try XCTUnwrap(home.agents.first { $0.id == id })
            home.askDelete(agent)
            XCTAssertTrue(home.confirmDelete())
            app.agentRemoved()
        }
        XCTAssertEqual(app.screen, .wizard)
        XCTAssertEqual(app.wizard.mode, .short, "sin agentes, el wizard corto: las conexiones ya están hechas")
    }

    func testRemovingAnAgentWhenOthersRemainStaysOnTheHome() throws {
        let home = makeModel()
        let app = AppModel(home: home, makeWizard: { WizardState(preferredLanguages: $0, draftStore: MemoryDraftStore()) })
        let agent = try XCTUnwrap(home.agents.first { $0.id == hera.id })
        home.askDelete(agent)
        XCTAssertTrue(home.confirmDelete())
        app.agentRemoved()
        XCTAssertEqual(app.screen, .home)
    }
}
