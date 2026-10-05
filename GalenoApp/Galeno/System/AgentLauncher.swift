import AppKit
import Foundation
import GalenoCore

// MARK: - Los enlaces

/// Cómo se abre el agente: los enlaces que documenta Anthropic, y el respaldo para Terminal.
///
/// - App de Claude: `claude://code/new?folder=<ruta>&q=<texto>` abre una sesión de Code en esa
///   carpeta con el texto escrito (no enviado). La app **siempre** le pide confirmar la carpeta
///   al usuario: toda carpeta que llega por un enlace se trata como no confiable.
/// - Terminal: `claude-cli://open?cwd=<ruta>&q=<texto>` lo registra Claude Code al enviar su
///   primer mensaje y abre la terminal que el usuario usó la última vez.
///
/// Ninguno ejecuta nada por sí solo: solo eligen carpeta y rellenan el texto.
nonisolated enum AgentLink {
    static func claudeApp(folder: URL, prompt: String?) -> URL {
        build("claude://code/new", [("folder", folder.path), ("q", prompt)])
    }

    /// Vuelve a una sesión concreta de la app de Claude. **No está documentado por Anthropic**: es el enlace que la
    /// propia app usa en su menú del Dock («Continuar la última sesión»). Si la app no lo entiende, abre su pantalla
    /// de Code y no rompe nada. El id debe tener la forma `local_…`.
    static func claudeAppContinue(sessionID: String) -> URL? {
        guard sessionID.range(of: ClaudeSessionStore.idPattern, options: .regularExpression) != nil else { return nil }
        return build("claude://code/continue", [("session", sessionID)])
    }

    static func claudeCLI(folder: URL, prompt: String?) -> URL {
        build("claude-cli://open", [("cwd", folder.path), ("q", prompt)])
    }

    /// Respaldo si Claude Code aún no registró su manejador: un `.command`, que Terminal.app
    /// abre y ejecuta sin pedir ningún permiso. Entra a la carpeta y arranca `claude` con la primera
    /// pregunta (citada). Aquí no hay forma de dejarla solo escrita: `claude "texto"` la envía.
    static func terminalScript(folder: URL, claudePath: String, prompt: String? = nil) -> String {
        let question = (prompt?.isEmpty == false) ? " " + quoted(prompt!) : ""
        return "#!/bin/zsh\ncd -- \(quoted(folder.path)) || exit 1\nexec \(quoted(claudePath))\(question)\n"
    }

    /// Cita para el shell: entre comillas simples, con las simples escapadas.
    static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Codifica todo lo que no sea una letra, un dígito o `-._~`: sin esto un `&`, un `=` o un
    /// `+` dentro del texto rompería el enlace.
    private static func build(_ base: String, _ items: [(String, String?)]) -> URL {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let query = items.compactMap { name, value -> String? in
            guard let value, !value.isEmpty,
                let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed)
            else { return nil }
            return "\(name)=\(encoded)"
        }.joined(separator: "&")
        return URL(string: query.isEmpty ? base : "\(base)?\(query)")!
    }
}

// MARK: - El primer comando

/// La primera pregunta de la pantalla 10 (`docs/03` §3): algo que el usuario puede probar ya con lo que
/// conectó. **Corta y acotada a propósito** («mis 3 chats más recientes», no «resume la semana»): es el
/// primer momento con el agente y tiene que responder en segundos. En la prueba real, «resume la semana
/// en mis grupos» tardó casi tres minutos.
nonisolated enum FirstCommand {
    static func suggestion(for tools: [Tool], language: Language) -> String {
        func pick(_ es: String, _ en: String) -> String { language == .spanish ? es : en }
        // WhatsApp primero: es lo que ninguna otra herramienta le da al usuario, y el momento que más sorprende.
        if tools.contains(.whatsapp) {
            return pick(
                "¿Qué hay de nuevo en mis 3 chats más recientes de WhatsApp?",
                "What’s new in my 3 most recent WhatsApp chats?")
        }
        if tools.contains(.slack) {
            return pick(
                "¿Cuáles son los 3 mensajes más recientes de Slack donde me mencionan?",
                "What are the 3 most recent Slack messages that mention me?")
        }
        if tools.contains(.notion) {
            return pick(
                "¿Cuáles son las 3 páginas de Notion que cambiaron más recientemente?",
                "Which 3 Notion pages changed most recently?")
        }
        if tools.contains(.jira) {
            return pick(
                "¿Cuáles son mis 3 tickets de Jira actualizados más recientemente?",
                "Which are my 3 most recently updated Jira tickets?")
        }
        if tools.contains(where: { [.fireflies, .granola, .fathom, .googleMeet].contains($0) }) {
            return pick("Resume mi última reunión", "Summarize my latest meeting")
        }
        if tools.contains(.googleCalendar) {
            return pick("¿Cuáles son mis 3 próximos eventos del calendario?", "What are my next 3 calendar events?")
        }
        if tools.contains(.gmail) {
            return pick("¿Cuáles son mis 3 correos más recientes sin leer?", "What are my 3 most recent unread emails?")
        }
        if tools.contains(.googleWorkspace) {
            return pick(
                "¿Cuáles son los 3 documentos de Drive que cambiaron más recientemente?",
                "Which 3 Drive documents changed most recently?")
        }
        if tools.contains(.claudeDesign) {
            return pick(
                "Revisa este diseño y dime qué le falta: [pega aquí el enlace de Claude Design]",
                "Review this design and tell me what is missing: [paste the Claude Design link here]")
        }
        // Sin nada conectado no hay fuentes que leer: que se presente.
        return pick("Preséntate en tres líneas y dime qué puedes hacer por mí", "Introduce yourself in three lines and tell me what you can do for me")
    }
}

