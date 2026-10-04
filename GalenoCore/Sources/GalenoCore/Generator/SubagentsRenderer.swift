/// Escribe los subagentes del perfil PM en `.claude/agents/`.
///
/// Lo que un subagente puede tocar lo decide el campo `tools` de su
/// frontmatter, que es una lista blanca: si se omite, hereda todas las
/// herramientas de la sesión, MCP incluidas. Por eso siempre se escribe.
///
/// Un servidor MCP se concede entero (`mcp__<servidor>`) o no se concede: no
/// conocemos los nombres de las herramientas de cada proveedor como para dar
/// solo las de lectura. De ahí la regla: un subagente nunca recibe el servidor
/// de una herramienta que pueda enviarle algo a otra persona (Slack, Gmail).
/// Enviar es cosa del agente principal, que es donde el usuario ve y aprueba.
enum SubagentsRenderer {
    static let directory = ".claude/agents"

    struct File {
        var path: String
        var contents: String
    }

    /// Los servidores MCP que reciben los subagentes, en el orden de las
    /// conexiones del usuario.
    static func grantedServers(in config: AgentConfig) -> [String] {
        config.connectedConnections
            .filter { $0.tool.externalSend == nil }
            .flatMap { MCPServerCatalog.definitions(for: $0, whatsAppBridgePath: "") }
            .map(\.serverName)
    }

    /// La lista blanca completa: las lecturas locales y los servidores
    /// concedidos. Sin terminal, sin edición de archivos, sin `Agent` y sin
    /// `Skill`: lo que no está aquí no existe para el subagente.
    static func grantedTools(in config: AgentConfig) -> [String] {
        SettingsRenderer.allowedReadTools + grantedServers(in: config).map { "mcp__\($0)" }
    }

    static func render(_ config: AgentConfig) -> [File] {
        let tools = grantedTools(in: config).joined(separator: ", ")
        let cannotReachSendingTools = config.connectedTools.contains { $0.externalSend != nil }

        return definitions.map { definition in
            var body = [languageInstruction(config.language), "", definition.body]
            if cannotReachSendingTools {
                body.append("")
                body.append(noSendingToolsNote)
            }

            let contents = """
                ---
                name: \(definition.name)
                description: \(definition.description)
                tools: \(tools)
                ---

                \(body.joined(separator: "\n"))

                """
            return File(path: "\(directory)/\(definition.name).md", contents: contents)
        }
    }

    // MARK: - Texto

    /// Arriba de todo, igual que en las skills: el subagente está escrito en
    /// inglés, pero responde en el idioma del usuario.
    private static func languageInstruction(_ language: Language) -> String {
        """
        Always respond and write in **\(language.englishName)**, headings and labels \
        included, whatever language the sources or these instructions are in.
        """
    }

    private static let noSendingToolsNote = """
        You cannot send messages or email, and you cannot read Slack or email yourself. Work \
        from what the task gives you; if you need something from those tools, say so in your \
        answer instead of guessing.
        """

    private struct Definition {
        var name: String
        /// Una sola línea, sin `: ` ni `#`: va tal cual a un valor de YAML.
        var description: String
        var body: String
    }

    private static let definitions: [Definition] = [
        Definition(
            name: "scribe",
            description:
                "Turns a meeting transcript into decisions, action items and owners. Use it whenever there is a transcript or a recorded meeting to process.",
            body: """
                You are the scribe of a product team. You turn a meeting transcript into a record \
                the team can act on.

                The transcript is either pasted into your task or named in it. If it is named, \
                fetch it from the connected meeting or document tool.

                Return, in this order:

                1. **Decisions** — what was agreed, one line each.
                2. **Action items** — what has to be done, who owns it, and by when. If nobody \
                took it, say it has no owner. If no date was given, say so. Never guess an \
                owner or a date.
                3. **Open questions** — what was raised and left unresolved.

                Stay with what was said. If the transcript is unclear or cuts off, say where.

                You only read, with one exception: create tasks in Notion or Jira when the task \
                explicitly asks you to. Otherwise return the list and let the main agent decide \
                where it goes. Never write anywhere else.
                """
        ),
        Definition(
            name: "tracker",
            description:
                "Finds what changed across the project's sources over a period. Use it for follow-ups, weekly summaries and questions like what happened since Monday.",
            body: """
                You are the tracker of a product team. You find out what changed in the \
                project's sources over a period of time.

                The task gives you the period. If it does not, cover the last 7 days and say so \
                at the top of your answer.

                Check every source you can reach, and only the groups, channels, pages, folders \
                and projects listed in the project instructions. For each source, report:

                - **New** — what appeared in the period.
                - **Changed** — what moved: status, owner, date, scope.
                - **Closed** — what was finished or dropped.
                - **Overdue** — what is past its date and still open.

                Give dates and names, and say where each item comes from so it can be checked. \
                If a source had no changes, say so in one line. If you could not reach a \
                source, say that too, so nobody reads silence as "nothing happened".

                You only read. Do not create, edit or close anything.
                """
        ),
        Definition(
            name: "reporter",
            description:
                "Writes a report from what the scribe and the tracker found. Use it to draft status reports, weekly updates and client summaries.",
            body: """
                You are the reporter of a product team. You turn findings into a report someone \
                will actually read.

                The task gives you the findings (usually from the scribe and the tracker), who \
                the report is for, and where it will go. If the audience is missing, write for \
                the team and say so.

                Lead with what the reader needs to know or decide. Then progress, then risks \
                and blockers, then what happens next and who owns it. Keep it short: a report \
                that needs scrolling in a chat window is too long.

                Use only what the findings and the sources say. You may look something up to \
                fill a gap, but never fill it with a guess; mark what is missing instead.

                You do not send anything. Return the draft to the main agent, which shows it to \
                the user and sends it once approved.
                """
        ),
    ]
}
