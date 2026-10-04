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
    /// Un conector de la cuenta de claude.ai del usuario (Gmail, Google Drive). Claude Code lo trae
    /// solo cuando el usuario entra con su cuenta de Claude: **no se registra ni va en `.mcp.json`**.
    /// `name` es el nombre con el que aparece en Claude («Google Drive» → `claude.ai Google Drive`) y
    /// `directorySlug` su página en el directorio de conectores (`claude.ai/directory/<slug>`), donde
    /// está el botón para conectarlo.
    case claudeConnector(name: String, directorySlug: String)
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
    /// Las que piden aprobación **siempre**, aunque la herramienta no envíe mensajes: compartir un
    /// archivo con otra persona o mandarlo a la papelera (Google Drive).
    public var alwaysAskTools: [String]

    public init(
        serverName: String,
        transport: MCPTransport,
        authentication: MCPAuthentication = .oauth,
        endpointIsVerified: Bool,
        readOnlyTools: [String] = [],
        writeTools: [String] = [],
        alwaysAskTools: [String] = []
    ) {
        self.alwaysAskTools = alwaysAskTools
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
/// por `Tool`. El `client_id` que el cliente trae para Slack
/// vive en `ToolConnection`, y es el renderer quien lo combina con
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
            // Un conector de claude.ai no se registra: su nombre lo pone Claude y no admite prefijo.
            if case .claudeConnector = definition.transport { return definition }
            guard let prefix = connection.serverNamePrefix, !prefix.isEmpty else { return definition }
            var renamed = definition
            renamed.serverName = prefix + definition.serverName
            return renamed
        }
    }

    /// Las definiciones de una herramienta. Vacío si no tiene servidor propio:
    /// es el caso de Google Meet, que no tiene MCP y se lee por Google Drive.
    /// Gmail y «Google Drive, Docs y Sheets» son conectores de la cuenta de
    /// Claude del usuario (`.claudeConnector`): no se registran.
    ///
    /// Para Slack, `authentication` queda en `.oauth` como relleno: el
    /// renderer la sustituye por `.oauthWithUserProvidedClient` usando el
    /// `client_id` de la conexión.
    /// Cómo nombra Claude Code las herramientas de un conector de claude.ai: `mcp__claude_ai_<Nombre>__…`,
    /// con los espacios del nombre como guiones bajos (visto con «Google Drive» y «Claude Docs»).
    public static func claudeConnectorServerName(_ name: String) -> String {
        "claude_ai_" + name.replacingOccurrences(of: " ", with: "_")
    }

    /// Los nombres de los conectores de claude.ai por los que llega una herramienta («Google Drive»,
    /// «Google Docs»…), tal como los muestra Claude. Vacío si la herramienta no usa conectores.
    public static func claudeConnectorNames(for tool: Tool) -> [String] {
        definitions(for: tool, whatsAppBridgePath: "").compactMap { definition in
            if case let .claudeConnector(name, _) = definition.transport { return name }
            return nil
        }
    }

    /// Un conector de Google de la cuenta de Claude del usuario. Los cinco (Gmail, Calendar, Drive, Docs y
    /// Sheets) se vieron en una cuenta real el 4 de octubre de 2026: el nombre con el que Claude los
    /// expone es el del directorio, y las listas de abajo son las herramientas que recibe la sesión. Si
    /// Google añade una, no estará en ninguna lista y el hook la detiene: el fallo es hacia preguntar de más.
    private static func googleConnector(
        _ name: String, slug: String, reads: [String], writes: [String], alwaysAsk: [String] = []
    ) -> MCPServerDefinition {
        MCPServerDefinition(
            serverName: claudeConnectorServerName(name),
            transport: .claudeConnector(name: name, directorySlug: slug),
            endpointIsVerified: true,
            readOnlyTools: reads,
            writeTools: writes,
            alwaysAskTools: alwaysAsk
        )
    }

    /// Las 30 herramientas del conector de Gmail. Estas seis solo leen.
    static let gmailReadOnlyTools = [
        "get_draft",
        "get_message",
        "get_thread",
        "list_drafts",
        "list_labels",
        "search_threads",
    ]

    /// Las otras 24: tres envían un correo (`send_message`, `reply`, `forward`) y el resto cambia algo en
    /// el buzón (borradores, etiquetas, papelera, spam). Gmail le habla a otras personas, así que todas
    /// piden aprobación.
    static let gmailWriteTools = [
        "apply_sensitive_message_label",
        "apply_sensitive_thread_label",
        "create_draft",
        "create_label",
        "delete_draft",
        "delete_label",
        "forward",
        "label_message",
        "label_thread",
        "mark_message_spam",
        "mark_thread_spam",
        "reply",
        "send_message",
        "trash_message",
        "trash_thread",
        "unlabel_message",
        "unlabel_thread",
        "unmark_message_spam",
        "unmark_thread_spam",
        "untrash_message",
        "untrash_thread",
        "update_draft",
        "update_label",
        "update_message_labels",
    ]

    /// Las 9 de Google Sheets: dos leen y siete cambian una hoja del propio usuario.
    static let googleSheetsReadOnlyTools = ["get_spreadsheet", "get_values"]
    static let googleSheetsWriteTools = [
        "append_values",
        "batch_clear_values",
        "copy_sheet_to_another_spreadsheet",
        "insert_dimension",
        "update_formulas",
        "update_spreadsheet",
        "update_values",
    ]

    /// Las 9 de Google Calendar: cinco leen; las otras cuatro crean, cambian o borran un evento, o
    /// responden a una invitación.
    static let googleCalendarReadOnlyTools = ["get_event", "list_calendars", "list_events", "search_events", "suggest_time"]
    static let googleCalendarWriteTools = ["create_event", "delete_event", "respond_to_event", "update_event"]

    /// Las 11 herramientas del conector de Google Drive, vistas en una cuenta real el 4 de octubre de
    /// 2026. Estas seis solo leen.
    static let googleDriveReadOnlyTools = [
        "download_file_content",
        "get_file_metadata",
        "get_file_permissions",
        "list_recent_files",
        "read_file_content",
        "search_files",
    ]

    /// Crean o cambian un archivo del propio usuario: siguen la regla de Docs y Sheets del paso «Reglas».
    static let googleDriveWriteTools = ["copy_file", "create_file", "update_file"]

    /// Compartir le llega a otra persona y la papelera quita un archivo: siempre piden aprobación.
    static let googleDriveAlwaysAskTools = ["share_file", "trash_file"]

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
            // Por el conector de Gmail de la cuenta de Claude del usuario (ver `.googleWorkspace`).
            return [googleConnector("Gmail", slug: "gmail-gmailmcp", reads: gmailReadOnlyTools, writes: gmailWriteTools)]

        case .googleWorkspace:
            // Por los conectores «Google Drive», «Google Docs» y «Google Sheets» de la cuenta de Claude
            // del usuario, que usan los servidores oficiales de Google con la app OAuth de Anthropic.
            //
            // Se descartó que cada cliente trajera su propia app de Google Cloud (octubre de 2026):
            // los servidores de Google siguen en Developer Preview, que exige inscribir el proyecto
            // en su programa (aprobación manual de días, solo cuentas de Workspace).
            return [
                googleConnector(
                    "Google Drive", slug: "google-drive-drivemcp",
                    reads: googleDriveReadOnlyTools, writes: googleDriveWriteTools,
                    alwaysAsk: googleDriveAlwaysAskTools),
                googleConnector(
                    "Google Docs", slug: "google-docs-docsmcp", reads: ["read_doc"], writes: ["update_doc"]),
                googleConnector(
                    "Google Sheets", slug: "google-sheets-sheetsmcp",
                    reads: googleSheetsReadOnlyTools, writes: googleSheetsWriteTools),
            ]

        case .googleCalendar:
            // Leer el calendario no pregunta. Crear, cambiar o borrar un evento, o responder a una
            // invitación, les llega a otras personas: siempre pide aprobación (`Tool.externalSend`).
            return [
                googleConnector(
                    "Google Calendar", slug: "google-calendar-calendarmcp",
                    reads: googleCalendarReadOnlyTools, writes: googleCalendarWriteTools)
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