// MARK: - Abrir

/// Cómo terminó el intento de abrir un agente.
enum AgentOpenOutcome: Equatable, Sendable {
    case opened
    /// No se pudo abrir (falta el manejador del enlace, o la app que lo abre).
    case failed
    /// Había que reiniciar la app de Claude para que viera los conectores del agente y no salió al pedírselo
    /// (un aviso suyo, una tarea a medias). **No se abre el agente en esa app**: no vería sus herramientas, y
    /// el usuario no sabría por qué. Se le dice que la cierre él.
    case claudeDidNotQuit
}

/// Cuándo abrir un agente obliga a reiniciar la app de Claude, y cómo se abre. Lo comparten «Listo» y el home.
///
/// La app de Claude carga los conectores de la cuenta (Gmail, Drive…) al arrancar y no los actualiza
/// (`docs/03` §4e): si lleva abierta desde antes de que el agente existiera, no ve los suyos.
@MainActor
enum AgentOpenPolicy {
    /// Si alguna de las herramientas conectadas llega por un conector de la cuenta de Claude.
    static func usesConnectors(_ tools: [Tool]) -> Bool {
        tools.contains { !MCPServerCatalog.claudeConnectorNames(for: $0).isEmpty }
    }

    /// Desde cuándo está listo el agente: cuando se escribió su configuración.
    static func readySince(_ folder: URL) -> Date {
        let settings = folder.appending(path: ".claude/settings.json")
        let attributes = try? FileManager.default.attributesOfItem(atPath: settings.path)
        return attributes?[.modificationDate] as? Date ?? Date()
    }

    static func needsClaudeRestart(tools: [Tool], folder: URL, opener: any AgentOpening) -> Bool {
        usesConnectors(tools) && opener.claudeAppNeedsRestart(since: readySince(folder))
    }

    /// Abre el agente donde el usuario eligió. En la app de Claude, y solo si hace falta, la cierra y la
    /// vuelve a abrir en el agente. Devuelve si pudo abrirlo.
    @discardableResult
    static func open(
        folder: URL, tools: [Tool], inApp: Bool, prompt: String?, resume: Bool = false, opener: any AgentOpening,
        claudePath: String
    ) async -> AgentOpenOutcome {
        if inApp {
            if needsClaudeRestart(tools: tools, folder: folder, opener: opener) {
                return await opener.restartClaudeAppAndOpen(folder: folder, prompt: prompt, resume: resume)
            }
            let opened = resume ? opener.continueInClaudeApp(folder: folder) : opener.openInClaudeApp(folder: folder, prompt: prompt)
            return opened ? .opened : .failed
        }
        return opener.openInTerminal(folder: folder, prompt: prompt, claudePath: claudePath) ? .opened : .failed
    }
}

