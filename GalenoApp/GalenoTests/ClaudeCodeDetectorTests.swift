import XCTest

@testable import Galeno

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
                "\(path) --version": ok("2.1.289 (Claude Code)\n"),
                "\(path) auth status": ok(#"{"loggedIn": true, "authMethod": "claude.ai"}"#),
            ], executables: [path])

        let status = await detector.detect()

        XCTAssertEqual(status, .found(version: "2.1.289", path: path, loggedIn: true))
        XCTAssertFalse(runner.calls.contains { $0.hasPrefix("/bin/zsh") }, "el shell es lo lento: no se pregunta si ya está")
    }

    func testFindsTheNativeInstallerPath() async {
        let path = "\(home)/.local/bin/claude"
        let (detector, _) = detector(
            ["\(path) --version": ok("2.1.300 (Claude Code)")], executables: [path])

        let status = await detector.detect()

        guard case .found(let version, let foundPath, _) = status else { return XCTFail("\(status)") }
        XCTAssertEqual(version, "2.1.300")
        XCTAssertEqual(foundPath, path)
    }

    func testFallsBackToTheLoginShellForNpmOrNvmInstalls() async {
        let path = "\(home)/.nvm/versions/node/v22/bin/claude"
        let (detector, runner) = detector(
            [
                // Un .zshrc que imprime cosas antes de la ruta.
                "/bin/zsh -lic command -v claude": ok("Bienvenido de nuevo\n\(path)\n"),
                "\(path) --version": ok("2.1.289 (Claude Code)"),
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
                "\(working) --version": ok("2.1.289 (Claude Code)"),
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
                "\(path) --version": ok("2.1.289 (Claude Code)"),
                "\(path) auth status": ok(#"{"loggedIn": false}"#),
            ], executables: [path])

        let status = await detector.detect()

        XCTAssertEqual(status, .found(version: "2.1.289", path: path, loggedIn: false))
    }

    /// Si no se puede saber (una versión sin `auth status`, o una salida que no es
    /// JSON), la sesión queda en `nil` y la pantalla no avisa de nada.
    func testTheSessionIsUnknownWhenAuthStatusCannotBeRead() async {
        let path = "/opt/homebrew/bin/claude"

        for authStatus in [nil, ok("error: unknown command 'auth'"), ok("{}")] {
            var responses = ["\(path) --version": ok("2.1.289 (Claude Code)")]
            responses["\(path) auth status"] = authStatus
            let (detector, _) = detector(responses, executables: [path])

            let status = await detector.detect()

            XCTAssertEqual(status, .found(version: "2.1.289", path: path, loggedIn: nil))
        }
    }

    // MARK: - La versión

    // MARK: - Versión mínima y varios `claude`

    /// El demo de Aquiles (5 oct 2026): un `claude` sin `mcp login`. No se sigue con él.
    func testAnOldClaudeIsOutdatedNotFound() async {
        let path = "/usr/local/bin/claude"
        let (detector, runner) = detector(["\(path) --version": ok("2.1.150 (Claude Code)")], executables: [path])

        let status = await detector.detect()

        XCTAssertEqual(status, .outdated(version: "2.1.150", path: path))
        XCTAssertFalse(status.isFound)
        XCTAssertFalse(status.isReady)
        XCTAssertEqual(status.path, path, "la ruta se conserva: es la que se va a actualizar")
        XCTAssertFalse(runner.calls.contains { $0.hasSuffix("auth status") }, "no se le pregunta la sesión a uno que no sirve")
    }

    func testWithSeveralInstallsTheNewestWins() async {
        let old = "/usr/local/bin/claude"
        let new = "\(home)/.local/bin/claude"
        let (detector, _) = detector(
            [
                "\(old) --version": ok("2.1.150 (Claude Code)"),
                "\(new) --version": ok("2.1.289 (Claude Code)"),
                "\(new) auth status": ok(#"{"loggedIn": true}"#),
            ], executables: [old, new])

        let status = await detector.detect()

        XCTAssertEqual(status, .found(version: "2.1.289", path: new, loggedIn: true))
    }

    func testAnOutdatedKnownPathStillAsksTheShellForANewerOne() async {
        let old = "/usr/local/bin/claude"
        let nvm = "\(home)/.nvm/versions/node/v22/bin/claude"
        let (detector, _) = detector(
            [
                "\(old) --version": ok("2.1.150 (Claude Code)"),
                "/bin/zsh -lic command -v claude": ok("\(nvm)\n"),
                "\(nvm) --version": ok("2.1.290 (Claude Code)"),
            ], executables: [old, nvm])

        let status = await detector.detect()

        guard case .found(let version, let path, _) = status else { return XCTFail("\(status)") }
        XCTAssertEqual(version, "2.1.290")
        XCTAssertEqual(path, nvm)
    }

    func testVersionsCompareByNumberNotByText() {
        XCTAssertEqual(ClaudeCodeDetector.compare("2.1.90", "2.1.281"), .orderedAscending)
        XCTAssertEqual(ClaudeCodeDetector.compare("2.1.281", "2.1.281"), .orderedSame)
        XCTAssertEqual(ClaudeCodeDetector.compare("2.2.0", "2.1.999"), .orderedDescending)
        XCTAssertEqual(ClaudeCodeDetector.compare("3.0", "2.9.9"), .orderedDescending)
        XCTAssertEqual(ClaudeCodeDetector.compare("2.1.281-beta.1", "2.1.281"), .orderedSame)
        XCTAssertTrue(ClaudeCodeDetector.isSupported(ClaudeCodeDetector.minimumVersion))
        XCTAssertTrue(ClaudeCodeDetector.isSupported("2.1.289"))
        XCTAssertFalse(ClaudeCodeDetector.isSupported("2.1.277"))
        XCTAssertFalse(ClaudeCodeDetector.isSupported("2.1.185"), "sin `claude mcp login`")
    }

    func testReadyMeansFoundWithASessionOrWithoutKnowing() {
        XCTAssertTrue(ClaudeCodeStatus.found(version: "2.1.289", path: "/c", loggedIn: true).isReady)
        XCTAssertTrue(ClaudeCodeStatus.found(version: "2.1.289", path: "/c", loggedIn: nil).isReady)
        XCTAssertFalse(ClaudeCodeStatus.found(version: "2.1.289", path: "/c", loggedIn: false).isReady)
        XCTAssertFalse(ClaudeCodeStatus.notFound.isReady)
        XCTAssertFalse(ClaudeCodeStatus.checking.isReady)
    }

    func testParseVersion() {
        XCTAssertEqual(ClaudeCodeDetector.parseVersion("2.1.289 (Claude Code)\n"), "2.1.289")
        XCTAssertEqual(ClaudeCodeDetector.parseVersion("  2.1.0-beta.1 (Claude Code)"), "2.1.0-beta.1")
        XCTAssertNil(ClaudeCodeDetector.parseVersion("v2"))
        XCTAssertNil(ClaudeCodeDetector.parseVersion(""))
        XCTAssertNil(ClaudeCodeDetector.parseVersion("Claude Code 2.1.289"))
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
