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

    /// El hook que deja pasar sin preguntar las lecturas de los conectores de la cuenta de Claude
    /// **en la app de Claude (escritorio)**. Ver `desktopConnectorPrefix`.
    static let connectorReadsHookPath = ".claude/hooks/allow-connector-reads.sh"

    /// Cómo nombra la app de Claude (escritorio) las herramientas de un conector de la cuenta:
    /// `mcp__<uuid>__<herramienta>`, con un identificador propio de cada usuario, y no
    /// `mcp__claude_ai_<Nombre>__…` como Terminal (visto el 4 de octubre de 2026). Las reglas de
    /// permiso no admiten comodín en el nombre del servidor (probado), así que allí no coincide
    /// ninguna: lo que las reglas hacen en Terminal, en la app lo hacen dos hooks, cuyo `matcher`
    /// sí es una expresión regular. Como el identificador no dice de qué conector es, se decide por
    /// el nombre de la herramienta.
    static let desktopConnectorPrefix =
        "mcp__[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}__"

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

    /// Un servidor al que se le aplica el hook, y las herramientas suyas que el hook deja pasar.
    private struct ApprovalTarget {
        var server: MCPServerDefinition
        /// Las que no pasan por el hook: las lecturas conocidas y, en un servidor que no envía a
        /// otras personas (Google Drive), las escrituras que siguen la regla del usuario.
        var exempt: [String]
    }

    /// Los servidores que envían a otras personas (Slack, Gmail, Google Calendar) y los demás que
    /// traen listas de herramientas (Google Drive, Docs y Sheets), para lo que no esté en ellas.
    private static func approvalTargets(in config: AgentConfig) -> [ApprovalTarget] {
        config.connectedConnections.flatMap { connection -> [ApprovalTarget] in
            let tool = connection.tool
            return MCPServerCatalog.definitions(for: connection, whatsAppBridgePath: "").compactMap { server in
                if tool.externalSend != nil {
                    return ApprovalTarget(server: server, exempt: server.readOnlyTools)
                }
                // Un servidor con listas que no envía a otras personas (Google Drive, Docs, Sheets): el
                // hook deja pasar lo que lee y lo que escribe bajo la regla, y detiene lo demás.
                guard !server.readOnlyTools.isEmpty else { return nil }
                return ApprovalTarget(server: server, exempt: server.readOnlyTools + server.writeTools)
            }
        }
    }

    /// Los conectores de la cuenta de Claude entre lo conectado (Gmail, Calendar, Drive, Docs, Sheets).
    private static func connectorTargets(in config: AgentConfig) -> [ApprovalTarget] {
        approvalTargets(in: config).filter {
            if case .claudeConnector = $0.server.transport { return true } else { return false }
        }
    }

    /// Lo que en la app de Claude **no** pasa por el hook de aprobación: lo mismo que en Terminal
    /// (`ApprovalTarget.exempt`), por nombre. Si un nombre fuera a la vez una herramienta que
    /// pregunta en otro conector, gana preguntar.
    static func desktopExemptTools(in config: AgentConfig) -> [String] {
        let targets = connectorTargets(in: config)
        let exempt = Set(targets.flatMap(\.exempt))
        let asks = Set(
            targets.flatMap { target in
                (target.server.readOnlyTools + target.server.writeTools + target.server.alwaysAskTools)
                    .filter { !target.exempt.contains($0) }
            })
        return exempt.subtracting(asks).sorted()
    }

    /// Las lecturas de los conectores que en la app de Claude pasan sin preguntar. **Solo lecturas**:
    /// una escritura se decide por nombre y otro conector que el usuario encienda podría tener una
    /// herramienta que se llame igual, así que en la app las escrituras preguntan.
    static func desktopAllowedReads(in config: AgentConfig) -> [String] {
        let targets = connectorTargets(in: config)
        let reads = Set(targets.flatMap(\.server.readOnlyTools))
        let others = Set(targets.flatMap { $0.server.writeTools + $0.server.alwaysAskTools })
        return reads.subtracting(others).sorted()
    }

    /// El `matcher` del hook que deja pasar esas lecturas, o `nil` si el agente no usa conectores.
    static func connectorReadsMatcher(in config: AgentConfig) -> String? {
        let reads = desktopAllowedReads(in: config)
        guard !reads.isEmpty else { return nil }
        return "^\(desktopConnectorPrefix)(?:\(reads.joined(separator: "|")))$"
    }

    private static func definitionsRequiringApproval(in config: AgentConfig) -> [MCPServerDefinition] {
        approvalTargets(in: config).map(\.server)
    }

    /// El `matcher` del hook de aprobación para un servidor. Con lista de lecturas, coincide con
    /// cualquier herramienta del servidor **menos** esas (probado contra Claude Code: el matcher
    /// admite `(?!…)`); sin lista, con todas. Contiene `.` y `*`, así que Claude Code lo trata como regex.
    static func approvalMatcher(for server: MCPServerDefinition) -> String {
        approvalMatcher(serverName: server.serverName, exempt: server.readOnlyTools)
    }

    static func approvalMatcher(serverName: String, exempt: [String]) -> String {
        guard !exempt.isEmpty else { return "mcp__\(serverName)__.*" }
        return "^mcp__\(serverName)__(?!(?:\(exempt.joined(separator: "|")))$).*"
    }

    /// El comando de un hook. **Entre comillas**: Claude Code lo pasa a `/bin/sh`, y la carpeta de un
    /// agente puede llevar espacios («Mi proyecto»). Sin ellas el hook falla sin bloquear nada
    /// (`/bin/sh: …: is a directory`) y deja de pedir aprobación: pasó en la prueba real del 4 de
    /// octubre de 2026 con un agente llamado «TESTING 2».
    static func hookCommand(_ path: String) -> String {
        "\"${CLAUDE_PROJECT_DIR}/\(path)\""
    }

    /// Las herramientas conectadas cuyas lecturas pasan sin pedir permiso, para decirlo en la app
    /// (paso «Reglas»). Son las que traen su lista de lecturas (Slack, Google) y las que van enteras
    /// a `allow`; una sin lista cuya escritura pregunta (Notion con «Preguntarme») pregunta también
    /// al leer, porque la regla cubre el servidor entero.
    static func toolsReadingWithoutAsking(in config: AgentConfig) -> [Tool] {
        config.connectedConnections.compactMap { connection -> Tool? in
            let tool = connection.tool
            let servers = MCPServerCatalog.definitions(for: connection, whatsAppBridgePath: "")
            guard !servers.isEmpty else { return nil }
            let writesAsk = tool.internalWrites.contains { config.sendingRules.policy(for: $0) == .ask }
            let free = servers.allSatisfy { server in
                if !server.readOnlyTools.isEmpty { return true }
                return tool.externalSend == nil && (tool.internalWrites.isEmpty || !writesAsk)
            }
            return free ? tool : nil
        }
    }

    static func render(_ config: AgentConfig) throws -> String {
        var allow = allowedReadTools + [memoryAllowRule]
        var ask: [String] = []

        for connection in config.connectedConnections {
            let tool = connection.tool
            let servers = MCPServerCatalog.definitions(for: connection, whatsAppBridgePath: "")
            guard !servers.isEmpty else { continue }  // Google Meet

            // Una sola decisión por herramienta para sus escrituras internas: si Sheets pide
            // confirmación, todo lo que escribe en Google va a `ask`.
            let writesAsk = tool.internalWrites.contains { config.sendingRules.policy(for: $0) == .ask }

            for server in servers {
                let prefix = "mcp__\(server.serverName)__"

                if server.readOnlyTools.isEmpty {
                    // Sin lista verificada de lo que solo lee, la regla cubre el servidor entero.
                    if tool.externalSend != nil {
                        // Slack sin lista o Gmail: dejar fuera una sola de envío abriría un hueco
                        // por el que saldría un mensaje sin preguntar.
                        ask.append(prefix + "*")
                    } else if tool.internalWrites.isEmpty || !writesAsk {
                        // Solo lectura, o escribe con permiso del usuario.
                        allow.append(prefix + "*")
                    } else {
                        ask.append(prefix + "*")
                    }
                    continue
                }

                // Con lista: leer no pregunta.
                allow.append(contentsOf: server.readOnlyTools.map { prefix + $0 })
                // Las de escritura: en un servidor que envía a otras personas, siempre preguntan;
                // en uno del propio mundo del usuario (Google Drive), siguen su regla del paso 8.
                let writes = server.writeTools.map { prefix + $0 }
                if tool.externalSend != nil || writesAsk {
                    ask.append(contentsOf: writes)
                } else {
                    allow.append(contentsOf: writes)
                }
                // Compartir o mandar a la papelera: siempre preguntan. Lo que no esté en ninguna
                // lista lo detiene el hook (ver `approvalMatcher`).
                ask.append(contentsOf: server.alwaysAskTools.map { prefix + $0 })
            }
        }

        let approvalTargets = approvalTargets(in: config)
        var approvalMatchers = approvalTargets.map { approvalMatcher(serverName: $0.server.serverName, exempt: $0.exempt) }
        // En la app de Claude los conectores llevan otro nombre (`desktopConnectorPrefix`): ahí pide
        // aprobación todo lo que no sea una lectura o una escritura conocida de las que siguen la regla.
        if !connectorTargets(in: config).isEmpty {
            approvalMatchers.append(
                "^\(desktopConnectorPrefix)(?!(?:\(desktopExemptTools(in: config).joined(separator: "|")))$).*")
        }
        var matchers: [HookMatcher] = []
        if !approvalMatchers.isEmpty {
            matchers.append(
                HookMatcher(
                    matcher: approvalMatchers.joined(separator: "|"),
                    hooks: [HookCommand(command: hookCommand(hookPath))]
                ))
        }
        if let reads = connectorReadsMatcher(in: config) {
            matchers.append(
                HookMatcher(
                    matcher: reads,
                    hooks: [HookCommand(command: hookCommand(connectorReadsHookPath))]
                ))
        }
        let hooks: Hooks? = matchers.isEmpty ? nil : Hooks(preToolUse: matchers)

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

extension AgentConfig {
    /// Las herramientas conectadas que el agente lee sin pedir permiso, según las reglas que se van a
    /// escribir (`SettingsRenderer`). La app lo muestra en el paso «Reglas»; no decide nada.
    public var toolsReadingWithoutAsking: [Tool] { SettingsRenderer.toolsReadingWithoutAsking(in: self) }
}
