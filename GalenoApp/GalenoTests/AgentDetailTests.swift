import GalenoCore
import XCTest

@testable import Galeno

/// El detalle de un agente (`docs/03` §3b): lo configurado a la vista y editable en su sitio. Todo en carpetas
/// temporales, con `claude`, el puente y la Papelera falsos: ninguna prueba toca el disco ni las cuentas reales.
@MainActor
final class AgentDetailTests: XCTestCase {
    private final class FakeDisconnector: AccountDisconnecting, @unchecked Sendable {
        private let lock = NSLock()
        private var list: [[String]] = []
        var shouldFail = false
        var calls: [[String]] { lock.withLock { list } }
        func remove(servers: [String]) async throws {
            struct Boom: Error {}
            if shouldFail { throw Boom() }
            lock.withLock { list.append(servers) }
        }
    }

    private final class Trashed: @unchecked Sendable {
        private let lock = NSLock()
        private var list: [URL] = []
        var urls: [URL] { lock.withLock { list } }
        /// «A la Papelera» sin tocar la real: el archivo temporal se quita del disco temporal.
        func send(_ url: URL) throws {
            lock.withLock { list.append(url) }
            try FileManager.default.removeItem(at: url)
        }
    }

    private var installer: AgentInstaller!
    private var hera: AgentRecord!
    private var jarvi: AgentRecord!
    private var defaults: UserDefaults!
    private var disconnector: FakeDisconnector!
    private var trash: Trashed!
    private var scratch: URL!

    override func setUp() async throws {
        installer = .sandboxed(skills: SkillsLocation.bundled())
        disconnector = FakeDisconnector()
        trash = Trashed()
        defaults = UserDefaults(suiteName: "agent-detail-\(UUID().uuidString)")!
        scratch = FileManager.default.temporaryDirectory.appending(path: "agent-detail-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)

        let catalog = try SkillCatalog.load(from: try XCTUnwrap(SkillsLocation.bundled()))
        func config(_ name: String, tools: [Tool], role: AgentRole = .productManager) -> AgentConfig {
            AgentConfig(
                agentName: name, language: .spanish, role: role, projectDescription: "Proyecto de \(name)",
                connections: tools.map {
                    ToolConnection(tool: $0, status: .connected, sources: .everything, serverNamePrefix: "galeno-")
                },
                skills: catalog.defaultSelection(for: role))
        }
        hera = try installer.install(config("Hera", tools: [.notion, .jira, .googleWorkspace])).record
        jarvi = try installer.install(config("Jarvi", tools: [.notion])).record
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: scratch)
        try? FileManager.default.removeItem(at: installer.agentsRoot.deletingLastPathComponent())
    }

    // MARK: Armar

    private func makeHome() -> HomeModel {
        HomeModel(
            store: installer.store, defaults: defaults, claudePath: "/ruta/claude", installer: installer, settle: {})
    }

    private func makeHealth(_ mcp: FakeMCP = FakeMCP()) -> HealthModel {
        HealthModel(
            store: installer.store, locateClaude: { "/ruta/claude" }, makeMCP: { _ in mcp }, whatsapp: FakeWhatsApp(),
            authorizer: nil, systemAuthorizer: nil, language: { .spanish }, openURL: { _ in }, returnToApp: {},
            sleep: { _ in }, playSound: { _ in })
    }

    /// El asistente que hospeda la conexión de otro número de WhatsApp, con su puente falso. `nil` sin puente.
    private func accountPicker(_ fake: FakeWhatsApp?, mcp: FakeMCP, slack: FakeSlackSetup)
        -> (@MainActor (GalenoInstallation, UUID, String) -> WizardState)?
    {
        guard let fake else { return nil }
        return { installation, id, _ in
            let services = ConnectServices(
                makeMCP: { _ in mcp }, whatsapp: fake, slack: slack,
                installer: .sandboxed(skills: SkillsLocation.bundled()), fetchRealData: false, sleep: SleepLog().sleeper)
            return WizardState(
                preferredLanguages: ["es-CO"],
                claudeStatus: .found(version: "2.1.277", path: "/ruta/claude", loggedIn: true),
                connectServices: services, startingFrom: installation, editing: id)
        }
    }

    private func numberBridge(_ fake: FakeWhatsApp?) -> (@MainActor (String) -> any WhatsAppLinking)? {
        guard let fake else { return nil }
        return { _ in fake }
    }

    private func makeDetail(
        _ record: AgentRecord? = nil, section: AgentDetailModel.Section = .general, mcp: FakeMCP = FakeMCP(),
        home: HomeModel? = nil, imported: [String: ContextFile] = [:], pickerMCP: FakeMCP = FakeMCP(),
        slack: FakeSlackSetup = FakeSlackSetup(), numbers: FakeWhatsApp? = nil
    ) -> AgentDetailModel {
        let record = record ?? hera!
        return AgentDetailModel(
            agentID: record.id, section: section, home: home ?? makeHome(), health: makeHealth(mcp), installer: installer,
            connectedHold: .zero,
            makePicker: { installation, id in
                WizardState(
                    preferredLanguages: ["es-CO"],
                    claudeStatus: .found(version: "2.1.277", path: "/ruta/claude", loggedIn: true),
                    connectServices: ConnectServices(
                        makeMCP: { _ in pickerMCP }, whatsapp: FakeWhatsApp(), slack: slack,
                        installer: .sandboxed(skills: SkillsLocation.bundled()), fetchRealData: false,
                        sleep: SleepLog().sleeper),
                    startingFrom: installation, editing: id)
            },
            disconnector: disconnector, makeMCP: { _ in mcp }, locateClaude: { "/ruta/claude" },
            makeAccountPicker: accountPicker(numbers, mcp: pickerMCP, slack: slack),
            numberBridge: numberBridge(numbers),
            trashContext: { [trash] in try trash!.send($0) },
            importContext: { url in
                if let file = imported[url.lastPathComponent] { return file }
                throw ContextImporter.Failure.unsupported
            },
            reveal: { _ in })
    }

