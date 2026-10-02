import Foundation

/// Todo lo que el wizard captura, y la única entrada del motor que genera la
/// configuración de Claude Code.
///
/// No contiene credenciales. Los tokens del usuario nunca pasan por aquí: en
/// `.mcp.json` quedan como referencias a variables de entorno. Un `AgentConfig`
/// se puede escribir a disco o adjuntar a un reporte de soporte sin riesgo.
public struct AgentConfig: Codable, Hashable, Sendable {
    /// La versión de formato que escribe esta versión de la app.
    public static let currentSchemaVersion = 1

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

    /// Las herramientas que el usuario marcó, en el orden del sub-wizard
    /// (pasos 4, 5 y 6). Se espera una entrada por herramienta, sin repetir.
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
        connections: [ToolConnection] = [],
        skills: [SelectedSkill] = [],
        sendingRules: SendingRules = .default
    ) {
        self.schemaVersion = schemaVersion
        self.agentName = agentName
        self.language = language
        self.role = role
        self.connections = connections
        self.skills = skills
        self.sendingRules = sendingRules
    }
}

extension AgentConfig {
    /// Las herramientas efectivamente conectadas. Las que el usuario marcó pero
    /// no llegó a conectar, y las que saltó con "Conectar después", no cuentan:
    /// el motor no las configura.
    public var connectedTools: [Tool] {
        connections.filter { $0.status == .connected }.map(\.tool)
    }

    /// La conexión de una herramienta, si el usuario la marcó.
    public func connection(for tool: Tool) -> ToolConnection? {
        connections.first { $0.tool == tool }
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
