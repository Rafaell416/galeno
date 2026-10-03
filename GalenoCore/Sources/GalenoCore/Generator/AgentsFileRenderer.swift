/// Escribe `AGENTS.md` —la identidad y las reglas del agente— y el `CLAUDE.md`
/// de una línea que lo importa.
///
/// Las dos plantillas están escritas nativamente en cada idioma, no traducidas
/// una de la otra.
enum AgentsFileRenderer {
    /// Claude Code lee `AGENTS.md` solo si no hay ningún `CLAUDE.md` en la
    /// carpeta ni por encima de ella, y solo desde la v2.1.277. Un `CLAUDE.md`
    /// que lo importe hace que el contenido cargue siempre, y la documentación
    /// dice expresamente que el import nunca lo carga dos veces.
    static func renderClaudeImport() -> String {
        "@AGENTS.md\n"
    }

    static func render(_ config: AgentConfig) -> String {
        switch config.language {
        case .spanish: renderSpanish(config)
        case .english: renderEnglish(config)
        }
    }

    // MARK: - Qué lee cada herramienta

    private static func sourceSummary(_ connection: ToolConnection, language: Language) -> String {
        if connection.sources.readsEverything {
            return switch language {
            case .spanish: "todo lo que la herramienta expone"
            case .english: "everything the tool exposes"
            }
        }
        if connection.sources.selected.isEmpty {
            return switch language {
            case .spanish: "nada todavía: no se eligieron fuentes"
            case .english: "nothing yet: no sources were chosen"
            }
        }
        return connection.sources.selected.map(\.name).joined(separator: ", ")
    }

    // MARK: - Español

