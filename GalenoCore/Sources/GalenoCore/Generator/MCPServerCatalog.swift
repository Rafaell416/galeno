/// Cómo se autentica un servidor MCP.
///
/// No existe un caso que lleve el valor de un token: `bearerToken` guarda el
/// **nombre** de una variable de entorno, y el renderer escribe `${NOMBRE}`. Así
/// no hay forma de que un token acabe en texto plano en `.mcp.json`.
public enum MCPAuthentication: Hashable, Sendable {
    /// Claude Code gestiona el OAuth; en `.mcp.json` no va nada de autenticación.
    case oauth
    /// Cabecera `Authorization: Bearer ${nombre}`.
    case bearerToken(environmentVariable: String)
}

/// Cómo se habla con un servidor MCP.
public enum MCPTransport: Hashable, Sendable {
    /// Un binario local que Claude Code lanza por stdio. Solo WhatsApp.
    case stdio(command: String, arguments: [String])
    case http(url: String)
}

/// La definición de un servidor MCP para una herramienta.
public struct MCPServerDefinition: Hashable, Sendable {
    /// La clave dentro de `mcpServers`, y el prefijo de sus herramientas en las
    /// reglas de permisos (`mcp__<serverName>__*`).
    public var serverName: String
    public var transport: MCPTransport
    public var authentication: MCPAuthentication
    /// Si el endpoint está confirmado. Los que no, salen como advertencia para
    /// que no se nos olvide verificarlos antes de vender.
    public var endpointIsVerified: Bool

    public init(
        serverName: String,
        transport: MCPTransport,
        authentication: MCPAuthentication = .oauth,
        endpointIsVerified: Bool
    ) {
        self.serverName = serverName
        self.transport = transport
        self.authentication = authentication
        self.endpointIsVerified = endpointIsVerified
    }
}

/// Qué servidor MCP le corresponde a cada herramienta.
public enum MCPServerCatalog {
    /// La definición de una herramienta, o `nil` si no tiene servidor propio.
    ///
    /// Google Meet devuelve `nil`: no tiene MCP propio. Las transcripciones que
    /// genera Gemini caen en Drive y se leen con el MCP de Google Workspace.
    public static func definition(
        for tool: Tool,
        whatsAppBridgePath: String
    ) -> MCPServerDefinition? {
        switch tool {
        case .whatsapp:
            // El único local: el binario Go que la app empaqueta y supervisa.
            // Es de solo lectura por estructura: no tiene herramientas de envío.
            return MCPServerDefinition(
                serverName: "whatsapp",
                transport: .stdio(command: whatsAppBridgePath, arguments: ["mcp"]),
                endpointIsVerified: true
            )

        // Confirmados en la spec §4b.
        case .fireflies:
            return MCPServerDefinition(
                serverName: "fireflies",
                transport: .http(url: "https://api.fireflies.ai/mcp"),
                endpointIsVerified: true
            )
        case .granola:
            return MCPServerDefinition(
                serverName: "granola",
                transport: .http(url: "https://mcp.granola.ai/mcp"),
                endpointIsVerified: true
            )
        case .fathom:
            return MCPServerDefinition(
                serverName: "fathom",
                transport: .http(url: "https://api.fathom.ai/mcp"),
                endpointIsVerified: true
            )

        // Sin verificar: la spec no da el endpoint y no lo hemos comprobado
        // conectándonos. Salen como advertencia en GenerationResult.
        case .slack:
            return MCPServerDefinition(
                serverName: "slack",
                transport: .http(url: "https://mcp.slack.com/mcp"),
                endpointIsVerified: false
            )
        case .notion:
            return MCPServerDefinition(
                serverName: "notion",
                transport: .http(url: "https://mcp.notion.com/mcp"),
                endpointIsVerified: false
            )
        case .gmail:
            return MCPServerDefinition(
                serverName: "gmail",
                transport: .http(url: "https://mcp.google.com/gmail/mcp"),
                endpointIsVerified: false
            )
        case .googleWorkspace:
            return MCPServerDefinition(
                serverName: "google-workspace",
                transport: .http(url: "https://mcp.google.com/workspace/mcp"),
                endpointIsVerified: false
            )
        case .jira:
            return MCPServerDefinition(
                serverName: "jira",
                transport: .http(url: "https://mcp.atlassian.com/v1/sse"),
                endpointIsVerified: false
            )

        case .googleMeet:
            return nil
        }
    }
}
