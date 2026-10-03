import Foundation

/// Escribe `.claude/settings.json`: los permisos y el registro del hook de
/// aprobación.
///
/// Claude Code evalúa las reglas en orden `deny` → `ask` → `allow` y gana la
/// primera que coincide; la especificidad no cambia nada. Por eso un `allow`
/// concreto no puede abrir una excepción dentro de un `ask` amplio, y por eso
/// Slack y Gmail van enteros a `ask`.
///
/// **Escritura de archivos.** El agente solo escribe en `memoria/`. Un `Write`
/// o `Edit` pelado en `deny` le quitaría las herramientas, y un patrón que
/// niegue todo el proyecto no se puede reabrir con una excepción `!`: se
/// probó contra Claude Code y la excepción no alcanza (la documentación lo
/// avisa). Así que se niega por nombre lo que el propio motor genera, y se
/// permite `memoria/`. Cualquier otra ruta no tiene regla y pide permiso al
/// usuario; no pasa sola. Las rutas van ancladas con `/` a la raíz del
/// proyecto, para que valgan aunque Claude Code arranque desde una subcarpeta.
///
/// `Edit(ruta)` cubre todas las herramientas que editan archivos. Una regla de
/// ruta escrita bajo `Write(...)` se acepta pero nunca se consulta.
enum SettingsRenderer {
    /// Las herramientas que el perfil PM nunca necesita. Con el nombre pelado
    /// en `deny`, Claude Code las quita del contexto del agente.
    static let deniedTools = ["Bash", "NotebookEdit"]

    /// Lo que el motor escribe fuera de `memoria/`, relativo a la raíz del
    /// proyecto. Si el generador empieza a escribir otro archivo, tiene que
    /// entrar aquí: un test lo comprueba.
    static let protectedPaths = ["/AGENTS.md", "/CLAUDE.md", "/.mcp.json", "/.claude/**"]

    /// La única ruta donde el agente escribe sin que nadie lo apruebe.
    static let memoryAllowRule = "Edit(/\(MemoryRenderer.directory)/**)"

    /// Las lecturas locales que siempre se permiten.
    static let allowedReadTools = ["Glob", "Grep", "Read"]

    static let hookPath = ".claude/hooks/require-external-approval.sh"

    private struct Permissions: Encodable {
        var allow: [String]
        var ask: [String]
        var deny: [String]
    }

    private struct HookCommand: Encodable {
        var type = "command"
        var command: String
    }

    private struct HookMatcher: Encodable {
        var matcher: String
        var hooks: [HookCommand]
    }

    private struct Hooks: Encodable {
        var preToolUse: [HookMatcher]

        enum CodingKeys: String, CodingKey {
            case preToolUse = "PreToolUse"
        }
    }

    private struct File: Encodable {
        var permissions: Permissions
        var hooks: Hooks?
    }

    /// Los servidores cuyas herramientas requieren aprobación, en orden estable.
    /// Son los que pueden hablarle a otras personas. Una herramienta puede
    /// tener más de un servidor físico (Google Workspace tiene tres), aunque
    /// hoy ninguna de las que envían externamente lo tiene.
    static func serversRequiringApproval(in config: AgentConfig) -> [String] {
        config.connectedTools
            .filter { $0.externalSend != nil }
            .flatMap { MCPServerCatalog.definitions(for: $0, whatsAppBridgePath: "") }
            .map(\.serverName)
    }

    static func render(_ config: AgentConfig) throws -> String {
        var allow = allowedReadTools + [memoryAllowRule]
        var ask: [String] = []

        for tool in config.connectedTools {
            let servers = MCPServerCatalog.definitions(for: tool, whatsAppBridgePath: "")
            guard !servers.isEmpty else { continue }  // Google Meet

            // Una sola decisión por herramienta, aplicada a todos sus
            // servidores físicos: si Sheets pide confirmación, los tres globs
            // de Google Workspace (drive/docs/sheets) van a `ask` por igual.
            let patterns = servers.map { "mcp__\($0.serverName)__*" }

            if tool.externalSend != nil {
                // Slack y Gmail enteros: no sabemos los nombres reales de
                // todas sus herramientas de envío, y dejar fuera una sola
                // abriría un hueco por el que saldría un mensaje sin preguntar.
                ask.append(contentsOf: patterns)
                continue
            }

            let writes = tool.internalWrites
            if writes.isEmpty {
                // Servidor de solo lectura.
                allow.append(contentsOf: patterns)
            } else if writes.contains(where: { config.sendingRules.policy(for: $0) == .ask }) {
                // Si cualquiera de sus escrituras pide confirmación, el
                // servidor entero va a `ask`: es lo conservador y lo único
                // expresable, porque la regla cubre todo el servidor.
                ask.append(contentsOf: patterns)
            } else {
                allow.append(contentsOf: patterns)
            }
        }

        let approvalServers = serversRequiringApproval(in: config)
        let hooks: Hooks? =
            approvalServers.isEmpty
            ? nil
            : Hooks(preToolUse: [
                HookMatcher(
                    // Contiene `.` y `*`, así que Claude Code lo trata como regex.
                    matcher: approvalServers.map { "mcp__\($0)__.*" }.joined(separator: "|"),
                    hooks: [HookCommand(command: "${CLAUDE_PROJECT_DIR}/\(hookPath)")]
                )
            ])

        let file = File(
            permissions: Permissions(
                allow: allow.sorted(), ask: ask.sorted(),
                deny: deniedTools + protectedPaths.map { "Edit(\($0))" }),
            hooks: hooks
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(file)
        return String(decoding: data, as: UTF8.self) + "\n"
    }
}
