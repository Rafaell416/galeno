@testable import GalenoCore

extension AgentConfig {
    /// Una config que ejercita todo el modelo: las diez herramientas, los tres
    /// estados de conexión, fuentes de cada tipo, skills de los dos orígenes y
    /// reglas de envío a medida.
    static var example: AgentConfig {
        AgentConfig(
            agentName: "Hipócrates",
            language: .spanish,
            role: .productManager,
            connections: [
                ToolConnection(
                    tool: .whatsapp,
                    status: .connected,
                    sources: .only([
                        Source(
                            id: "120363021234567890@g.us",
                            name: "Equipo Cliente A",
                            kind: .group
                        ),
                        Source(
                            id: "573001112233@s.whatsapp.net",
                            name: "Ana Restrepo",
                            kind: .chat
                        ),
                    ])
                ),
                ToolConnection(
                    tool: .slack,
                    status: .connected,
                    sources: .only([
                        Source(id: "C024BE91L", name: "#producto", kind: .channel)
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
                ToolConnection(
                    tool: .googleWorkspace,
                    status: .connected,
                    sources: .only([
                        Source(id: "1AbCdEfGh", name: "Cliente A", kind: .folder)
                    ])
                ),
                ToolConnection(
                    tool: .gmail,
                    status: .connected,
                    sources: .only([
                        Source(id: "Label_12", name: "Cliente A", kind: .mailLabel)
                    ])
                ),
                ToolConnection(
                    tool: .jira,
                    status: .connected,
                    sources: .only([
                        Source(id: "CLA", name: "Cliente A", kind: .project)
                    ])
                ),
                // Las de transcripción no tienen fuentes que elegir.
                ToolConnection(tool: .fireflies, status: .connected, sources: .everything),
                // Saltada con "Conectar después".
                ToolConnection(tool: .granola, status: .skipped, sources: .nothing),
                // Marcada en el paso 4, todavía sin conectar.
                ToolConnection(tool: .fathom, status: .selected, sources: .nothing),
                ToolConnection(
                    tool: .googleMeet,
                    status: .connected,
                    sources: .only([
                        Source(id: "1XyZ9", name: "Meet Recordings", kind: .folder)
                    ])
                ),
            ],
            skills: [
                SelectedSkill(id: "prd", source: .galeno),
                SelectedSkill(id: "informe-slack", source: .galeno),
                SelectedSkill(id: "acta", source: .galeno),
                // Sin "/": un id tiene que ser un solo segmento de ruta, para
                // que no pueda escribir fuera de .claude/skills/.
                SelectedSkill(id: "phuryn-discovery-interview", source: .curated),
            ],
            sendingRules: {
                var rules = SendingRules.default
                // El usuario prefiere que le pregunten antes de tocar Jira.
                rules.setPolicy(.ask, for: .jira)
                return rules
            }()
        )
    }
}
