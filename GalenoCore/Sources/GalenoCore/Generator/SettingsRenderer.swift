import Foundation

/// Escribe `.claude/settings.json`: los permisos y el registro del hook de
/// aprobación.
///
/// Claude Code evalúa las reglas en orden `deny` → `ask` → `allow` y gana la
/// primera que coincide; la especificidad no cambia nada. Por eso un `allow`
/// concreto no puede abrir una excepción dentro de un `ask` amplio, y por eso
/// Slack y Gmail van enteros a `ask`.
enum SettingsRenderer {
    /// Las herramientas de edición que el perfil PM nunca necesita. Con el
    /// nombre pelado en `deny`, Claude Code las quita del contexto del agente.
    static let deniedTools = ["Bash", "Edit", "NotebookEdit", "Write"]

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
    /// Son los que pueden hablarle a otras personas.
    static func serversRequiringApproval(in config: AgentConfig) -> [String] {
        config.connectedTools
            .filter { $0.externalSend != nil }
            .compactMap { MCPServerCatalog.definition(for: $0, whatsAppBridgePath: "")?.serverName }
    }

    static func render(_ config: AgentConfig) throws -> String {
        var allow = allowedReadTools
        var ask: [String] = []

        for tool in config.connectedTools {
            guard
                let server = MCPServerCatalog.definition(for: tool, whatsAppBridgePath: "")?
                    .serverName
            else { continue }

            let pattern = "mcp__\(server)__*"

            if tool.externalSend != nil {
                // Slack y Gmail enteros: no sabemos los nombres reales de sus
                // herramientas de envío, y dejar fuera una sola abriría un
                // hueco por el que saldría un mensaje sin preguntar.
                ask.append(pattern)
                continue
            }

            let writes = tool.internalWrites
            if writes.isEmpty {
                // Servidor de solo lectura.
                allow.append(pattern)
            } else if writes.contains(where: { config.sendingRules.policy(for: $0) == .ask }) {
                // Si cualquiera de sus escrituras pide confirmación, el servidor
                // entero va a `ask`: es lo conservador y lo único expresable,
                // porque la regla cubre todo el servidor.
                ask.append(pattern)
            } else {
                allow.append(pattern)
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
            permissions: Permissions(allow: allow.sorted(), ask: ask.sorted(), deny: deniedTools),
            hooks: hooks
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(file)
        return String(decoding: data, as: UTF8.self) + "\n"
    }
}
