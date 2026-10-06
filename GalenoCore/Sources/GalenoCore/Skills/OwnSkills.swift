import Foundation

/// Una skill propia del usuario, tal como está en `skills-propias/<id>/` de su agente.
public struct OwnSkill: Hashable, Sendable, Identifiable {
    /// El nombre de su carpeta: con él se instala (`.claude/skills/<id>/`) y se invoca (`/<id>`).
    public var id: String
    /// El `name` del frontmatter de su `SKILL.md`, o el id si no lo trae.
    public var name: String
    /// La `description` del frontmatter, o la primera línea de texto si no la trae. Puede quedar vacía.
    public var summary: String

    public init(id: String, name: String, summary: String) {
        self.id = id
        self.name = name
        self.summary = summary
    }
}

/// Las skills propias del usuario (`docs/03` §6.3; decisión de Rafa, 6 oct 2026).
///
/// Son archivos de su propio Mac que la app copia a `skills-propias/<id>/` dentro de la carpeta del agente.
/// Esa carpeta es del usuario: el motor no la escribe ni la borra al regenerar (como `memoria/`), solo lee de
/// ella para instalar cada skill marcada en `.claude/skills/`. El agente generado tampoco puede editarla
/// (`SettingsRenderer.protectedPaths`): una skill le dice al agente cómo comportarse, y nadie más que el
/// usuario la cambia. **Nada remoto**: no hay catálogo de terceros, ni enlaces, ni descargas.
public enum OwnSkills {
    /// La carpeta, dentro de la del agente.
    public static let directoryName = "skills-propias"

    /// El archivo que hace a una carpeta una skill.
    public static let skillFileName = "SKILL.md"

    public static func directory(in agentFolder: URL) -> URL {
        agentFolder.appending(path: directoryName, directoryHint: .isDirectory)
    }

    /// Las mismas reglas que un id del catálogo: un nombre de carpeta que no sale de donde se instala.
    public static func validate(_ id: String) throws {
        try SkillsInstaller.validate(id)
    }

    /// Un id a partir del nombre de una carpeta o de un archivo («Mi Skill de Ventas.md» → `mi-skill-de-ventas`):
    /// minúsculas, sin tildes, guiones en vez de espacios, solo `a-z`, `0-9` y `-`. Vacío si no queda nada.
    public static func identifier(from name: String) -> String {
        var base = name
        if base.lowercased().hasSuffix(".md") { base = String(base.dropLast(3)) }
        let folded = base.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es"))
            .lowercased()
        var result = ""
        var pendingDash = false
        for scalar in folded.unicodeScalars {
            if (scalar >= "a" && scalar <= "z") || (scalar >= "0" && scalar <= "9") {
                if pendingDash, !result.isEmpty { result.append("-") }
                pendingDash = false
                result.unicodeScalars.append(scalar)
            } else {
                pendingDash = true
            }
        }
        return result
    }

    /// `name` y `description` del frontmatter YAML de un `SKILL.md` (solo esas dos claves, en una línea cada una,
    /// con o sin comillas). Si no hay frontmatter, nada.
    public static func frontmatter(of text: String) -> (name: String?, description: String?) {
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return (nil, nil) }
        var name: String?
        var description: String?
        for line in lines.dropFirst() {
            if line.trimmingCharacters(in: .whitespaces) == "---" { break }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let first = value.first, let last = value.last, first == last, first == "\"" || first == "'" {
                value = String(value.dropFirst().dropLast())
            }
            switch key {
            case "name": name = value.isEmpty ? nil : value
            case "description": description = value.isEmpty ? nil : value
            default: break
            }
        }
        return (name, description)
    }

    /// La primera línea de texto después del frontmatter que no sea un título ni esté vacía.
    static func firstParagraph(of text: String) -> String {
        var lines = text.components(separatedBy: "\n")[...]
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
            lines = lines.dropFirst()
            if let end = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
                lines = lines[lines.index(after: end)...]
            }
        }
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            return trimmed
        }
        return ""
    }

    /// Lo que una skill dice de sí misma, leído de su `SKILL.md`.
    public static func describe(id: String, skillText text: String) -> OwnSkill {
        let front = frontmatter(of: text)
        return OwnSkill(id: id, name: front.name ?? id, summary: front.description ?? firstParagraph(of: text))
    }

    /// Las propias que hay en la carpeta de un agente: cada subcarpeta con un `SKILL.md` y un id válido, por nombre.
    public static func list(in agentFolder: URL, fileManager: FileManager = .default) -> [OwnSkill] {
        let root = directory(in: agentFolder)
        guard let entries = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])
        else { return [] }
        return entries.compactMap { folder -> OwnSkill? in
            guard (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            let id = folder.lastPathComponent
            guard (try? validate(id)) != nil else { return nil }
            guard let text = try? String(contentsOf: folder.appending(path: skillFileName), encoding: .utf8) else {
                return nil
            }
            return describe(id: id, skillText: text)
        }
        .sorted { $0.id < $1.id }
    }
}
