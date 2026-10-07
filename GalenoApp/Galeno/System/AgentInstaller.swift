import Foundation
import GalenoCore

/// Lo que ocurre al final del wizard: el agente se registra en la instalación de Galeno, se
/// escribe su carpeta (`~/Galeno/<nombre>/`) y la instalación se guarda.
///
/// Todo el trabajo es del motor (`ConfigGenerator`, `GalenoInstallation`); aquí solo se junta.
/// **Primero se genera y después se guarda**: si algo falla, `installation.json` no se toca y no
/// queda un agente apuntando a una carpeta que no existe. Y generar de nuevo para el mismo
/// agente reusa su carpeta (no crea `Aurora 2`) y deja `memoria/` como estaba.
nonisolated struct AgentInstaller: Sendable {
    var store: InstallationStore = InstallationStore()
    var agentsRoot: URL = AgentFolder.defaultRoot
    var options: ConfigGenerator.Options

    struct Outcome: Sendable, Equatable {
        var record: AgentRecord
        var result: GenerationResult
    }

    /// Una skill propia que el usuario trajo de su Mac y hay que copiar a `skills-propias/` del agente.
    struct OwnSkillImport: Sendable, Equatable {
        var id: String
        var source: URL
    }

    /// - Parameter existingAgentID: el agente que ya se generó en esta sesión, si se vuelve a
    ///   generar (el usuario regresó a cambiar algo).
    /// - Parameter importedContext: material que el usuario trajo; el motor lo deja en `memoria/contexto/`
    ///   sin pisar nada de lo que ya haya.
    /// - Parameter ownSkills: las skills propias que trajo en esta sesión; se copian a su carpeta antes de
    ///   generar, porque el motor las instala desde ahí (`docs/03` §6.3).
    /// - Parameter ownSkillsToTrash: las propias que quitó y ya estaban en la carpeta: van a la Papelera.
    func install(
        _ config: AgentConfig, existingAgentID: UUID? = nil, importedContext: [ContextFile] = [],
        ownSkills: [OwnSkillImport] = [], ownSkillsToTrash: [String] = []
    ) throws -> Outcome {
        var installation = try store.load() ?? GalenoInstallation(language: config.language)
        installation.language = config.language

        // Las conexiones se hacen una vez y se comparten entre agentes. Solo se guardan las que
        // quedaron conectadas; una saltada solo si nadie la había conectado antes, para no
        // dejar "desconectada" una herramienta que otro agente ya usa.
        for connection in config.connections {
            // Que el usuario aceptó el envío por WhatsApp es de la conexión, no de un agente: guardar un agente
            // cuya config no lo trae no lo borra.
            let shared = SharedConnection(
                tool: connection.tool, status: connection.status,
                oauthClientID: connection.oauthClientID, serverNamePrefix: connection.serverNamePrefix,
                sendingAccepted: connection.sendingAccepted
                    ?? installation.connection(for: connection.tool)?.sendingAccepted)
            switch connection.status {
            case .connected:
                installation.setConnection(shared)
            case .skipped where installation.connection(for: connection.tool) == nil:
                installation.setConnection(shared)
            case .skipped, .selected:
                break
            }
        }

        let record: AgentRecord
        if let existingAgentID, installation.agent(id: existingAgentID) != nil {
            try installation.setConfig(config, for: existingAgentID)
            record = installation.agent(id: existingAgentID)!
        } else {
            record = installation.addAgent(config, agentsRoot: agentsRoot)
        }

        // Las skills propias son del usuario: se copian a su carpeta (el motor solo lee de ahí) y las que
        // quitó van a la Papelera, nunca se borran.
        for skill in ownSkills { try OwnSkillImporter.copy(skill.source, id: skill.id, into: record.folder) }
        for id in ownSkillsToTrash { try OwnSkillImporter.trash(id: id, in: record.folder) }

        // El motor recibe la config con el estado y el `client_id` tomados de la instalación.
        guard let resolved = installation.resolvedConfig(for: record.id) else {
            throw InstallationError.unknownAgent(record.id)
        }
        let result = try ConfigGenerator().generate(
            resolved, into: record.folder, options: options, importedContext: importedContext)

        try store.save(installation)
        return Outcome(record: record, result: result)
    }
}
