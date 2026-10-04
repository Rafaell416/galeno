/// Cómo se autentica un servidor MCP.
///
/// No existe un caso que lleve el valor de un token o de un `client_secret`.
/// `bearerToken` guarda el **nombre** de una variable de entorno, y
/// `oauthWithUserProvidedClient` guarda el `client_id` —que no es secreto, es
/// un identificador público— de la app que el propio cliente registró con el
/// proveedor. El renderer compone el JSON a partir de esto; no hay forma de
/// que un valor secreto acabe en texto plano en `.mcp.json`.
public enum MCPAuthentication: Hashable, Sendable {
    /// Registro dinámico de cliente: Claude Code se presenta solo ante el
    /// servidor, sin que nadie haya creado una app de antemano. Así funcionan
    /// Notion y Jira.
    case oauth
    /// La app OAuth la registró el propio cliente —nunca Galeno— con el
    /// proveedor (Slack, Google). `clientID` es ese identificador público;
    /// `scopes`, los permisos que esa app debe pedir.
    case oauthWithUserProvidedClient(clientID: String, scopes: [String])
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
    /// Si el endpoint está confirmado contra la documentación oficial del
    /// proveedor. Los que no, salen como advertencia para que no se nos
    /// olvide verificarlos antes de vender.
    public var endpointIsVerified: Bool
    /// Las herramientas del servidor que **solo leen**, por su nombre exacto y verificadas contra el
    /// servidor real. Solo importa en los servidores que también envían a otras personas (Slack):
    /// estas van sin preguntar, y todo lo demás del servidor —lo conocido y lo que aparezca
    /// después— pide aprobación. Vacío = no se sabe cuáles leen, así que todo el servidor pregunta.
    public var readOnlyTools: [String]
    /// Las herramientas del servidor que escriben o envían, verificadas igual. Llevan su regla
    /// `ask` explícita; el hook de aprobación cubre además cualquiera que no esté en ninguna lista.
    public var writeTools: [String]

    public init(
        serverName: String,
        transport: MCPTransport,
        authentication: MCPAuthentication = .oauth,
        endpointIsVerified: Bool,
        readOnlyTools: [String] = [],
        writeTools: [String] = []
    ) {
        self.serverName = serverName
        self.transport = transport
        self.authentication = authentication
        self.endpointIsVerified = endpointIsVerified
        self.readOnlyTools = readOnlyTools
        self.writeTools = writeTools
    }
}

/// Qué servidor (o servidores) MCP le corresponden a cada herramienta.
///
/// No sabe nada de una conexión concreta del usuario: es un catálogo estático,
/// por `Tool`. El `client_id` que el cliente trae para Slack/Gmail/Google
/// Workspace vive en `ToolConnection`, y es el renderer quien lo combina con
/// lo que hay aquí al momento de generar — así el catálogo se queda simple y
/// se puede seguir probando sin nada de estado.
public enum MCPServerCatalog {
    /// Prefijo del nombre alternativo (`galeno-slack`) para cuando el normal ya
    /// lo usa otro servidor del usuario en Claude Code.
    public static let alternateNamePrefix = "galeno-"

    /// Las definiciones de una conexión concreta: las de su herramienta, con el
    /// nombre con el que de verdad quedó registrada (`serverNamePrefix`).
    /// Las 27 herramientas del MCP de Slack, vistas en el servidor real el 4 de octubre de 2026 (la
    /// lista que Claude Code recibe al conectarse). Estas 14 solo leen. Si Slack añade una, no estará
    /// aquí y pedirá aprobación hasta que se revise: el fallo es hacia preguntar de más, nunca de menos.
    static let slackReadOnlyTools = [
        "slack_get_reactions",
        "slack_list_channel_members",
        "slack_list_user_channels",
        "slack_read_canvas",
        "slack_read_channel",
        "slack_read_file",
        "slack_read_list",
        "slack_read_thread",
        "slack_read_user_profile",
        "slack_search_channels",
        "slack_search_emojis",
        "slack_search_public",
        "slack_search_public_and_private",
        "slack_search_users",
    ]

    /// Las otras 13: envían un mensaje o cambian algo en Slack. Siempre piden aprobación.
    static let slackWriteTools = [
        "slack_add_list_record",
        "slack_add_reaction",
        "slack_complete_file_upload",
        "slack_create_canvas",
        "slack_create_conversation",
        "slack_create_list",
        "slack_get_file_upload_url",
        "slack_schedule_message",
        "slack_send_message",
        "slack_send_message_draft",
        "slack_update_canvas",
        "slack_update_list",
        "slack_update_list_record",
    ]

    public static func definitions(
        for connection: ToolConnection,
        whatsAppBridgePath: String
    ) -> [MCPServerDefinition] {
        definitions(for: connection.tool, whatsAppBridgePath: whatsAppBridgePath).map { definition in
            guard let prefix = connection.serverNamePrefix, !prefix.isEmpty else { return definition }
            var renamed = definition
            renamed.serverName = prefix + definition.serverName
            return renamed
        }
    }

