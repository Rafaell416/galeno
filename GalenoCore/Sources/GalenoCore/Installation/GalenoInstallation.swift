import Foundation

/// Un agente de la instalación: su config y su carpeta.
public struct AgentRecord: Codable, Hashable, Sendable, Identifiable {
    /// Estable: renombrar el agente no lo cambia.
    public var id: UUID
    public var config: AgentConfig
    /// Ruta absoluta de la carpeta del agente. Se fija al crearlo (ver
    /// ``AgentFolder``) y no cambia sola.
    public var folderPath: String

    public var folder: URL { URL(filePath: folderPath, directoryHint: .isDirectory) }

    public init(id: UUID = UUID(), config: AgentConfig, folderPath: String) {
        self.id = id
        self.config = config
        self.folderPath = folderPath
    }
}

public enum InstallationError: Error, Equatable {
    /// El archivo existe pero no se pudo leer o no es una instalación válida.
    /// No se sobrescribe: puede ser lo único que recuerda los agentes.
    case unreadable(path: String, reason: String)
    /// Lo guardó una versión más nueva de la app.
    case newerThanThisApp(found: Int, supported: Int)
    case unknownAgent(UUID)
}

extension InstallationError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .unreadable(path, reason):
            "No pude leer la instalación de Galeno en \(path): \(reason). No la toqué."
        case let .newerThanThisApp(found, supported):
            "La instalación la guardó una versión más nueva de Galeno (formato \(found); esta lee hasta el \(supported))."
        case let .unknownAgent(id):
            "No hay ningún agente con el id \(id)."
        }
    }
}

/// Todo lo que Galeno recuerda entre una sesión y otra: las conexiones, que se
/// hacen una vez y se comparten, y la lista de agentes, uno por proyecto.
///
/// Sin secretos, igual que ``AgentConfig``: se puede escribir a disco o
/// adjuntar a un reporte de soporte sin riesgo.
public struct GalenoInstallation: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int

    /// El idioma que se eligió en el paso 1 del wizard. Vive aquí y no en cada
    /// agente porque el wizard corto no lo vuelve a preguntar.
    public var language: Language

    public var connections: [SharedConnection]
    public var agents: [AgentRecord]

    public init(
        schemaVersion: Int = GalenoInstallation.currentSchemaVersion,
        language: Language,
        connections: [SharedConnection] = [],
        agents: [AgentRecord] = []
    ) {
        self.schemaVersion = schemaVersion
        self.language = language
        self.connections = connections
        self.agents = agents
    }
}

// MARK: - Conexiones

extension GalenoInstallation {
    public func connection(for tool: Tool) -> SharedConnection? {
        connections.first { $0.tool == tool }
    }

    /// Añade la conexión, o reemplaza la que ya había de esa herramienta.
    public mutating func setConnection(_ connection: SharedConnection) {
        if let index = connections.firstIndex(where: { $0.tool == connection.tool }) {
            connections[index] = connection
        } else {
            connections.append(connection)
        }
    }
}

// MARK: - Agentes

extension GalenoInstallation {
    public func agent(id: UUID) -> AgentRecord? {
        agents.first { $0.id == id }
    }

    /// El punto de partida de un agente nuevo: la base del wizard corto.
    ///
    /// Trae el idioma de la instalación, el rol PM, las reglas por defecto, y
    /// una conexión por cada herramienta **ya conectada**, con su `client_id`.
    /// Qué lee de cada una queda sin elegir —el paso "qué leer" del wizard
    /// corto lo decide—, salvo en las de transcripción, que no tienen fuentes
    /// que elegir y leen todo. Las herramientas saltadas o sin conectar no
    /// entran: son las que el wizard corto vuelve a ofrecer. Sin skills: el
    /// catálogo vive fuera del motor.
    public func startingPoint(agentName: String, projectDescription: String = "") -> AgentConfig {
        let connected = connections
            .filter { $0.status == .connected }
            .map { shared in
                ToolConnection(
                    tool: shared.tool,
                    status: .connected,
                    sources: shared.tool.selectableSourceKinds.isEmpty ? .everything : .nothing,
                    oauthClientID: shared.oauthClientID,
                    serverNamePrefix: shared.serverNamePrefix
                )
            }

        return AgentConfig(
            agentName: agentName,
            language: language,
            projectDescription: projectDescription,
            connections: connected
        )
    }

    /// Registra un agente nuevo y le asigna su carpeta en `agentsRoot`
    /// (`~/Galeno` por defecto), sin chocar con la de otro agente ni con nada
    /// que ya exista en disco. No escribe ningún archivo del agente: eso lo
    /// hace ``ConfigGenerator``.
    @discardableResult
    public mutating func addAgent(
        _ config: AgentConfig,
        agentsRoot: URL = AgentFolder.defaultRoot,
        fileManager: FileManager = .default
    ) -> AgentRecord {
        let folder = AgentFolder.uniqueFolder(
            for: config.agentName,
            in: agentsRoot,
            avoiding: agents.map(\.folder),
            fileManager: fileManager
        )
        let record = AgentRecord(config: config, folderPath: folder.path)
        agents.append(record)
        return record
    }

    /// Reemplaza la config de un agente que ya existe (la base de "gestionar
    /// la config").
    public mutating func setConfig(_ config: AgentConfig, for agentID: UUID) throws {
        guard let index = agents.firstIndex(where: { $0.id == agentID }) else {
            throw InstallationError.unknownAgent(agentID)
        }
        agents[index].config = config
    }

    /// Saca un agente de la lista. **No toca nada en disco**: su carpeta, su memoria y las conexiones compartidas
    /// (que otros agentes usan) quedan como estaban; quien llama decide qué hacer con la carpeta.
    @discardableResult
    public mutating func removeAgent(id agentID: UUID) throws -> AgentRecord {
        guard let index = agents.firstIndex(where: { $0.id == agentID }) else {
            throw InstallationError.unknownAgent(agentID)
        }
        return agents.remove(at: index)
    }

    /// La config del agente lista para el generador: el estado y el `client_id`
    /// de cada herramienta se toman de las conexiones compartidas.
    ///
    /// Así hay una sola fuente de verdad. Cambiar el `client_id` de Slack una
    /// vez llega a todos los agentes, y una herramienta que se desconecta
    /// desaparece de todos al regenerar. Una herramienta del agente que no está
    /// entre las compartidas se queda como estaba.
    public func resolvedConfig(for agentID: UUID) -> AgentConfig? {
        guard var config = agent(id: agentID)?.config else { return nil }

        config.connections = config.connections.map { connection in
            guard let shared = self.connection(for: connection.tool) else { return connection }
            var resolved = connection
            resolved.status = shared.status
            resolved.oauthClientID = shared.oauthClientID
            resolved.serverNamePrefix = shared.serverNamePrefix
            return resolved
        }
        return config
    }
}
