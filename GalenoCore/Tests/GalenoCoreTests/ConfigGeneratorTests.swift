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

    /// Google Workspace cubre Docs y Sheets, y son tres servidores físicos
    /// (Drive, Docs, Sheets). Si cualquiera de las dos escrituras pide
    /// confirmación, los tres van a `ask` por igual: la regla no distingue
    /// servidor por servidor, es una sola decisión por herramienta.
    func testGoogleWorkspaceGoesToAskIfEitherDocsOrSheetsAsks() throws {
        var config = GeneratorFixtures.englishEightTools
        config.sendingRules.setPolicy(.ask, for: .googleSheets)

        try generate(config)
        let permissions = try decodedPermissions()

        for server in ["google-drive", "google-docs", "google-sheets"] {
            XCTAssertTrue(permissions.ask.contains("mcp__\(server)__*"), server)
            XCTAssertFalse(permissions.allow.contains("mcp__\(server)__*"), server)
        }
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
        // Google Workspace son tres servidores físicos, no uno.
        XCTAssertTrue(servers.isSuperset(of: ["google-drive", "google-docs", "google-sheets"]))
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
    /// La investigación cerró las cinco dudas que había (Slack, Notion,
    /// Gmail, Google Workspace, Jira): ya no queda ningún endpoint sin
    /// verificar en el catálogo, así que esta advertencia no se dispara hoy.
    func testNoEndpointWarningsForTheToolsWeSupport() throws {
        let result = try generate(GeneratorFixtures.englishEightTools)

        let unverified = result.warnings.compactMap {
            if case let .unverifiedEndpoint(tool, _) = $0 { return tool }
            return nil
        }

        XCTAssertTrue(unverified.isEmpty, "\(unverified)")
    }

    /// El mecanismo en sí sigue existiendo y es constructible, aunque hoy
    /// ningún tool real lo dispare: si algún día se añade una herramienta sin
    /// verificar, `MCPServerDefinition.endpointIsVerified = false` basta para
    /// que `MCPRenderer` (ver su `switch definition.transport`) añada
    /// `.unverifiedEndpoint` a `GenerationResult.warnings`.
    func testUnverifiedEndpointWarningIsStillConstructible() {
        let definition = MCPServerDefinition(
            serverName: "ejemplo",
            transport: .http(url: "https://example.com/mcp"),
            endpointIsVerified: false
        )
        let warning = GenerationWarning.unverifiedEndpoint(
            tool: .slack, url: "https://example.com/mcp")

        XCTAssertFalse(definition.endpointIsVerified)
        XCTAssertEqual(warning, .unverifiedEndpoint(tool: .slack, url: "https://example.com/mcp"))
    }

    func testResultListsEveryFileWritten() throws {
        let result = try generate(GeneratorFixtures.spanishThreeTools)

        XCTAssertEqual(result.writtenFiles, try SnapshotSupport.filePaths(in: destination))
    }

    // MARK: - App OAuth del cliente (Slack, Gmail, Google Workspace)

    /// Sin client_id, el motor no puede generar nada para estas tres: esa app
    /// la trae el cliente, Galeno no puede inventarla.
    func testMissingOAuthClientFailsForEachToolThatNeedsOne() throws {
        for tool in [Tool.slack, .gmail, .googleWorkspace] {
            var config = AgentConfig(agentName: "Galena", language: .spanish)
            config.connections = [
                ToolConnection(tool: tool, status: .connected, sources: .everything)
                // oauthClientID se queda en nil a propósito.
            ]

            XCTAssertThrowsError(try generate(config), "\(tool)") { error in
                XCTAssertEqual(error as? GenerationError, .missingOAuthClient(tool: tool))
            }
        }
    }

    /// Un client_id de puros espacios cuenta como ausente.
    func testBlankOAuthClientIDFails() throws {
        var config = AgentConfig(agentName: "Galena", language: .spanish)
        config.connections = [
            ToolConnection(
                tool: .slack, status: .connected, sources: .everything, oauthClientID: "   ")
        ]

        XCTAssertThrowsError(try generate(config)) { error in
            XCTAssertEqual(error as? GenerationError, .missingOAuthClient(tool: .slack))
        }
    }

    /// Notion y Jira no necesitan client_id: su registro es dinámico, así que
    /// una conexión sin él genera sin problema.
    func testToolsWithDynamicRegistrationDontNeedAClientID() throws {
        var config = AgentConfig(agentName: "Galena", language: .spanish)
        config.connections = [
            ToolConnection(tool: .notion, status: .connected, sources: .everything),
            ToolConnection(tool: .jira, status: .connected, sources: .everything),
        ]

        XCTAssertNoThrow(try generate(config))
    }

    func testSlackEntryCarriesTheClientIDAndCallbackPort() throws {
        try generate(GeneratorFixtures.spanishThreeTools)
        let mcp = try decodedMCPFile()
        let slack = try XCTUnwrap(mcp["slack"] as? [String: Any])
        let oauth = try XCTUnwrap(slack["oauth"] as? [String: Any])

        XCTAssertEqual(oauth["clientId"] as? String, "1234567890123.1234567890123")
        XCTAssertEqual(oauth["callbackPort"] as? Int, SlackOAuth.callbackPort)
        XCTAssertEqual(oauth["scopes"] as? String, SlackManifestRenderer.requiredScopes.joined(separator: " "))
    }

    /// Las tres entradas de Google Workspace comparten el mismo client_id: es
    /// la misma app del cliente la que cubre Drive, Docs y Sheets.
    func testGoogleWorkspaceServersShareTheSameClientID() throws {
        try generate(GeneratorFixtures.englishEightTools)
        let mcp = try decodedMCPFile()

        let clientIDs = try ["google-drive", "google-docs", "google-sheets"].map { name in
            let server = try XCTUnwrap(mcp[name] as? [String: Any])
            let oauth = try XCTUnwrap(server["oauth"] as? [String: Any])
            return try XCTUnwrap(oauth["clientId"] as? String)
        }

        XCTAssertEqual(Set(clientIDs).count, 1)
    }

    /// Notion y Jira se registran dinámicamente: su entrada no lleva `oauth`.
    func testDynamicRegistrationToolsHaveNoOAuthObject() throws {
        try generate(GeneratorFixtures.englishEightTools)
        let mcp = try decodedMCPFile()

        for name in ["notion", "jira"] {
            let server = try XCTUnwrap(mcp[name] as? [String: Any])
            XCTAssertNil(server["oauth"], name)
        }
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
        Set(try decodedMCPFile().keys)
    }

    private func decodedMCPFile() throws -> [String: Any] {
        let data = try Data(contentsOf: destination.appending(path: ".mcp.json"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(object["mcpServers"] as? [String: Any])
    }
}
