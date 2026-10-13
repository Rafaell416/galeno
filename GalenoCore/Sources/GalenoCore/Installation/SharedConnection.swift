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
    /// Ver `ToolConnection.serverNamePrefix`.
    public var serverNamePrefix: String?
    /// Ver `ToolConnection.sendingAccepted`. WhatsApp es un solo dispositivo vinculado para todos los agentes,
    /// así que la advertencia se acepta una vez y vale para todos.
    public var sendingAccepted: Bool?
    /// Ver `ToolConnection.accountID`. `nil` es la cuenta de siempre de la herramienta.
    public var accountID: String?
    /// Ver `ToolConnection.accountName`.
    public var accountName: String?

    /// Ver `ToolConnection.galenoOwnsServers`.
    public var galenoOwnsServers: Bool {
        serverNamePrefix?.hasPrefix(MCPServerCatalog.ownedNamePrefix) == true
    }

    public var id: ConnectionID { ConnectionID(tool: tool, account: accountID) }

    public init(
        tool: Tool,
        status: ConnectionStatus,
        oauthClientID: String? = nil,
        serverNamePrefix: String? = nil,
        sendingAccepted: Bool? = nil,
        accountID: String? = nil,
        accountName: String? = nil
    ) {
        self.tool = tool
        self.status = status
        self.oauthClientID = oauthClientID
        self.serverNamePrefix = serverNamePrefix
        self.sendingAccepted = sendingAccepted
        self.accountID = accountID
        self.accountName = accountName
    }
}
