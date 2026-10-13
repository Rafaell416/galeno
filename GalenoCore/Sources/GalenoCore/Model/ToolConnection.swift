/// Una herramienta que el usuario marcó en el paso 4, con su estado de conexión
/// (paso 5) y las fuentes que eligió leer (paso 6).
public struct ToolConnection: Codable, Hashable, Sendable, Identifiable {
    public var tool: Tool
    public var status: ConnectionStatus
    /// Qué lee el agente de esta herramienta.
    public var sources: SourceSelection

    /// Cuál de las cuentas de la herramienta es (`AccountID.slug(from:)`). `nil` es la cuenta de siempre: la que
    /// se conectó antes de que existieran las cuentas, o la única. Solo las herramientas que Galeno registra por
    /// su cuenta (`Tool.supportsMultipleAccounts`) pueden tener más de una.
    public var accountID: String?

    /// El nombre que el usuario le dio a esta cuenta («Trabajo»). Es lo que se muestra; `accountID` es lo que se
    /// escribe en el nombre del servidor.
    public var accountName: String?

    /// El `client_id` de la app OAuth que el propio cliente trajo, para las
    /// herramientas que lo exigen (`tool.requiresUserProvidedOAuthClient`).
    /// `nil` para las demás, y para esta mientras el usuario aún no la trae.
    ///
    /// No es secreto: es un identificador público, como un nombre de
    /// usuario, así que puede vivir en texto plano en esta config. El
    /// `client_secret` nunca entra a este modelo.
    public var oauthClientID: String?

    /// Prefijo con el que esta herramienta quedó registrada en Claude Code (`galeno-` → `galeno-slack`).
    /// Las conexiones nuevas lo llevan siempre (`MCPServerCatalog.defaultNamePrefix`). `nil` es el nombre del
    /// catálogo (`slack`): una conexión hecha antes de que Galeno tuviera nombres propios, que puede ser también
    /// del usuario. Se guarda para que `.mcp.json`, los permisos y los subagentes usen el mismo nombre con el que
    /// de verdad se registró.
    public var serverNamePrefix: String?

    /// Solo WhatsApp: el usuario aceptó la advertencia que dice que **su agente puede enviar mensajes** con su
    /// aprobación (la del 7 oct 2026). `nil` es una conexión de antes, hecha con la advertencia que decía «solo
    /// lectura»: ese agente sigue solo leyendo hasta que el usuario acepte la nueva. Sin esto, actualizar la app
    /// le daría a alguien un permiso que no dio.
    public var sendingAccepted: Bool?

    /// ¿Puede el agente escribir o enviar por esta conexión? Lo que dice la herramienta, salvo en WhatsApp,
    /// donde además hace falta que el usuario haya aceptado el envío (`sendingAccepted`).
    public var allowsWriting: Bool {
        tool.allowsWriting && (tool != .whatsapp || sendingAccepted == true)
    }

    /// ¿Le llega algo a otras personas por esta conexión? Es lo que decide si lleva regla `ask` y hook de
    /// aprobación. Un WhatsApp de solo lectura no envía nada: no los necesita.
    public var sendsToOthers: Bool {
        tool.externalSend != nil && (tool != .whatsapp || sendingAccepted == true)
    }

    /// ¿Registró Galeno este servidor con su nombre propio? Solo de esos puede cerrar la sesión o quitarlos:
    /// un servidor con el nombre genérico (`notion`) pudo ponerlo el usuario y lo usan sus otros proyectos.
    public var galenoOwnsServers: Bool {
        serverNamePrefix?.hasPrefix(MCPServerCatalog.ownedNamePrefix) == true
    }

    public var id: ConnectionID { ConnectionID(tool: tool, account: accountID) }

    /// El nombre que ve el usuario: el de la herramienta y, si es una cuenta aparte, el de la cuenta
    /// («Notion (Trabajo)»).
    public func displayName(in language: Language) -> String {
        let base = tool.displayName(in: language)
        guard let accountName, !accountName.isEmpty else { return base }
        return "\(base) (\(accountName))"
    }

    public init(
        tool: Tool,
        status: ConnectionStatus = .selected,
        sources: SourceSelection = .nothing,
        oauthClientID: String? = nil,
        serverNamePrefix: String? = nil,
        sendingAccepted: Bool? = nil,
        accountID: String? = nil,
        accountName: String? = nil
    ) {
        self.tool = tool
        self.status = status
        self.sources = sources
        self.oauthClientID = oauthClientID
        self.serverNamePrefix = serverNamePrefix
        self.sendingAccepted = sendingAccepted
        self.accountID = accountID
        self.accountName = accountName
    }
}

/// El estado de una herramienta dentro del sub-wizard de conexión (paso 5).
public enum ConnectionStatus: String, Codable, CaseIterable, Sendable {
    /// El usuario la marcó en el paso 4 pero todavía no la conectó.
    case selected
    /// El OAuth o el QR se completó.
    case connected
    /// El usuario dio "Conectar después". Queda marcada para conectarla más
    /// tarde desde la app; el motor no la configura.
    case skipped
}

/// Qué lee el agente de una herramienta (paso 6).
///
/// Es un tipo propio y no un `[Source]` pelado porque un array vacío sería
/// ambiguo: no distinguiría "el usuario todavía no eligió nada" de "lee todo".
/// Las tres herramientas de transcripción no tienen fuentes que elegir, así que
/// para ellas lo correcto es ``everything``.
public struct SourceSelection: Codable, Hashable, Sendable {
    /// El agente lee todo lo que la herramienta expone.
    public var readsEverything: Bool

    /// Las fuentes elegidas. Se ignora si ``readsEverything`` es `true`.
    public var selected: [Source]

    public init(readsEverything: Bool, selected: [Source]) {
        self.readsEverything = readsEverything
        self.selected = selected
    }

    /// Lee todo lo que la herramienta expone.
    public static let everything = SourceSelection(readsEverything: true, selected: [])

    /// No lee nada: el usuario todavía no eligió. Es el default seguro.
    public static let nothing = SourceSelection(readsEverything: false, selected: [])

    /// Lee solo estas fuentes.
    public static func only(_ sources: [Source]) -> SourceSelection {
        SourceSelection(readsEverything: false, selected: sources)
    }
}

/// Una fuente concreta dentro de una herramienta: un canal, un grupo, una
/// carpeta, un proyecto.
public struct Source: Codable, Hashable, Sendable, Identifiable {
    /// El id nativo de la herramienta: el id del canal de Slack, la clave del
    /// proyecto de Jira, el JID del grupo de WhatsApp.
    public var id: String

    /// Lo que el usuario ve: "#producto", "Equipo Cliente A".
    public var name: String

    public var kind: SourceKind

    public init(id: String, name: String, kind: SourceKind) {
        self.id = id
        self.name = name
        self.kind = kind
    }
}

/// El tipo de una fuente. Determina cómo la nombra la UI y cómo la escribe el
/// motor en la config.
public enum SourceKind: String, Codable, CaseIterable, Sendable {
    /// Slack.
    case channel
    /// WhatsApp, grupo.
    case group
    /// WhatsApp, conversación individual.
    case chat
    /// Notion.
    case page
    /// Notion.
    case database
    /// Google Drive.
    case folder
    /// Jira.
    case project
    /// Gmail.
    case mailLabel = "mail-label"
}
