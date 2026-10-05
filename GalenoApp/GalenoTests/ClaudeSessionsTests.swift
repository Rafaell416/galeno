import XCTest

@testable import Galeno

/// Volver a la conversación de un agente: se busca su sesión más reciente en la carpeta de datos de la app de
/// Claude (solo lectura, solo cuatro campos) y se arma el enlace con el id. Todo en una carpeta temporal.
final class ClaudeSessionsTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("galeno-sessions-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    private func write(
        _ id: String, cwd: String, at: Double, archived: Bool = false, level: String = "u1", file: String? = nil
    ) throws {
        let dir = root.appendingPathComponent("org").appendingPathComponent(level, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let json: [String: Any] = [
            "sessionId": id, "cwd": cwd, "isArchived": archived, "lastActivityAt": at,
            "title": "algo que nunca se lee",
        ]
        try JSONSerialization.data(withJSONObject: json).write(to: dir.appendingPathComponent("\(file ?? id).json"))
    }

    private var store: ClaudeSessionStore { ClaudeSessionStore(root: root) }
    private let folder = URL(fileURLWithPath: "/Users/prueba/Galeno/Hera", isDirectory: true)

    func testThereIsNothingToContinueWithoutSessions() {
        XCTAssertNil(store.latestSessionID(in: folder))
        XCTAssertNil(ClaudeSessionStore(root: root.appendingPathComponent("no-existe")).latestSessionID(in: folder))
    }

    func testItPicksTheMostRecentSessionOfThatFolder() throws {
        try write("local_aaa", cwd: folder.path, at: 100)
        try write("local_bbb", cwd: folder.path, at: 300)
        try write("local_ccc", cwd: folder.path, at: 200)
        XCTAssertEqual(store.latestSessionID(in: folder), "local_bbb")
    }

    func testOtherFoldersAndArchivedSessionsAreIgnored() throws {
        try write("local_otra", cwd: "/Users/prueba/Galeno/Aurora", at: 900)
        try write("local_vieja", cwd: folder.path, at: 800, archived: true)
        try write("local_buena", cwd: folder.path, at: 100, level: "u2")
        XCTAssertEqual(store.latestSessionID(in: folder), "local_buena")
    }

    func testAnIdThatIsNotShapedLikeASessionNeverBecomesALink() throws {
        try write("local_ok", cwd: folder.path, at: 1)
        try write("../../etc/passwd", cwd: folder.path, at: 999, file: "local_raro")
        XCTAssertNil(AgentLink.claudeAppContinue(sessionID: "../../etc/passwd"))
        XCTAssertNil(AgentLink.claudeAppContinue(sessionID: "local_x&q=hola"))
        XCTAssertNil(AgentLink.claudeAppContinue(sessionID: "session_123"))
        XCTAssertEqual(store.latestSessionID(in: folder), "local_ok", "la entrada con un id raro se descarta")
    }

    func testTheContinueLink() {
        XCTAssertEqual(
            AgentLink.claudeAppContinue(sessionID: "local_00000000-0000")?.absoluteString,
            "claude://code/continue?session=local_00000000-0000")
    }

    func testAFileThatIsNotWhatWeExpectIsSkippedWithoutFailing() throws {
        let dir = root.appendingPathComponent("org/u1", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("no es json".utf8).write(to: dir.appendingPathComponent("local_rota.json"))
        try write("local_ok", cwd: folder.path, at: 1)
        XCTAssertEqual(store.latestSessionID(in: folder), "local_ok")
    }
}
