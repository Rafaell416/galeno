import GalenoCore
import XCTest

@testable import Galeno

/// Lo que escribe en el disco al final del wizard, siempre en carpetas temporales.
final class AgentInstallerTests: XCTestCase {
    private var sandbox: URL!

    override func setUpWithError() throws {
        sandbox = FileManager.default.temporaryDirectory
            .appending(path: "galeno-installer/\(UUID().uuidString)", directoryHint: .isDirectory)
        for id in ["prd", "acta"] {
            let folder = sandbox.appending(path: "skills/galeno/\(id)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try "---\nname: \(id)\ndescription: \"x\"\n---\nbody\n".write(
                to: folder.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
        }
    }

    override func tearDownWithError() throws {
        if let sandbox { try? FileManager.default.removeItem(at: sandbox) }
    }

    private var supportDirectory: URL { sandbox.appending(path: "support", directoryHint: .isDirectory) }
    private var agentsRoot: URL { sandbox.appending(path: "Galeno", directoryHint: .isDirectory) }
    private var store: InstallationStore { InstallationStore(directory: supportDirectory) }

    private var installer: AgentInstaller {
        AgentInstaller(
            store: store, agentsRoot: agentsRoot,
            options: ConfigGenerator.Options(
                skillsDirectory: sandbox.appending(path: "skills"), whatsAppBridgePath: "/bridge/galeno-whatsapp"))
    }

    private func config(
        name: String = "Hera", skills: [String] = ["prd"], slackStatus: ConnectionStatus = .connected,
        prefix: String? = nil
    ) -> AgentConfig {
        AgentConfig(
            agentName: name, language: .spanish, projectDescription: "Proyecto de prueba",
            connections: [
                ToolConnection(
                    tool: .slack, status: slackStatus, sources: .only([Source(id: "C1", name: "#producto", kind: .channel)]),
                    oauthClientID: "1234567890123.1234567890123", serverNamePrefix: prefix),
                ToolConnection(tool: .notion, status: .connected, sources: .nothing),
            ],
            skills: skills.map { SelectedSkill(id: $0, source: .galeno) })
    }

    private func exists(_ relative: String, in folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder.appending(path: relative).path)
    }

    // MARK: Lo básico

    func testInstallWritesTheAgentsFolderAndSavesTheInstallation() throws {
        let outcome = try installer.install(config())

        let folder = outcome.record.folder
        XCTAssertEqual(folder.lastPathComponent, "Hera")
        XCTAssertEqual(folder.deletingLastPathComponent().path, agentsRoot.path)
        for file in ["AGENTS.md", "CLAUDE.md", ".mcp.json", ".claude/settings.json", ".claude/skills/prd/SKILL.md", "memoria/proyecto.md"] {
            XCTAssertTrue(exists(file, in: folder), file)
        }

        let saved = try XCTUnwrap(try store.load())
        XCTAssertEqual(saved.agents.map(\.id), [outcome.record.id])
        XCTAssertEqual(saved.language, .spanish)
        XCTAssertEqual(saved.connection(for: .slack)?.oauthClientID, "1234567890123.1234567890123")
        XCTAssertEqual(saved.connection(for: .slack)?.status, .connected)
    }

    func testTheGeneratedFolderCarriesTheChosenSourcesAndSkills() throws {
        let folder = try installer.install(config()).record.folder
        let agents = try String(contentsOf: folder.appending(path: "AGENTS.md"), encoding: .utf8)
        XCTAssertTrue(agents.contains("#producto"), "lo que eligió leer queda en el AGENTS.md")
        XCTAssertFalse(exists(".claude/skills/acta", in: folder), "lo que no marcó no se copia")
    }

    func testTheAlternateServerNameIsUsedEverywhereAndRemembered() throws {
        let outcome = try installer.install(config(prefix: "galeno-"))
        let mcp = try String(contentsOf: outcome.record.folder.appending(path: ".mcp.json"), encoding: .utf8)
        XCTAssertTrue(mcp.contains("\"galeno-slack\""))
        XCTAssertEqual(try store.load()?.connection(for: .slack)?.serverNamePrefix, "galeno-")
    }

    func testNoSecretEndsUpInTheInstallationFile() throws {
        _ = try installer.install(config())
        let text = try String(contentsOf: store.fileURL, encoding: .utf8).lowercased()
        XCTAssertFalse(text.contains("secret"))
        XCTAssertFalse(text.contains("xox"))
    }

    // MARK: Varios agentes

    func testASecondAgentGetsItsOwnFolderAndSharesTheConnections() throws {
        let first = try installer.install(config(name: "Hera"))
        let second = try installer.install(config(name: "Hera"))

        XCTAssertNotEqual(first.record.folder, second.record.folder)
        XCTAssertEqual(second.record.folder.lastPathComponent, "Hera 2")
        let saved = try XCTUnwrap(try store.load())
        XCTAssertEqual(saved.agents.count, 2)
        XCTAssertEqual(saved.connections.filter { $0.tool == .slack }.count, 1, "una sola conexión compartida")
    }

    // MARK: Volver a generar

    func testGeneratingAgainForTheSameAgentReusesItsFolderAndNeverTouchesItsMemory() throws {
        let first = try installer.install(config(skills: ["prd", "acta"]))
        let memory = first.record.folder.appending(path: "memoria/proyecto.md")
        try "Notas del agente: no tocar\n".write(to: memory, atomically: true, encoding: .utf8)

        let again = try installer.install(config(skills: ["prd"]), existingAgentID: first.record.id)

        XCTAssertEqual(again.record.id, first.record.id)
        XCTAssertEqual(again.record.folder, first.record.folder, "no crea «Hera 2»")
        XCTAssertEqual(try String(contentsOf: memory, encoding: .utf8), "Notas del agente: no tocar\n")
        XCTAssertFalse(exists(".claude/skills/acta", in: again.record.folder), "la desmarcada se quita")
        XCTAssertEqual(try store.load()?.agents.count, 1)
    }

    // MARK: Cuando algo falla, no queda nada a medias

    func testAFailedGenerationLeavesNoFolderAndNoRecord() throws {
        XCTAssertThrowsError(try installer.install(config(skills: ["no-existe"]))) {
            guard case GenerationError.missingSkill = $0 else { return XCTFail("\($0)") }
        }
        XCTAssertNil(try store.load(), "installation.json no se escribió")
        XCTAssertFalse(FileManager.default.fileExists(atPath: agentsRoot.appending(path: "Hera").path))
    }

    func testAFailedRegenerationKeepsTheSavedAgentAsItWas() throws {
        let first = try installer.install(config())
        XCTAssertThrowsError(try installer.install(config(skills: ["no-existe"]), existingAgentID: first.record.id))

        let saved = try XCTUnwrap(try store.load())
        XCTAssertEqual(saved.agents.first?.config.skills.map(\.id), ["prd"], "la config guardada no cambió")
    }

    /// Un `installation.json` que no se puede leer puede ser lo único que recuerda los agentes.
    func testAnUnreadableInstallationIsNeverOverwritten() throws {
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        try "esto no es json".write(to: store.fileURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try installer.install(config()))

        XCTAssertEqual(try String(contentsOf: store.fileURL, encoding: .utf8), "esto no es json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: agentsRoot.appending(path: "Hera").path))
    }

    // MARK: Las conexiones compartidas

    func testSkippingAToolNeverDowngradesOneAnotherAgentAlreadyConnected() throws {
        _ = try installer.install(config(name: "Hera"))
        _ = try installer.install(config(name: "Zeus", slackStatus: .skipped))

        XCTAssertEqual(try store.load()?.connection(for: .slack)?.status, .connected)
    }

    func testASkippedToolNobodyConnectedIsRecordedAsSkipped() throws {
        _ = try installer.install(config(slackStatus: .skipped))
        XCTAssertEqual(try store.load()?.connection(for: .slack)?.status, .skipped)
    }
}

// MARK: - La pantalla 9

@MainActor
final class GenerationFlowTests: XCTestCase {
    private let outcome = AgentInstaller.Outcome(
        record: AgentRecord(config: AgentConfig(agentName: "Hera", language: .spanish), folderPath: "/tmp/Hera"),
        result: GenerationResult(writtenFiles: ["AGENTS.md"]))

    private struct Boom: Error, CustomStringConvertible { var description: String { "boom" } }

    func testTheStepsCompleteInOrderAndEndSucceeded() async {
        let flow = GenerationFlow(sleep: SleepLog().sleeper) { [outcome] in outcome }

        flow.start()
        let done = await waitUntil { flow.phase == .succeeded }

        XCTAssertTrue(done, "\(flow.phase)")
        XCTAssertEqual(flow.completed, Set(GenerationFlow.Step.allCases))
        XCTAssertEqual(flow.outcome, outcome)
        XCTAssertNil(flow.current)
    }

    /// Un fallo se muestra donde ocurrió y no se disfraza de éxito.
    func testAFailureStopsTheStepsAndSaysWhy() async {
        let flow = GenerationFlow(sleep: SleepLog().sleeper) { throw Boom() }

        flow.start()
        let failed = await waitUntil { flow.phase == .failed("boom") }

        XCTAssertTrue(failed, "\(flow.phase)")
        XCTAssertNotEqual(flow.completed, Set(GenerationFlow.Step.allCases))
        XCTAssertNil(flow.outcome)
    }

    func testRetryRunsAgainAndCanSucceed() async {
        let attempts = Counter()
        let flow = GenerationFlow(sleep: SleepLog().sleeper) { [outcome] in
            if attempts.increment() == 1 { throw Boom() }
            return outcome
        }
        flow.start()
        _ = await waitUntil { flow.phase == .failed("boom") }

        flow.retry()
        let done = await waitUntil { flow.phase == .succeeded }

        XCTAssertTrue(done, "\(flow.phase)")
        XCTAssertEqual(attempts.value, 2)
    }

    func testStartingTwiceDoesNotGenerateTwice() async {
        let attempts = Counter()
        let flow = GenerationFlow(sleep: SleepLog().sleeper) { [outcome] in
            _ = attempts.increment()
            return outcome
        }
        flow.start()
        flow.start()
        _ = await waitUntil { flow.phase == .succeeded }
        XCTAssertEqual(attempts.value, 1)
    }

    func testEngineErrorsAreExplainedInTheirOwnWords() {
        XCTAssertEqual(
            GenerationFlow.describe(GenerationError.emptyAgentName), "El agente necesita un nombre.")
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    @discardableResult func increment() -> Int { lock.withLock { count += 1; return count } }
}

// MARK: - Abrir el agente

final class AgentLinkTests: XCTestCase {
    private let folder = URL(fileURLWithPath: "/Users/ana/Galeno/Hera 2", isDirectory: true)

    func testTheClaudeAppLinkCarriesTheFolderAndThePrompt() throws {
        let url = AgentLink.claudeApp(folder: folder, prompt: "Resume lo que pasó & lo de «mañana»")
        let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.scheme, "claude")
        XCTAssertEqual(parts.host, "code")
        XCTAssertEqual(parts.path, "/new")
        XCTAssertEqual(parts.queryItems?.first { $0.name == "folder" }?.value, "/Users/ana/Galeno/Hera 2")
        XCTAssertEqual(parts.queryItems?.first { $0.name == "q" }?.value, "Resume lo que pasó & lo de «mañana»")
    }

    func testTheTerminalLinkUsesCwd() throws {
        let url = AgentLink.claudeCLI(folder: folder, prompt: nil)
        XCTAssertEqual(url.scheme, "claude-cli")
        XCTAssertEqual(url.absoluteString, "claude-cli://open?cwd=%2FUsers%2Fana%2FGaleno%2FHera%202")
    }

    /// Un `&` o un `=` dentro del texto no puede cortar ni inventar parámetros del enlace.
    func testSpecialCharactersCannotInjectParameters() throws {
        let url = AgentLink.claudeApp(folder: folder, prompt: "a&folder=/etc&x=1+2")
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.map(\.name), ["folder", "q"])
        XCTAssertEqual(items.first { $0.name == "folder" }?.value, "/Users/ana/Galeno/Hera 2")
        XCTAssertEqual(items.first { $0.name == "q" }?.value, "a&folder=/etc&x=1+2")
    }

    func testTheTerminalFallbackScriptQuotesEverything() {
        let script = AgentLink.terminalScript(
            folder: URL(fileURLWithPath: "/Users/ana/Galeno/O'Brien; rm -rf ~", isDirectory: true),
            claudePath: "/opt/homebrew/bin/claude")
        XCTAssertEqual(
            script,
            "#!/bin/zsh\ncd -- '/Users/ana/Galeno/O'\\''Brien; rm -rf ~' || exit 1\nexec '/opt/homebrew/bin/claude'\n")
    }

    /// Con la primera pregunta: va citada, como la ruta, y nada de lo que diga puede salirse de las comillas.
    func testTheTerminalFallbackScriptCarriesTheFirstQuestionQuoted() {
        let script = AgentLink.terminalScript(
            folder: URL(fileURLWithPath: "/Users/ana/Galeno/Hera", isDirectory: true),
            claudePath: "/opt/homebrew/bin/claude", prompt: "Resume lo de 'hoy'; rm -rf ~")
        XCTAssertEqual(
            script,
            "#!/bin/zsh\ncd -- '/Users/ana/Galeno/Hera' || exit 1\nexec '/opt/homebrew/bin/claude' 'Resume lo de '\\''hoy'\\''; rm -rf ~'\n")
    }

    func testTheFirstCommandFollowsWhatTheUserConnected() {
        XCTAssertEqual(
            FirstCommand.suggestion(for: [.notion, .slack], language: .spanish),
            "¿Cuáles son los 3 mensajes más recientes de Slack donde me mencionan?")
        XCTAssertEqual(
            FirstCommand.suggestion(for: [.slack, .notion, .whatsapp], language: .spanish),
            "¿Qué hay de nuevo en mis 3 chats más recientes de WhatsApp?", "con WhatsApp conectado, la primera prueba es WhatsApp")
        XCTAssertEqual(
            FirstCommand.suggestion(for: [.jira, .notion], language: .spanish),
            "¿Cuáles son las 3 páginas de Notion que cambiaron más recientemente?")
        XCTAssertEqual(
            FirstCommand.suggestion(for: [.whatsapp], language: .english), "What’s new in my 3 most recent WhatsApp chats?")
        XCTAssertEqual(FirstCommand.suggestion(for: [.fathom], language: .spanish), "Resume mi última reunión")
        XCTAssertEqual(FirstCommand.suggestion(for: [], language: .spanish), "Preséntate en tres líneas y dime qué puedes hacer por mí")
    }

    /// La primera pregunta tiene que responderse en segundos: acotada («3», «última»), nunca «resume la semana».
    func testTheFirstCommandForAConnectedToolIsAlwaysBounded() {
        for tool in Tool.allCases where tool != .claudeDesign {
            for language in Language.allCases {
                let suggestion = FirstCommand.suggestion(for: [tool], language: language)
                XCTAssertNotNil(
                    suggestion.range(of: #"3|tres|three|última|latest"#, options: .regularExpression),
                    "\(tool) [\(language)]: \(suggestion)")
                XCTAssertFalse(suggestion.contains("esta semana") || suggestion.contains("this week"), suggestion)
            }
        }
    }
}