/// Quien abre el agente. Las pruebas lo reemplazan.
@MainActor
protocol AgentOpening {
    /// ¿Está instalada la app de Claude (el manejador de `claude://`)?
    var isClaudeAppAvailable: Bool { get }
    @discardableResult func openInClaudeApp(folder: URL, prompt: String?) -> Bool
    /// Vuelve a la última conversación de esa carpeta en la app de Claude; si no hay ninguna, abre una nueva.
    @discardableResult func continueInClaudeApp(folder: URL) -> Bool
    /// ¿Hay que reiniciar la app de Claude para que vea los conectores de un agente listo desde `date`?
    /// La app carga los conectores de la cuenta al arrancar y no los actualiza (`docs/03` §4e): si
    /// lleva abierta desde antes, no ve los que se conectaron después.
    func claudeAppNeedsRestart(since date: Date) -> Bool
    /// Cierra la app de Claude, espera a que termine y la vuelve a abrir en el agente.
    /// `resume`: al reabrir, volver a la última conversación de la carpeta en vez de abrir una nueva.
    @discardableResult func restartClaudeAppAndOpen(folder: URL, prompt: String?, resume: Bool) async -> AgentOpenOutcome
    @discardableResult func openInTerminal(folder: URL, prompt: String?, claudePath: String) -> Bool
    func reveal(_ folder: URL)
}

extension AgentOpening {
    /// «Listo»: una conversación nueva, con la primera pregunta escrita.
    @discardableResult
    func restartClaudeAppAndOpen(folder: URL, prompt: String?) async -> AgentOpenOutcome {
        await restartClaudeAppAndOpen(folder: folder, prompt: prompt, resume: false)
    }
}

@MainActor
struct SystemAgentOpener: AgentOpening {
    var sessions = ClaudeSessionStore()

    /// Lo que registra Claude Code en macOS para `claude-cli://`.
    static var cliHandler: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/Claude Code URL Handler.app")
    }

    var isClaudeAppAvailable: Bool {
        NSWorkspace.shared.urlForApplication(toOpen: URL(string: "claude://code/new")!) != nil
    }

    func openInClaudeApp(folder: URL, prompt: String?) -> Bool {
        NSWorkspace.shared.open(AgentLink.claudeApp(folder: folder, prompt: prompt))
    }

    func continueInClaudeApp(folder: URL) -> Bool {
        if let id = sessions.latestSessionID(in: folder), let link = AgentLink.claudeAppContinue(sessionID: id) {
            return NSWorkspace.shared.open(link)
        }
        return openInClaudeApp(folder: folder, prompt: nil)
    }

    /// El identificador de la app de Claude para Mac.
    static let claudeBundleID = "com.anthropic.claudefordesktop"

    private var runningClaudeApps: [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: Self.claudeBundleID)
    }

    func claudeAppNeedsRestart(since date: Date) -> Bool {
        // Cerrada no hace falta: el enlace la arranca y carga los conectores de ahora.
        runningClaudeApps.contains { ($0.launchDate ?? .distantPast) < date }
    }

    /// Se le pide salir como lo haría Cmd+Q (nunca se la mata) y se espera hasta 15 s. Si no salió —un aviso
    /// suyo de «¿salir?», una tarea a medias—, **no se abre el agente**: en la app que quedó no vería sus
    /// conectores y nadie sabría por qué (así pasó en un demo). Se devuelve `.claudeDidNotQuit` y la pantalla
    /// le pide al usuario que la cierre.
    func restartClaudeAppAndOpen(folder: URL, prompt: String?, resume: Bool) async -> AgentOpenOutcome {
        let apps = runningClaudeApps
        for app in apps { app.terminate() }
        for _ in 0..<150 {
            if apps.allSatisfy(\.isTerminated) { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard apps.allSatisfy(\.isTerminated) else { return .claudeDidNotQuit }
        // Un respiro para que el sistema dé por cerrada la app antes de volver a lanzarla.
        try? await Task.sleep(for: .milliseconds(600))
        let opened = resume ? continueInClaudeApp(folder: folder) : openInClaudeApp(folder: folder, prompt: prompt)
        return opened ? .opened : .failed
    }

    func openInTerminal(folder: URL, prompt: String?, claudePath: String) -> Bool {
        if FileManager.default.fileExists(atPath: Self.cliHandler.path) {
            return NSWorkspace.shared.open(AgentLink.claudeCLI(folder: folder, prompt: prompt))
        }
        // Sin el manejador: un `.command` en la carpeta temporal del usuario (0700) que Terminal
        // ejecuta. No se escribe nada dentro de la carpeta del agente.
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal")
        else { return false }
        let script = FileManager.default.temporaryDirectory
            .appendingPathComponent("galeno-open-\(UUID().uuidString).command")
        do {
            try AgentLink.terminalScript(folder: folder, claudePath: claudePath, prompt: prompt)
                .write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        } catch { return false }
        NSWorkspace.shared.open([script], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
        // Terminal ya lo leyó: se borra.
        Task {
            try? await Task.sleep(for: .seconds(30))
            try? FileManager.default.removeItem(at: script)
        }
        return true
    }

    func reveal(_ folder: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }
}
