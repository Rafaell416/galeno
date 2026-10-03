import Foundation

/// Copia las skills seleccionadas a `.claude/skills/`.
///
/// Origen: `<skillsDirectory>/<galeno|curated>/<id>/`. Destino:
/// `.claude/skills/<id>/`. Se copia la carpeta entera, no solo `SKILL.md`: una
/// skill puede traer plantillas o ejemplos al lado.
enum SkillsInstaller {
    /// Rechaza un id que escribiría fuera de la carpeta destino.
    ///
    /// Los ids vienen del catálogo, pero el catálogo es datos y las curadas son
    /// de terceros: un id como `../../.ssh` no debe poder salir de `.claude/skills/`.
    static func validate(_ id: String) throws {
        guard !id.isEmpty,
            !id.contains("/"),
            !id.contains("\\"),
            id != ".",
            !id.contains("..")
        else {
            throw GenerationError.unsafeSkillIdentifier(id)
        }
    }

    /// Una skill ya validada: su id es seguro y su carpeta de origen existe.
    struct Validated {
        var skill: SelectedSkill
        var source: URL
    }

    /// Valida todas las skills **antes** de escribir nada: que el id sea
    /// seguro y que exista su `SKILL.md`. Así un error no deja la carpeta
    /// destino a medias.
    static func validateAll(
        _ skills: [SelectedSkill],
        from skillsDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> [Validated] {
        try skills.map { skill in
            try validate(skill.id)

            let source = skillsDirectory
                .appending(path: skill.source.rawValue, directoryHint: .isDirectory)
                .appending(path: skill.id, directoryHint: .isDirectory)

            guard fileManager.fileExists(atPath: source.appending(path: "SKILL.md").path) else {
                throw GenerationError.missingSkill(
                    id: skill.id,
                    source: skill.source,
                    expectedAt: source.appending(path: "SKILL.md").path
                )
            }
            return Validated(skill: skill, source: source)
        }
    }

    /// Copia las skills ya validadas y devuelve las rutas relativas escritas,
    /// ordenadas.
    static func install(
        _ skills: [Validated],
        into destination: URL,
        fileManager: FileManager = .default
    ) throws -> [String] {
        guard !skills.isEmpty else { return [] }

        let skillsRoot = destination.appending(path: skillsPath, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: skillsRoot, withIntermediateDirectories: true)

        var written: [String] = []

        for validated in skills {
            let target = skillsRoot.appending(path: validated.skill.id, directoryHint: .isDirectory)
            // Generar dos veces sobre la misma carpeta no debe fallar.
            if fileManager.fileExists(atPath: target.path) {
                try fileManager.removeItem(at: target)
            }
            try fileManager.copyItem(at: validated.source, to: target)

            written.append(contentsOf: try relativeFilePaths(of: target, under: destination))
        }

        return written.sorted()
    }

    /// Quita las carpetas de `.claude/skills/` que ya no están marcadas, y
    /// devuelve las rutas relativas de los archivos que había dentro.
    ///
    /// Solo mira carpetas directamente bajo `.claude/skills/`: un archivo
    /// suelto ahí no se toca. Borra también una skill que alguien haya puesto
    /// a mano, porque `.claude/` es de Galeno y la config regenerada tiene que
    /// quedar igual que una nueva (docs/03 §3b); por eso devuelve lo quitado.
    static func removeUnselected(
        keeping selected: [SelectedSkill],
        in destination: URL,
        fileManager: FileManager = .default
    ) throws -> [String] {
        let skillsRoot = destination.appending(path: skillsPath, directoryHint: .isDirectory)
        guard
            let entries = try? fileManager.contentsOfDirectory(
                at: skillsRoot, includingPropertiesForKeys: [.isDirectoryKey])
        else { return [] }

        let keep = Set(selected.map(\.id))
        var removed: [String] = []

        for entry in entries where !keep.contains(entry.lastPathComponent) {
            guard try entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
                continue
            }
            removed.append(contentsOf: try relativeFilePaths(of: entry, under: destination))
            try fileManager.removeItem(at: entry)
        }

        return removed.sorted()
    }

    static let skillsPath = ".claude/skills"

    /// Las rutas de los archivos dentro de una carpeta, relativas a `base`.
    private static func relativeFilePaths(of directory: URL, under base: URL) throws -> [String] {
        let fileManager = FileManager.default
        let basePath = base.standardizedFileURL.path
        var paths: [String] = []

        guard
            let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey]
            )
        else { return [] }

        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(basePath + "/") else { continue }
            paths.append(String(path.dropFirst(basePath.count + 1)))
        }

        return paths
    }
}
