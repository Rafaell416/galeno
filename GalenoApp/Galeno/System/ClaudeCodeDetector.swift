import Foundation

/// Lo que la pantalla 2 sabe de Claude Code (`docs/03` §3).
nonisolated enum ClaudeCodeStatus: Equatable, Sendable {
    /// Todavía no se ha mirado, o se está mirando.
    case checking
    /// Instalado. `loggedIn` es `nil` si no se pudo saber (una versión sin
    /// `claude auth status`): en ese caso no se avisa de nada.
    case found(version: String, path: String, loggedIn: Bool?)

    /// La versión encontrada, si la hay.
    var version: String? {
        switch self {
        case .found(let version, _, _), .outdated(let version, _): version
        default: nil
        }
    }
    /// Instalado, pero es una versión anterior a la mínima con la que Galeno sabe conectar
    /// (`ClaudeCodeDetector.minimumVersion`). No se sigue con ella: se actualiza.
    case outdated(version: String, path: String)
    case notFound

    var isFound: Bool {
        if case .found = self { return true }
        return false
    }

    /// Listo para seguir: instalado, al día y con sesión. Sin poder saber si hay sesión (`nil`) no se
    /// detiene a nadie.
    var isReady: Bool {
        if case .found(_, _, let loggedIn) = self { return loggedIn != false }
        return false
    }

    /// Dónde está `claude`, aunque esté desactualizado.
    var path: String? {
        switch self {
        case .found(_, let path, _), .outdated(_, let path): path
        case .checking, .notFound: nil
        }
    }
}

/// El resultado de un comando que terminó a tiempo.
nonisolated struct CommandResult: Sendable, Equatable {
    var status: Int32
    var output: String
}

/// Lanza un comando. Es lo único del detector que toca el sistema, así que las
/// pruebas lo reemplazan por uno falso.
nonisolated protocol CommandRunning: Sendable {
    /// `nil` si no se pudo lanzar o no terminó dentro de `timeout` segundos.
    ///
    /// `environment` se **añade** al entorno de la app. Es por donde viaja un secreto
    /// (`MCP_CLIENT_SECRET`): nunca por los argumentos, que cualquier proceso del usuario
    /// puede leer con `ps`.
    func run(
        _ executable: String, arguments: [String], environment: [String: String], timeout: TimeInterval
    ) async -> CommandResult?
}

extension CommandRunning {
    func run(_ executable: String, arguments: [String], timeout: TimeInterval) async -> CommandResult? {
        await run(executable, arguments: arguments, environment: [:], timeout: timeout)
    }
}

/// Busca `claude` y pregunta su versión y si hay sesión iniciada.
///
/// Una app que se abre desde Finder hereda un PATH mínimo (sin Homebrew ni
/// `~/.local/bin`), así que no sirve preguntar solo "¿está en el PATH?". Se
/// miran primero las rutas donde lo dejan los instaladores y, si no está ahí,
/// se le pregunta a un shell de login, que sí ve el PATH del usuario (npm, nvm).
///
/// El detector solo mira. Instalar, actualizar e iniciar sesión los hace `ClaudeCodeSetup`,
/// cuando el usuario lo pide (`docs/03` §3).
nonisolated struct ClaudeCodeDetector: Sendable {
    /// La versión más vieja de Claude Code con la que Galeno conecta. No es un gusto: por debajo, lo que
    /// Galeno usa no existe o miente (CHANGELOG de Claude Code):
    ///
    /// - `claude mcp login` aparece en la 2.1.186. Sin él no se autoriza ninguna herramienta («unknown
    ///   command 'login'», demo de Aquiles, 5 oct 2026).
    /// - Hasta la 2.1.281, `MCP_CONNECTION_NONBLOCKING=0` se rendía con los conectores de la cuenta al
    ///   segundo, sin respetar `MCP_CONNECT_TIMEOUT_MS`: el sondeo (`ClaudeSessionProbe`) los veía
    ///   `pending` aunque estuvieran bien.
    static let minimumVersion = "2.1.281"


    var runner: any CommandRunning = ProcessRunner()
    var homeDirectory: String = NSHomeDirectory()
    var isExecutable: @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }

    /// Dónde dejan `claude` el instalador nativo, Homebrew y la instalación local.
    var knownPaths: [String] {
        [
            "\(homeDirectory)/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(homeDirectory)/.claude/local/claude",
        ]
    }

    /// Un Mac puede tener varios `claude` (uno viejo de npm y el nativo, por ejemplo): se miran todos y
    /// se usa **el más nuevo**. Si ni ese llega a la versión mínima, está desactualizado.
    func detect() async -> ClaudeCodeStatus {
        var tried: Set<String> = []
        var best: (version: String, path: String)?
        func consider(_ path: String) async {
            guard tried.insert(path).inserted, let version = await version(at: path) else { return }
            if best == nil || Self.compare(version, best!.version) == .orderedDescending { best = (version, path) }
        }

        // Primero las rutas conocidas: son instantáneas. El shell de login es lo
        // lento (puede cargar un `.zshrc` pesado), así que solo se le pregunta si
        // ninguna de ellas dio un `claude` que sirva.
        for path in knownPaths.filter(isExecutable) { await consider(path) }
        if best.map({ !Self.isSupported($0.version) }) ?? true, let path = await pathFromLoginShell() {
            await consider(path)
        }

        guard let best else { return .notFound }
        guard Self.isSupported(best.version) else { return .outdated(version: best.version, path: best.path) }
        return .found(version: best.version, path: best.path, loggedIn: await loginState(at: best.path))
    }

    // MARK: Versiones

    static func isSupported(_ version: String) -> Bool {
        compare(version, minimumVersion) != .orderedAscending
    }

    /// Compara `2.1.90` con `2.1.281` por números, no por letras. Lo que siga a los tres números
    /// (`-beta.1`) no cuenta.
    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        func numbers(_ version: String) -> [Int] {
            let parts = version.split(separator: ".").prefix(3).map { part in
                Int(part.prefix { $0.isNumber }) ?? 0
            }
            return parts + Array(repeating: 0, count: max(0, 3 - parts.count))
        }
        for (x, y) in zip(numbers(a), numbers(b)) where x != y {
            return x < y ? .orderedAscending : .orderedDescending
        }
        return .orderedSame
    }

    // MARK: Pasos

    private func pathFromLoginShell() async -> String? {
        // `-i` además de `-l`: el PATH de nvm y de npm suele ponerse en `.zshrc`.
        guard
            let result = await runner.run(
                "/bin/zsh", arguments: ["-lic", "command -v claude"], timeout: 5),
            result.status == 0
        else { return nil }
        // Un `.zshrc` puede imprimir cosas: nos quedamos con la última línea que sea una ruta.
        return result.output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { $0.hasPrefix("/") && isExecutable($0) }
    }

    /// "2.1.277 (Claude Code)" → "2.1.277".
    private func version(at path: String) async -> String? {
        guard let result = await runner.run(path, arguments: ["--version"], timeout: 10),
            result.status == 0
        else { return nil }
        return Self.parseVersion(result.output)
    }

    /// Solo se lee si hay sesión. `claude auth status` también devuelve el
    /// correo de la cuenta: ese dato no se guarda, ni se muestra, ni se registra.
    private func loginState(at path: String) async -> Bool? {
        guard let result = await runner.run(path, arguments: ["auth", "status"], timeout: 10),
            let data = result.output.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let loggedIn = json["loggedIn"] as? Bool
        else { return nil }
        return loggedIn
    }

    static func parseVersion(_ output: String) -> String? {
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = text.range(of: #"^\d+\.\d+\.\d+[0-9A-Za-z.+-]*"#, options: .regularExpression)
        else { return nil }
        return String(text[range])
    }
}

