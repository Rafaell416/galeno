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

    @discardableResult
    public func generate(
        _ config: AgentConfig,
        into destination: URL,
        options: Options
    ) throws -> GenerationResult {
        guard !config.agentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GenerationError.emptyAgentName
        }

        let fileManager = FileManager.default
        var written: [String] = []
        var warnings: [GenerationWarning] = []

        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        // AGENTS.md lleva el contenido; CLAUDE.md solo lo importa, para que
        // cargue aunque el usuario tenga otro CLAUDE.md más arriba o una
        // versión de Claude Code que no lea AGENTS.md directamente.
        try write(AgentsFileRenderer.render(config), to: "AGENTS.md", in: destination, &written)

        let claudePath = destination.appending(path: "CLAUDE.md")
        let existingClaude = try? String(contentsOf: claudePath, encoding: .utf8)
        if let existingClaude, !existingClaude.contains("@AGENTS.md") {
            // No pisamos lo que el usuario ya tenía escrito.
            warnings.append(.existingClaudeFileLeftAlone(path: "CLAUDE.md"))
        } else {
            try write(
                AgentsFileRenderer.renderClaudeImport(), to: "CLAUDE.md", in: destination, &written)
        }

        try write(
            try SettingsRenderer.render(config),
            to: ".claude/settings.json", in: destination, &written)

        let mcp = try MCPRenderer.render(config, whatsAppBridgePath: options.whatsAppBridgePath)
        warnings.append(contentsOf: mcp.warnings)
        try write(mcp.json, to: ".mcp.json", in: destination, &written)

        // El hook solo tiene sentido si hay algo que pueda salir hacia afuera.
        if !SettingsRenderer.serversRequiringApproval(in: config).isEmpty {
            try write(
                ApprovalHookRenderer.render(language: config.language),
                to: SettingsRenderer.hookPath,
                in: destination,
                &written,
                posixPermissions: 0o755
            )
        }

        // La memoria es del agente: se crea una vez y no se vuelve a tocar,
        // ni el archivo ni nada más dentro de `memoria/`.
        try fileManager.createDirectory(
            at: destination.appending(path: MemoryRenderer.directory, directoryHint: .isDirectory),
            withIntermediateDirectories: true)
        if !fileManager.fileExists(
            atPath: destination.appending(path: MemoryRenderer.mainFile).path)
        {
            try write(
                MemoryRenderer.renderInitialFile(language: config.language),
                to: MemoryRenderer.mainFile, in: destination, &written)
        }

        for subagent in SubagentsRenderer.render(config) {
            try write(subagent.contents, to: subagent.path, in: destination, &written)
        }

        written.append(
            contentsOf: try SkillsInstaller.install(
                config.skills,
                from: options.skillsDirectory,
                into: destination
            )
        )

        return GenerationResult(writtenFiles: written.sorted(), warnings: warnings)
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
