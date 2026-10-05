import Foundation

/// Un texto en los dos idiomas del producto.
public struct LocalizedText: Codable, Hashable, Sendable {
    public var es: String
    public var en: String

    public init(es: String, en: String) {
        self.es = es
        self.en = en
    }

    public func text(in language: Language) -> String {
        switch language {
        case .spanish: es
        case .english: en
        }
    }
}

/// Varias líneas de texto en los dos idiomas (lo que «sale» en el ejemplo de una skill).
public struct LocalizedLines: Codable, Hashable, Sendable {
    public var es: [String]
    public var en: [String]

    public init(es: [String], en: [String]) {
        self.es = es
        self.en = en
    }

    public func lines(in language: Language) -> [String] {
        switch language {
        case .spanish: es
        case .english: en
        }
    }
}

/// Un grupo de skills en el paso «Skills» ("Producir documentos de producto"…).
public struct SkillGroup: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: LocalizedText
}

/// El ejemplo de la vista previa de una skill: la app lo muestra como una conversación (se escribe la pregunta,
/// el agente lee y aparece el resultado). **Es ilustrativo**: se escribe a mano, no sale de ejecutar nada, y la
/// pantalla lo dice.
public struct SkillExample: Codable, Hashable, Sendable {
    /// De qué parte el agente, como complemento de «Hera lee …»: «la transcripción de la reunión de ayer».
    public var input: LocalizedText
    /// El resultado, con la forma de lo que esa skill entrega. Cada línea es un bloque, según cómo empieza:
    /// `# ` título · `## ` sección · `- ` viñeta · `> ` mensaje en borrador · `| a | b |` fila de tabla (la
    /// primera fila es el encabezado) · cualquier otra cosa, un párrafo.
    public var output: LocalizedLines

    public init(input: LocalizedText, output: LocalizedLines) {
        self.input = input
        self.output = output
    }
}

/// De quién es una skill que no escribimos nosotros: su autor, su repositorio y su licencia. Va siempre a la
/// vista en la app, con el enlace al original.
public struct SkillCredit: Codable, Hashable, Sendable {
    /// El autor, tal como se acredita en la pantalla.
    public var author: String
    /// El repositorio de origen.
    public var repository: URL
    /// La ruta de la skill dentro del repositorio.
    public var path: String
    /// La licencia (SPDX).
    public var license: String

    public init(author: String, repository: URL, path: String, license: String) {
        self.author = author
        self.repository = repository
        self.path = path
        self.license = license
    }

    /// El link a la skill dentro de su GitHub.
    public var sourceURL: URL {
        repository.appending(path: "tree/main").appending(path: path)
    }
}

/// Una skill tal como la muestra el paso «Skills»: una tarjeta con su vista previa. Las nuestras salen de
/// `galeno` en el catálogo (contenido en `skills/galeno/<id>/SKILL.md`); las de terceros ya traídas y
/// revisadas, de `curated` (``CuratedSkill/card``, contenido en `skills/curated/<id>/`), y llevan `credit`.
public struct CatalogSkill: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var group: String
    public var name: LocalizedText
    public var summary: LocalizedText
    /// Dónde puede escribir, para decírselo al usuario ("Escribe en Notion o Google Docs").
    public var writes: [Tool]
    /// Si está vacío, la skill sirve con lo que sea. Si no, necesita **alguna** de estas
    /// herramientas conectadas: sin ninguna, la pantalla avisa que todavía no le serviría.
    public var needsAny: [Tool]
    /// Cómo pedirla con palabras propias («Hazme el acta de la reunión de ayer»). Opcional: un
    /// catálogo anterior no lo trae.
    public var ask: LocalizedText?
    /// El ejemplo de su vista previa.
    public var example: SkillExample?
    /// Una garantía propia de esta skill, para la vista previa («No crea ninguna tarea sin tu "sí"»).
    public var guarantee: LocalizedText?
    /// De quién es, si no es nuestra. `nil` = la escribimos nosotros.
    public var credit: SkillCredit?

    public init(
        id: String, group: String, name: LocalizedText, summary: LocalizedText, writes: [Tool] = [],
        needsAny: [Tool] = [], ask: LocalizedText? = nil, example: SkillExample? = nil,
        guarantee: LocalizedText? = nil, credit: SkillCredit? = nil
    ) {
        self.credit = credit
        self.id = id
        self.group = group
        self.name = name
        self.summary = summary
        self.writes = writes
        self.needsAny = needsAny
        self.ask = ask
        self.example = example
        self.guarantee = guarantee
    }

    /// El comando con el que se invoca.
    public var command: String { "/" + id }

    /// De qué carpeta se instala: las nuestras de `galeno/`, las de terceros de `curated/`.
    public var source: SkillSource { credit == nil ? .galeno : .curated }

    /// ¿Puede terminar enviando algo a otras personas? Hoy, las que escriben en Slack. La vista
    /// previa lo dice: «Siempre te pide aprobación antes de enviar».
    public var sendsToOthers: Bool { writes.contains { $0.externalSend != nil } }

    /// ¿Le serviría con estas herramientas conectadas?
    public func isUseful(with connected: [Tool]) -> Bool {
        needsAny.isEmpty || needsAny.contains { connected.contains($0) }
    }
}

