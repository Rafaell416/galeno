import Foundation

/// El motor: convierte lo que capturó el wizard en la configuración de Claude
/// Code dentro de una carpeta del usuario.
///
/// Es lo único que toca el disco; cada renderer produce texto y se puede probar
/// sin archivos. Generar dos veces sobre la misma carpeta da el mismo resultado.
public struct ConfigGenerator: Sendable {
    public struct Options: Sendable {
        /// De dónde copiar las skills: `<dir>/<galeno|curated>/<id>/SKILL.md`.
        /// En la app real viene de dentro del `.app`, no del repo.
        public var skillsDirectory: URL

        /// Ruta al binario del bridge de WhatsApp que la app empaqueta.
        public var whatsAppBridgePath: String

        public init(skillsDirectory: URL, whatsAppBridgePath: String) {
            self.skillsDirectory = skillsDirectory
            self.whatsAppBridgePath = whatsAppBridgePath
        }
    }

    public init() {}

    /// Genera la config del agente en `destination`, o la regenera si la
    /// carpeta ya tiene una: deja exactamente lo que dice `config`.
    ///
    /// Primero calcula todo —los textos, las skills— sin tocar el disco, que
    /// es donde las cosas pueden fallar (falta una skill, falta el `client_id`
    /// de Slack). Solo si todo salió bien escribe, y entonces quita lo que la
    /// config ya no pide. Un error deja la carpeta como estaba, no a medias.
    ///
    /// `memoria/` es del agente: se crea una vez y no se vuelve a tocar.
    ///
    /// - Parameter importedContext: material que el usuario trajo (de claude.ai, de un documento).
    ///   Se deja en `memoria/contexto/` **solo si ese archivo no existe**: nunca se pisa nada, ni
    ///   se toca lo que el agente o el usuario ya pusieron ahí.
    @discardableResult
    public func generate(
        _ config: AgentConfig,
        into destination: URL,
        options: Options,
        importedContext: [ContextFile] = []
    ) throws -> GenerationResult {
        guard !config.agentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GenerationError.emptyAgentName
        }

        let fileManager = FileManager.default
        var warnings: [GenerationWarning] = []

        // MARK: 1. Calcular (no toca el disco)

        struct Planned {
            var path: String
            var contents: String
            var posixPermissions: Int?
        }
        var planned: [Planned] = []

        // AGENTS.md lleva el contenido; CLAUDE.md solo lo importa, para que
        // cargue aunque el usuario tenga otro CLAUDE.md más arriba o una
        // versión de Claude Code que no lea AGENTS.md directamente.
        planned.append(Planned(path: "AGENTS.md", contents: AgentsFileRenderer.render(config)))

        let existingClaude = try? String(
            contentsOf: destination.appending(path: "CLAUDE.md"), encoding: .utf8)
        if let existingClaude, !existingClaude.contains("@AGENTS.md") {
            // No pisamos lo que el usuario ya tenía escrito.
            warnings.append(.existingClaudeFileLeftAlone(path: "CLAUDE.md"))
        } else {
            planned.append(
                Planned(path: "CLAUDE.md", contents: AgentsFileRenderer.renderClaudeImport()))
        }

        planned.append(
            Planned(path: ".claude/settings.json", contents: try SettingsRenderer.render(config)))

        let mcp = try MCPRenderer.render(config, whatsAppBridgePath: options.whatsAppBridgePath)
        warnings.append(contentsOf: mcp.warnings)
        planned.append(Planned(path: ".mcp.json", contents: mcp.json))

        // El hook solo tiene sentido si hay algo que pueda salir hacia afuera.
        let needsApprovalHook = !SettingsRenderer.serversRequiringApproval(in: config).isEmpty
        if needsApprovalHook {
            planned.append(
                Planned(
                    path: SettingsRenderer.hookPath,
                    contents: ApprovalHookRenderer.render(language: config.language),
                    posixPermissions: 0o755  // Claude Code no corre un hook que no sea ejecutable.
                ))
        }

        // La memoria es del agente: se crea una vez y no se vuelve a tocar,
        // ni el archivo ni nada más dentro de `memoria/`.
        if !fileManager.fileExists(
            atPath: destination.appending(path: MemoryRenderer.mainFile).path)
        {
            planned.append(
                Planned(
                    path: MemoryRenderer.mainFile,
                    contents: MemoryRenderer.renderInitialFile(language: config.language)))
        }

        for (index, file) in ContextFile.normalized(importedContext).enumerated() {
            let path = "\(MemoryRenderer.contextDirectory)/\(file.fileName(index: index))"
            if !fileManager.fileExists(atPath: destination.appending(path: path).path) {
                planned.append(Planned(path: path, contents: file.rendered(language: config.language)))
            }
        }

        for subagent in SubagentsRenderer.render(config) {
            planned.append(Planned(path: subagent.path, contents: subagent.contents))
        }

        let skills = try SkillsInstaller.validateAll(config.skills, from: options.skillsDirectory)

        // MARK: 2. Escribir

        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: destination.appending(path: MemoryRenderer.directory, directoryHint: .isDirectory),
            withIntermediateDirectories: true)

        var written: [String] = []
        for file in planned {
            try write(
                file.contents, to: file.path, in: destination, &written,
                posixPermissions: file.posixPermissions)
        }
        written.append(contentsOf: try SkillsInstaller.install(skills, into: destination))

        // MARK: 3. Quitar lo que la config ya no pide

        var removed: [String] = []
        if !needsApprovalHook {
            let hook = destination.appending(path: SettingsRenderer.hookPath)
            if fileManager.fileExists(atPath: hook.path) {
                try fileManager.removeItem(at: hook)
                removed.append(SettingsRenderer.hookPath)
            }
        }
        removed.append(
            contentsOf: try SkillsInstaller.removeUnselected(
                keeping: config.skills, in: destination))

        // Una carpeta nueva no tendría estas carpetas vacías.
        for directory in [hooksDirectory(destination), skillsDirectory(destination)] {
            if let contents = try? fileManager.contentsOfDirectory(atPath: directory.path),
                contents.isEmpty
            {
                try fileManager.removeItem(at: directory)
            }
        }

        return GenerationResult(
            writtenFiles: written.sorted(), warnings: warnings, removedFiles: removed.sorted())
    }

    private func hooksDirectory(_ destination: URL) -> URL {
        destination.appending(path: SettingsRenderer.hookPath).deletingLastPathComponent()
    }

    private func skillsDirectory(_ destination: URL) -> URL {
        destination.appending(path: SkillsInstaller.skillsPath, directoryHint: .isDirectory)
    }

    private func write(
        _ contents: String,
        to relativePath: String,
        in destination: URL,
        _ written: inout [String],
        posixPermissions: Int? = nil
    ) throws {
        let url = destination.appending(path: relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url, options: .atomic)

        if let posixPermissions {
            // Claude Code no corre un hook que no sea ejecutable.
            try FileManager.default.setAttributes(
                [.posixPermissions: posixPermissions], ofItemAtPath: url.path)
        }

        written.append(relativePath)
    }
}