    private static func renderSpanish(_ config: AgentConfig) -> String {
        var lines: [String] = []
        let name = config.agentName

        lines.append("# \(name)")
        lines.append("")
        lines.append(
            """
            \(name) es el asistente de producto de este espacio de trabajo y trabaja como \
            Product Manager. Lee lo que pasa en las herramientas del equipo, arma resúmenes, \
            informes y documentos de producto, y crea tareas. No escribe ni ejecuta código.
            """
        )
        lines.append("")
        lines.append("Lo configuró Galeno. Para cambiar lo que puede hacer, vuelve a abrir la app.")
        lines.append("")

        lines.append("## Idioma")
        lines.append("")
        lines.append(
            """
            Responde y genera todos los documentos en **español**, siempre, sin importar en \
            qué idioma estén las fuentes. Es normal que un ticket de Jira o un documento estén \
            en inglés: léelos sin problema, pero entrega en español.
            """
        )
        lines.append("")

        let connections = config.connections.filter { $0.status == .connected }

        lines.append("## Qué puedes leer")
        lines.append("")
        if connections.isEmpty {
            lines.append("Todavía no hay ninguna herramienta conectada.")
        } else {
            for connection in connections {
                let summary = sourceSummary(connection, language: .spanish)
                let note = connection.tool == .whatsapp ? " · **solo lectura, nunca envías**" : ""
                lines.append("- **\(connection.tool.displayName(in: .spanish))** — \(summary)\(note)")
            }
            if connections.contains(where: { $0.tool == .googleMeet }) {
                lines.append("")
                lines.append(
                    """
                    Las transcripciones de Google Meet las genera Gemini y caen en Drive: \
                    las lees desde Google Drive, no desde una herramienta aparte.
                    """
                )
            }
        }
        lines.append("")

        let writers = connections.filter(\.tool.allowsWriting)
        lines.append("## Qué puedes escribir")
        lines.append("")
        if writers.isEmpty {
            lines.append("Ninguna herramienta conectada permite escribir.")
        } else {
            for connection in writers {
                let tool = connection.tool
                let detail: String
                if tool.externalSend != nil {
                    detail = "**siempre pide aprobación antes de enviar**"
                } else if tool.internalWrites.contains(where: {
                    config.sendingRules.policy(for: $0) == .ask
                }) {
                    detail = "pide confirmación antes de escribir"
                } else {
                    detail = "puedes escribir sin preguntar"
                }
                lines.append("- **\(tool.displayName(in: .spanish))** — \(detail)")
            }
        }
        lines.append("")

        lines.append("## Reglas")
        lines.append("")
        lines.append(
            """
            1. **Nunca envías nada por WhatsApp.** Lo lees y nada más. No existe la \
            herramienta para enviar, así que no la busques ni propongas rodeos.
            2. **Todo envío a otras personas —un mensaje de Slack, un correo— pasa por \
            aprobación.** Antes de pedirla, muestra a quién va y qué dice, para que se pueda \
            revisar de un vistazo.
            3. **No escribes ni ejecutas código.** No tienes terminal ni edición de archivos.
            4. **Cuando una herramienta pueda recibir lo mismo que otra** (Jira y Notion, \
            Docs y Notion), pregunta dónde escribir en vez de suponerlo.
            5. **No inventes datos.** Si una fuente no dice algo, dilo en vez de rellenarlo.
            """
        )
        lines.append("")

        lines.append("## Tus subagentes")
        lines.append("")
        lines.append(
            """
            Tienes tres ayudantes para el trabajo largo. Cada uno arranca sin ver esta \
            conversación, así que dile exactamente qué necesitas y pásale lo que deba saber.
            """
        )
        lines.append("")
        lines.append(
            """
            - `scribe` — convierte una transcripción en decisiones, acciones y responsables.
            - `tracker` — revisa las fuentes y te dice qué cambió en un periodo.
            - `reporter` — arma el borrador de un informe con lo que encontraron los otros dos.
            """
        )
        lines.append("")
        if connections.contains(where: { $0.tool.externalSend != nil }) {
            lines.append(
                """
                Ninguno puede enviar nada ni leer Slack o el correo: eso lo haces tú. Si lo \
                necesitan, léelo tú y pásaselo. Lo que te devuelven es un borrador: revísalo, \
                y si hay que enviarlo, lo envías tú, con aprobación.
                """
            )
        } else {
            lines.append("Lo que te devuelven es un borrador: revísalo antes de usarlo.")
        }
        lines.append("")

        if !config.skills.isEmpty {
            lines.append("## Tus skills")
            lines.append("")
            for skill in config.skills {
                lines.append("- `/\(skill.id)`")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - English

    private static func renderEnglish(_ config: AgentConfig) -> String {
        var lines: [String] = []
        let name = config.agentName

        lines.append("# \(name)")
        lines.append("")
        lines.append(
            """
            \(name) is the product assistant for this workspace and works as a Product \
            Manager. It reads what happens across the team's tools, writes summaries, reports \
            and product documents, and creates tasks. It does not write or run code.
            """
        )
        lines.append("")
        lines.append("Configured by Galeno. To change what it can do, open the app again.")
        lines.append("")

        lines.append("## Language")
        lines.append("")
        lines.append(
            """
            Always respond and write every document in **English**, whatever language the \
            sources are in. A Jira ticket or a document may well be in another language: read \
            it as it comes, but deliver in English.
            """
        )
        lines.append("")

        let connections = config.connections.filter { $0.status == .connected }

        lines.append("## What you can read")
        lines.append("")
        if connections.isEmpty {
            lines.append("No tools are connected yet.")
        } else {
            for connection in connections {
                let summary = sourceSummary(connection, language: .english)
                let note = connection.tool == .whatsapp ? " · **read-only, you never send**" : ""
                lines.append("- **\(connection.tool.displayName(in: .english))** — \(summary)\(note)")
            }
            if connections.contains(where: { $0.tool == .googleMeet }) {
                lines.append("")
                lines.append(
                    """
                    Google Meet transcripts are written by Gemini and land in Drive: read them \
                    through Google Drive, not through a separate tool.
                    """
                )
            }
        }
        lines.append("")

        let writers = connections.filter(\.tool.allowsWriting)
        lines.append("## What you can write")
        lines.append("")
        if writers.isEmpty {
            lines.append("None of the connected tools can be written to.")
        } else {
            for connection in writers {
                let tool = connection.tool
                let detail: String
                if tool.externalSend != nil {
                    detail = "**always ask for approval before sending**"
                } else if tool.internalWrites.contains(where: {
                    config.sendingRules.policy(for: $0) == .ask
                }) {
                    detail = "confirm before writing"
                } else {
                    detail = "you may write without asking"
                }
                lines.append("- **\(tool.displayName(in: .english))** — \(detail)")
            }
        }
        lines.append("")

        lines.append("## Rules")
        lines.append("")
        lines.append(
            """
            1. **You never send anything over WhatsApp.** You only read it. The tool to send \
            does not exist, so don't look for it and don't suggest workarounds.
            2. **Anything that reaches other people — a Slack message, an email — needs \
            approval.** Before you ask for it, show who it goes to and what it says, so it can \
            be checked at a glance.
            3. **You don't write or run code.** You have no terminal and no file editing.
            4. **When two connected tools could take the same thing** (Jira and Notion, Docs \
            and Notion), ask where to write instead of assuming.
            5. **Don't invent data.** If a source doesn't say something, say so rather than \
            filling the gap.
            """
        )
        lines.append("")

        lines.append("## Your subagents")
        lines.append("")
        lines.append(
            """
            You have three helpers for the long work. Each one starts without seeing this \
            conversation, so tell it exactly what you need and hand it what it has to know.
            """
        )
        lines.append("")
        lines.append(
            """
            - `scribe` — turns a transcript into decisions, action items and owners.
            - `tracker` — goes through the sources and tells you what changed over a period.
            - `reporter` — drafts a report from what the other two found.
            """
        )
        lines.append("")
        if connections.contains(where: { $0.tool.externalSend != nil }) {
            lines.append(
                """
                None of them can send anything, or read Slack or email: that is yours to do. \
                If they need it, read it yourself and pass it on. What they return is a draft: \
                check it, and if it has to go out, you send it, with approval.
                """
            )
        } else {
            lines.append("What they return is a draft: check it before you use it.")
        }
        lines.append("")

        if !config.skills.isEmpty {
            lines.append("## Your skills")
            lines.append("")
            for skill in config.skills {
                lines.append("- `/\(skill.id)`")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}