/// Una skill de la comunidad, seleccionada y revisada por nosotros. Siempre lleva el
/// crédito a su autor y el link a su GitHub: es buena ética y buen marketing.
public struct CuratedSkill: Codable, Hashable, Sendable, Identifiable {
    /// El id con el que se instala (`.claude/skills/<id>/`) y con el que se guarda en la
    /// config: único en todo el catálogo.
    public var id: String
    public var name: LocalizedText
    public var summary: LocalizedText
    /// El autor, tal como se acredita en la pantalla.
    public var author: String
    /// El repositorio de origen.
    public var repository: URL
    /// La ruta de la skill dentro del repositorio.
    public var path: String
    /// La licencia (SPDX). Solo se aceptan las verificadas: ver ``SkillCatalog/permittedLicenses``.
    public var license: String
    /// `false` mientras su contenido todavía no se ha traído a `skills/curated/<id>/`: se
    /// muestra con su crédito pero no se puede marcar.
    public var available: Bool
    /// El grupo del paso «Skills» donde se muestra. Sin grupo no tiene tarjeta (las de la comunidad que solo
    /// están listadas).
    public var group: String?
    /// Lo mismo que en ``CatalogSkill``: dónde escribe, qué necesita y lo que enseña su vista previa.
    public var writes: [Tool]?
    public var needsAny: [Tool]?
    public var ask: LocalizedText?
    public var example: SkillExample?
    public var guarantee: LocalizedText?

    public var credit: SkillCredit {
        SkillCredit(author: author, repository: repository, path: path, license: license)
    }

    /// El link a la skill dentro de su GitHub.
    public var sourceURL: URL { credit.sourceURL }

    /// Su tarjeta en el paso «Skills»: solo si su contenido ya está traído y tiene grupo.
    public var card: CatalogSkill? {
        guard available, let group else { return nil }
        return CatalogSkill(
            id: id, group: group, name: name, summary: summary, writes: writes ?? [], needsAny: needsAny ?? [],
            ask: ask, example: example, guarantee: guarantee, credit: credit)
    }
}

public enum SkillCatalogError: Error, Equatable, CustomStringConvertible {
    case unreadable(path: String, reason: String)
    case newerThanThisApp(found: Int, supported: Int)
    case invalid(String)

    public var description: String {
        switch self {
        case let .unreadable(path, reason): "No pude leer el catálogo de skills en \(path): \(reason)."
        case let .newerThanThisApp(found, supported):
            "El catálogo de skills es de un formato más nuevo (\(found); esta versión lee hasta el \(supported))."
        case let .invalid(reason): "El catálogo de skills no es válido: \(reason)."
        }
    }
}

/// El catálogo de skills (`skills/catalog.json`): las nuestras y las curadas.
///
/// No contiene el contenido de las skills, solo lo necesario para elegirlas. Es contenido y no
/// código: se publica aparte de la app (`docs/03` §4f, capa 3).
public struct SkillCatalog: Codable, Hashable, Sendable {
    public static let supportedSchemaVersion = 1
    public static let fileName = "catalog.json"

    /// Las únicas licencias con las que se acepta contenido de terceros (`AGENTS.md`).
    public static let permittedLicenses: Set<String> = ["Apache-2.0", "MIT"]

    public var schemaVersion: Int
    public var groups: [SkillGroup]
    public var galeno: [CatalogSkill]
    public var curated: [CuratedSkill]

    public init(
        schemaVersion: Int = SkillCatalog.supportedSchemaVersion, groups: [SkillGroup] = [],
        galeno: [CatalogSkill] = [], curated: [CuratedSkill] = []
    ) {
        self.schemaVersion = schemaVersion
        self.groups = groups
        self.galeno = galeno
        self.curated = curated
    }

    // MARK: Leer

    /// Lee y valida `catalog.json` de la carpeta `skills/` (o de su copia dentro de la app).
    public static func load(from skillsDirectory: URL) throws -> SkillCatalog {
        let file = skillsDirectory.appending(path: fileName)
        let data: Data
        do { data = try Data(contentsOf: file) } catch {
            throw SkillCatalogError.unreadable(path: file.path, reason: error.localizedDescription)
        }
        return try decode(data, at: file.path)
    }

