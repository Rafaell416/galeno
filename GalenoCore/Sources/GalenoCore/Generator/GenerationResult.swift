/// Lo que el motor escribió, y lo que la app debe contarle al usuario.
public struct GenerationResult: Hashable, Sendable {
    /// Rutas relativas a la carpeta destino, ordenadas.
    public var writtenFiles: [String]
    /// Cosas que no impiden generar pero que alguien debería mirar.
    public var warnings: [GenerationWarning]
    /// Archivos que había en la carpeta y la config ya no pide (una skill
    /// desmarcada, el hook de aprobación sin nada a qué aplicarlo), ordenados.
    /// Vacío la primera vez que se genera.
    public var removedFiles: [String]

    public init(
        writtenFiles: [String], warnings: [GenerationWarning] = [], removedFiles: [String] = []
    ) {
        self.writtenFiles = writtenFiles
        self.warnings = warnings
        self.removedFiles = removedFiles
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

extension GenerationWarning: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .unverifiedEndpoint(tool, url):
            "El endpoint de \(tool.rawValue) (\(url)) no está verificado; confírmalo antes de vender."
        case let .existingClaudeFileLeftAlone(path):
            "Ya había un \(path) sin el import de AGENTS.md; no se tocó. Revísalo a mano."
        }
    }
}

public enum GenerationError: Error, Equatable {
    /// Falta la carpeta de una skill seleccionada.
    case missingSkill(id: String, source: SkillSource, expectedAt: String)
    /// Un id de skill que escribiría fuera de la carpeta destino.
    case unsafeSkillIdentifier(String)
    /// Dos skills marcadas con el mismo id (una propia y una del catálogo, por
    /// ejemplo): irían a la misma carpeta.
    case duplicateSkill(String)
    /// El nombre del agente está vacío o es solo espacios.
    case emptyAgentName
    /// Esta herramienta exige que el cliente traiga su propia app OAuth, y la
    /// conexión no tiene un `client_id`. Esa app no es algo que Galeno pueda
    /// generar: la crea el cliente (o, para Google, la automatización del
    /// wizard), antes de llegar aquí.
    case missingOAuthClient(tool: Tool)
}

extension GenerationError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .missingSkill(id, source, expectedAt):
            "No encontré la skill \"\(id)\" (\(source.rawValue)). Se esperaba en \(expectedAt)."
        case let .unsafeSkillIdentifier(id):
            "El id de skill \"\(id)\" escribiría fuera de la carpeta destino."
        case let .duplicateSkill(id):
            "Hay dos skills con el id \"\(id)\"; ponle otro nombre a la tuya."
        case .emptyAgentName:
            "El agente necesita un nombre."
        case let .missingOAuthClient(tool):
            "Falta el client_id de \(tool.rawValue). Esa app la trae el cliente, Galeno no puede generarla."
        }
    }
}
