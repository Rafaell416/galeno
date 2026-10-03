/// Una herramienta conectada una sola vez, compartida por todos los agentes.
///
/// El OAuth de cada herramienta lo guarda Claude Code por usuario, y WhatsApp es
/// un solo dispositivo vinculado: conectar Slack para el primer agente lo deja
/// listo para los demás. Aquí solo vive lo que es de la conexión. Qué lee cada
/// agente de ella (canales, grupos, carpetas) es de cada agente y vive en su
/// `AgentConfig`.
///
/// Sin secretos, igual que `AgentConfig`: el `client_id` es un identificador
/// público, y el `client_secret` nunca entra a este modelo.
public struct SharedConnection: Codable, Hashable, Sendable, Identifiable {
    public var tool: Tool
    public var status: ConnectionStatus
    /// El `client_id` de la app OAuth que el propio cliente trajo, para las
    /// herramientas que lo exigen (`tool.requiresUserProvidedOAuthClient`).
    public var oauthClientID: String?

    public var id: Tool { tool }

    public init(tool: Tool, status: ConnectionStatus, oauthClientID: String? = nil) {
        self.tool = tool
        self.status = status
        self.oauthClientID = oauthClientID
    }
}
