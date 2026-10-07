import Foundation
import XCTest

@testable import GalenoCore

final class InstallationTests: XCTestCase {
    private var sandbox: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        sandbox = FileManager.default.temporaryDirectory
            .appending(path: "galeno-installation/\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let sandbox { try? FileManager.default.removeItem(at: sandbox) }
        try super.tearDownWithError()
    }

    private var agentsRoot: URL { sandbox.appending(path: "Galeno", directoryHint: .isDirectory) }

    /// Una instalación con de todo: conectadas, una saltada, una sin conectar.
    private func installation() -> GalenoInstallation {
        GalenoInstallation(
            language: .spanish,
            connections: [
                SharedConnection(tool: .slack, status: .connected, oauthClientID: "1234567890123.1234567890123"),
                SharedConnection(tool: .notion, status: .connected),
                SharedConnection(tool: .jira, status: .skipped),
                SharedConnection(tool: .fireflies, status: .connected),
                SharedConnection(tool: .whatsapp, status: .connected),
                SharedConnection(tool: .gmail, status: .selected),
            ]
        )
    }

    // MARK: - El modelo

    func testRoundTripPreservesTheWholeInstallation() throws {
        var original = installation()
        original.addAgent(original.startingPoint(agentName: "Aurora"), agentsRoot: agentsRoot)

        let encoder = JSONEncoder()
        let decoded = try JSONDecoder().decode(
            GalenoInstallation.self, from: try encoder.encode(original))

        XCTAssertEqual(decoded, original)
    }

    func testNothingSecretIsEverEncoded() throws {
        var original = installation()
        original.addAgent(original.startingPoint(agentName: "Aurora"), agentsRoot: agentsRoot)

        let text = String(decoding: try JSONEncoder().encode(original), as: UTF8.self).lowercased()

        for forbidden in ["xoxb-", "xoxp-", "bearer", "client_secret", "clientsecret", "password"] {
            XCTAssertFalse(text.contains(forbidden), forbidden)
        }
    }

    func testSettingAConnectionReplacesTheOneOfThatToolAndKeepsTheOrder() {
        var value = installation()
        let before = value.connections.map(\.tool)

        value.setConnection(SharedConnection(tool: .jira, status: .connected))
        value.setConnection(SharedConnection(tool: .fathom, status: .connected))

        XCTAssertEqual(value.connection(for: .jira)?.status, .connected)
        XCTAssertEqual(value.connections.map(\.tool), before + [.fathom])
        XCTAssertNil(value.connection(for: .granola))
    }

    // MARK: - El punto de partida (wizard corto)

    func testTheStartingPointHasOnlyTheConnectedTools() {
        let config = installation().startingPoint(agentName: "Hera")

        XCTAssertEqual(config.connections.map(\.tool), [.slack, .notion, .fireflies, .whatsapp])
        XCTAssertTrue(config.connections.allSatisfy { $0.status == .connected })
    }

    func testTheStartingPointLeavesWhatToReadUnchosenExceptWhereThereIsNothingToChoose() {
        let config = installation().startingPoint(agentName: "Hera")

        func sources(_ tool: Tool) -> SourceSelection? { config.connection(for: tool)?.sources }
        XCTAssertEqual(sources(.slack), .nothing)
        XCTAssertEqual(sources(.notion), .nothing)
        XCTAssertEqual(sources(.whatsapp), .nothing)
        // Las de transcripción no tienen fuentes que elegir: leen todo.
        XCTAssertEqual(sources(.fireflies), .everything)
    }

    func testTheStartingPointCarriesTheLanguageTheClientIDAndTheDefaults() {
        let config = installation().startingPoint(
            agentName: "Hera", projectDescription: "Tienda de ropa del Cliente B.")

        XCTAssertEqual(config.agentName, "Hera")
        XCTAssertEqual(config.language, .spanish)
        XCTAssertEqual(config.role, .productManager)
        XCTAssertEqual(config.projectDescription, "Tienda de ropa del Cliente B.")
        XCTAssertEqual(config.connection(for: .slack)?.oauthClientID, "1234567890123.1234567890123")
        XCTAssertNil(config.connection(for: .notion)?.oauthClientID)
        XCTAssertEqual(config.sendingRules, .default)
        XCTAssertEqual(config.skills, [])
    }

    func testTheStartingPointFollowsTheInstallationLanguage() {
        var value = installation()
        value.language = .english
        XCTAssertEqual(value.startingPoint(agentName: "Vesalius").language, .english)
    }

    func testTheStartingPointOfAnEmptyInstallationHasNoConnections() {
        let config = GalenoInstallation(language: .english).startingPoint(agentName: "Primero")
        XCTAssertEqual(config.connections, [])
    }

