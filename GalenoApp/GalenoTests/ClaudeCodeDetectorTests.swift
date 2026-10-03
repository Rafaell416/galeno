import XCTest

@testable import Galeno

/// Un `CommandRunning` con respuestas fijas, para probar el detector sin lanzar
/// nada. La clave es el comando entero: "/ruta/claude --version".
private final class FakeRunner: CommandRunning, @unchecked Sendable {
    private let responses: [String: CommandResult]
    private let lock = NSLock()
    private var recorded: [String] = []

    init(_ responses: [String: CommandResult]) { self.responses = responses }

    var calls: [String] { lock.withLock { recorded } }

    func run(_ executable: String, arguments: [String], timeout: TimeInterval) async -> CommandResult? {
        let command = ([executable] + arguments).joined(separator: " ")
        lock.withLock { recorded.append(command) }
        return responses[command]
    }
}

private func ok(_ output: String) -> CommandResult { CommandResult(status: 0, output: output) }

final class ClaudeCodeDetectorTests: XCTestCase {
    private let home = "/Users/prueba"

    private func detector(
        _ responses: [String: CommandResult], executables: Set<String>
    ) -> (ClaudeCodeDetector, FakeRunner) {
        let runner = FakeRunner(responses)
        let detector = ClaudeCodeDetector(
            runner: runner, homeDirectory: home, isExecutable: { executables.contains($0) })
        return (detector, runner)
    }

    // MARK: - Dónde lo encuentra

