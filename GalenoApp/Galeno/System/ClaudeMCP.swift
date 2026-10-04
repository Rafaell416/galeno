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
    /// Ya hay un servidor con ese nombre pero **otro** (otra dirección, o uno local de
    /// `npx`): registrar el nuestro encima lo pisaría, y darlo por conectado sería mentira.
    case differentServer
}

/// Cuántos elementos vio Claude Code al mirar un servidor recién conectado.
nonisolated struct ItemCount: Equatable, Sendable {
    var value: Int
    /// `true` si lo que devolvió el servidor era solo una primera página: "al menos N".
    var isPartial: Bool
}

nonisolated enum MCPConnectError: Error, Equatable, Sendable {
    /// El `client_id` no es válido para pasarlo como argumento.
    case invalidClientID
    case registerFailed(String)
    case removeFailed(String)
    case loginFailed(String)
    /// El usuario no autorizó a tiempo.
    case loginTimedOut
    /// El comando terminó bien pero el servidor sigue sin responder.
    case notConnectedAfterLogin
    case cancelled
}

/// Quien recibe la dirección de autorización que `claude` iba a abrir en el navegador. Devuelve
/// `true` si la mostró él (en la ventana de Galeno); si devuelve `false`, el cliente la abre en
/// el navegador del sistema, como haría `claude`.
typealias AuthorizationOpener = @MainActor @Sendable (URL) async -> Bool

/// Conecta servidores MCP hospedados con la CLI de `claude`. Las pruebas lo
/// reemplazan por uno falso.
nonisolated protocol MCPConnecting: Sendable {
    /// `expectingURL`: si el servidor existe pero apunta a otra dirección, `.differentServer`.
    func status(of server: String, expectingURL: String?) async -> MCPStatus
    /// `claude mcp add --transport http -s user <servidor> <url>`, y con una app OAuth propia
    /// `--client-id`, `--callback-port` y `--client-secret` (el secreto por el entorno).
    func register(server: String, url: String, oauth: OAuthClientRegistration?) async throws
    /// `claude mcp login <servidor>`: abre el navegador y espera la autorización. Con
    /// `openAuthorization`, la dirección de autorización va a ese cierre en vez de al navegador
    /// del sistema (se intercepta la variable `BROWSER` del proceso `claude`).
    func login(server: String, openAuthorization: AuthorizationOpener?) async throws
    /// `claude mcp remove <servidor> -s user`. **Solo** tras una confirmación explícita del
    /// usuario: borra la configuración de ese servidor para todos sus proyectos.
    func remove(server: String) async throws
    /// Un dato real ("12 canales") pidiéndole a Claude Code que mire el servidor.
    /// `nil` si no se pudo, por la razón que sea: nunca es un error para el usuario.
    func countItems(server: String, noun: String) async -> ItemCount?
    /// La línea `Issue:` de `claude mcp get`: por qué un servidor registrado no conecta (p. ej. una
    /// app de Slack sin el MCP activado). `nil` si no hay o no se pudo leer.
    func issue(of server: String) async -> String?
}

extension MCPConnecting {
    func login(server: String) async throws { try await login(server: server, openAuthorization: nil) }
    func issue(of server: String) async -> String? { nil }
    func status(of server: String) async -> MCPStatus { await status(of: server, expectingURL: nil) }
    func register(server: String, url: String) async throws {
        try await register(server: server, url: url, oauth: nil)
    }
}

/// Lanza un comando en un terminal. `claude mcp login` lo exige.
nonisolated protocol TerminalRunning: Sendable {
    /// `nil` si no se pudo lanzar. `environment` se suma al del proceso.
    func runInTerminal(
        _ executable: String, arguments: [String], environment: [String: String], timeout: TimeInterval
    ) async -> ManagedProcess.Result?
}

extension TerminalRunning {
    func runInTerminal(
        _ executable: String, arguments: [String], timeout: TimeInterval
    ) async -> ManagedProcess.Result? {
        await runInTerminal(executable, arguments: arguments, environment: [:], timeout: timeout)
    }
}

