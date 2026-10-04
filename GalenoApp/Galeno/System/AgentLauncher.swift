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

    static func claudeCLI(folder: URL, prompt: String?) -> URL {
        build("claude-cli://open", [("cwd", folder.path), ("q", prompt)])
    }

    /// Respaldo si Claude Code aún no registró su manejador: un `.command`, que Terminal.app
    /// abre y ejecuta sin pedir ningún permiso. Entra a la carpeta y arranca `claude`.
    static func terminalScript(folder: URL, claudePath: String) -> String {
        "#!/bin/zsh\ncd -- \(quoted(folder.path)) || exit 1\nexec \(quoted(claudePath))\n"
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

/// "Pídele: resume lo que pasó esta semana en Slack" (`docs/03` §3, pantalla 10): una frase que
/// el usuario puede probar ya, de las herramientas que conectó.
nonisolated enum FirstCommand {
    static func suggestion(for tools: [Tool], language: Language) -> String {
        func pick(_ es: String, _ en: String) -> String { language == .spanish ? es : en }
        if tools.contains(.slack) {
            return pick("Resume lo que pasó esta semana en Slack", "Summarize what happened this week in Slack")
        }
        if tools.contains(.whatsapp) {
            return pick(
                "Resume lo que pasó esta semana en mis grupos de WhatsApp",
                "Summarize what happened this week in my WhatsApp groups")
        }
        if tools.contains(.jira) {
            return pick("Resume lo que pasó esta semana en Jira", "Summarize what happened this week in Jira")
        }
        if tools.contains(.notion) {
            return pick("Resume lo que pasó esta semana en Notion", "Summarize what happened this week in Notion")
        }
        if tools.contains(where: { [.fireflies, .granola, .fathom, .googleMeet].contains($0) }) {
            return pick("Resume mis últimas reuniones", "Summarize my latest meetings")
        }
        return pick(
            "Resume lo que pasó esta semana en el proyecto", "Summarize what happened this week in the project")
    }
}

// MARK: - Abrir

/// Quien abre el agente. Las pruebas lo reemplazan.
@MainActor
protocol AgentOpening {
    /// ¿Está instalada la app de Claude (el manejador de `claude://`)?
    var isClaudeAppAvailable: Bool { get }
    @discardableResult func openInClaudeApp(folder: URL, prompt: String?) -> Bool
    @discardableResult func openInTerminal(folder: URL, prompt: String?, claudePath: String) -> Bool
    func reveal(_ folder: URL)
}

@MainActor
struct SystemAgentOpener: AgentOpening {
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
            try AgentLink.terminalScript(folder: folder, claudePath: claudePath)
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