    private func storedConfig(_ record: AgentRecord? = nil) throws -> AgentConfig {
        let installation = try XCTUnwrap(try installer.store.load())
        return try XCTUnwrap(installation.resolvedConfig(for: (record ?? hera).id))
    }

    private func file(_ path: String, in record: AgentRecord? = nil) throws -> String {
        try String(contentsOf: (record ?? hera).folder.appending(path: path), encoding: .utf8)
    }

    private func exists(_ path: String, in record: AgentRecord? = nil) -> Bool {
        FileManager.default.fileExists(atPath: (record ?? hera).folder.appending(path: path).path)
    }

    // MARK: Lo que se ve

    func testItShowsWhatTheAgentHasAndWhoElseUsesIt() throws {
        let detail = makeDetail()
        XCTAssertEqual(detail.name, "Hera")
        XCTAssertEqual(detail.role, .productManager)
        XCTAssertEqual(detail.toolRows.map(\.tool), [.notion, .jira, .googleWorkspace])
        // Notion la lee también Jarvi; Jira, no.
        XCTAssertEqual(detail.toolRows.first { $0.tool == .notion }?.sharedWith, ["Jarvi"])
        XCTAssertEqual(detail.toolRows.first { $0.tool == .jira }?.sharedWith, [])
        XCTAssertNotNil(detail.createdAt, "se lee de la carpeta del agente")
        XCTAssertEqual(detail.skillCount, 18, "las 17 de producto y /crear-skill")
        XCTAssertFalse(detail.skillsDirty, "sin abrir las cards no hay nada sin guardar")
    }

    func testTheAddableToolsAreTheOnesItDoesNotReadYet() {
        let detail = makeDetail()
        let addable = detail.addableTools
        XCTAssertFalse(addable.contains(.notion))
        XCTAssertFalse(addable.contains(.jira))
        XCTAssertFalse(addable.contains(.googleMeet), "se lee por Drive y no tiene conexión propia")
        XCTAssertTrue(addable.contains(.whatsapp))
        XCTAssertTrue(addable.allSatisfy { !$0.isComingSoon })
    }

    /// El estado sale de `HealthModel`; el «2 !» de la navegación cuenta lo que pide mirarse. Si no se pudo averiguar,
    /// se dice «Sin saber» (nunca «Conectada»).
    func testTheToolStatesComeFromHealthAndCountWhatNeedsReview() async throws {
        let mcp = FakeMCP(statuses: [
            "galeno-notion": .connected, "galeno-jira": .needsAuthentication,
            "claude.ai Google Drive": .connected, "claude.ai Google Docs": .connected, "claude.ai Google Sheets": .connected,
        ])
        let detail = makeDetail(mcp: mcp)
        await detail.health.check()

        XCTAssertEqual(detail.toolRows.first { $0.tool == .notion }?.status, .hosted(.connected))
        XCTAssertEqual(detail.toolRows.first { $0.tool == .jira }?.status, .hosted(.needsAuthorization))
        XCTAssertEqual(detail.reviewCount, 1)
        XCTAssertTrue(detail.toolRows.first { $0.tool == .jira }?.needsReview == true)
    }

    // MARK: General

    /// Cambiar el rol vuelve a escribir los archivos al momento y no toca `memoria/`.
    func testChangingTheRoleRewritesTheFolderAtOnceAndKeepsTheMemory() throws {
        let memory = hera.folder.appending(path: "memoria/mis-notas.md")
        try "lo que aprendió".write(to: memory, atomically: true, encoding: .utf8)
        let detail = makeDetail()
        let before = try file("AGENTS.md")

        detail.setRole(.marketing)

        XCTAssertEqual(detail.role, .marketing)
        XCTAssertEqual(try storedConfig().role, .marketing)
        XCTAssertNotEqual(try file("AGENTS.md"), before, "el AGENTS.md cambió: se presenta por su rol")
        XCTAssertEqual(try String(contentsOf: memory, encoding: .utf8), "lo que aprendió")
        XCTAssertEqual(try storedConfig().skills.count, 18, "cambia las skills sugeridas, no las marcadas")
        XCTAssertNil(detail.error)
        // Y lo mismo otra vez no escribe nada.
        let now = try file("AGENTS.md")
        detail.setRole(.marketing)
        XCTAssertEqual(try file("AGENTS.md"), now)
    }

    func testRenamingFromTheHomeDialogShowsTheNewName() throws {
        let home = makeHome()
        let detail = makeDetail(home: home)
        let agent = try XCTUnwrap(detail.agent)
        XCTAssertTrue(home.rename(agent, to: "Hera Pro"))
        XCTAssertEqual(detail.name, "Hera Pro")
        XCTAssertEqual(try storedConfig().agentName, "Hera Pro")
    }

    func testTheOpenTargetCanBeSwitchedWithoutOpeningAnything() {
        let home = makeHome()
        home.setOpenTarget(.terminal)
        XCTAssertEqual(home.effectiveTarget, .terminal)
        XCTAssertEqual(defaults.string(forKey: Prefs.openTarget), "terminal")
    }

    func testDeletingNeedsTheNameTypedAndIgnoresCaseAndSpaces() {
        XCTAssertTrue(HomeModel.deleteConfirmed(typed: "hera", name: "Hera"))
        XCTAssertTrue(HomeModel.deleteConfirmed(typed: "  HERA ", name: "Hera"))
        XCTAssertFalse(HomeModel.deleteConfirmed(typed: "Her", name: "Hera"))
        XCTAssertFalse(HomeModel.deleteConfirmed(typed: "", name: ""))
    }

    // MARK: Reglas

    /// Un interruptor aplica al momento: el `settings.json` ya lo refleja, sin pasar por ningún «Guardar».
    func testARuleChangeIsWrittenAtOnce() throws {
        let detail = makeDetail()
        XCTAssertEqual(detail.policy(for: .notion), .allow, "de fábrica, las escrituras internas van sin preguntar")
        XCTAssertTrue(detail.configurableWrites.contains(.notion))
        let before = try file(".claude/settings.json")

        detail.setPolicy(.ask, for: .notion)

        XCTAssertEqual(detail.policy(for: .notion), .ask)
        XCTAssertEqual(try storedConfig().sendingRules.policy(for: .notion), .ask)
        XCTAssertNotEqual(try file(".claude/settings.json"), before)
        XCTAssertEqual(
            detail.configurableWrites, InternalWrite.allCases.filter { write in
                [Tool.notion, .jira, .googleWorkspace].contains { $0.internalWrites.contains(write) }
            })
    }

