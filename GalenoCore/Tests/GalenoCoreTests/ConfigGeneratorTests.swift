import Foundation
import XCTest

@testable import GalenoCore

/// Lo que un snapshot no atrapa: las invariantes que deben valer para
/// *cualquier* config, no solo para las dos de ejemplo.
final class ConfigGeneratorTests: GeneratorTestCase {

    // MARK: - Tokens

    /// Nada de lo generado puede llevar el valor de un token.
    func testNoGeneratedFileContainsATokenValue() throws {
        try generate(GeneratorFixtures.englishEightTools)

        for path in try SnapshotSupport.filePaths(in: destination) {
            let text = try contents(of: path).lowercased()
            for forbidden in ["xoxb-", "xoxp-", "bearer sk-", "api_key\":", "secret\":"] {
                XCTAssertFalse(text.contains(forbidden), "\(path) menciona \(forbidden)")
            }
        }
    }

    /// Un servidor con cabecera escribe la referencia `${VAR}`, nunca el valor.
    /// El tipo solo guarda el nombre de la variable, así que no hay otra opción.
    func testBearerTokenIsWrittenAsAnEnvironmentReference() throws {
        let definition = MCPServerDefinition(
            serverName: "ejemplo",
            transport: .http(url: "https://example.com/mcp"),
            authentication: .bearerToken(environmentVariable: "GALENO_EJEMPLO_TOKEN"),
            endpointIsVerified: true
        )

        guard case let .bearerToken(variable) = definition.authentication else {
            return XCTFail("se esperaba bearerToken")
        }
        XCTAssertEqual(variable, "GALENO_EJEMPLO_TOKEN")
        // El renderer compone "Bearer ${VAR}"; lo que se guarda es el nombre.
        XCTAssertFalse(variable.contains("$"), "se guarda el nombre, no la referencia ya formada")
    }

    // MARK: - Permisos

    func testCodeToolsAreAlwaysDenied() throws {
        for config in [GeneratorFixtures.spanishThreeTools, GeneratorFixtures.englishEightTools] {
            try generate(config)
            let permissions = try decodedPermissions()

            for tool in ["Bash", "Edit", "Write", "NotebookEdit"] {
                XCTAssertTrue(permissions.deny.contains(tool), "falta \(tool) en deny")
                XCTAssertFalse(permissions.allow.contains(tool))
                XCTAssertFalse(permissions.ask.contains(tool))
            }
        }
    }

    /// Slack y Gmail van enteros a `ask`. La precedencia de Claude Code es
    /// deny → ask → allow y gana la primera, así que no pueden estar también en
    /// `allow`: sería una regla muerta que confunde a quien lea el archivo.
    func testExternalSendServersAreAskedNeverAllowed() throws {
        try generate(GeneratorFixtures.englishEightTools)
        let permissions = try decodedPermissions()

        for server in ["slack", "gmail"] {
            XCTAssertTrue(permissions.ask.contains("mcp__\(server)__*"), "\(server) debería estar en ask")
            XCTAssertFalse(
                permissions.allow.contains(where: { $0.hasPrefix("mcp__\(server)__") }),
                "\(server) no debe aparecer en allow"
            )
        }
    }

    func testReadOnlyServersAreAllowed() throws {
        try generate(GeneratorFixtures.englishEightTools)
        let permissions = try decodedPermissions()

        XCTAssertTrue(permissions.allow.contains("mcp__whatsapp__*"))
        XCTAssertTrue(permissions.allow.contains("mcp__fireflies__*"))
    }

    /// Una escritura interna puesta en `ask` mueve su servidor de `allow` a `ask`.
    func testAnInternalWriteSetToAskMovesItsServer() throws {
        var config = GeneratorFixtures.spanishThreeTools
        XCTAssertEqual(config.sendingRules.policy(for: .notion), .allow)

        try generate(config)
        XCTAssertTrue(try decodedPermissions().allow.contains("mcp__notion__*"))

        config.sendingRules.setPolicy(.ask, for: .notion)
        try generate(config)

        let permissions = try decodedPermissions()
        XCTAssertTrue(permissions.ask.contains("mcp__notion__*"))
        XCTAssertFalse(permissions.allow.contains("mcp__notion__*"))
    }

    /// Google Workspace cubre Docs y Sheets. Si cualquiera de los dos pide
    /// confirmación, el servidor entero va a `ask`: la regla no distingue.
    func testGoogleWorkspaceGoesToAskIfEitherDocsOrSheetsAsks() throws {
        var config = GeneratorFixtures.englishEightTools
        config.sendingRules.setPolicy(.ask, for: .googleSheets)

        try generate(config)
        let permissions = try decodedPermissions()

        XCTAssertTrue(permissions.ask.contains("mcp__google-workspace__*"))
        XCTAssertFalse(permissions.allow.contains("mcp__google-workspace__*"))
    }