nonisolated struct ProcessTerminalRunner: TerminalRunning {
    func runInTerminal(
        _ executable: String, arguments: [String], environment: [String: String], timeout: TimeInterval
    ) async -> ManagedProcess.Result? {
        let process = ManagedProcess(
            executable: executable, arguments: arguments,
            environment: environment.isEmpty ? nil : environment, usesTerminal: true)
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

    func status(of server: String, expectingURL: String?) async -> MCPStatus {
        guard let result = await runner.run(claudePath, arguments: ["mcp", "get", server], timeout: 30)
        else { return .failed }
        let status = Self.parseStatus(result.output, exitStatus: result.status)
        // Un servidor que existe pero apunta a otra cosa no es el nuestro.
        if let expectingURL, status != .notRegistered, Self.hasStatusLine(result.output),
            !Self.sameURL(Self.parseURL(result.output), expectingURL)
        {
            return .differentServer
        }
        return status
    }

    func register(server: String, url: String, oauth: OAuthClientRegistration?) async throws {
        var arguments = ["mcp", "add", "--transport", "http", "-s", "user", server, url]
        var environment: [String: String] = [:]

        if let oauth {
            guard OAuthClientRegistration.isValidClientID(oauth.clientID) else {
                throw MCPConnectError.invalidClientID
            }
            arguments += ["--client-id", oauth.clientID]
            if let port = oauth.callbackPort { arguments += ["--callback-port", String(port)] }
            // El secreto va por el entorno (`MCP_CLIENT_SECRET`), nunca en los argumentos: con
            // `--client-secret` solo, Claude Code lo toma de ahí en vez de preguntarlo.
            if let secret = oauth.secret, !secret.isEmpty {
                arguments.append("--client-secret")
                secret.withValue { environment["MCP_CLIENT_SECRET"] = $0 }
            }
        }

        guard
            let result = await runner.run(
                claudePath, arguments: arguments, environment: environment, timeout: 30)
        else { throw MCPConnectError.registerFailed("no respondió") }
        guard result.status == 0 else { throw MCPConnectError.registerFailed(Self.tail(result.output)) }
    }

    func remove(server: String) async throws {
        guard
            let result = await runner.run(
                claudePath, arguments: ["mcp", "remove", server, "-s", "user"], timeout: 30)
        else { throw MCPConnectError.removeFailed("no respondió") }
        guard result.status == 0 else { throw MCPConnectError.removeFailed(Self.tail(result.output)) }
    }

    func login(server: String, openAuthorization: AuthorizationOpener?) async throws {
        // `claude` abre la autorización con `$BROWSER` si existe. Se le da un «navegador» que solo
        // escribe la dirección en un archivo privado; Galeno la recoge y decide dónde mostrarla.
        var environment: [String: String] = [:]
        var interceptor: BrowserInterceptor?
        if openAuthorization != nil, let made = BrowserInterceptor() {
            interceptor = made
            environment["BROWSER"] = made.scriptPath
        }
        defer { interceptor?.cleanUp() }

        let watcher: Task<Void, Never>? = {
            guard let interceptor, let openAuthorization else { return nil }
            let runner = self.runner
            return Task {
                guard let url = await interceptor.waitForURL() else { return }
                if await openAuthorization(url) { return }
                _ = await runner.run("/usr/bin/open", arguments: [url.absoluteString], timeout: 10)
            }
        }()
        defer { watcher?.cancel() }

        guard
            let result = await terminal.runInTerminal(
                claudePath, arguments: ["mcp", "login", server], environment: environment,
                timeout: loginTimeout)
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

    func issue(of server: String) async -> String? {
        guard let result = await runner.run(claudePath, arguments: ["mcp", "get", server], timeout: 30)
        else { return nil }
        return Self.parseIssue(result.output)
    }

    /// `Issue: HTTP 400: …` → el texto después de `Issue:`.
    static func parseIssue(_ output: String) -> String? {
        output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.lowercased().hasPrefix("issue:") }
            .map { String($0.dropFirst(6)).trimmingCharacters(in: .whitespaces) }
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

    /// La línea `URL:` de `claude mcp get`, o `nil` si no la hay (un servidor local no la tiene).
    static func parseURL(_ output: String) -> String? {
        output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.lowercased().hasPrefix("url:") }
            .map { String($0.dropFirst(4)).trimmingCharacters(in: .whitespaces) }
    }

    static func hasStatusLine(_ output: String) -> Bool {
        output.split(whereSeparator: \.isNewline)
            .contains { $0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("status:") }
    }

    /// Dos direcciones son la misma si solo cambia una barra final.
    static func sameURL(_ found: String?, _ expected: String) -> Bool {
        guard let found else { return false }
        func normalized(_ url: String) -> String { url.hasSuffix("/") ? String(url.dropLast()) : url }
        return normalized(found) == normalized(expected)
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

/// El «navegador» que se le da a `claude`: un script que escribe la dirección que recibe en un
/// archivo dentro de una carpeta privada (`$TMPDIR` es del usuario, y la carpeta es 0700). Sirve
/// para que Galeno muestre la autorización donde quiera, y se borra al terminar.
nonisolated final class BrowserInterceptor: @unchecked Sendable {
    private let directory: URL
    private let urlFile: URL
    let scriptPath: String

    init?() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("galeno-oauth-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            let script = directory.appendingPathComponent("open-url.sh")
            let hidden = directory.appendingPathComponent(".url").path
            let final = directory.appendingPathComponent("url").path
            // Se escribe aparte y se renombra: el lector nunca ve una dirección a medias.
            let body = "#!/bin/sh\nprintf '%s' \"$1\" > '\(hidden)' && mv '\(hidden)' '\(final)'\n"
            try body.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            self.directory = directory
            self.urlFile = directory.appendingPathComponent("url")
            self.scriptPath = script.path
        } catch {
            try? FileManager.default.removeItem(at: directory)
            return nil
        }
    }

    /// Espera a que `claude` llame al «navegador». `nil` si se cancela antes. Solo vale `https`.
    func waitForURL() async -> URL? {
        while !Task.isCancelled {
            if let text = try? String(contentsOf: urlFile, encoding: .utf8),
                let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
                url.scheme?.lowercased() == "https"
            {
                return url
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    func cleanUp() { try? FileManager.default.removeItem(at: directory) }
}
