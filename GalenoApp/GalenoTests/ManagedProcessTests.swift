import XCTest

@testable import Galeno

/// Procesos de verdad (`/bin/sh`, `/bin/sleep`): el supervisor es lo único de la capa de
/// procesos que no se puede probar con un falso sin dejar de probar lo importante.
final class ManagedProcessTests: XCTestCase {
    func testCapturesStdoutAndStderrTogether() async throws {
        let process = ManagedProcess(executable: "/bin/sh", arguments: ["-c", "echo uno; echo dos 1>&2"])
        try process.start()

        let result = await process.wait(timeout: 5)

        XCTAssertTrue(result.succeeded)
        XCTAssertTrue(result.output.contains("uno"))
        XCTAssertTrue(result.output.contains("dos"), "stderr también: es donde un programa dice por qué falló")
    }

    func testReportsAFailingStatus() async throws {
        let process = ManagedProcess(executable: "/bin/sh", arguments: ["-c", "exit 3"])
        try process.start()

        let result = await process.wait(timeout: 5)

        XCTAssertEqual(result.status, 3)
        XCTAssertFalse(result.succeeded)
        XCTAssertFalse(result.wasStopped)
    }

    func testTheOutputIsReadableWhileItRuns() async throws {
        let process = ManagedProcess(executable: "/bin/sh", arguments: ["-c", "echo hola; sleep 30"])
        try process.start()
        defer { process.killNow() }

        var seen = false
        for _ in 0..<100 where !seen {
            seen = process.output.contains("hola")
            if !seen { try await Task.sleep(for: .milliseconds(20)) }
        }

        XCTAssertTrue(seen, "el QR y el estado se leen sin esperar a que termine")
        XCTAssertTrue(process.isRunning)
    }

    func testStopEndsAProcessThatWouldNeverFinish() async throws {
        let process = ManagedProcess(executable: "/bin/sleep", arguments: ["30"])
        try process.start()
        let start = Date()

        process.stop()
        let result = await process.wait()

        XCTAssertTrue(result.wasStopped)
        XCTAssertFalse(result.succeeded)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    func testTheTimeoutStopsTheProcess() async throws {
        let process = ManagedProcess(executable: "/bin/sleep", arguments: ["30"])
        try process.start()

        let result = await process.wait(timeout: 0.3)

        XCTAssertTrue(result.wasStopped)
    }

    func testCancellingTheTaskStopsTheProcess() async throws {
        let process = ManagedProcess(executable: "/bin/sleep", arguments: ["30"])
        try process.start()

        let task = Task { await process.wait() }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        let result = await task.value

        XCTAssertTrue(result.wasStopped)
    }

    func testAMissingExecutableFailsToStart() {
        let process = ManagedProcess(executable: "/no/existe", arguments: [])

        XCTAssertThrowsError(try process.start())
    }

    // MARK: - Terminal

    /// `claude mcp login` se niega a correr sin terminal: "stdin isn't a terminal".
    func testWithATerminalTheChildSeesOne() async throws {
        let process = ManagedProcess(
            executable: "/bin/sh", arguments: ["-c", "if [ -t 0 ] && [ -t 1 ]; then echo conterminal; else echo sinterminal; fi"],
            usesTerminal: true)
        try process.start()

        let result = await process.wait(timeout: 5)

        XCTAssertTrue(result.output.contains("conterminal"), result.output)
        XCTAssertFalse(result.output.contains("sinterminal"))
    }

    func testWithoutATerminalTheChildDoesNotSeeOne() async throws {
        let process = ManagedProcess(
            executable: "/bin/sh", arguments: ["-c", "if [ -t 0 ]; then echo conterminal; else echo sinterminal; fi"])
        try process.start()

        let result = await process.wait(timeout: 5)

        XCTAssertTrue(result.output.contains("sinterminal"), result.output)
    }

    func testTheTerminalOutputIsCompleteWhenTheChildExits() async throws {
        let process = ManagedProcess(
            executable: "/bin/sh", arguments: ["-c", "for i in 1 2 3 4 5; do echo linea$i; done"], usesTerminal: true)
        try process.start()

        let result = await process.wait(timeout: 5)

        for i in 1...5 { XCTAssertTrue(result.output.contains("linea\(i)"), "falta linea\(i): \(result.output)") }
    }

    func testStopEndsATerminalProcessToo() async throws {
        let process = ManagedProcess(executable: "/bin/sleep", arguments: ["30"], usesTerminal: true)
        try process.start()

        process.stop()
        let result = await process.wait()

        XCTAssertTrue(result.wasStopped)
    }

    func testTerminalCodesAreStrippedFromWhatTheUserWouldSee() {
        // Salida real de `claude mcp login`: hipervínculo OSC 8, movimiento del cursor y CRs.
        let raw = "Starting authentication\r\nIf the browser didn't open, visit:\r\n"
            + "  \u{1B}]8;;https://mcp.notion.com/authorize?x=1\u{07}https://mcp.notion.com/authorize?x=1\u{1B}]8;;\u{07}\r\n"
            + "\u{1B}[1G\u{1B}[0JOr paste the redirect URL here: \u{1B}[33G\r\n"
            + "Authenticated with \"galeno-prueba\".\r\n\u{1B}[?25h"

        let clean = ManagedProcess.stripTerminalCodes(raw)

        XCTAssertFalse(clean.contains("\u{1B}"))
        XCTAssertFalse(clean.contains("\r"))
        XCTAssertTrue(clean.contains("Authenticated with \"galeno-prueba\"."))
        XCTAssertTrue(clean.contains("https://mcp.notion.com/authorize?x=1"))
    }

    // MARK: - El registro

    func testTheRegistryTracksLiveProcessesAndKillsThemAll() async throws {
        let registry = ProcessRegistry.shared
        let before = registry.count
        let first = ManagedProcess(executable: "/bin/sleep", arguments: ["30"])
        let second = ManagedProcess(executable: "/bin/sleep", arguments: ["30"], usesTerminal: true)
        try first.start()
        try second.start()
        XCTAssertEqual(registry.count, before + 2)

        registry.killAll()
        async let a = first.wait(timeout: 5)
        async let b = second.wait(timeout: 5)
        let results = await [a, b]

        XCTAssertTrue(results.allSatisfy { $0.wasStopped })
        XCTAssertEqual(registry.count, before, "al terminar, no queda ninguno registrado")
        XCTAssertFalse(first.isRunning)
        XCTAssertFalse(second.isRunning)
    }
}
