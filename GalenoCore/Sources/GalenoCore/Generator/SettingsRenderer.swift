import Foundation

/// Escribe `.claude/settings.json`: los permisos y el registro del hook de
/// aprobación.
///
/// Claude Code evalúa las reglas en orden `deny` → `ask` → `allow` y gana la
/// primera que coincide; la especificidad no cambia nada. Por eso un `allow`
/// concreto no puede abrir una excepción dentro de un `ask` amplio.
///
/// **Servidores que envían a otras personas (Slack, Gmail).** Leer no pide
/// permiso; enviar o escribir, siempre. Si el catálogo trae la lista verificada de
/// herramientas de solo lectura del servidor (Slack), esas van a `allow` por su
/// nombre exacto, las de escritura conocidas a `ask`, y el hook de aprobación
/// se aplica a **todo lo que no sea una lectura conocida** —también a una
/// herramienta que el proveedor añada mañana—. Sin lista (Gmail), el servidor
/// entero va a `ask`, como antes.
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

    /// El esfuerzo de razonamiento con el que corre el agente (`effortLevel` de Claude Code). El trabajo
    /// del agente es sobre todo leer y resumir, y ahí `low` responde de 2 a 3 veces más rápido que el
    /// `high` que muchos usuarios traen de fábrica (medido el 4 de octubre de 2026: 12–25 s frente a
    /// 28–43 s en leer tres fuentes y resumirlas). El `settings.json` del proyecto manda sobre el ajuste
    /// personal del usuario; dentro de una sesión, `/effort` lo sube cuando haga falta (un PRD largo).
    ///
    /// **El modelo no se fija**: cada usuario usa el de su plan.
    static let effortLevel = "low"

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
        var effortLevel: String
        var permissions: Permissions
        var hooks: Hooks?
    }

    /// Los servidores cuyas herramientas requieren aprobación, en orden estable.
    /// Son los que pueden hablarle a otras personas. Una herramienta puede
    /// tener más de un servidor físico (Google Workspace tiene tres), aunque
    /// hoy ninguna de las que envían externamente lo tiene.
    static func serversRequiringApproval(in config: AgentConfig) -> [String] {
        definitionsRequiringApproval(in: config).map(\.serverName)
    }

    private static func definitionsRequiringApproval(in config: AgentConfig) -> [MCPServerDefinition] {
        config.connectedConnections
            .filter { $0.tool.externalSend != nil }
            .flatMap { MCPServerCatalog.definitions(for: $0, whatsAppBridgePath: "") }
    }

    /// El `matcher` del hook de aprobación para un servidor. Con lista de lecturas, coincide con
    /// cualquier herramienta del servidor **menos** esas (probado contra Claude Code: el matcher
    /// admite `(?!…)`); sin lista, con todas. Contiene `.` y `*`, así que Claude Code lo trata como regex.
    static func approvalMatcher(for server: MCPServerDefinition) -> String {
        guard !server.readOnlyTools.isEmpty else { return "mcp__\(server.serverName)__.*" }
        return "^mcp__\(server.serverName)__(?!(?:\(server.readOnlyTools.joined(separator: "|")))$).*"
    }

    static func render(_ config: AgentConfig) throws -> String {
        var allow = allowedReadTools + [memoryAllowRule]
        var ask: [String] = []

        for connection in config.connectedConnections {
            let tool = connection.tool
            let servers = MCPServerCatalog.definitions(for: connection, whatsAppBridgePath: "")
            guard !servers.isEmpty else { continue }  // Google Meet

            // Una sola decisión por herramienta, aplicada a todos sus
            // servidores físicos: si Sheets pide confirmación, los tres globs
            // de Google Workspace (drive/docs/sheets) van a `ask` por igual.
            let patterns = servers.map { "mcp__\($0.serverName)__*" }

            if tool.externalSend != nil {
                for server in servers {
                    let prefix = "mcp__\(server.serverName)__"
                    if server.readOnlyTools.isEmpty {
                        // No sabemos cuáles leen (Gmail): el servidor entero pregunta. Dejar fuera
                        // una sola de envío abriría un hueco por el que saldría un mensaje sin preguntar.
                        ask.append(prefix + "*")
                    } else {
                        // Leer no pregunta. Las de escritura conocidas llevan su `ask`; lo que no
                        // esté en ninguna lista lo detiene el hook (ver `approvalMatcher`).
                        allow.append(contentsOf: server.readOnlyTools.map { prefix + $0 })
                        ask.append(contentsOf: server.writeTools.map { prefix + $0 })
                    }
                }
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

        let approvalServers = definitionsRequiringApproval(in: config)
        let hooks: Hooks? =
            approvalServers.isEmpty
            ? nil
            : Hooks(preToolUse: [
                HookMatcher(
                    matcher: approvalServers.map(approvalMatcher(for:)).joined(separator: "|"),
                    hooks: [HookCommand(command: "${CLAUDE_PROJECT_DIR}/\(hookPath)")]
                )
            ])

        let file = File(
            effortLevel: effortLevel,
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
