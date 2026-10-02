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

    /// Copia las skills y devuelve las rutas relativas escritas, ordenadas.
    static func install(
        _ skills: [SelectedSkill],
        from skillsDirectory: URL,
        into destination: URL,
        fileManager: FileManager = .default
    ) throws -> [String] {
        guard !skills.isEmpty else { return [] }

        let skillsRoot = destination.appending(path: ".claude/skills", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: skillsRoot, withIntermediateDirectories: true)

        var written: [String] = []

        for skill in skills {
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

            let target = skillsRoot.appending(path: skill.id, directoryHint: .isDirectory)
            // Generar dos veces sobre la misma carpeta no debe fallar.
            if fileManager.fileExists(atPath: target.path) {
                try fileManager.removeItem(at: target)
            }
            try fileManager.copyItem(at: source, to: target)

            written.append(contentsOf: try relativeFilePaths(of: target, under: destination))
        }

        return written.sorted()
    }

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