    /// Las definiciones de una herramienta. Vacío si no tiene servidor propio:
    /// es el caso de Google Meet, que no tiene MCP y se lee por el de Google
    /// Workspace. Google Workspace es la única con más de una (Drive, Docs y
    /// Sheets son tres servidores separados del lado de Google, aunque el
    /// wizard los muestre como una sola tool).
    ///
    /// Para Slack, Gmail y Google Workspace, `authentication` queda en
    /// `.oauth` como relleno: el renderer la sustituye por
    /// `.oauthWithUserProvidedClient` usando el `client_id` de la conexión.
    public static func definitions(
        for tool: Tool,
        whatsAppBridgePath: String
    ) -> [MCPServerDefinition] {
        switch tool {
        case .whatsapp:
            // El único local: el binario Go que la app empaqueta y supervisa.
            // Es de solo lectura por estructura: no tiene herramientas de envío.
            return [
                MCPServerDefinition(
                    serverName: "whatsapp",
                    transport: .stdio(command: whatsAppBridgePath, arguments: ["serve"]),
                    endpointIsVerified: true
                )
            ]

        // Confirmados en la spec §4b.
        case .fireflies:
            return [
                MCPServerDefinition(
                    serverName: "fireflies",
                    transport: .http(url: "https://api.fireflies.ai/mcp"),
                    endpointIsVerified: true
                )
            ]
        case .granola:
            return [
                MCPServerDefinition(
                    serverName: "granola",
                    transport: .http(url: "https://mcp.granola.ai/mcp"),
                    endpointIsVerified: true
                )
            ]
        case .fathom:
            return [
                MCPServerDefinition(
                    serverName: "fathom",
                    transport: .http(url: "https://api.fathom.ai/mcp"),
                    endpointIsVerified: true
                )
            ]

        case .notion:
            // Registro dinámico: confirmado contra developers.notion.com.
            return [
                MCPServerDefinition(
                    serverName: "notion",
                    transport: .http(url: "https://mcp.notion.com/mcp"),
                    endpointIsVerified: true
                )
            ]
        case .jira:
            // v2/mcp confirmado contra la documentación de Atlassian Rovo MCP.
            // v1/sse (lo que tenía antes) se apaga el 30 de junio de 2026.
            // Registro dinámico, como Notion: nadie necesita crear una app.
            return [
                MCPServerDefinition(
                    serverName: "jira",
                    transport: .http(url: "https://mcp.atlassian.com/v2/mcp"),
                    endpointIsVerified: true
                )
            ]

        case .slack:
            // Confirmado contra docs.slack.dev. Requiere una app que el
            // cliente trae (ver SlackManifestRenderer); el renderer rellena
            // la autenticación real con el client_id de la conexión.
            return [
                MCPServerDefinition(
                    serverName: "slack",
                    transport: .http(url: "https://mcp.slack.com/mcp"),
                    endpointIsVerified: true,
                    readOnlyTools: slackReadOnlyTools,
                    writeTools: slackWriteTools
                )
            ]
        case .gmail:
            // Confirmado contra developers.google.com/workspace. Igual que
            // Slack: requiere la app propia del cliente.
            return [
                MCPServerDefinition(
                    serverName: "gmail",
                    transport: .http(url: "https://gmailmcp.googleapis.com/mcp/v1"),
                    endpointIsVerified: true
                )
            ]
        case .googleWorkspace:
            // No es un servidor, son tres: Drive, Docs y Sheets tienen cada
            // uno su propio endpoint del lado de Google. El wizard los
            // muestra como una sola tool; aquí se reparten en tres entradas
            // de .mcp.json, las tres con el mismo client_id del cliente.
            return [
                MCPServerDefinition(
                    serverName: "google-drive",
                    transport: .http(url: "https://drivemcp.googleapis.com/mcp/v1"),
                    endpointIsVerified: true
                ),
                MCPServerDefinition(
                    serverName: "google-docs",
                    transport: .http(url: "https://docsmcp.googleapis.com/mcp/v1"),
                    endpointIsVerified: true
                ),
                MCPServerDefinition(
                    serverName: "google-sheets",
                    transport: .http(url: "https://sheetsmcp.googleapis.com/mcp/v1"),
                    endpointIsVerified: true
                ),
            ]

        case .claudeDesign:
            // **No verificado**: es el servidor que Claude Code ya inyecta solo como `claude_design`, pero no
            // está documentado como servidor que se registre. Va con otro nombre (`claude-design`) para no
            // chocar con el inyectado, y la generación avisa con `unverifiedEndpoint`.
            return [
                MCPServerDefinition(
                    serverName: "claude-design",
                    transport: .http(url: "https://api.anthropic.com/v1/design/mcp"),
                    endpointIsVerified: false
                )
            ]

        case .googleMeet:
            return []
        }
    }
}