extension ClaudeCodeDetector {
    /// El detector real. En Debug, el argumento de arranque `-galeno-claude-missing`
    /// finge que `claude` no está, para ver esa pantalla en un Mac que sí lo tiene. **Ojo:** sin
    /// `-galeno-fake-connect`, «Instalar» corre el instalador de verdad.
    static var live: ClaudeCodeDetector {
        #if DEBUG
        // Con conectores falsos, el Mac también es de mentira: el paso 2 se puede recorrer sin instalar nada.
        if ProcessInfo.processInfo.arguments.contains("-galeno-fake-connect") {
            return ScriptedClaudeMac.shared.detector
        }
        if ProcessInfo.processInfo.arguments.contains("-galeno-claude-missing") {
            return ClaudeCodeDetector(runner: NothingRunner(), isExecutable: { _ in false })
        }
        #endif
        return ClaudeCodeDetector()
    }
}

#if DEBUG
    private nonisolated struct NothingRunner: CommandRunning {
        func run(
            _ executable: String, arguments: [String], environment: [String: String], timeout: TimeInterval
        ) async -> CommandResult? { nil }
    }
#endif

// MARK: - Lanzar procesos

/// Corre un comando de verdad, con tiempo máximo.
///
/// La salida va a un archivo temporal y no a un `Pipe`: un `.zshrc` puede dejar
/// un proceso vivo que mantenga el pipe abierto, y leer hasta el final no
/// terminaría nunca. Con un archivo, basta con esperar a que muera el proceso.
nonisolated struct ProcessRunner: CommandRunning {
    func run(
        _ executable: String, arguments: [String], environment: [String: String], timeout: TimeInterval
    ) async -> CommandResult? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: Self.runBlocking(executable, arguments, environment, timeout))
            }
        }
    }

    private static func runBlocking(
        _ executable: String, _ arguments: [String], _ environment: [String: String], _ timeout: TimeInterval
    ) -> CommandResult? {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("galeno-\(UUID().uuidString).out")
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil),
            let sink = try? FileHandle(forWritingTo: outputURL)
        else { return nil }
        defer {
            try? sink.close()
            try? FileManager.default.removeItem(at: outputURL)
        }

        let job = Job()
        job.process.executableURL = URL(fileURLWithPath: executable)
        job.process.arguments = arguments
        // Un directorio neutro: así `claude` no carga el `CLAUDE.md` ni los ajustes
        // de la carpeta desde la que se haya abierto la app.
        job.process.currentDirectoryURL = FileManager.default.temporaryDirectory
        if !environment.isEmpty {
            job.process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }
        job.process.standardInput = FileHandle.nullDevice
        job.process.standardOutput = sink
        job.process.standardError = FileHandle.nullDevice

        do { try job.process.run() } catch { return nil }

        let watchdog = DispatchWorkItem { job.timeOut() }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        job.process.waitUntilExit()
        watchdog.cancel()

        guard !job.timedOut else { return nil }
        let data = (try? Data(contentsOf: outputURL)) ?? Data()
        return CommandResult(
            status: job.process.terminationStatus,
            output: String(decoding: data, as: UTF8.self))
    }

    /// El proceso y si se agotó el tiempo. Se comparte con el temporizador, que
    /// corre en otro hilo.
    private final class Job: @unchecked Sendable {
        let process = Process()
        private let lock = NSLock()
        private var expired = false

        var timedOut: Bool { lock.withLock { expired } }

        func timeOut() {
            lock.withLock { expired = true }
            // SIGKILL y no `terminate()`: un shell interactivo ignora SIGTERM.
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }
}