    public static func decode(_ data: Data, at path: String = "catalog.json") throws -> SkillCatalog {
        let catalog: SkillCatalog
        do { catalog = try JSONDecoder().decode(SkillCatalog.self, from: data) } catch {
            throw SkillCatalogError.unreadable(path: path, reason: String(describing: error))
        }
        guard catalog.schemaVersion <= supportedSchemaVersion else {
            throw SkillCatalogError.newerThanThisApp(
                found: catalog.schemaVersion, supported: supportedSchemaVersion)
        }
        try catalog.validate()
        return catalog
    }

    /// Lo que tiene que cumplir un catálogo para que la app lo use. Se comprueba al leerlo y
    /// en las pruebas del repositorio: un catálogo roto se nota antes de llegar al usuario.
    public func validate() throws {
        let ids = galeno.map(\.id) + curated.map(\.id)
        if let repeated = Dictionary(grouping: ids, by: { $0 }).first(where: { $1.count > 1 })?.key {
            throw SkillCatalogError.invalid("el id «\(repeated)» está repetido")
        }
        for id in ids {
            do { try SkillsInstaller.validate(id) } catch {
                throw SkillCatalogError.invalid("el id «\(id)» no es seguro como nombre de carpeta")
            }
        }
        let groupIDs = Set(groups.map(\.id))
        for skill in galeno where !groupIDs.contains(skill.group) {
            throw SkillCatalogError.invalid("«\(skill.id)» está en un grupo que no existe: \(skill.group)")
        }
        // Una nuestra no lleva crédito de nadie: si lo llevara, se instalaría desde `curated/`.
        for skill in galeno where skill.credit != nil {
            throw SkillCatalogError.invalid("«\(skill.id)» está entre las nuestras y trae crédito de un tercero")
        }
        for skill in curated {
            if let group = skill.group, !groupIDs.contains(group) {
                throw SkillCatalogError.invalid("«\(skill.id)» está en un grupo que no existe: \(group)")
            }
            guard Self.permittedLicenses.contains(skill.license) else {
                throw SkillCatalogError.invalid("«\(skill.id)» tiene una licencia no permitida: \(skill.license)")
            }
            guard skill.repository.scheme == "https", skill.repository.host == "github.com" else {
                throw SkillCatalogError.invalid("«\(skill.id)» no apunta a un repositorio de GitHub")
            }
            guard !skill.author.isEmpty else {
                throw SkillCatalogError.invalid("«\(skill.id)» no tiene autor")
            }
        }
    }

    // MARK: Usar

    /// Todas las skills que tienen tarjeta: las nuestras y las de terceros ya traídas, en el orden del catálogo.
    public var cards: [CatalogSkill] { galeno + curated.compactMap(\.card) }

    /// Las skills de un grupo, en el orden del catálogo: primero las nuestras.
    public func skills(in group: SkillGroup) -> [CatalogSkill] {
        cards.filter { $0.group == group.id }
    }

    /// Lo que viene marcado de fábrica: todas las nuestras. El usuario desmarca las que no quiere, y marca
    /// las de terceros que le sirvan.
    public var defaultSelection: [SelectedSkill] {
        galeno.map { SelectedSkill(id: $0.id, source: .galeno) }
    }

    /// Lo que trae marcado un agente de ese rol: todas las skills con tarjeta de sus grupos
    /// (`AgentRole.skillGroups`), nuestras o de terceros. Para producto son las 17 nuestras.
    public func defaultSelection(for role: AgentRole) -> [SelectedSkill] {
        let groups = Set(role.skillGroups)
        return cards.filter { groups.contains($0.group) }.map { SelectedSkill(id: $0.id, source: $0.source) }
    }

    /// Las curadas que ya se pueden instalar.
    public var availableCurated: [CuratedSkill] { curated.filter(\.available) }

    /// Los ids de las skills que dicen estar disponibles pero a las que les falta su carpeta con
    /// `SKILL.md` en `skillsDirectory`. Vacío = el catálogo y la carpeta cuadran.
    public func missingFiles(in skillsDirectory: URL, fileManager: FileManager = .default) -> [String] {
        let ours = galeno.map { (id: $0.id, source: SkillSource.galeno) }
        let theirs = availableCurated.map { (id: $0.id, source: SkillSource.curated) }
        return (ours + theirs).compactMap { entry in
            let file = skillsDirectory.appending(path: "\(entry.source.rawValue)/\(entry.id)/SKILL.md")
            return fileManager.fileExists(atPath: file.path) ? nil : entry.id
        }
    }
}
