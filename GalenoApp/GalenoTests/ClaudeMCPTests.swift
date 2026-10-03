import XCTest

@testable import Galeno

/// Un terminal falso: devuelve lo que se le diga y anota el comando.
private final class FakeTerminal: TerminalRunning, @unchecked Sendable {
    private let result: ManagedProcess.Result?
    private let lock = NSLock()
    private var recorded: [String] = []

    init(_ result: ManagedProcess.Result?) { self.result = result }

    var calls: [String] { lock.withLock { recorded } }

    func runInTerminal(_ executable: String, arguments: [String], timeout: TimeInterval) async -> ManagedProcess.Result? {
        lock.withLock { recorded.append(([executable] + arguments).joined(separator: " ")) }
        return result
    }
}

final class ClaudeMCPTests: XCTestCase {
    private let claude = "/opt/homebrew/bin/claude"

    // MARK: - El estado (`claude mcp get`)

    func testParsesTheRealOutputsOfClaudeMcpGet() {
        let connected = """
            galeno-prueba:
              Scope: User config (available in all your projects)
              Status: ✔ Connected
              Type: http
              URL: https://mcp.notion.com/mcp
            """
        let needsAuth = connected.replacingOccurrences(of: "✔ Connected", with: "! Needs authentication")
        let failed = connected.replacingOccurrences(of: "✔ Connected", with: "✘ Failed to connect")

        XCTAssertEqual(ClaudeMCPClient.parseStatus(connected), .connected)
        XCTAssertEqual(ClaudeMCPClient.parseStatus(needsAuth), .needsAuthentication)
        XCTAssertEqual(ClaudeMCPClient.parseStatus(failed), .failed)
    }

    func testAServerClaudeDoesNotKnowIsNotRegistered() {
        // El mensaje real de Claude Code 2.1.277, que sale por stderr.
        let real = "No MCP server named \"notion\". Configured servers: claude.ai Notion, github, slack"

        XCTAssertEqual(ClaudeMCPClient.parseStatus(real, exitStatus: 1), .notRegistered)
        XCTAssertEqual(ClaudeMCPClient.parseStatus("No MCP server found with name: x"), .notRegistered)
    }

    /// El ejecutor descarta stderr, así que de un servidor que no existe solo llega el código
    /// de salida (1) y una salida vacía. Esto fue un defecto real: la app lo tomaba por "falló",
    /// se saltaba el registro y `login` respondía "No MCP server named notion".
    func testAnEmptyOutputWithAnErrorExitMeansNotRegistered() async {
        let runner = FakeRunner(["\(claude) mcp get notion": CommandResult(status: 1, output: "")])
        let client = ClaudeMCPClient(claudePath: claude, runner: runner, terminal: FakeTerminal(nil))

        let status = await client.status(of: "notion")

        XCTAssertEqual(status, .notRegistered)
        XCTAssertEqual(ClaudeMCPClient.parseStatus("", exitStatus: 0), .failed, "vacío pero con éxito sigue siendo un fallo")
    }

    func testAServerThatExistsNeverLooksUnregisteredBecauseOfItsStatusLine() {
        let output = "notion:\n  Status: ✘ Failed to connect\n"

        XCTAssertEqual(ClaudeMCPClient.parseStatus(output, exitStatus: 1), .failed)
    }

    func testGarbageIsNeverMistakenForConnected() {
        XCTAssertEqual(ClaudeMCPClient.parseStatus(""), .failed)
        XCTAssertEqual(ClaudeMCPClient.parseStatus("Connected"), .failed, "sin la línea Status: no se da por conectado")
        XCTAssertEqual(ClaudeMCPClient.parseStatus("Status: ?"), .failed)
    }

    func testStatusAsksClaudeAboutThatServerOnly() async {
        let runner = FakeRunner(["\(claude) mcp get notion": ok("notion:\n  Status: ✔ Connected\n")])
        let client = ClaudeMCPClient(claudePath: claude, runner: runner, terminal: FakeTerminal(nil))

        let status = await client.status(of: "notion")

        XCTAssertEqual(status, .connected)
        XCTAssertEqual(runner.calls, ["\(claude) mcp get notion"])
    }

    func testStatusIsFailedWhenClaudeDoesNotAnswer() async {
        let client = ClaudeMCPClient(claudePath: claude, runner: FakeRunner([:]), terminal: FakeTerminal(nil))

        let status = await client.status(of: "notion")

        XCTAssertEqual(status, .failed)
    }

