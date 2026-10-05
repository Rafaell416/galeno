import GalenoCore
import XCTest

@testable import Galeno

/// Eliminar un agente manda a la Papelera su carpeta y lo que Claude guardó de ella, y nada más. Todo en carpetas
/// temporales y con una «Papelera» falsa que solo anota: ninguna prueba mueve nada real.
final class AgentRemoverTests: XCTestCase {
    private var root: URL!
    private var agents: URL!
    private var projects: URL!
    private var sessions: URL!
    private final class Trashed: @unchecked Sendable {
        private let lock = NSLock()
        private var list: [URL] = []
        var urls: [URL] { lock.withLock { list } }
        func add(_ url: URL) { lock.withLock { list.append(url) } }
    }
    private var trashed: Trashed!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("galeno-remover-\(UUID().uuidString)", isDirectory: true)
        agents = root.appendingPathComponent("Galeno", isDirectory: true)
        projects = root.appendingPathComponent("claude/projects", isDirectory: true)
        sessions = root.appendingPathComponent("claude/sessions", isDirectory: true)
        for url in [agents!, projects!, sessions!] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        trashed = Trashed()
    }

    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    private func remover() -> AgentRemover {
        let log = trashed!
        return AgentRemover(
            agentsRoot: agents, claudeProjects: projects, desktopSessions: ClaudeSessionStore(root: sessions),
            trash: { log.add($0) })
    }

    private func makeAgent(_ name: String, claudeData: Bool = true, sessionCount: Int = 1) throws -> AgentRecord {
        let folder = agents.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("memoria"), withIntermediateDirectories: true)
        if claudeData {
            let project = projects.appendingPathComponent(AgentRemover.projectFolderName(for: folder), isDirectory: true)
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: project.appendingPathComponent("a.jsonl"))
            try Data("{}".utf8).write(to: project.appendingPathComponent("b.jsonl"))
        }
        for index in 0..<sessionCount {
            let dir = sessions.appendingPathComponent("org/user", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let id = "local_\(name)-\(index)"
            let json: [String: Any] = ["sessionId": id, "cwd": folder.path, "isArchived": index == 1]
            try JSONSerialization.data(withJSONObject: json).write(to: dir.appendingPathComponent("\(id).json"))
        }
        return AgentRecord(config: AgentConfig(agentName: name, language: .spanish), folderPath: folder.path)
    }

    // MARK: - Cómo nombra Claude Code la carpeta

    func testTheProjectFolderNameMatchesWhatClaudeCodeWrites() {
        XCTAssertEqual(
            AgentRemover.projectFolderName(for: URL(fileURLWithPath: "/Users/rafa/Galeno/Hera")), "-Users-rafa-Galeno-Hera")
        XCTAssertEqual(
            AgentRemover.projectFolderName(for: URL(fileURLWithPath: "/Users/rafa/Galeno/TESTING 2")),
            "-Users-rafa-Galeno-TESTING-2", "el espacio también es un guion")
        // Con acentos hay dos formas posibles (`ó` suelta o `o` + acento); se buscan las dos.
        let accented = AgentRemover.projectFolderNames(for: URL(fileURLWithPath: "/Users/rafa/Galeno/Hip\u{F3}crates.v2"))
        XCTAssertTrue(accented.contains("-Users-rafa-Galeno-Hip-crates-v2"))
        XCTAssertTrue(accented.contains("-Users-rafa-Galeno-Hipo-crates-v2"))
        XCTAssertEqual(AgentRemover.projectFolderNames(for: URL(fileURLWithPath: "/Users/rafa/Galeno/Hera")).count, 1)
    }

    // MARK: - Qué se va a mandar

    func testThePlanListsTheFolderTheClaudeCodeDataAndEverySessionOfThatFolder() throws {
        let record = try makeAgent("Hera", sessionCount: 2)
        _ = try makeAgent("Aurora")  // otro agente: no debe aparecer

        let plan = remover().plan(for: record)

        XCTAssertEqual(plan.folder?.lastPathComponent, "Hera")
        XCTAssertEqual(plan.claudeCodeData?.lastPathComponent, AgentRemover.projectFolderName(for: record.folder))
        XCTAssertEqual(plan.desktopSessions.count, 2, "las archivadas también")
        XCTAssertTrue(plan.desktopSessions.allSatisfy { $0.lastPathComponent.hasPrefix("local_Hera") })
        XCTAssertEqual(plan.conversationCount, 2)
    }

    func testAnAgentWithNothingFromClaudeOnlyPlansItsFolder() throws {
        let record = try makeAgent("Hera", claudeData: false, sessionCount: 0)
        let plan = remover().plan(for: record)
        XCTAssertNotNil(plan.folder)
        XCTAssertNil(plan.claudeCodeData)
        XCTAssertTrue(plan.desktopSessions.isEmpty)
        XCTAssertEqual(plan.conversationCount, 0)
    }

    // MARK: - Lo que nunca se toca

    /// Una ruta rara en `installation.json` (la carpeta personal, la raíz, otra carpeta) no nos hace borrar nada.
    func testAFolderOutsideTheAgentsFolderIsNeverPlanned() throws {
        for path in [NSHomeDirectory(), "/", root.path, agents.path, agents.path + "/../Otra", "/Users/rafa/Documents"] {
            let record = AgentRecord(config: AgentConfig(agentName: "X", language: .spanish), folderPath: path)
            XCTAssertNil(remover().plan(for: record).folder, path)
        }
    }

    func testASymbolicLinkInsideTheAgentsFolderIsNotFollowed() throws {
        let target = root.appendingPathComponent("importante", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let link = agents.appendingPathComponent("Enlace")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let record = AgentRecord(config: AgentConfig(agentName: "Enlace", language: .spanish), folderPath: link.path)
        XCTAssertNil(remover().plan(for: record).folder)
    }

    func testAFolderThatIsAlreadyGoneStillAllowsRemovingTheRecord() throws {
        let record = AgentRecord(config: AgentConfig(agentName: "Hera", language: .spanish), folderPath: agents.appendingPathComponent("Hera").path)
        XCTAssertTrue(remover().plan(for: record).isEmpty)
    }

    // MARK: - Mandar a la Papelera

    func testExecutingSendsExactlyThePlannedItemsToTheTrash() throws {
        let record = try makeAgent("Hera", sessionCount: 2)
        let other = try makeAgent("Aurora")
        let remover = remover()
        let plan = remover.plan(for: record)

        let outcome = try remover.execute(plan)

        XCTAssertTrue(outcome.failed.isEmpty)
        let names = Set(trashed.urls.map(\.lastPathComponent))
        XCTAssertEqual(trashed.urls.count, 4)  // carpeta, datos de Claude Code y 2 sesiones
        XCTAssertTrue(names.contains("Hera"))
        XCTAssertFalse(names.contains("Aurora"))
        XCTAssertFalse(trashed.urls.contains { $0.path.hasPrefix(other.folder.path) })
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.folder.path), "el otro agente sigue ahí")
    }

    /// Si no se puede mandar la carpeta del agente a la Papelera, no se sigue: no se quita a medias.
    func testIfTheAgentFolderCannotBeTrashedNothingElseIsTouched() throws {
        struct Boom: Error {}
        let record = try makeAgent("Hera")
        let log = trashed!
        let failing = AgentRemover(
            agentsRoot: agents, claudeProjects: projects, desktopSessions: ClaudeSessionStore(root: sessions),
            trash: { url in
                if url.lastPathComponent == "Hera" { throw Boom() }
                log.add(url)
            })
        XCTAssertThrowsError(try failing.execute(failing.plan(for: record)))
        XCTAssertTrue(trashed.urls.isEmpty)
    }

    /// Lo de Claude se intenta aunque una pieza falle, y lo que no se pudo se devuelve para decírselo al usuario.
    func testWhateverClaudeDataCannotBeTrashedIsReportedNotHidden() throws {
        struct Boom: Error {}
        let record = try makeAgent("Hera", sessionCount: 1)
        let log = trashed!
        let flaky = AgentRemover(
            agentsRoot: agents, claudeProjects: projects, desktopSessions: ClaudeSessionStore(root: sessions),
            trash: { url in
                if url.pathExtension == "json" { throw Boom() }
                log.add(url)
            })
        let outcome = try flaky.execute(flaky.plan(for: record))
        XCTAssertEqual(outcome.failed.map(\.pathExtension), ["json"])
        XCTAssertEqual(trashed.urls.count, 2, "la carpeta y los datos de Claude Code sí")
    }
}
