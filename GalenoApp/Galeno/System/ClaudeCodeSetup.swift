import Foundation

/// Cómo terminó algo que Galeno hizo por el usuario para dejar Claude Code listo.
nonisolated enum ClaudeSetupOutcome: Equatable, Sendable {
    case done
    /// No hubo red para descargar.
    case offline
    case timedOut
    case cancelled
    /// Falló. El texto son las últimas líneas del programa que falló, para el detalle.
    case failed(String)
}

/// Lo que el paso 2 está haciendo ahora por el usuario.
nonisolated enum ClaudeSetupPhase: Equatable, Sendable {
    case idle
    /// Instalando o actualizando: es el mismo instalador.
    case installing
    /// El navegador está abierto y se espera a que el usuario entre con su cuenta.
    case signingIn
    case failed(ClaudeSetupFailure)

    var isWorking: Bool { self == .installing || self == .signingIn }
}

nonisolated enum ClaudeSetupFailure: Equatable, Sendable {
    /// No hubo red para descargar el instalador o Claude Code.
    case offline
    case installTimedOut
    /// El instalador falló, o terminó y sigue sin haber un Claude Code que sirva.
    case installFailed(detail: String)
    /// Pasó el tiempo sin que el usuario terminara de entrar en el navegador.
    case signInTimedOut
    /// `claude auth login` falló, o terminó y sigue sin haber sesión.
    case signInFailed(detail: String)

    var detail: String {
        switch self {
        case .installFailed(let detail), .signInFailed(let detail): detail
        case .offline, .installTimedOut, .signInTimedOut: ""
        }
    }
}

/// Lo que Galeno hace por el usuario en el paso 2: instalar (o actualizar) Claude Code e iniciar su sesión.
/// Las pruebas lo reemplazan por uno falso: el de verdad descarga y ejecuta.
nonisolated protocol ClaudeCodeSettingUp: Sendable {
    /// Instala la última versión. Sirve igual para actualizar: el instalador deja la nueva en
    /// `~/.local/bin/claude`, y el detector usa la más nueva que encuentre.
    func install() async -> ClaudeSetupOutcome
    /// `claude auth login`: abre el navegador y espera a que el usuario entre con su cuenta.
    func signIn(claudePath: String) async -> ClaudeSetupOutcome
}

/// El de verdad.
///
/// **Decisión de Rafa (5 oct 2026):** Galeno corre estos comandos en vez de mostrárselos al usuario, que no
/// sabe qué es una Terminal (demo de Aquiles). Es la **única** vez que la app ejecuta un script remoto, y con
/// estos límites, que no se relajan sin preguntar:
///
/// - Solo el instalador oficial de Anthropic (`installerURL`), fijo en el código: nunca una dirección que
///   venga de un archivo, de la red ni del usuario.
/// - Solo por `https` (`--proto '=https'`), sin `sudo`: instala en la carpeta del usuario.
/// - Solo cuando el usuario pulsa «Instalar» o «Actualizar». Nada se instala al abrir la app.
/// - El inicio de sesión ocurre en el navegador del usuario: Galeno no ve la cuenta ni la contraseña, y no
///   guarda ni muestra lo que `claude` imprima (su salida trae la dirección de autorización).
nonisolated struct ClaudeCodeSetup: ClaudeCodeSettingUp {
    var terminal: any TerminalRunning = ProcessTerminalRunner()
    /// Descarga unos 200 MB: con una red lenta tarda minutos.
    var installTimeout: TimeInterval = 900
    var signInTimeout: TimeInterval = 300

    static let installerURL = "https://claude.ai/install.sh"

    /// `pipefail`: si `curl` falla, el código de salida es el suyo y no el de un `bash` que no recibió nada.
    static let installScript =
        "set -o pipefail; /usr/bin/curl -fsSL --proto '=https' --tlsv1.2 \(installerURL) | /bin/bash"

    /// Los códigos con los que `curl` dice «no hay red»: no resolvió el nombre, no conectó, se agotó el
    /// tiempo, o la conexión se cortó.
    static let offlineCodes: Set<Int32> = [5, 6, 7, 28, 35, 52, 56]

    func install() async -> ClaudeSetupOutcome {
        guard
            let result = await terminal.runInTerminal(
                "/bin/bash", arguments: ["-c", Self.installScript], timeout: installTimeout)
        else { return .failed("") }
        if result.wasStopped { return Task.isCancelled ? .cancelled : .timedOut }
        if result.status == 0 { return .done }
        if Self.offlineCodes.contains(result.status) { return .offline }
        return .failed(Self.detail(result.output))
    }

    func signIn(claudePath: String) async -> ClaudeSetupOutcome {
        guard
            let result = await terminal.runInTerminal(
                claudePath, arguments: ["auth", "login"], timeout: signInTimeout)
        else { return .failed("") }
        if result.wasStopped { return Task.isCancelled ? .cancelled : .timedOut }
        return result.status == 0 ? .done : .failed(Self.detail(result.output))
    }

    /// Las últimas líneas de una salida, para el detalle de un error. Las que traen una dirección se
    /// quitan: la de `claude auth login` lleva los parámetros de la autorización.
    static func detail(_ output: String) -> String {
        ManagedProcess.stripTerminalCodes(output)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.contains("://") && !$0.lowercased().hasPrefix("paste code") }
            .suffix(2)
            .joined(separator: " ")
    }
}

/// El que no hace nada. Es el valor por defecto de `ConnectServices`, para que ninguna prueba ni vista
/// previa descargue ni ejecute nada por descuido: el de verdad solo lo pone `ConnectServices.live()`.
nonisolated struct NoClaudeCodeSetup: ClaudeCodeSettingUp {
    func install() async -> ClaudeSetupOutcome { .failed("") }
    func signIn(claudePath: String) async -> ClaudeSetupOutcome { .failed("") }
}
