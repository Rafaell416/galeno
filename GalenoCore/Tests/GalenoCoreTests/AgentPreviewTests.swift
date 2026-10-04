import Testing

@testable import GalenoCore

@Suite("Vista previa del AGENTS.md")
struct AgentPreviewTests {
    private func config(language: Language = .spanish) -> AgentConfig {
        AgentConfig(
            agentName: "Hera", language: language, role: .productManager, projectDescription: "App de citas",
            connections: [], skills: [], sendingRules: .default)
    }

    @Test("es lo mismo que escribiría el motor")
    func matchesWhatTheGeneratorWrites() {
        let c = config()
        #expect(AgentPreview.agentsFile(for: c) == AgentsFileRenderer.render(c))
    }

    @Test("lleva el nombre del agente y habla el idioma de la config")
    func carriesTheNameAndLanguage() {
        #expect(AgentPreview.agentsFile(for: config()).contains("# Hera"))
        #expect(AgentPreview.agentsFile(for: config(language: .english)).contains("# Hera"))
        #expect(
            AgentPreview.agentsFile(for: config()) != AgentPreview.agentsFile(for: config(language: .english)))
    }
}
