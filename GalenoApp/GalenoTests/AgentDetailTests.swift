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

    private func makeDetail(
        _ record: AgentRecord? = nil, section: AgentDetailModel.Section = .general, mcp: FakeMCP = FakeMCP(),
        home: HomeModel? = nil, imported: [String: ContextFile] = [:]
    ) -> AgentDetailModel {
        let record = record ?? hera!
        return AgentDetailModel(
            agentID: record.id, section: section, home: home ?? makeHome(), health: makeHealth(mcp), installer: installer,
            makePicker: { installation, id in
                WizardState(
                    preferredLanguages: ["es-CO"],
                    claudeStatus: .found(version: "2.1.277", path: "/ruta/claude", loggedIn: true),
                    connectServices: ConnectServices(
                        makeMCP: { _ in FakeMCP() }, whatsapp: FakeWhatsApp(),
                        installer: .sandboxed(skills: SkillsLocation.bundled()), fetchRealData: false,
                        sleep: SleepLog().sleeper),
                    startingFrom: installation, editing: id)
            },
            disconnector: disconnector, trashContext: { [trash] in try trash!.send($0) },
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
        XCTAssertEqual(detail.skillCount, 17)
        // El resumen por grupo: los cuatro de producto, con lo marcado.
        XCTAssertEqual(detail.skillSummary.map(\.id), ["documents", "work", "reports", "meetings"])
        XCTAssertEqual(detail.skillSummary.first?.selected, detail.skillSummary.first?.total, "todas marcadas de fábrica")
        XCTAssertTrue(detail.skillSummary.first?.names.contains("PRD") == true)
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
        XCTAssertEqual(try storedConfig().skills.count, 17, "cambia las skills sugeridas, no las marcadas")
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

    func testChoosingSkillsSavesOnlyOnSaveAndCancelChangesNothing() throws {
        let detail = makeDetail()
        detail.openSkillsPicker()
        let picker = try XCTUnwrap(detail.picker)
        XCTAssertTrue(picker.isSkillSelected("prd", source: .galeno))
        picker.toggleSkill("prd", source: .galeno)

        detail.cancelSkillsPicker()
        XCTAssertNil(detail.picker)
        XCTAssertTrue(exists(".claude/skills/prd/SKILL.md"), "cancelar no cambia nada")
        XCTAssertEqual(try storedConfig().skills.count, 17)

        detail.openSkillsPicker()
        let again = try XCTUnwrap(detail.picker)
        again.toggleSkill("prd", source: .galeno)
        detail.saveSkills()

        XCTAssertNil(detail.picker)
        XCTAssertEqual(try storedConfig().skills.count, 16)
        XCTAssertFalse(exists(".claude/skills/prd/SKILL.md"))
        XCTAssertEqual(detail.skillCount, 16)
        XCTAssertTrue(exists(".claude/skills/roadmap/SKILL.md"))
    }

    /// Una skill propia traída en el catálogo se copia a `skills-propias/` al guardar, y entra al resumen.
    func testAnOwnSkillBroughtInThePickerIsCopiedOnSaveAndShownInTheSummary() throws {
        let folder = scratch.appending(path: "Cierre", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "---\nname: cierre\ndescription: \"Cierra la semana.\"\n---\n\nHaz esto.\n"
            .write(to: folder.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
        let detail = makeDetail()
        detail.openSkillsPicker()
        let picker = try XCTUnwrap(detail.picker)
        XCTAssertNil(picker.addOwnSkill(from: folder))

        detail.saveSkills()

        XCTAssertTrue(exists("skills-propias/cierre/SKILL.md"))
        XCTAssertTrue(exists(".claude/skills/cierre/SKILL.md"))
        XCTAssertEqual(detail.skillSummary.last?.id, WizardState.ownSkillGroupID)
        XCTAssertEqual(detail.skillSummary.last?.names, ["cierre"])
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

    /// «Añadir herramienta» abre el asistente de «Gestionar» con esa herramienta marcada, en el paso de herramientas; al
    /// cancelar o terminar se vuelve al detalle, en «Herramientas».
    func testAddingAToolOpensTheAssistantWithItTickedAndComesBackToTheDetail() throws {
        let app = makeApp()
        app.openAgent(hera.id)

        app.addTool(.fathom, to: hera.id)

        XCTAssertEqual(app.screen, .wizard)
        XCTAssertEqual(app.wizard.mode, .edit)
        XCTAssertEqual(app.wizard.step, .tools)
        XCTAssertTrue(app.wizard.isSelected(.fathom))
        XCTAssertNil(app.agentDetail?.picker)

        app.cancelWizard()

        XCTAssertEqual(app.screen, .agent)
        XCTAssertEqual(app.agentDetail?.agentID, hera.id)
        XCTAssertEqual(app.agentDetail?.section, .tools)
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
}
