@testable import GalenoCore

/// Las dos configs de los snapshots.
enum GeneratorFixtures {
    /// Español, tres herramientas: el caso mínimo realista. Cubre el bridge
    /// local por QR, un servidor de envío externo y uno de escritura interna.
    static var spanishThreeTools: AgentConfig {
        AgentConfig(
            agentName: "Hipócrates",
            language: .spanish,
            connections: [
                ToolConnection(
                    tool: .whatsapp,
                    status: .connected,
                    sources: .only([
                        Source(
                            id: "120363021234567890@g.us", name: "Equipo Cliente A", kind: .group),
                        Source(id: "573001112233@s.whatsapp.net", name: "Ana Restrepo", kind: .chat),
                    ])
                ),
                ToolConnection(
                    tool: .slack,
                    status: .connected,
                    sources: .only([
                        Source(id: "C024BE91L", name: "#producto", kind: .channel),
                        Source(id: "C024BE92M", name: "#cliente-a", kind: .channel),
                    ])
                ),
                ToolConnection(
                    tool: .notion,
                    status: .connected,
                    sources: .only([
                        Source(id: "a1b2c3d4", name: "PRDs", kind: .page),
                        Source(id: "e5f6a7b8", name: "Backlog", kind: .database),
                    ])
                ),
            ],
            skills: [
                SelectedSkill(id: "prd", source: .galeno),
                SelectedSkill(id: "acta", source: .galeno),
                SelectedSkill(id: "informe-slack", source: .galeno),
            ],
            sendingRules: .default
        )
    }

    /// Inglés, ocho herramientas. Cubre Google Meet (que no debe producir
    /// entrada en `.mcp.json`), una escritura interna puesta en `ask`, una
    /// herramienta saltada y una skill curada.
    static var englishEightTools: AgentConfig {
        AgentConfig(
            agentName: "Vesalius",
            language: .english,
            connections: [
                ToolConnection(
                    tool: .whatsapp,
                    status: .connected,
                    sources: .only([
                        Source(id: "120363099887766554@g.us", name: "Acme Team", kind: .group)
                    ])
                ),
                ToolConnection(
                    tool: .slack,
                    status: .connected,
                    sources: .only([
                        Source(id: "C07ABCDEF", name: "#product", kind: .channel)
                    ])
                ),
                ToolConnection(
                    tool: .notion,
                    status: .connected,
                    sources: .only([
                        Source(id: "11aa22bb", name: "Product wiki", kind: .page)
                    ])
                ),
                ToolConnection(
                    tool: .googleWorkspace,
                    status: .connected,
                    sources: .only([
                        Source(id: "1AbCdEfGh", name: "Acme", kind: .folder)
                    ])
                ),
                ToolConnection(
                    tool: .gmail,
                    status: .connected,
                    sources: .only([
                        Source(id: "Label_18", name: "Acme", kind: .mailLabel)
                    ])
                ),
                ToolConnection(
                    tool: .jira,
                    status: .connected,
                    sources: .only([
                        Source(id: "ACME", name: "Acme", kind: .project)
                    ])
                ),
                ToolConnection(tool: .fireflies, status: .connected, sources: .everything),
                ToolConnection(
                    tool: .googleMeet,
                    status: .connected,
                    sources: .only([
                        Source(id: "1MeetRec", name: "Meet Recordings", kind: .folder)
                    ])
                ),
                // Saltada: no debe aparecer en ningún archivo generado.
                ToolConnection(tool: .granola, status: .skipped, sources: .nothing),
            ],
            skills: [
                SelectedSkill(id: "prd", source: .galeno),
                SelectedSkill(id: "user-stories", source: .galeno),
                SelectedSkill(id: "phuryn-discovery-interview", source: .curated),
            ],
            sendingRules: {
                var rules = SendingRules.default
                // Este usuario quiere que le pregunten antes de tocar Jira.
                rules.setPolicy(.ask, for: .jira)
                return rules
            }()
        )
    }
}