    func testFindsClaudeInAKnownPathWithoutAskingTheShell() async {
        let path = "/opt/homebrew/bin/claude"
        let (detector, runner) = detector(
            [
                "\(path) --version": ok("2.1.277 (Claude Code)\n"),
                "\(path) auth status": ok(#"{"loggedIn": true, "authMethod": "claude.ai"}"#),
            ], executables: [path])

        let status = await detector.detect()

        XCTAssertEqual(status, .found(version: "2.1.277", path: path, loggedIn: true))
        XCTAssertFalse(runner.calls.contains { $0.hasPrefix("/bin/zsh") }, "el shell es lo lento: no se pregunta si ya está")
    }

    func testFindsTheNativeInstallerPath() async {
        let path = "\(home)/.local/bin/claude"
        let (detector, _) = detector(
            ["\(path) --version": ok("2.1.211 (Claude Code)")], executables: [path])

        let status = await detector.detect()

        guard case .found(let version, let foundPath, _) = status else { return XCTFail("\(status)") }
        XCTAssertEqual(version, "2.1.211")
        XCTAssertEqual(foundPath, path)
    }

    func testFallsBackToTheLoginShellForNpmOrNvmInstalls() async {
        let path = "\(home)/.nvm/versions/node/v22/bin/claude"
        let (detector, runner) = detector(
            [
                // Un .zshrc que imprime cosas antes de la ruta.
                "/bin/zsh -lic command -v claude": ok("Bienvenido de nuevo\n\(path)\n"),
                "\(path) --version": ok("2.1.277 (Claude Code)"),
            ], executables: [path])

        let status = await detector.detect()

        guard case .found(_, let foundPath, _) = status else { return XCTFail("\(status)") }
        XCTAssertEqual(foundPath, path)
        XCTAssertTrue(runner.calls.contains("/bin/zsh -lic command -v claude"))
    }

    func testAnAliasPrintedByTheShellIsNotAPath() async {
        let (detector, _) = detector(
            ["/bin/zsh -lic command -v claude": ok("alias claude='~/otra/cosa'\n")], executables: [])

        let status = await detector.detect()

        XCTAssertEqual(status, .notFound)
    }

    // MARK: - Cuando no está

    func testNotFoundWhenNothingIsInstalled() async {
        let (detector, _) = detector(
            ["/bin/zsh -lic command -v claude": CommandResult(status: 1, output: "")], executables: [])

        let status = await detector.detect()

        XCTAssertEqual(status, .notFound)
    }

    func testNotFoundWhenTheShellTimesOut() async {
        // Sin respuesta registrada, el runner falso devuelve `nil`, como un tiempo agotado.
        let (detector, _) = detector([:], executables: [])

        let status = await detector.detect()

        XCTAssertEqual(status, .notFound)
    }

    func testABrokenBinaryIsNotFoundAndTheNextCandidateGetsATry() async {
        let broken = "\(home)/.local/bin/claude"
        let working = "/opt/homebrew/bin/claude"
        let (detector, _) = detector(
            [
                "\(broken) --version": CommandResult(status: 1, output: "dyld: Library not loaded"),
                "\(working) --version": ok("2.1.277 (Claude Code)"),
            ], executables: [broken, working])

        let status = await detector.detect()

        guard case .found(_, let path, _) = status else { return XCTFail("\(status)") }
        XCTAssertEqual(path, working)
    }

    func testAVersionThatDoesNotLookLikeOneIsNotFound() async {
        let path = "/usr/local/bin/claude"
        let (detector, _) = detector(
            ["\(path) --version": ok("command not found")], executables: [path])

        let status = await detector.detect()

        XCTAssertEqual(status, .notFound)
    }

    // MARK: - La sesión

    func testReportsWhenThereIsNoSession() async {
        let path = "/opt/homebrew/bin/claude"
        let (detector, _) = detector(
            [
                "\(path) --version": ok("2.1.277 (Claude Code)"),
                "\(path) auth status": ok(#"{"loggedIn": false}"#),
            ], executables: [path])

        let status = await detector.detect()

        XCTAssertEqual(status, .found(version: "2.1.277", path: path, loggedIn: false))
    }

    /// Si no se puede saber (una versión sin `auth status`, o una salida que no es
    /// JSON), la sesión queda en `nil` y la pantalla no avisa de nada.
    func testTheSessionIsUnknownWhenAuthStatusCannotBeRead() async {
        let path = "/opt/homebrew/bin/claude"

        for authStatus in [nil, ok("error: unknown command 'auth'"), ok("{}")] {
            var responses = ["\(path) --version": ok("2.1.277 (Claude Code)")]
            responses["\(path) auth status"] = authStatus
            let (detector, _) = detector(responses, executables: [path])

            let status = await detector.detect()

            XCTAssertEqual(status, .found(version: "2.1.277", path: path, loggedIn: nil))
        }
    }

    // MARK: - La versión

    func testParseVersion() {
        XCTAssertEqual(ClaudeCodeDetector.parseVersion("2.1.277 (Claude Code)\n"), "2.1.277")
        XCTAssertEqual(ClaudeCodeDetector.parseVersion("  2.1.0-beta.1 (Claude Code)"), "2.1.0-beta.1")
        XCTAssertNil(ClaudeCodeDetector.parseVersion("v2"))
        XCTAssertNil(ClaudeCodeDetector.parseVersion(""))
        XCTAssertNil(ClaudeCodeDetector.parseVersion("Claude Code 2.1.277"))
    }

    // MARK: - El lanzador de procesos de verdad

    func testProcessRunnerCapturesOutput() async throws {
        let result = await ProcessRunner().run("/bin/echo", arguments: ["hola"], timeout: 5)

        XCTAssertEqual(result, CommandResult(status: 0, output: "hola\n"))
    }

    func testProcessRunnerReportsAFailingStatus() async throws {
        let result = await ProcessRunner().run("/usr/bin/false", arguments: [], timeout: 5)

        XCTAssertEqual(result?.status, 1)
    }

    func testProcessRunnerGivesUpOnAProcessThatNeverEnds() async throws {
        let start = Date()

        let result = await ProcessRunner().run("/bin/sleep", arguments: ["30"], timeout: 0.3)

        XCTAssertNil(result)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5, "el tiempo máximo no cortó el proceso")
    }

    func testProcessRunnerReturnsNilForAMissingExecutable() async {
        let result = await ProcessRunner().run("/no/existe/claude", arguments: [], timeout: 5)

        XCTAssertNil(result)
    }
}