    // MARK: - Registrar

    func testRegisterUsesUserScopeSoAgentsShareTheConnection() async throws {
        let expected = "\(claude) mcp add --transport http -s user notion https://mcp.notion.com/mcp"
        let runner = FakeRunner([expected: ok("Added HTTP MCP server")])
        let client = ClaudeMCPClient(claudePath: claude, runner: runner, terminal: FakeTerminal(nil))

        try await client.register(server: "notion", url: "https://mcp.notion.com/mcp")

        XCTAssertEqual(runner.calls, [expected])
    }

    func testRegisterFailureCarriesTheLastLinesOfTheMessage() async {
        let command = "\(claude) mcp add --transport http -s user notion https://x"
        let runner = FakeRunner([command: CommandResult(status: 1, output: "linea 1\nError: ya existe\n")])
        let client = ClaudeMCPClient(claudePath: claude, runner: runner, terminal: FakeTerminal(nil))

        do {
            try await client.register(server: "notion", url: "https://x")
            XCTFail("debía fallar")
        } catch let error as MCPConnectError {
            XCTAssertEqual(error, .registerFailed("linea 1 Error: ya existe"))
        } catch {
            XCTFail("\(error)")
        }
    }

    func testNoSecretsTravelInTheArguments() async throws {
        // `--client-secret` se entrega por la variable MCP_CLIENT_SECRET, nunca en argumentos
        // (AGENTS.md). En este paso ninguna herramienta lleva secreto: se comprueba que no hay
        // forma de pasarlo por aquí.
        let runner = FakeRunner([:])
        let client = ClaudeMCPClient(claudePath: claude, runner: runner, terminal: FakeTerminal(nil))

        _ = try? await client.register(server: "notion", url: "https://mcp.notion.com/mcp")

        XCTAssertFalse(runner.calls.joined().contains("--client-secret"))
        XCTAssertFalse(runner.calls.joined().contains("--client-id"))
    }

    // MARK: - Autorizar

    func testLoginRunsInATerminalAndConfirmsTheServerIsConnected() async throws {
        let terminal = FakeTerminal(ManagedProcess.Result(status: 0, output: "Authenticated with \"notion\".", wasStopped: false))
        let runner = FakeRunner(["\(claude) mcp get notion": ok("notion:\n  Status: ✔ Connected\n")])
        let client = ClaudeMCPClient(claudePath: claude, runner: runner, terminal: terminal)

        try await client.login(server: "notion")

        XCTAssertEqual(terminal.calls, ["\(claude) mcp login notion"])
        XCTAssertEqual(runner.calls, ["\(claude) mcp get notion"], "se confirma con `get`, no se confía solo en la salida")
    }

    func testLoginThatTimesOutIsReportedAsSuch() async {
        let terminal = FakeTerminal(ManagedProcess.Result(status: 15, output: "", wasStopped: true))
        let client = ClaudeMCPClient(claudePath: claude, runner: FakeRunner([:]), terminal: terminal)

        await assertLoginThrows(client, .loginTimedOut)
    }

    func testLoginThatExitsWithAnErrorKeepsTheMessage() async {
        let terminal = FakeTerminal(ManagedProcess.Result(
            status: 1, output: "Couldn't complete authentication\r\n\u{1B}[?25h", wasStopped: false))
        let client = ClaudeMCPClient(claudePath: claude, runner: FakeRunner([:]), terminal: terminal)

        await assertLoginThrows(client, .loginFailed("Couldn't complete authentication"))
    }

    func testLoginThatCannotLaunchFails() async {
        let client = ClaudeMCPClient(claudePath: claude, runner: FakeRunner([:]), terminal: FakeTerminal(nil))

        await assertLoginThrows(client, .loginFailed("no se pudo lanzar"))
    }

    func testLoginThatSucceedsButLeavesTheServerUnreachableIsNotConnected() async {
        let terminal = FakeTerminal(ManagedProcess.Result(status: 0, output: "Authenticated", wasStopped: false))
        let runner = FakeRunner(["\(claude) mcp get notion": ok("notion:\n  Status: ✘ Failed to connect\n")])
        let client = ClaudeMCPClient(claudePath: claude, runner: runner, terminal: terminal)

        await assertLoginThrows(client, .notConnectedAfterLogin)
    }