    // MARK: Herramientas

    /// «Quitar de este agente»: deja de leerla; la cuenta sigue conectada y los demás agentes la siguen usando.
    func testRemovingAToolFromTheAgentKeepsTheAccountForTheOthers() throws {
        let home = makeHome()
        let detail = makeDetail(home: home)
        XCTAssertTrue(detail.removeFromAgent(.notion))

        XCTAssertEqual(detail.toolRows.map(\.tool), [.jira, .googleWorkspace])
        XCTAssertFalse(try file(".mcp.json").contains("galeno-notion"), "ya no está en su carpeta")
        XCTAssertTrue(try file(".mcp.json", in: jarvi).contains("galeno-notion"), "Jarvi la sigue leyendo")
        let installation = try XCTUnwrap(try installer.store.load())
        XCTAssertEqual(installation.connection(for: .notion)?.status, .connected, "la cuenta sigue conectada")
        XCTAssertNotNil(defaults.dictionary(forKey: Prefs.toolsChangedAt)?[hera.id.uuidString], "se anota para reiniciar Claude")
        XCTAssertNil(detail.sheet)
    }

    /// «Desconectar la cuenta»: solo si es de Galeno. Quita **sus** servidores, la deja por conectar para todos y vuelve
    /// a escribir cada agente que la tenía.
    func testDisconnectingAnAccountOfOursRemovesItsServersAndRewritesEveryAgentThatHadIt() async throws {
        let detail = makeDetail()
        XCTAssertTrue(detail.canDisconnectAccount(.notion))

        let done = await detail.disconnectAccount(.notion)

        XCTAssertTrue(done)
        XCTAssertEqual(disconnector.calls, [["galeno-notion"]], "solo sus servidores")
        let installation = try XCTUnwrap(try installer.store.load())
        XCTAssertEqual(installation.connection(for: .notion)?.status, .selected, "queda por conectar para todos")
        XCTAssertFalse(try file(".mcp.json").contains("galeno-notion"))
        XCTAssertFalse(try file(".mcp.json", in: jarvi).contains("galeno-notion"), "Jarvi también la deja de leer")
        XCTAssertEqual(detail.toolRows.map(\.tool), [.jira, .googleWorkspace])
        XCTAssertNotNil(defaults.dictionary(forKey: Prefs.toolsChangedAt)?[jarvi.id.uuidString])
        XCTAssertTrue(detail.addableTools.contains(.notion), "se puede volver a añadir")
    }

    /// Lo que no es de Galeno no se desconecta desde aquí: un conector de la cuenta de Claude, WhatsApp, ni un servidor
    /// con el nombre genérico (de otro proyecto del usuario).
    func testItNeverDisconnectsAnAccountThatIsNotGalenos() async throws {
        let detail = makeDetail()
        // Un conector de la cuenta de Claude (Google): sus servidores no son de Galeno.
        XCTAssertFalse(detail.canDisconnectAccount(.googleWorkspace))
        XCTAssertFalse(detail.canDisconnectAccount(.whatsapp))
        let google = await detail.disconnectAccount(.googleWorkspace)
        XCTAssertFalse(google)

        // Una conexión guardada antes del prefijo propio (nombre genérico).
        var installation = try XCTUnwrap(try installer.store.load())
        installation.setConnection(SharedConnection(tool: .jira, status: .connected, serverNamePrefix: nil))
        try installer.store.save(installation)
        detail.reload()
        XCTAssertFalse(detail.canDisconnectAccount(.jira))
        let jira = await detail.disconnectAccount(.jira)
        XCTAssertFalse(jira)

        XCTAssertTrue(disconnector.calls.isEmpty, "no se llamó a `claude mcp remove` para ninguna")
    }

    func testAFailedDisconnectChangesNothing() async throws {
        disconnector.shouldFail = true
        let detail = makeDetail()

        let done = await detail.disconnectAccount(.notion)

        XCTAssertFalse(done)
        XCTAssertNotNil(detail.error)
        XCTAssertEqual(try XCTUnwrap(try installer.store.load()).connection(for: .notion)?.status, .connected)
        XCTAssertTrue(try file(".mcp.json").contains("galeno-notion"))
    }

    // MARK: Skills

    /// Las skills como cards, aquí mismo: marcar no guarda; «Descartar» vuelve a lo guardado y «Guardar skills» escribe la carpeta.
    func testTickingSkillsSavesOnlyOnSaveAndDiscardChangesNothing() throws {
        let detail = makeDetail()
        detail.prepareSkillsEditor()
        let picker = try XCTUnwrap(detail.picker)
        XCTAssertTrue(picker.isSkillSelected("prd", source: .galeno))
        XCTAssertFalse(detail.skillsDirty)
        picker.toggleSkill("prd", source: .galeno)
        XCTAssertTrue(detail.skillsDirty)
        XCTAssertTrue(exists(".claude/skills/prd/SKILL.md"), "marcar no guarda")

        detail.discardSkillChanges()
        XCTAssertFalse(detail.skillsDirty)
        XCTAssertTrue(try XCTUnwrap(detail.picker).isSkillSelected("prd", source: .galeno), "volvió a lo guardado")
        XCTAssertEqual(try storedConfig().skills.count, 18)

        try XCTUnwrap(detail.picker).toggleSkill("prd", source: .galeno)
        detail.saveSkills()

        XCTAssertFalse(detail.skillsDirty, "ya está guardado")
        XCTAssertEqual(try storedConfig().skills.count, 17)
        XCTAssertFalse(exists(".claude/skills/prd/SKILL.md"))
        XCTAssertEqual(detail.skillCount, 17)
        XCTAssertTrue(exists(".claude/skills/roadmap/SKILL.md"))
        XCTAssertNotNil(detail.picker, "las cards siguen a la vista, ya desde lo guardado")
    }

