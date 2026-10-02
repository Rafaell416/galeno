/// Una herramienta que el usuario marcó en el paso 4, con su estado de conexión
/// (paso 5) y las fuentes que eligió leer (paso 6).
public struct ToolConnection: Codable, Hashable, Sendable, Identifiable {
    public var tool: Tool
    public var status: ConnectionStatus
    /// Qué lee el agente de esta herramienta.
    public var sources: SourceSelection

    /// El `client_id` de la app OAuth que el propio cliente trajo, para las
    /// herramientas que lo exigen (`tool.requiresUserProvidedOAuthClient`).
    /// `nil` para las demás, y para esta mientras el usuario aún no la trae.
    ///
    /// No es secreto: es un identificador público, como un nombre de
    /// usuario, así que puede vivir en texto plano en esta config. El
    /// `client_secret` nunca entra a este modelo.
    public var oauthClientID: String?

    public var id: Tool { tool }

    public init(
        tool: Tool,
        status: ConnectionStatus = .selected,
        sources: SourceSelection = .nothing,
        oauthClientID: String? = nil
    ) {
        self.tool = tool
        self.status = status
        self.sources = sources
        self.oauthClientID = oauthClientID
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
