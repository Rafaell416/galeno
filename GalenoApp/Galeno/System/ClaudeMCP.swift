import Foundation

/// El estado de un servidor MCP según `claude mcp get`.
nonisolated enum MCPStatus: Equatable, Sendable {
    case connected
    /// Registrado, pero falta que el usuario autorice (OAuth).
    case needsAuthentication
    /// Registrado, pero no responde.
    case failed
    /// Claude Code no lo conoce.
    case notRegistered
}

/// Cuántos elementos vio Claude Code al mirar un servidor recién conectado.
nonisolated struct ItemCount: Equatable, Sendable {
    var value: Int
    /// `true` si lo que devolvió el servidor era solo una primera página: "al menos N".
    var isPartial: Bool
}

nonisolated enum MCPConnectError: Error, Equatable, Sendable {
    case registerFailed(String)
    case loginFailed(String)
    /// El usuario no autorizó a tiempo.
    case loginTimedOut
    /// El comando terminó bien pero el servidor sigue sin responder.
    case notConnectedAfterLogin
    case cancelled
}

/// Conecta servidores MCP hospedados con la CLI de `claude`. Las pruebas lo
/// reemplazan por uno falso.
nonisolated protocol MCPConnecting: Sendable {
    func status(of server: String) async -> MCPStatus
    /// `claude mcp add --transport http -s user <servidor> <url>`.
    func register(server: String, url: String) async throws
    /// `claude mcp login <servidor>`: abre el navegador y espera la autorización.
    func login(server: String) async throws
    /// Un dato real ("12 canales") pidiéndole a Claude Code que mire el servidor.
    /// `nil` si no se pudo, por la razón que sea: nunca es un error para el usuario.
    func countItems(server: String, noun: String) async -> ItemCount?
}

/// Lanza un comando en un terminal. `claude mcp login` lo exige.
nonisolated protocol TerminalRunning: Sendable {
    /// `nil` si no se pudo lanzar.
    func runInTerminal(
        _ executable: String, arguments: [String], timeout: TimeInterval
    ) async -> ManagedProcess.Result?
}

nonisolated struct ProcessTerminalRunner: TerminalRunning {
    func runInTerminal(
        _ executable: String, arguments: [String], timeout: TimeInterval
    ) async -> ManagedProcess.Result? {
        let process = ManagedProcess(executable: executable, arguments: arguments, usesTerminal: true)
        do { try process.start() } catch { return nil }
        return await process.wait(timeout: timeout)
    }
}

nonisolated struct ClaudeMCPClient: MCPConnecting {
    /// La ruta a `claude` que encontró el paso 2 (`ClaudeCodeStatus.found`).
    var claudePath: String
    var runner: any CommandRunning = ProcessRunner()
    var terminal: any TerminalRunning = ProcessTerminalRunner()

    /// Cuánto se espera a que el usuario autorice en el navegador.
    var loginTimeout: TimeInterval = 180
    var countTimeout: TimeInterval = 60
    /// Tope de gasto de cada consulta del dato real. Una búsqueda en Notion
    /// llegó a costar ~$0,06 y una respuesta grande puede pasar de $0,10 y
    /// quedar sin resultado, así que el tope es holgado.
    var countBudgetUSD = "0.15"

    func status(of server: String) async -> MCPStatus {
        guard let result = await runner.run(claudePath, arguments: ["mcp", "get", server], timeout: 30)
        else { return .failed }
        return Self.parseStatus(result.output, exitStatus: result.status)
    }

    func register(server: String, url: String) async throws {
        let arguments = ["mcp", "add", "--transport", "http", "-s", "user", server, url]
        guard let result = await runner.run(claudePath, arguments: arguments, timeout: 30) else {
            throw MCPConnectError.registerFailed("no respondió")
        }
        guard result.status == 0 else { throw MCPConnectError.registerFailed(Self.tail(result.output)) }
    }

    func login(server: String) async throws {
        guard
            let result = await terminal.runInTerminal(
                claudePath, arguments: ["mcp", "login", server], timeout: loginTimeout)
        else { throw MCPConnectError.loginFailed("no se pudo lanzar") }

        if result.wasStopped {
            throw Task.isCancelled ? MCPConnectError.cancelled : MCPConnectError.loginTimedOut
        }
        guard result.status == 0 else { throw MCPConnectError.loginFailed(Self.tail(result.output)) }
        // `login` imprime "Authenticated with …" al terminar bien: con eso no hace falta otro
        // `get` (4 s). Si no lo imprime, se confirma el estado por si acaso.
        if ManagedProcess.stripTerminalCodes(result.output).contains("Authenticated with") { return }
        guard await status(of: server) == .connected else { throw MCPConnectError.notConnectedAfterLogin }
    }

    func countItems(server: String, noun: String) async -> ItemCount? {
        let prompt =
            "Using only the tools of the MCP server named \(server), count how many \(noun) you can "
            + "list (use its listing or search tool). Reply with ONLY an integer; if the tool "
            + "returned only a first page or a capped list, append a plus sign. No other text."
        let arguments = [
            "-p", prompt,
            "--allowedTools", "mcp__\(server)__*",
            "--model", "haiku",
            "--output-format", "json",
            "--no-session-persistence",
            "--max-budget-usd", countBudgetUSD,
            "--max-turns", "5",
        ]
        guard let result = await runner.run(claudePath, arguments: arguments, timeout: countTimeout),
            result.status == 0
        else { return nil }
        return Self.parseCount(jsonOutput: result.output)
    }

    // MARK: - Lectura de la salida de `claude`

    /// `claude mcp get` imprime `Status: ✔ Connected`, `Status: ! Needs authentication` o
    /// `Status: ✘ Failed to connect`, y sale con 0 en todos esos casos: el estado se lee del
    /// texto. Si el servidor **no existe** sale con 1 y escribe `No MCP server named "x"` por
    /// **stderr**, que el ejecutor descarta: por eso también se mira el código de salida (sin
    /// línea `Status:` y con error, es que no está registrado).
    static func parseStatus(_ output: String, exitStatus: Int32 = 0) -> MCPStatus {
        let lower = output.lowercased()
        if lower.contains("no mcp server named") || lower.contains("no mcp server found") {
            return .notRegistered
        }
        guard
            let line = output.split(whereSeparator: \.isNewline)
                .map({ $0.trimmingCharacters(in: .whitespaces) })
                .first(where: { $0.lowercased().hasPrefix("status:") })?.lowercased()
        else { return exitStatus == 0 ? .failed : .notRegistered }
        if line.contains("needs authentication") { return .needsAuthentication }
        if line.contains("failed") { return .failed }
        if line.contains("connected") { return .connected }
        return .failed
    }

    /// `{"result": "10+", "is_error": false, …}` → 10, parcial. Todo lo que no sea
    /// un entero (con un `+` opcional) se descarta: nunca se muestra un número inventado.
    static func parseCount(jsonOutput: String) -> ItemCount? {
        guard let data = jsonOutput.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            (json["is_error"] as? Bool) != true,
            let text = (json["result"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            text.range(of: #"^\d{1,6}\+?$"#, options: .regularExpression) != nil,
            let value = Int(text.dropLast(text.hasSuffix("+") ? 1 : 0))
        else { return nil }
        return ItemCount(value: value, isPartial: text.hasSuffix("+"))
    }

    /// Las últimas líneas de una salida, para un mensaje de error.
    private static func tail(_ output: String) -> String {
        let lines = ManagedProcess.stripTerminalCodes(output)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.suffix(2).joined(separator: " ")
    }
}