    private func assertLoginThrows(
        _ client: ClaudeMCPClient, _ expected: MCPConnectError, line: UInt = #line
    ) async {
        do {
            try await client.login(server: "notion")
            XCTFail("debía fallar", line: line)
        } catch let error as MCPConnectError {
            XCTAssertEqual(error, expected, line: line)
        } catch {
            XCTFail("\(error)", line: line)
        }
    }

    // MARK: - El dato real

    func testParseCountAcceptsAnIntegerWithAnOptionalPlus() {
        XCTAssertEqual(ClaudeMCPClient.parseCount(jsonOutput: #"{"result":"12","is_error":false}"#), ItemCount(value: 12, isPartial: false))
        XCTAssertEqual(ClaudeMCPClient.parseCount(jsonOutput: #"{"result":"10+","is_error":false}"#), ItemCount(value: 10, isPartial: true))
        XCTAssertEqual(ClaudeMCPClient.parseCount(jsonOutput: #"{"result":" 7\n"}"#), ItemCount(value: 7, isPartial: false))
        XCTAssertEqual(ClaudeMCPClient.parseCount(jsonOutput: #"{"result":"0"}"#), ItemCount(value: 0, isPartial: false))
    }

    /// Nunca se muestra un número que el modelo no dio como número.
    func testParseCountRejectsAnythingElse() {
        for result in ["about 12", "12 channels", "", "twelve", "-3", "1.5", "12+3", "1234567", "I could not access the tools."] {
            let json = #"{"result":"\#(result)","is_error":false}"#
            XCTAssertNil(ClaudeMCPClient.parseCount(jsonOutput: json), result)
        }
        XCTAssertNil(ClaudeMCPClient.parseCount(jsonOutput: #"{"result":"12","is_error":true}"#))
        XCTAssertNil(ClaudeMCPClient.parseCount(jsonOutput: #"{"is_error":false}"#))
        XCTAssertNil(ClaudeMCPClient.parseCount(jsonOutput: "no es json"))
        XCTAssertNil(ClaudeMCPClient.parseCount(jsonOutput: ""))
    }

    func testCountItemsAsksClaudeToLookOnlyAtThatServerWithABudget() async throws {
        let runner = RecordingRunner(result: ok(#"{"result":"12","is_error":false}"#))
        let client = ClaudeMCPClient(claudePath: claude, runner: runner, terminal: FakeTerminal(nil))

        let count = await client.countItems(server: "slack", noun: "channels")

        XCTAssertEqual(count, ItemCount(value: 12, isPartial: false))
        let arguments = try XCTUnwrap(runner.lastArguments)
        XCTAssertEqual(arguments.first, "-p")
        XCTAssertTrue(arguments[1].contains("slack"))
        XCTAssertTrue(arguments[1].contains("channels"))
        XCTAssertEqual(value(after: "--allowedTools", in: arguments), "mcp__slack__*", "solo ese servidor")
        XCTAssertEqual(value(after: "--model", in: arguments), "haiku")
        XCTAssertEqual(value(after: "--output-format", in: arguments), "json")
        XCTAssertNotNil(value(after: "--max-budget-usd", in: arguments), "con tope de gasto")
        XCTAssertTrue(arguments.contains("--no-session-persistence"), "no deja una sesión en el historial del usuario")
        XCTAssertFalse(arguments.contains("--bare"), "--bare no lee el llavero y no está autenticado")
    }

    func testCountItemsIsNilWhenClaudeFailsOrTimesOut() async {
        let failing = ClaudeMCPClient(
            claudePath: claude, runner: RecordingRunner(result: CommandResult(status: 1, output: "x")), terminal: FakeTerminal(nil))
        let silent = ClaudeMCPClient(claudePath: claude, runner: RecordingRunner(result: nil), terminal: FakeTerminal(nil))

        let first = await failing.countItems(server: "slack", noun: "channels")
        let second = await silent.countItems(server: "slack", noun: "channels")

        XCTAssertNil(first)
        XCTAssertNil(second)
    }

    private func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}

/// Anota los argumentos del último comando y devuelve siempre lo mismo.
private final class RecordingRunner: CommandRunning, @unchecked Sendable {
    private let result: CommandResult?
    private let lock = NSLock()
    private var arguments: [String]?

    init(result: CommandResult?) { self.result = result }

    var lastArguments: [String]? { lock.withLock { arguments } }

    func run(_ executable: String, arguments: [String], timeout: TimeInterval) async -> CommandResult? {
        lock.withLock { self.arguments = arguments }
        return result
    }
}
