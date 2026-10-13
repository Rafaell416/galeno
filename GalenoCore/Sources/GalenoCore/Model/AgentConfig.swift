import Foundation

/// Todo lo que el wizard captura, y la única entrada del motor que genera la
/// configuración de Claude Code.
///
/// No contiene credenciales. Los tokens del usuario nunca pasan por aquí: en
/// `.mcp.json` quedan como referencias a variables de entorno. Un `AgentConfig`
/// se puede escribir a disco o adjuntar a un reporte de soporte sin riesgo.
public struct AgentConfig: Codable, Hashable, Sendable {
    /// La versión de formato que escribe esta versión de la app.
    public static let currentSchemaVersion = 2

    /// Versión del formato, para poder migrar configs guardadas por versiones
    /// anteriores de la app.
    public var schemaVersion: Int

    /// El nombre que el usuario le puso a *su* agente (paso 3 del wizard).
    /// Galeno es la app; el agente es del usuario.
    public var agentName: String

    /// Idioma del wizard y del output del agente (paso 1).
    public var language: Language

    /// El rol del agente (paso 3). En v0.0.1 solo `.productManager`.
    public var role: AgentRole

    /// Una línea que describe el proyecto (paso 3 del wizard). El agente la
    /// completa en su primera sesión y guarda el resumen en su memoria. Vacía
    /// si el usuario no la escribió, y en toda config guardada con el formato 1.
    public var projectDescription: String

    /// Las herramientas que el usuario marcó, en el orden del sub-wizard
    /// (pasos 4, 5 y 6). Una entrada por cuenta: sin repetir `(herramienta, cuenta)`. Casi siempre es una por
    /// herramienta; Notion, Jira y Slack pueden llevar más de una cuenta (`ToolConnection.accountID`).
    public var connections: [ToolConnection]

    /// Las skills que quedaron marcadas (paso 7).
    public var skills: [SelectedSkill]

    /// Qué escrituras internas van sin preguntar (paso 8). Los envíos externos
    /// no son configurables: ver ``SendingRules``.
    public var sendingRules: SendingRules

    public init(
        schemaVersion: Int = AgentConfig.currentSchemaVersion,
        agentName: String,
        language: Language,
        role: AgentRole = .productManager,
        projectDescription: String = "",
        connections: [ToolConnection] = [],
        skills: [SelectedSkill] = [],
        sendingRules: SendingRules = .default
    ) {
        self.schemaVersion = schemaVersion
        self.agentName = agentName
        self.language = language
        self.role = role
        self.projectDescription = projectDescription
        self.connections = connections
        self.skills = skills
        self.sendingRules = sendingRules
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, agentName, language, role, projectDescription
        case connections, skills, sendingRules
    }

    /// Lee una config guardada con cualquier versión anterior. Los campos que
    /// el formato 1 no tenía se leen vacíos; `schemaVersion` queda como estaba
    /// guardado, para saber de dónde viene.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        agentName = try container.decode(String.self, forKey: .agentName)
        language = try container.decode(Language.self, forKey: .language)
        role = try container.decode(AgentRole.self, forKey: .role)
        projectDescription =
            try container.decodeIfPresent(String.self, forKey: .projectDescription) ?? ""
        connections = try container.decode([ToolConnection].self, forKey: .connections)
        skills = try container.decode([SelectedSkill].self, forKey: .skills)
        sendingRules = try container.decode(SendingRules.self, forKey: .sendingRules)
    }
}

extension AgentConfig {
    /// Las herramientas efectivamente conectadas. Las que el usuario marcó pero
    /// no llegó a conectar, y las que saltó con "Conectar después", no cuentan:
    /// el motor no las configura.
    public var connectedTools: [Tool] {
        var seen = Set<Tool>()
        return connections.filter { $0.status == .connected }.map(\.tool).filter { seen.insert($0).inserted }
    }

    /// Las conexiones efectivamente conectadas, con todo lo que las describe.
    public var connectedConnections: [ToolConnection] {
        connections.filter { $0.status == .connected }
    }

    /// La conexión de una herramienta, si el usuario la marcó. Con varias cuentas, la de siempre
    /// (`accountID == nil`) y, si no la hay, la primera.
    public func connection(for tool: Tool) -> ToolConnection? {
        connections.first { $0.tool == tool && $0.accountID == nil } ?? connections.first { $0.tool == tool }
    }

    /// La conexión de una cuenta concreta de una herramienta.
    public func connection(for id: ConnectionID) -> ToolConnection? {
        connections.first { $0.id == id }
    }

    /// Todas las cuentas de una herramienta, en el orden en que se marcaron.
    public func connections(for tool: Tool) -> [ToolConnection] {
        connections.filter { $0.tool == tool }
    }
}

extension AgentConfig {
    /// El encoder que usa el motor: claves ordenadas para que el archivo sea
    /// estable entre corridas, y con sangría para poder leerlo a ojo.
    ///
    /// Es una propiedad calculada y no una constante porque `JSONEncoder` no es
    /// `Sendable`: cada quien usa la suya.
    public static var jsonEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    public static var jsonDecoder: JSONDecoder {
        JSONDecoder()
    }
}