    /// Lo que arma el punto de partida se puede generar tal cual.
    func testTheStartingPointGeneratesAWorkingAgent() throws {
        var value = installation()
        let record = value.addAgent(value.startingPoint(agentName: "Hera"), agentsRoot: agentsRoot)

        let result = try ConfigGenerator().generate(
            try XCTUnwrap(value.resolvedConfig(for: record.id)),
            into: record.folder,
            options: SnapshotSupport.options)

        XCTAssertTrue(result.writtenFiles.contains("AGENTS.md"))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: record.folder.appending(path: ".mcp.json").path))
    }

    // MARK: - Agentes y carpetas

    func testAddingAgentsAssignsDistinctFoldersUnderTheRoot() {
        var value = installation()

        let first = value.addAgent(value.startingPoint(agentName: "Aurora"), agentsRoot: agentsRoot)
        let second = value.addAgent(value.startingPoint(agentName: "Aurora"), agentsRoot: agentsRoot)
        let third = value.addAgent(value.startingPoint(agentName: "aurora"), agentsRoot: agentsRoot)

        XCTAssertEqual(first.folder.lastPathComponent, "Aurora")
        XCTAssertEqual(second.folder.lastPathComponent, "Aurora 2")
        XCTAssertEqual(third.folder.lastPathComponent, "aurora 3")
        XCTAssertEqual(Set([first.id, second.id, third.id]).count, 3)
        XCTAssertEqual(value.agents.map(\.id), [first.id, second.id, third.id])
        XCTAssertEqual(first.folder.deletingLastPathComponent().path, agentsRoot.path)
    }

    /// Una carpeta "Aurora" de un agente que el usuario borró a mano no se
    /// reasigna a otro: el registro sigue apuntando a ella.
    func testAFolderStillRegisteredIsNotReusedEvenIfItIsGoneFromDisk() {
        var value = installation()
        value.addAgent(value.startingPoint(agentName: "Aurora"), agentsRoot: agentsRoot)

        let second = value.addAgent(value.startingPoint(agentName: "Aurora"), agentsRoot: agentsRoot)

        XCTAssertEqual(second.folder.lastPathComponent, "Aurora 2")
    }

    func testRenamingAnAgentKeepsItsFolderAndId() throws {
        var value = installation()
        let record = value.addAgent(value.startingPoint(agentName: "Aurora"), agentsRoot: agentsRoot)

        var renamed = record.config
        renamed.agentName = "Aurora Clínica"
        try value.setConfig(renamed, for: record.id)

        let after = try XCTUnwrap(value.agent(id: record.id))
        XCTAssertEqual(after.config.agentName, "Aurora Clínica")
        XCTAssertEqual(after.folderPath, record.folderPath)
    }

    func testSettingTheConfigOfAnUnknownAgentFails() {
        var value = installation()
        let id = UUID()
        XCTAssertThrowsError(
            try value.setConfig(value.startingPoint(agentName: "X"), for: id)
        ) { XCTAssertEqual($0 as? InstallationError, .unknownAgent(id)) }
    }

    func testRemovingAnAgentOnlyLeavesTheListAndTouchesNothingElse() throws {
        var value = installation()
        value.setConnection(SharedConnection(tool: .notion, status: .connected))
        let hera = value.addAgent(value.startingPoint(agentName: "Hera"), agentsRoot: agentsRoot)
        let aurora = value.addAgent(value.startingPoint(agentName: "Aurora"), agentsRoot: agentsRoot)

        let removed = try value.removeAgent(id: hera.id)

        XCTAssertEqual(removed, hera, "devuelve el registro, para que quien llama sepa su carpeta")
        XCTAssertEqual(value.agents.map(\.id), [aurora.id])
        XCTAssertEqual(value.connection(for: .notion)?.status, .connected, "las conexiones son de todos")
    }

    func testRemovingAnUnknownAgentFails() {
        var value = installation()
        let id = UUID()
        XCTAssertThrowsError(try value.removeAgent(id: id)) { XCTAssertEqual($0 as? InstallationError, .unknownAgent(id)) }
    }

    // MARK: - Una sola fuente de verdad

    func testTheResolvedConfigTakesStatusAndClientIDFromTheSharedConnections() throws {
        var value = installation()
        let record = value.addAgent(value.startingPoint(agentName: "Hera"), agentsRoot: agentsRoot)

        // Se cambia una sola vez, en la conexión compartida.
        value.setConnection(
            SharedConnection(tool: .slack, status: .connected, oauthClientID: "9999999999999.0000000000000"))
        value.setConnection(SharedConnection(tool: .notion, status: .skipped))

        let resolved = try XCTUnwrap(value.resolvedConfig(for: record.id))
        XCTAssertEqual(resolved.connection(for: .slack)?.oauthClientID, "9999999999999.0000000000000")
        XCTAssertEqual(resolved.connection(for: .notion)?.status, .skipped)
        // Lo que el agente eligió leer no se toca.
        XCTAssertEqual(resolved.connection(for: .fireflies)?.sources, .everything)
        // Y el agente guardado no cambió: es solo lo que se le pasa al generador.
        XCTAssertEqual(value.agent(id: record.id)?.config.connection(for: .slack)?.oauthClientID,
            "1234567890123.1234567890123")
    }

    func testAChangeInASharedConnectionReachesTheRegeneratedFiles() throws {
        var value = installation()
        let record = value.addAgent(value.startingPoint(agentName: "Hera"), agentsRoot: agentsRoot)
        let generator = ConfigGenerator()
        try generator.generate(
            try XCTUnwrap(value.resolvedConfig(for: record.id)),
            into: record.folder, options: SnapshotSupport.options)
        let mcp = record.folder.appending(path: ".mcp.json")
        let hook = record.folder.appending(path: SettingsRenderer.hookPath)
        XCTAssertTrue(try String(contentsOf: mcp, encoding: .utf8).contains("1234567890123.1234567890123"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: hook.path))

        // Slack se desconecta para todos: desaparece del agente al regenerar.
        value.setConnection(SharedConnection(tool: .slack, status: .skipped))
        let result = try generator.generate(
            try XCTUnwrap(value.resolvedConfig(for: record.id)),
            into: record.folder, options: SnapshotSupport.options)

        let text = try String(contentsOf: mcp, encoding: .utf8)
        XCTAssertFalse(text.contains("slack"))
        XCTAssertTrue(text.contains("notion"))
        // El hook sigue, por WhatsApp (lo que no sea una de sus lecturas pregunta), pero ya no nombra a Slack.
        let settings = record.folder.appending(path: ".claude/settings.json")
        XCTAssertFalse(try String(contentsOf: settings, encoding: .utf8).contains("slack"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: hook.path))
        XCTAssertFalse(result.removedFiles.contains(SettingsRenderer.hookPath))

        // Y sin WhatsApp no queda nada que aprobar: el hook se va.
        value.setConnection(SharedConnection(tool: .whatsapp, status: .skipped))
        let withoutWhatsApp = try generator.generate(
            try XCTUnwrap(value.resolvedConfig(for: record.id)),
            into: record.folder, options: SnapshotSupport.options)
        XCTAssertFalse(FileManager.default.fileExists(atPath: hook.path))
        XCTAssertTrue(withoutWhatsApp.removedFiles.contains(SettingsRenderer.hookPath))
    }

    func testAToolWithoutASharedConnectionStaysAsTheAgentHadIt() throws {
        var value = GalenoInstallation(language: .spanish)
        var config = value.startingPoint(agentName: "Suelto")
        config.connections = [ToolConnection(tool: .notion, status: .connected, sources: .everything)]
        let record = value.addAgent(config, agentsRoot: agentsRoot)

        XCTAssertEqual(value.resolvedConfig(for: record.id)?.connections, config.connections)
    }

    func testResolvingAnUnknownAgentGivesNothing() {
        XCTAssertNil(installation().resolvedConfig(for: UUID()))
    }

    // MARK: - El almacén

    private var store: InstallationStore { InstallationStore(directory: sandbox) }

    func testWithoutAFileThereIsNoInstallationYet() throws {
        XCTAssertNil(try store.load())
    }

    func testSavingAndLoading() throws {
        var original = installation()
        original.addAgent(original.startingPoint(agentName: "Aurora"), agentsRoot: agentsRoot)

        try store.save(original)

        XCTAssertEqual(try store.load(), original)
        XCTAssertEqual(store.fileURL.lastPathComponent, "installation.json")
    }

    func testSavingCreatesTheFolderAndLeavesNoTemporaryFiles() throws {
        let nested = InstallationStore(directory: sandbox.appending(path: "no/existe/todavia"))

        try nested.save(installation())
        try nested.save(installation())

        let files = try FileManager.default.contentsOfDirectory(atPath: nested.directory.path)
        XCTAssertEqual(files, ["installation.json"])
    }

    /// Un archivo corrupto no se sobrescribe ni se ignora: puede ser lo único
    /// que recuerda los agentes.
    func testACorruptFileThrowsAndIsLeftAlone() throws {
        let garbage = Data("esto no es json".utf8)
        try garbage.write(to: store.fileURL)

        XCTAssertThrowsError(try store.load()) { error in
            guard case InstallationError.unreadable = error else {
                return XCTFail("se esperaba unreadable, llegó \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: store.fileURL), garbage)
    }

    func testAFileFromANewerVersionThrowsAndIsLeftAlone() throws {
        let newer = Data(
            #"{"schemaVersion": 99, "language": "es", "connections": [], "agents": [], "algoNuevo": true}"#.utf8)
        try newer.write(to: store.fileURL)

        XCTAssertThrowsError(try store.load()) {
            XCTAssertEqual(
                $0 as? InstallationError,
                .newerThanThisApp(found: 99, supported: GalenoInstallation.currentSchemaVersion))
        }
        XCTAssertEqual(try Data(contentsOf: store.fileURL), newer)
    }

    func testTheDefaultDirectoryIsApplicationSupportGaleno() {
        XCTAssertTrue(
            InstallationStore.defaultDirectory.path.hasSuffix("/Library/Application Support/Galeno"))
    }
}
