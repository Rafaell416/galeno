/// Lo que el motor escribió, y lo que la app debe contarle al usuario.
public struct GenerationResult: Hashable, Sendable {
    /// Rutas relativas a la carpeta destino, ordenadas.
    public var writtenFiles: [String]
    /// Cosas que no impiden generar pero que alguien debería mirar.
    public var warnings: [GenerationWarning]

    public init(writtenFiles: [String], warnings: [GenerationWarning] = []) {
        self.writtenFiles = writtenFiles
        self.warnings = warnings
    }
}

public enum GenerationWarning: Hashable, Sendable {
    /// El endpoint de este servidor no está confirmado: el agente podría no
    /// poder conectarse. Hay que verificarlo contra la documentación del
    /// proveedor antes de vender.
    case unverifiedEndpoint(tool: Tool, url: String)

    /// Ya existía un `CLAUDE.md` en la carpeta destino y lo reemplazamos por el
    /// que importa `AGENTS.md`. El contenido anterior se perdería, así que el
    /// motor no lo toca y avisa.
    case existingClaudeFileLeftAlone(path: String)
}

public enum GenerationError: Error, Equatable {
    /// Falta la carpeta de una skill seleccionada.
    case missingSkill(id: String, source: SkillSource, expectedAt: String)
    /// Un id de skill que escribiría fuera de la carpeta destino.
    case unsafeSkillIdentifier(String)
    /// El nombre del agente está vacío o es solo espacios.
    case emptyAgentName
}

extension GenerationError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .missingSkill(id, source, expectedAt):
            "No encontré la skill \"\(id)\" (\(source.rawValue)). Se esperaba en \(expectedAt)."
        case let .unsafeSkillIdentifier(id):
            "El id de skill \"\(id)\" escribiría fuera de la carpeta destino."
        case .emptyAgentName:
            "El agente necesita un nombre."
        }
    }
}