    /// Una skill propia traída en las cards se copia a `skills-propias/` al guardar y queda como una más.
    func testAnOwnSkillBroughtInTheCardsIsCopiedOnSave() throws {
        let folder = scratch.appending(path: "Cierre", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "---\nname: cierre\ndescription: \"Cierra la semana.\"\n---\n\nHaz esto.\n"
            .write(to: folder.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
        let detail = makeDetail()
        detail.prepareSkillsEditor()
        let picker = try XCTUnwrap(detail.picker)
        XCTAssertNil(picker.addOwnSkill(from: folder))
        XCTAssertTrue(detail.skillsDirty, "lo traído también cuenta como sin guardar")

        detail.saveSkills()

        XCTAssertTrue(exists("skills-propias/cierre/SKILL.md"))
        XCTAssertTrue(exists(".claude/skills/cierre/SKILL.md"))
        XCTAssertFalse(detail.skillsDirty)
        XCTAssertEqual(try XCTUnwrap(detail.picker).ownSkillCards.map(\.id), ["cierre"], "queda como una de «Tus skills»")
    }

    // MARK: Conectar una herramienta nueva, aquí mismo

    private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<500 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    /// «Añadir herramienta» → elegir una: se abre **su conexión** encima del detalle (sin pasar por el asistente); al quedar
    /// conectada se guarda en el agente, anota el cambio y su fila entra a la lista.
    func testAddingAToolConnectsItRightThereAndItEntersTheList() async throws {
        let home = makeHome()
        let detail = makeDetail(home: home)
        XCTAssertTrue(detail.addableTools.contains(.fathom))

        await detail.startConnecting(.fathom)
        let wizard = try XCTUnwrap(detail.connecting)
        XCTAssertEqual(detail.connectingTool, .fathom)
        XCTAssertEqual(wizard.connectFlow?.tools, [.fathom], "solo esa herramienta")
        XCTAssertFalse(try file(".mcp.json").contains("galeno-fathom"), "hasta conectarla no se guarda nada")

        wizard.connectFlow?.connect()
        let done = await waitUntil { detail.connecting == nil }

        XCTAssertTrue(done, "\(String(describing: wizard.connectFlow?.phase))")
        XCTAssertEqual(detail.toolRows.map(\.tool), [.notion, .jira, .googleWorkspace, .fathom])
        XCTAssertEqual(detail.justAdded, .fathom, "su fila entra con el destello")
        XCTAssertTrue(try file(".mcp.json").contains("galeno-fathom"))
        XCTAssertEqual(try XCTUnwrap(try installer.store.load()).connection(for: .fathom)?.status, .connected)
        XCTAssertNotNil(defaults.dictionary(forKey: Prefs.toolsChangedAt)?[hera.id.uuidString], "se anota para reiniciar Claude")
        XCTAssertEqual(detail.section, .tools)
        XCTAssertFalse(detail.addableTools.contains(.fathom))
    }

    func testCancellingTheConnectionSavesNothing() async throws {
        let detail = makeDetail()
        await detail.startConnecting(.fathom)
        XCTAssertNotNil(detail.connecting)

        detail.cancelConnecting()

        XCTAssertNil(detail.connecting)
        XCTAssertNil(detail.connectingTool)
        XCTAssertEqual(detail.toolRows.map(\.tool), [.notion, .jira, .googleWorkspace])
        XCTAssertFalse(try file(".mcp.json").contains("galeno-fathom"))
    }

    /// «Conectar después» dentro de la conexión cierra todo sin guardar: no queda «saltada» ni a medias.
    func testSkippingTheToolInTheConnectionClosesItWithoutSaving() async throws {
        let detail = makeDetail()
        await detail.startConnecting(.fathom)

        detail.connecting?.connectFlow?.skip()
        let closed = await waitUntil { detail.connecting == nil }

        XCTAssertTrue(closed)
        XCTAssertFalse(try file(".mcp.json").contains("galeno-fathom"))
        XCTAssertEqual(detail.toolRows.map(\.tool), [.notion, .jira, .googleWorkspace])
    }

    func testItDoesNotConnectAToolTheAgentAlreadyReadsOrTwoAtOnce() async throws {
        let detail = makeDetail()
        await detail.startConnecting(.notion)
        XCTAssertNil(detail.connecting, "Notion ya la lee: no hay nada que conectar")

        await detail.startConnecting(.fathom)
        let first = detail.connecting
        await detail.startConnecting(.whatsapp)
        XCTAssertTrue(detail.connecting === first, "una conexión a la vez")
        XCTAssertEqual(detail.connectingTool, .fathom)
    }

    // MARK: Contexto

    func testTheProjectLineAndTheFilesAreSavedTogetherAndNeverOverwrite() throws {
        let brief = ContextFile(title: "Brief clínica X.pdf", text: "Lanzamos en noviembre.")
        let detail = makeDetail(imported: ["brief.pdf": brief])
        XCTAssertFalse(detail.hasUnsavedContext)
        XCTAssertEqual(detail.projectDraft, "Proyecto de Hera")

        detail.projectDraft = "App de citas para la clínica X"
        detail.addContext(from: scratch.appending(path: "brief.pdf"))
        XCTAssertTrue(detail.hasUnsavedContext)
        XCTAssertEqual(detail.pendingContext, [brief])
        XCTAssertFalse(exists("memoria/contexto/01-brief-clinica-x.md"), "hasta «Guardar contexto» no se escribe nada")

        XCTAssertTrue(detail.saveContext())

        XCTAssertTrue(try file("AGENTS.md").contains("App de citas para la clínica X"))
        XCTAssertTrue(try file("memoria/contexto/01-brief-clinica-x.md").contains("Lanzamos en noviembre."))
        XCTAssertFalse(detail.hasUnsavedContext)
        XCTAssertEqual(detail.contextEntries.map(\.title), ["Brief clínica X.pdf"])
        XCTAssertTrue(detail.pendingContext.isEmpty)
    }

    func testRemovingAContextFileGoesToTheTrashOnSaveAndUndoWorks() throws {
        try ContextFolder.add([ContextFile(title: "Roadmap", text: "Q4")], to: hera.folder, language: .spanish)
        let detail = makeDetail()
        let entry = try XCTUnwrap(detail.contextEntries.first)

        detail.toggleRemoveContext(entry)
        XCTAssertTrue(detail.hasUnsavedContext)
        detail.toggleRemoveContext(entry)
        XCTAssertFalse(detail.hasUnsavedContext, "deshacer lo devuelve")

        detail.toggleRemoveContext(entry)
        XCTAssertTrue(exists("memoria/contexto/\(entry.fileName)"), "hasta guardar sigue ahí")
        XCTAssertTrue(detail.saveContext())
        XCTAssertEqual(trash.urls.map(\.lastPathComponent), [entry.fileName], "a la Papelera, no se borra")
        XCTAssertTrue(detail.contextEntries.isEmpty)
    }

    func testContextProblemsAreSaidAndNothingIsAdded() {
        let detail = makeDetail(imported: ["vacio.md": ContextFile(title: "vacío", text: "   ")])
        detail.addContext(from: scratch.appending(path: "vacio.md"))
        XCTAssertEqual(detail.contextProblem, .empty)
        detail.addContext(from: scratch.appending(path: "foto.png"))
        XCTAssertEqual(detail.contextProblem, .unsupported)
        XCTAssertTrue(detail.pendingContext.isEmpty)
    }

    func testOnlyTenContextFilesFitCountingWhatIsPendingAndWhatIsRemoved() throws {
        try ContextFolder.add(
            (1...9).map { ContextFile(title: "m\($0)", text: "t\($0)") }, to: hera.folder, language: .spanish)
        let one = ContextFile(title: "nueva", text: "texto")
        let detail = makeDetail(imported: ["a.md": one, "b.md": one])
        XCTAssertEqual(detail.contextSlotsLeft, 1)
        detail.addContext(from: scratch.appending(path: "a.md"))
        XCTAssertEqual(detail.contextSlotsLeft, 0)
        detail.addContext(from: scratch.appending(path: "b.md"))
        XCTAssertEqual(detail.contextProblem, .tooMany)
        // Quitar uno hace sitio.
        detail.toggleRemoveContext(try XCTUnwrap(detail.contextEntries.first))
        XCTAssertEqual(detail.contextSlotsLeft, 1)
    }

    // MARK: Cómo se llega y cómo se vuelve

    private func makeApp(home: HomeModel? = nil) -> AppModel {
        let home = home ?? makeHome()
        let installer = installer!
        let disconnector = disconnector!
        func services() -> ConnectServices {
            ConnectServices(
                makeMCP: { _ in FakeMCP() }, whatsapp: FakeWhatsApp(), installer: installer, fetchRealData: false,
                sleep: SleepLog().sleeper)
        }
        return AppModel(
            home: home,
            makeWizard: { WizardState(preferredLanguages: $0, draftStore: MemoryDraftStore()) },
            makeShortWizard: { WizardState(preferredLanguages: [$0.language.rawValue], connectServices: services(), startingFrom: $0) },
            makeEditWizard: {
                WizardState(
                    preferredLanguages: [$0.language.rawValue], connectServices: services(), startingFrom: $0, editing: $1)
            },
            makeHealth: { language in HealthModel(store: installer.store, language: { language }) },
            makeAgentDetail: { id, section, home, language in
                AgentDetailModel(
                    agentID: id, section: section, home: home,
                    health: HealthModel(
                        store: installer.store, locateClaude: { nil }, whatsapp: FakeWhatsApp(), authorizer: nil,
                        systemAuthorizer: nil, language: { language }),
                    installer: installer, disconnector: disconnector, reveal: { _ in })
            })
    }

    func testOpeningTheDetailAndGoingBackToTheHome() {
        let app = makeApp()
        XCTAssertEqual(app.screen, .home)

        app.openAgent(hera.id)
        XCTAssertEqual(app.screen, .agent)
        XCTAssertEqual(app.agentDetail?.agentID, hera.id)
        XCTAssertEqual(app.agentDetail?.section, .general)

        app.closeAgent()
        XCTAssertEqual(app.screen, .home)
        XCTAssertNil(app.agentDetail)
    }

    func testAnUnknownAgentDoesNotOpenAnything() {
        let app = makeApp()
        app.openAgent(UUID())
        XCTAssertEqual(app.screen, .home)
        XCTAssertNil(app.agentDetail)
    }

    func testManagingFromTheOldPathStillReturnsToTheHome() {
        let app = makeApp()
        app.manageAgent(hera.id)
        XCTAssertEqual(app.screen, .wizard)
        app.cancelWizard()
        XCTAssertEqual(app.screen, .home, "sin «volver al detalle», cancelar vuelve al home de siempre")
    }

    func testDeletingFromTheDetailLeavesItForTheHome() throws {
        let app = makeApp()
        app.openAgent(jarvi.id)
        let agent = try XCTUnwrap(app.home.agents.first { $0.id == jarvi.id })
        app.home.askDelete(agent)
        XCTAssertNotNil(app.home.dialog)

        app.agentRemovedFromDetail()

        XCTAssertNil(app.agentDetail)
        XCTAssertEqual(app.screen, .home)
    }

    // MARK: Si el agente ya no está

    func testAnAgentThatIsNoLongerInTheInstallationIsSaidInsteadOfCrashing() throws {
        let detail = makeDetail()
        var installation = try XCTUnwrap(try installer.store.load())
        try installation.removeAgent(id: hera.id)
        try installer.store.save(installation)

        detail.reload()

        XCTAssertNil(detail.config)
        XCTAssertTrue(detail.toolRows.isEmpty)
        XCTAssertNil(detail.agent == nil ? nil : detail.config)
    }

    // MARK: Otra cuenta de una herramienta

    private func waitForAccount(_ detail: AgentDetailModel) async {
        for _ in 0..<400 where detail.accountPhase == .working { try? await Task.sleep(for: .milliseconds(5)) }
    }

    private func addAccount(_ name: String, tool: Tool = .notion, mcp: FakeMCP = FakeMCP()) async throws
        -> AgentDetailModel
    {
        let detail = makeDetail(mcp: mcp)
        detail.askAddAccount(tool)
        detail.accountDraft = name
        detail.addAccount()
        await waitForAccount(detail)
        return detail
    }

    func testOnlyToolsGalenoRegistersOfferAnotherAccount() {
        XCTAssertTrue(AccountConnector.canAdd(.notion))
        XCTAssertTrue(AccountConnector.canAdd(.jira))
        XCTAssertTrue(AccountConnector.canAdd(.slack), "Slack también, con su propia app por cuenta")
        XCTAssertFalse(AccountConnector.canAdd(.whatsapp))
        XCTAssertFalse(AccountConnector.canAdd(.googleWorkspace))
        XCTAssertFalse(AccountConnector.canAdd(.gmail))
    }

    func testAddingAnAccountRegistersItAsItsOwnServerAndAddsItToTheAgent() async throws {
        let mcp = FakeMCP()
        let detail = try await addAccount("Trabajo", mcp: mcp)

        XCTAssertEqual(detail.accountPhase, .idle)
        XCTAssertNil(detail.sheet)
        XCTAssertEqual(mcp.calls.filter { $0.hasPrefix("register") }, ["register galeno-notion-trabajo"])
        XCTAssertTrue(mcp.calls.contains("login galeno-notion-trabajo"))

        let rows = detail.toolRows.filter { $0.tool == .notion }
        XCTAssertEqual(rows.count, 2, "la de siempre y la nueva")
        XCTAssertEqual(rows.last?.accountName, "Trabajo")
        XCTAssertEqual(rows.last?.displayName(in: .spanish), "Notion (Trabajo)")

        let stored = try storedConfig()
        XCTAssertEqual(stored.connections(for: .notion).count, 2)
        let mcpJSON = try file(".mcp.json")
        XCTAssertTrue(mcpJSON.contains("\"galeno-notion\""))
        XCTAssertTrue(mcpJSON.contains("\"galeno-notion-trabajo\""))
        // La instalación recuerda cada cuenta aparte: la de siempre no se tocó.
        let installation = try XCTUnwrap(try installer.store.load())
        XCTAssertNil(installation.connection(for: ConnectionID(tool: .notion))?.accountID)
        XCTAssertEqual(installation.connection(for: ConnectionID(tool: .notion, account: "trabajo"))?.accountName, "Trabajo")
    }

    /// El punto que importa para la aprobación: la cuenta nueva lleva sus **propias** reglas.
    func testTheNewAccountGetsItsOwnPermissionRules() async throws {
        _ = try await addAccount("Trabajo")
        let settings = try file(".claude/settings.json")
        XCTAssertTrue(settings.contains("mcp__galeno-notion-trabajo__*"), "su regla, no la de la cuenta de siempre")
    }

    func testAnAccountNeverTouchesAnotherAgentUsingTheDefaultOne() async throws {
        _ = try await addAccount("Trabajo")
        let other = try storedConfig(jarvi)
        XCTAssertEqual(other.connections(for: .notion).count, 1, "Jarvi sigue con la de siempre")
        XCTAssertFalse(try file(".mcp.json", in: jarvi).contains("galeno-notion-trabajo"))
    }

    func testAddingAnAccountNotesThatTheToolsChanged() async throws {
        let home = makeHome()
        let mcp = FakeMCP()
        let detail = makeDetail(mcp: mcp, home: home)
        detail.askAddAccount(.notion)
        detail.accountDraft = "Trabajo"
        detail.addAccount()
        await waitForAccount(detail)
        XCTAssertNotNil(defaults.dictionary(forKey: Prefs.toolsChangedAt)?[hera.id.uuidString])
    }

    func testANameWithoutLettersIsRefusedAndNothingIsRegistered() async throws {
        let mcp = FakeMCP()
        let detail = try await addAccount("!!!", mcp: mcp)
        XCTAssertEqual(detail.accountPhase, .failed(.invalidName))
        XCTAssertTrue(mcp.calls.isEmpty)
        XCTAssertEqual(try storedConfig().connections(for: .notion).count, 1)
    }

    func testTheSameNameTwiceIsRefused() async throws {
        let detail = try await addAccount("Trabajo")
        detail.askAddAccount(.notion)
        detail.accountDraft = "trabajo"
        detail.addAccount()
        await waitForAccount(detail)
        XCTAssertEqual(detail.accountPhase, .failed(.alreadyExists))
        XCTAssertEqual(try storedConfig().connections(for: .notion).count, 2)
    }

    func testAServerOfTheUserWithThatNameIsNeverOverwritten() async throws {
        let mcp = FakeMCP(otherServers: ["galeno-notion-trabajo"])
        let detail = try await addAccount("Trabajo", mcp: mcp)
        XCTAssertEqual(detail.accountPhase, .failed(.nameInUse))
        XCTAssertFalse(mcp.calls.contains { $0.hasPrefix("register") || $0.hasPrefix("login") || $0.hasPrefix("remove") })
        XCTAssertEqual(try storedConfig().connections(for: .notion).count, 1)
    }

    func testIfTheUserDoesNotAuthorizeNothingIsSaved() async throws {
        let mcp = FakeMCP(loginFailures: ["galeno-notion-trabajo": [.loginTimedOut]])
        let detail = try await addAccount("Trabajo", mcp: mcp)
        XCTAssertEqual(detail.accountPhase, .failed(.notAuthorizedInTime))
        XCTAssertEqual(try storedConfig().connections(for: .notion).count, 1)
        XCTAssertFalse(try file(".mcp.json").contains("galeno-notion-trabajo"))
    }

    func testRemovingAnExtraAccountFromTheAgentKeepsTheOneOfAlways() async throws {
        let detail = try await addAccount("Trabajo")
        let id = ConnectionID(tool: .notion, account: "trabajo")
        XCTAssertTrue(detail.removeAccountFromAgent(id))
        let stored = try storedConfig()
        XCTAssertEqual(stored.connections(for: .notion).count, 1)
        XCTAssertNil(stored.connection(for: .notion)?.accountID)
        XCTAssertTrue(disconnector.calls.isEmpty, "quitar de un agente no desconecta la cuenta")
    }

    func testDisconnectingAnExtraAccountRemovesOnlyItsServer() async throws {
        let detail = try await addAccount("Trabajo")
        let id = ConnectionID(tool: .notion, account: "trabajo")
        let done = await detail.disconnectExtraAccount(id)
        XCTAssertTrue(done)
        XCTAssertEqual(disconnector.calls, [["galeno-notion-trabajo"]], "ni el de siempre ni otro del usuario")
        let installation = try XCTUnwrap(try installer.store.load())
        XCTAssertNil(installation.connection(for: id))
        XCTAssertNotNil(installation.connection(for: ConnectionID(tool: .notion)))
        XCTAssertEqual(try storedConfig().connections(for: .notion).count, 1)
    }

    func testAnExtraAccountsStateComesFromItsOwnServer() async throws {
        let mcp = FakeMCP(statuses: ["galeno-notion": .connected, "galeno-notion-trabajo": .needsAuthentication])
        let detail = makeDetail(mcp: mcp)
        detail.askAddAccount(.notion)
        detail.accountDraft = "Trabajo"
        detail.addAccount()
        await waitForAccount(detail)
        detail.refreshHealth()
        for _ in 0..<200 where detail.health.isChecking { try? await Task.sleep(for: .milliseconds(5)) }
        let extra = detail.toolRows.first { $0.accountID == "trabajo" }
        // Tras autorizar, el guion de la prueba la deja conectada: lo que importa es que su estado es el suyo.
        XCTAssertEqual(extra?.status, .hosted(.connected))
    }

    // MARK: Otra cuenta de Slack (una app de Slack por cuenta)

    func testSlackIsOfferedButItNeedsItsOwnApp() {
        XCTAssertTrue(AccountConnector.canAdd(.slack))
        XCTAssertTrue(AccountConnector.needsOwnApp(.slack))
        XCTAssertFalse(AccountConnector.needsOwnApp(.notion))
    }

    func testAddingASlackAccountRunsTheWholeFlowAndAddsItToTheAgent() async throws {
        let eco = try installer.install(
            AgentConfig(
                agentName: "Eco", language: .spanish,
                connections: [
                    ToolConnection(
                        tool: .slack, status: .connected, sources: .everything, oauthClientID: "1111.2222",
                        serverNamePrefix: "galeno-")
                ])
        ).record
        let mcp = FakeMCP(statuses: ["galeno-slack": .connected])
        let slack = FakeSlackSetup(clientID: "3333.4444", secretValue: "SECRETO-DE-PRUEBA")
        let detail = makeDetail(eco, pickerMCP: mcp, slack: slack)

        detail.askAddAccount(.slack)
        detail.accountDraft = "Cliente A"
        detail.addAccount()
        // Pasa por la conexión de siempre: primero pide el token de configuración.
        for _ in 0..<400 where detail.connecting?.connectFlow?.phase != .slackToken {
            try? await Task.sleep(for: .milliseconds(5))
        }
        let flow = try XCTUnwrap(detail.connecting?.connectFlow, "se abrió la conexión de Slack")
        XCTAssertEqual(flow.phase, .slackToken)
        XCTAssertEqual(detail.connectingAccount, ConnectionID(tool: .slack, account: "cliente-a"))

        flow.submitSlackToken("xoxe.xoxp-token-de-prueba")
        for _ in 0..<600 where detail.connecting != nil { try? await Task.sleep(for: .milliseconds(5)) }

        XCTAssertNil(detail.connecting, "al quedar conectada se cierra sola")
        XCTAssertEqual(slack.calls, ["validate", "createApp"])
        XCTAssertTrue(mcp.calls.contains("register galeno-slack-cliente-a con app propia"))
        XCTAssertTrue(mcp.calls.contains("login galeno-slack-cliente-a"))
        XCTAssertFalse(mcp.calls.contains { $0.hasPrefix("register galeno-slack ") || $0 == "register galeno-slack" },
            "el servidor de siempre no se vuelve a registrar")

        let stored = try storedConfig(eco)
        XCTAssertEqual(stored.connections(for: .slack).count, 2)
        let extra = try XCTUnwrap(stored.connection(for: ConnectionID(tool: .slack, account: "cliente-a")))
        XCTAssertEqual(extra.oauthClientID, "3333.4444", "su propia app, no la de la cuenta de siempre")
        XCTAssertEqual(stored.connection(for: ConnectionID(tool: .slack))?.oauthClientID, "1111.2222")

        let mcpJSON = try file(".mcp.json", in: eco)
        XCTAssertTrue(mcpJSON.contains("\"galeno-slack-cliente-a\""))
        XCTAssertTrue(mcpJSON.contains("3333.4444"))
        let settings = try file(".claude/settings.json", in: eco)
        XCTAssertTrue(settings.contains("mcp__galeno-slack-cliente-a__slack_send_message"), "pregunta antes de enviar")
        // El secreto nunca llega a un archivo.
        XCTAssertFalse(mcpJSON.contains("SECRETO-DE-PRUEBA"))
        XCTAssertFalse(settings.contains("SECRETO-DE-PRUEBA"))
    }

    func testCancellingASlackAccountSavesNothing() async throws {
        let eco = try installer.install(
            AgentConfig(
                agentName: "Eco", language: .spanish,
                connections: [
                    ToolConnection(
                        tool: .slack, status: .connected, sources: .everything, oauthClientID: "1111.2222",
                        serverNamePrefix: "galeno-")
                ])
        ).record
        let detail = makeDetail(eco, pickerMCP: FakeMCP(statuses: ["galeno-slack": .connected]))
        detail.askAddAccount(.slack)
        detail.accountDraft = "Cliente A"
        detail.addAccount()
        for _ in 0..<400 where detail.connecting == nil { try? await Task.sleep(for: .milliseconds(5)) }
        detail.cancelConnecting()
        XCTAssertNil(detail.connecting)
        XCTAssertNil(detail.connectingAccount)
        XCTAssertEqual(try storedConfig(eco).connections(for: .slack).count, 1)
    }

    // MARK: Otro número de WhatsApp

    private func agentWithWhatsApp(numbers: [(account: String?, name: String?)] = [(nil, nil)]) throws -> AgentRecord {
        try installer.install(
            AgentConfig(
                agentName: "Eco", language: .spanish,
                connections: numbers.map { number in
                    ToolConnection(
                        tool: .whatsapp, status: .connected, sources: .everything, sendingAccepted: true,
                        accountID: number.account, accountName: number.name)
                })
        ).record
    }

    func testASecondNumberIsOfferedUntilTheCap() throws {
        let one = makeDetail(try agentWithWhatsApp())
        XCTAssertTrue(one.canAddAccount(.whatsapp))
        let two = makeDetail(try agentWithWhatsApp(numbers: [(nil, nil), ("trabajo", "Trabajo")]))
        XCTAssertFalse(two.canAddAccount(.whatsapp), "dos números es el máximo")
    }

    func testAThirdNumberIsRefusedAndNothingIsLinked() async throws {
        let eco = try agentWithWhatsApp(numbers: [(nil, nil), ("trabajo", "Trabajo")])
        let fake = FakeWhatsApp()
        let detail = makeDetail(eco, numbers: fake)
        detail.askAddAccount(.whatsapp)
        XCTAssertNil(detail.sheet, "ni se abre la hoja")
        // Aunque se llegara a `addAccount`, el tope también está en `prepare`.
        let refused = AccountConnector.prepare(
            tool: .whatsapp, name: "Otro",
            existing: [ConnectionID(tool: .whatsapp), ConnectionID(tool: .whatsapp, account: "trabajo")])
        XCTAssertEqual(refused.failureValue, .limitReached)
        XCTAssertTrue(fake.calls.isEmpty)
    }

    func testLinkingASecondNumberAddsItWithItsOwnServerAndRules() async throws {
        let eco = try agentWithWhatsApp()
        let fake = FakeWhatsApp(state: .notLinked, pairEvents: [.qr(Data([0x89])), .succeeded])
        let detail = makeDetail(eco, numbers: fake)

        detail.askAddAccount(.whatsapp)
        detail.accountDraft = "Trabajo"
        detail.addAccount()
        for _ in 0..<400 where detail.connecting?.connectFlow == nil { try? await Task.sleep(for: .milliseconds(5)) }
        let flow = try XCTUnwrap(detail.connecting?.connectFlow)
        XCTAssertEqual(detail.connectingAccount, ConnectionID(tool: .whatsapp, account: "trabajo"))

        flow.connect()  // lo que hace el botón «Continuar» tras la advertencia
        for _ in 0..<800 where detail.connecting != nil { try? await Task.sleep(for: .milliseconds(5)) }

        XCTAssertNil(detail.connecting)
        XCTAssertTrue(fake.calls.contains("pair"))
        XCTAssertTrue(fake.calls.contains("installLaunchd"), "su servicio de fondo")

        let stored = try storedConfig(eco)
        let number = try XCTUnwrap(stored.connection(for: ConnectionID(tool: .whatsapp, account: "trabajo")))
        XCTAssertEqual(number.sendingAccepted, true, "aceptó la advertencia al vincular")
        XCTAssertNil(number.serverNamePrefix)

        let mcpJSON = try file(".mcp.json", in: eco)
        XCTAssertTrue(mcpJSON.contains("\"whatsapp-trabajo\""))
        XCTAssertTrue(mcpJSON.contains("--account"))
        let settings = try file(".claude/settings.json", in: eco)
        XCTAssertTrue(settings.contains("mcp__whatsapp-trabajo__send_message"), "pregunta antes de enviar")
        XCTAssertTrue(settings.contains("mcp__whatsapp__send_message"), "y el de siempre sigue igual")
    }

    func testDisconnectingANumberClosesItsSessionAndServiceButNotTheOtherOne() async throws {
        let eco = try agentWithWhatsApp(numbers: [(nil, nil), ("trabajo", "Trabajo")])
        let fake = FakeWhatsApp()
        let detail = makeDetail(eco, numbers: fake)
        let id = ConnectionID(tool: .whatsapp, account: "trabajo")

        let done = await detail.disconnectNumber(id)

        XCTAssertTrue(done)
        XCTAssertEqual(fake.calls.filter { $0 == "unlink" || $0 == "uninstallService" }, ["unlink", "uninstallService"])
        let installation = try XCTUnwrap(try installer.store.load())
        XCTAssertNil(installation.connection(for: id))
        XCTAssertNotNil(installation.connection(for: ConnectionID(tool: .whatsapp)), "el de siempre sigue")
        XCTAssertFalse(try file(".mcp.json", in: eco).contains("whatsapp-trabajo"))
        XCTAssertTrue(try file(".mcp.json", in: eco).contains("\"whatsapp\""))
    }

    func testRelinkingANumberClosesItsSessionAndStartsTheLinkAgain() async throws {
        let eco = try agentWithWhatsApp(numbers: [(nil, nil), ("trabajo", "Trabajo")])
        let fake = FakeWhatsApp()
        let detail = makeDetail(eco, numbers: fake)

        detail.relinkNumber(ConnectionID(tool: .whatsapp, account: "trabajo"))
        for _ in 0..<400 where detail.connecting == nil { try? await Task.sleep(for: .milliseconds(5)) }

        XCTAssertNotNil(detail.connecting)
        XCTAssertTrue(fake.calls.contains("unlink"))
        XCTAssertEqual(detail.connectingAccount, ConnectionID(tool: .whatsapp, account: "trabajo"))
        detail.cancelConnecting()
    }
}

private extension Result {
    var failureValue: Failure? {
        if case .failure(let failure) = self { return failure }
        return nil
    }
}
