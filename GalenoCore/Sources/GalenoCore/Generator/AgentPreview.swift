/// Una vista previa del `AGENTS.md` de un agente, para mostrarla mientras se configura.
///
/// Es exactamente lo que el motor escribiría con esa config, pero **no escribe nada**: solo devuelve el texto.
/// Sirve a la app para enseñar el archivo a medida que el usuario decide (nombre, herramientas, reglas).
public enum AgentPreview {
    public static func agentsFile(for config: AgentConfig) -> String {
        AgentsFileRenderer.render(config)
    }
}