    /// Ninguna regla `mcp__` puede llevar paréntesis: Claude Code las descarta
    /// en silencio al cargar el archivo.
    func testNoMCPRuleUsesParentheses() throws {
        try generate(GeneratorFixtures.englishEightTools)
        let permissions = try decodedPermissions()

        for rule in permissions.allow + permissions.ask + permissions.deny
        where rule.hasPrefix("mcp__") {
            XCTAssertFalse(rule.contains("("), "la regla \(rule) se descartaría")
        }
    }

    // MARK: - El hook

    func testTheHookIsExecutable() throws {
        try generate(GeneratorFixtures.spanishThreeTools)

        let path = destination.appending(path: SettingsRenderer.hookPath).path
        let mode = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? NSNumber)

        XCTAssertEqual(mode.int16Value & 0o111, 0o111, "Claude Code no corre un hook sin permiso de ejecución")
    }

    /// El hook de verdad: lo ejecutamos y comprobamos que escupe el JSON que
    /// Claude Code espera.
    func testRunningTheHookAsksForApproval() throws {
        try generate(GeneratorFixtures.spanishThreeTools)

        let process = Process()
        process.executableURL = destination.appending(path: SettingsRenderer.hookPath)
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let output = try XCTUnwrap(object["hookSpecificOutput"] as? [String: Any])
        XCTAssertEqual(output["hookEventName"] as? String, "PreToolUse")
        XCTAssertEqual(output["permissionDecision"] as? String, "ask")
        XCTAssertFalse((output["permissionDecisionReason"] as? String ?? "").isEmpty)
    }

    /// Sin Slack ni Gmail no hay nada que pueda salir hacia afuera, así que no
    /// se escribe el hook ni se registra.
    func testNoHookWhenNothingCanLeave() throws {
        let config = AgentConfig(
            agentName: "Galena",
            language: .spanish,
            connections: [ToolConnection(tool: .notion, status: .connected, sources: .everything)]
        )

        try generate(config)

        XCTAssertFalse(exists(SettingsRenderer.hookPath))
        XCTAssertFalse(try contents(of: ".claude/settings.json").contains("PreToolUse"))
    }

    // MARK: - Herramientas

    /// Google Meet no tiene MCP propio: se lee por el de Google Workspace.
    func testGoogleMeetProducesNoMCPEntry() throws {
        try generate(GeneratorFixtures.englishEightTools)

        let servers = try decodedMCPServerNames()
        XCTAssertFalse(servers.contains("google-meet"))
        XCTAssertTrue(servers.contains("google-workspace"))
        // Pero sí se le cuenta al agente de dónde salen sus transcripciones.
        XCTAssertTrue(try contents(of: "AGENTS.md").contains("Google Meet"))
    }

    /// Lo que el usuario saltó o aún no conectó no se configura.
    func testSkippedToolsAppearNowhere() throws {
        try generate(GeneratorFixtures.englishEightTools)

        for path in try SnapshotSupport.filePaths(in: destination) {
            XCTAssertFalse(
                try contents(of: path).lowercased().contains("granola"),
                "\(path) menciona una herramienta saltada"
            )
        }
    }

    // MARK: - AGENTS.md y CLAUDE.md

    /// Claude Code lee AGENTS.md solo si no hay ningún CLAUDE.md en la carpeta
    /// ni por encima, y solo desde la v2.1.277. El import lo cubre siempre.
    func testWritesBothAgentsAndClaudeFiles() throws {
        try generate(GeneratorFixtures.spanishThreeTools)

        XCTAssertEqual(try contents(of: "CLAUDE.md").trimmingCharacters(in: .whitespacesAndNewlines), "@AGENTS.md")
        XCTAssertTrue(try contents(of: "AGENTS.md").contains("Hipócrates"))
    }

    /// Un CLAUDE.md que el usuario ya tenía no se pisa.
    func testAnExistingClaudeFileIsLeftAlone() throws {
        let existing = "# Mis instrucciones\n\nNo me las borres.\n"
        try Data(existing.utf8).write(to: destination.appending(path: "CLAUDE.md"))

        let result = try generate(GeneratorFixtures.spanishThreeTools)

        XCTAssertEqual(try contents(of: "CLAUDE.md"), existing)
        XCTAssertTrue(result.warnings.contains(.existingClaudeFileLeftAlone(path: "CLAUDE.md")))
    }

    func testTheLanguageInstructionIsExplicit() throws {
        try generate(GeneratorFixtures.spanishThreeTools)
        XCTAssertTrue(try contents(of: "AGENTS.md").contains("en **español**"))

        try generate(GeneratorFixtures.englishEightTools)
        XCTAssertTrue(try contents(of: "AGENTS.md").contains("in **English**"))
    }

    /// El nombre de Google Workspace estaba en español dentro del AGENTS.md en
    /// inglés. Que no vuelva.
    func testTheEnglishFileHasNoSpanishLeftovers() throws {
        try generate(GeneratorFixtures.englishEightTools)
        let text = try contents(of: "AGENTS.md")

        XCTAssertFalse(text.contains("Docs y Sheets"))
        XCTAssertTrue(text.contains("Docs and Sheets"))
    }

    // MARK: - Skills

    func testCopiesTheWholeSkillFolder() throws {
        try generate(GeneratorFixtures.spanishThreeTools)

        XCTAssertTrue(exists(".claude/skills/prd/SKILL.md"))
        // No solo el SKILL.md: una skill puede traer plantillas al lado.
        XCTAssertTrue(exists(".claude/skills/prd/template.md"))
        XCTAssertTrue(exists(".claude/skills/acta/SKILL.md"))
    }

    func testCuratedSkillsComeFromTheirOwnFolder() throws {
        try generate(GeneratorFixtures.englishEightTools)

        XCTAssertTrue(exists(".claude/skills/phuryn-discovery-interview/SKILL.md"))
    }

    func testAMissingSkillFailsLoudly() throws {
        var config = GeneratorFixtures.spanishThreeTools
        config.skills.append(SelectedSkill(id: "no-existe", source: .galeno))

        XCTAssertThrowsError(try generate(config)) { error in
            guard case let GenerationError.missingSkill(id, source, _) = error else {
                return XCTFail("se esperaba missingSkill, llegó \(error)")
            }
            XCTAssertEqual(id, "no-existe")
            XCTAssertEqual(source, .galeno)
        }
    }

    /// Un id de skill no puede escribir fuera de la carpeta destino.
    func testASkillIdCannotEscapeTheDestination() throws {
        for dangerous in ["../escapada", "..", "sub/dir", "a/../../b", #"windows\ruta"#] {
            var config = GeneratorFixtures.spanishThreeTools
            config.skills = [SelectedSkill(id: dangerous, source: .galeno)]

            XCTAssertThrowsError(try generate(config), "\(dangerous) debería rechazarse") { error in
                guard case GenerationError.unsafeSkillIdentifier = error else {
                    return XCTFail("se esperaba unsafeSkillIdentifier para \(dangerous), llegó \(error)")
                }
            }
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: destination.appending(path: "../escapada").path),
                "no se escribió nada fuera"
            )
        }
    }

    // MARK: - Otros

    func testAnEmptyAgentNameFails() {
        let config = AgentConfig(agentName: "   ", language: .spanish)

        XCTAssertThrowsError(try generate(config)) { error in
            XCTAssertEqual(error as? GenerationError, .emptyAgentName)
        }
    }

    /// Los endpoints que no hemos verificado salen como advertencia, para que
    /// la app los muestre y no se nos olviden antes de vender.
    func testUnverifiedEndpointsAreReported() throws {
        let result = try generate(GeneratorFixtures.englishEightTools)

        let unverified: Set<Tool> = Set(
            result.warnings.compactMap {
                if case let .unverifiedEndpoint(tool, _) = $0 { return tool }
                return nil
            })

        XCTAssertEqual(unverified, [.slack, .notion, .gmail, .googleWorkspace, .jira])
        // Los tres de la spec §4b sí están confirmados.
        XCTAssertFalse(unverified.contains(.fireflies))
    }

    func testResultListsEveryFileWritten() throws {
        let result = try generate(GeneratorFixtures.spanishThreeTools)

        XCTAssertEqual(result.writtenFiles, try SnapshotSupport.filePaths(in: destination))
    }

    // MARK: - Ayudas

    private struct Permissions: Decodable {
        var allow: [String]
        var ask: [String]
        var deny: [String]
    }

    private struct SettingsFile: Decodable {
        var permissions: Permissions
    }

    private func decodedPermissions() throws -> Permissions {
        let data = try Data(contentsOf: destination.appending(path: ".claude/settings.json"))
        return try JSONDecoder().decode(SettingsFile.self, from: data).permissions
    }

    private func decodedMCPServerNames() throws -> Set<String> {
        let data = try Data(contentsOf: destination.appending(path: ".mcp.json"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let servers = try XCTUnwrap(object["mcpServers"] as? [String: Any])
        return Set(servers.keys)
    }
}
