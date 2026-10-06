import GalenoCore
import XCTest

@testable import Galeno

/// Las skills propias del usuario (`docs/03` §6.3; decisión de Rafa, 6 oct 2026): archivos de su propio Mac que entran
/// al paso «Skills» bajo «Tus skills», se copian a `skills-propias/` del agente al crear o guardar, y el motor las
/// instala desde ahí. Nada remoto, y una propia no cambia ningún permiso. Todo en carpetas temporales.
@MainActor
final class OwnSkillsTests: XCTestCase {
    private var scratch: URL!

    override func setUp() async throws {
        scratch = FileManager.default.temporaryDirectory.appending(path: "own-skills-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    /// Una carpeta de skill como la escribiría Simon: `SKILL.md` con frontmatter y una plantilla al lado.
    private func makeSkillFolder(_ name: String, description: String = "Cierra la semana a mi manera.") throws -> URL {
        let folder = scratch.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "---\nname: \(OwnSkills.identifier(from: name))\ndescription: \"\(description)\"\n---\n\nHaz esto.\n"
            .write(to: folder.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
        try "plantilla".write(to: folder.appending(path: "plantilla.md"), atomically: true, encoding: .utf8)
        return folder
    }

    private func makeReadyState() -> WizardState {
        let state = WizardState(
            preferredLanguages: ["es-CO"],
            claudeStatus: .found(version: "2.1.277", path: "/ruta/claude", loggedIn: true),
            connectServices: ConnectServices(
                makeMCP: { _ in FakeMCP() }, whatsapp: FakeWhatsApp(), installer: .sandboxed(skills: SkillsLocation.bundled()),
                fetchRealData: false, sleep: SleepLog().sleeper))
        state.agentName = "Aurora"
        state.toggle(.notion)
        state.loadSkillCatalog()
        return state
    }

    /// Hasta «Listo» (o, en «Gestionar», hasta que guardó: ahí «Guardando» es el último paso).
    private func runToTheEnd(_ state: WizardState) {
        for _ in 0..<20 {
            if state.step == .connect {
                state.beginConnecting()
                for _ in 0..<20 where state.connectFlow?.isFinished != true { state.connectFlow?.skip() }
            }
            if state.step == .generating {
                state.beginGeneration()
                let deadline = Date().addingTimeInterval(5)
                while state.generation?.phase == .running, Date() < deadline {
                    RunLoop.main.run(until: Date().addingTimeInterval(0.01))
                }
                state.finishGeneration()
                if state.mode == .edit { return }
                continue
            }
            if state.isLastStep { return }
            state.next()
        }
    }

    // MARK: El importador

    func testAFolderWithASkillFileOrALooseMarkdownIsASkill() throws {
        let folder = try makeSkillFolder("Mi Cierre")
        let fromFolder = try OwnSkillImporter.inspect(folder)
        XCTAssertEqual(fromFolder.id, "mi-cierre")
        XCTAssertEqual(fromFolder.name, "mi-cierre")
        XCTAssertEqual(fromFolder.summary, "Cierra la semana a mi manera.")

        let loose = scratch.appending(path: "Notas de Ventas.md")
        try "# Notas\n\nResume la reunión en tres líneas.\n".write(to: loose, atomically: true, encoding: .utf8)
        let fromFile = try OwnSkillImporter.inspect(loose)
        XCTAssertEqual(fromFile.id, "notas-de-ventas")
        XCTAssertEqual(fromFile.summary, "Resume la reunión en tres líneas.", "sin frontmatter, el primer párrafo")

        let empty = scratch.appending(path: "vacia", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        XCTAssertThrowsError(try OwnSkillImporter.inspect(empty)) { XCTAssertEqual($0 as? OwnSkillImporter.Failure, .noSkillFile) }
        let image = scratch.appending(path: "foto.png")
        try Data([0]).write(to: image)
        XCTAssertThrowsError(try OwnSkillImporter.inspect(image)) { XCTAssertEqual($0 as? OwnSkillImporter.Failure, .noSkillFile) }
        let odd = scratch.appending(path: "¿?.md")
        try "x".write(to: odd, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try OwnSkillImporter.inspect(odd)) { XCTAssertEqual($0 as? OwnSkillImporter.Failure, .invalidName) }
    }

    /// Copiar deja `skills-propias/<id>/SKILL.md` (la carpeta entera, o el `.md` como `SKILL.md`) y no toca el original.
    func testCopyingLeavesTheSkillInTheAgentFolderAndTheOriginalAlone() throws {
        let agent = scratch.appending(path: "Agente", directoryHint: .isDirectory)
        let folder = try makeSkillFolder("Mi Cierre")
        try OwnSkillImporter.copy(folder, id: "mi-cierre", into: agent)
        XCTAssertTrue(FileManager.default.fileExists(atPath: agent.appending(path: "skills-propias/mi-cierre/SKILL.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: agent.appending(path: "skills-propias/mi-cierre/plantilla.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appending(path: "SKILL.md").path), "el original sigue ahí")

        let loose = scratch.appending(path: "notas.md")
        try "# Notas\n".write(to: loose, atomically: true, encoding: .utf8)
        try OwnSkillImporter.copy(loose, id: "notas", into: agent)
        XCTAssertEqual(
            try String(contentsOf: agent.appending(path: "skills-propias/notas/SKILL.md"), encoding: .utf8), "# Notas\n")
        XCTAssertEqual(OwnSkills.list(in: agent).map(\.id), ["mi-cierre", "notas"])
    }

    // MARK: El asistente

    /// Traer una la deja marcada bajo «Tus skills», con lo que su `SKILL.md` dice; al crear el agente se copia a su
    /// carpeta y queda instalada como cualquier otra.
    func testAnOwnSkillIsTickedAndInstalledWithTheAgent() throws {
        let state = makeReadyState()
        let before = state.skills.count
        XCTAssertNil(state.addOwnSkill(from: try makeSkillFolder("Mi Cierre")))

        XCTAssertEqual(state.ownSkillCards.map(\.id), ["mi-cierre"])
        XCTAssertEqual(state.ownSkillCards.first?.source, .own)
        XCTAssertEqual(state.ownSkillCards.first?.group, WizardState.ownSkillGroupID)
        XCTAssertEqual(state.ownSkillCards.first?.summary.es, "Cierra la semana a mi manera.")
        XCTAssertTrue(state.isSkillSelected("mi-cierre", source: .own))
        XCTAssertEqual(state.skills.count, before + 1)
        // Se puede desmarcar sin quitarla, como cualquier otra.
        state.toggleSkill("mi-cierre", source: .own)
        XCTAssertFalse(state.isSkillSelected("mi-cierre", source: .own))
        XCTAssertEqual(state.ownSkillCards.count, 1)
        state.toggleSkill("mi-cierre", source: .own)

        runToTheEnd(state)
        let folder = try XCTUnwrap(state.generatedAgent?.folder)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appending(path: "skills-propias/mi-cierre/SKILL.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appending(path: ".claude/skills/mi-cierre/SKILL.md").path))
        XCTAssertTrue(state.generatedAgent?.config.skills.contains(SelectedSkill(id: "mi-cierre", source: .own)) == true)
        XCTAssertTrue(
            try String(contentsOf: folder.appending(path: "AGENTS.md"), encoding: .utf8).contains("- `/mi-cierre`"))
        // Y el agente no puede editarla: solo el usuario.
        let settings = try String(contentsOf: folder.appending(path: ".claude/settings.json"), encoding: .utf8)
        XCTAssertTrue(settings.contains("\"Edit(/skills-propias/**)\""))
        XCTAssertTrue(state.ownSkills.allSatisfy { $0.pendingSource == nil }, "ya está en la carpeta")
    }

    /// El id de una del catálogo está ocupado; una propia repetida, también. Quitarla antes de crear no deja rastro.
    func testACatalogIdOrARepeatedOneIsRefusedAndRemovingForgetsIt() throws {
        let state = makeReadyState()
        XCTAssertEqual(state.addOwnSkill(from: try makeSkillFolder("PRD")), .duplicate("prd"))
        XCTAssertNil(state.addOwnSkill(from: try makeSkillFolder("Mi Cierre")))
        XCTAssertEqual(state.addOwnSkill(from: try makeSkillFolder("mi cierre")), .duplicate("mi-cierre"))
        XCTAssertEqual(state.ownSkillCards.count, 1)

        state.removeOwnSkill("mi-cierre")
        XCTAssertTrue(state.ownSkillCards.isEmpty)
        XCTAssertFalse(state.skills.contains { $0.source == .own })

        runToTheEnd(state)
        let folder = try XCTUnwrap(state.generatedAgent?.folder)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appending(path: "skills-propias").path))
    }

    /// Un borrador no sabe de dónde copiar una propia: al reanudar, no vuelve marcada (no se podría instalar).
    func testADraftNeverBringsBackAnOwnSkill() throws {
        let store = MemoryDraftStore()
        let state = WizardState(preferredLanguages: ["es-CO"], draftStore: store)
        state.agentName = "Aurora"
        state.next()
        state.loadSkillCatalog()
        XCTAssertNil(state.addOwnSkill(from: try makeSkillFolder("Mi Cierre")))
        state.saveDraft()
        XCTAssertTrue(try XCTUnwrap(store.load()).skills.contains { $0.source == .own })

        let resumed = WizardState(preferredLanguages: ["es-CO"], draftStore: store)
        resumed.resumeDraft()
        XCTAssertFalse(resumed.skills.contains { $0.source == .own })
        XCTAssertTrue(resumed.ownSkillCards.isEmpty)
    }

    /// «Gestionar»: las propias que ya están en la carpeta aparecen con lo que dicen; traer otra y guardar la copia
    /// al lado, y la carpeta de las propias no la toca el motor.
    func testManagingAnAgentListsItsOwnSkillsAndAddsTheNewOnes() throws {
        let installer = AgentInstaller.sandboxed(skills: SkillsLocation.bundled())
        var config = AgentConfig(agentName: "Hera", language: .spanish, projectDescription: "Lanzamiento")
        config.connections = [ToolConnection(tool: .notion, status: .connected, sources: .everything)]
        let record = try installer.install(
            config, ownSkills: [.init(id: "mi-cierre", source: try makeSkillFolder("Mi Cierre"))]
        ).record
        defer { try? FileManager.default.removeItem(at: record.folder.deletingLastPathComponent().deletingLastPathComponent()) }
        XCTAssertEqual(OwnSkills.list(in: record.folder).map(\.id), ["mi-cierre"])

        // Se guardó con la propia marcada.
        var installation = try XCTUnwrap(try installer.store.load())
        var saved = try XCTUnwrap(installation.agent(id: record.id)?.config)
        saved.skills.append(SelectedSkill(id: "mi-cierre", source: .own))
        try installation.setConfig(saved, for: record.id)
        try installer.store.save(installation)

        let editor = WizardState(
            preferredLanguages: ["es-CO"],
            claudeStatus: .found(version: "2.1.277", path: "/ruta/claude", loggedIn: true),
            connectServices: ConnectServices(
                makeMCP: { _ in FakeMCP() }, whatsapp: FakeWhatsApp(), installer: installer,
                fetchRealData: false, sleep: SleepLog().sleeper),
            startingFrom: try installer.store.load(), editing: record.id)
        XCTAssertEqual(editor.mode, .edit)
        XCTAssertEqual(editor.ownSkillCards.map(\.id), ["mi-cierre"])
        XCTAssertTrue(editor.isSkillSelected("mi-cierre", source: .own))
        XCTAssertTrue(editor.ownSkills.allSatisfy { $0.pendingSource == nil })

        editor.loadSkillCatalog()
        XCTAssertNil(editor.addOwnSkill(from: try makeSkillFolder("Notas")))
        runToTheEnd(editor)
        XCTAssertEqual(OwnSkills.list(in: record.folder).map(\.id), ["mi-cierre", "notas"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.folder.appending(path: ".claude/skills/notas/SKILL.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.folder.appending(path: ".claude/skills/mi-cierre/SKILL.md").path))
    }
}
