import GalenoCore
import SwiftUI
import XCTest

@testable import Galeno

/// El paso «Skills» como cards (`docs/03` §3): lo que dice cada card y su vista previa sale del catálogo y nunca
/// afirma más que él; cada skill tiene su dibujo; y ↩ es de la card cuando tiene el foco.
@MainActor
final class SkillsStepTests: XCTestCase {
    private let es = Locale(identifier: "es")
    private let en = Locale(identifier: "en")

    private func skill(_ id: String = "x", writes: [Tool] = [], needsAny: [Tool] = []) -> CatalogSkill {
        CatalogSkill(
            id: id, group: "g", name: LocalizedText(es: "X", en: "X"), summary: LocalizedText(es: "s", en: "s"),
            writes: writes, needsAny: needsAny)
    }

    // MARK: Lo que falta

    func testASkillThatTakesAnyMeetingToolSaysItNeedsAMeetingsTool() {
        let acta = skill(needsAny: [.fireflies, .granola, .fathom, .googleWorkspace])
        XCTAssertEqual(
            SkillPresentation.missingLabel(for: acta, language: .spanish, locale: es), "Falta: herramienta de reuniones")
        XCTAssertEqual(SkillPresentation.missingLabel(for: acta, language: .english, locale: en), "Missing: meetings tool")
    }

    func testASkillThatNeedsOneToolNamesIt() {
        XCTAssertEqual(
            SkillPresentation.missingLabel(for: skill(needsAny: [.slack]), language: .spanish, locale: es), "Falta: Slack")
        XCTAssertEqual(
            SkillPresentation.missingLabel(for: skill(needsAny: [.jira]), language: .english, locale: en), "Missing: Jira")
    }

    // MARK: Qué necesita y dónde escribe

    func testASkillThatWritesNowhereSaysItAnswersInTheConversation() {
        XCTAssertEqual(
            SkillPresentation.needsText(for: skill(), language: .spanish, locale: es),
            "No escribe en ninguna herramienta: te responde en la conversación.")
    }

    func testOnePlaceIsNamedAndSeveralAreOfferedAsAChoice() {
        XCTAssertEqual(
            SkillPresentation.needsText(for: skill(writes: [.notion]), language: .spanish, locale: es), "Escribe en Notion.")
        XCTAssertEqual(
            SkillPresentation.needsText(for: skill(writes: [.notion, .googleWorkspace]), language: .spanish, locale: es),
            "Escribe en Notion o Google Drive, donde tú elijas.")
        XCTAssertEqual(
            SkillPresentation.needsText(for: skill(writes: [.notion, .googleWorkspace, .slack]), language: .english, locale: en),
            "Writes in Notion, Google Drive or Slack, wherever you choose.")
    }

    func testAMeetingsSkillNamesTheBrandsAndWhereItWrites() {
        let acta = skill(writes: [.notion, .jira], needsAny: [.fireflies, .granola, .fathom, .googleWorkspace])
        XCTAssertEqual(
            SkillPresentation.needsText(for: acta, language: .spanish, locale: es),
            "Una herramienta de reuniones conectada (Fireflies, Granola o Fathom). Escribe en Notion o Jira, donde tú elijas.")
    }

    func testASlackOnlySkillSaysItPostsToTheChannel() {
        let report = skill(writes: [.slack], needsAny: [.slack])
        XCTAssertEqual(
            SkillPresentation.needsText(for: report, language: .spanish, locale: es),
            "Publica en el canal del proyecto en Slack.")
        XCTAssertTrue(report.sendsToOthers, "y la vista previa añade que siempre pide aprobación")
    }

    func testOneOfJoinsLikeASentence() {
        XCTAssertEqual(SkillPresentation.oneOf([], locale: es), "")
        XCTAssertEqual(SkillPresentation.oneOf(["A"], locale: es), "A")
        XCTAssertEqual(SkillPresentation.oneOf(["A", "B"], locale: es), "A o B")
        XCTAssertEqual(SkillPresentation.oneOf(["A", "B", "C"], locale: en), "A, B or C")
    }

    // MARK: El catálogo que viaja con la app

    /// Cada skill del catálogo empaquetado tiene su dibujo, su «cómo pedirla» y su ejemplo: ninguna card sale con el
    /// símbolo genérico ni una vista previa vacía.
    func testEveryBundledSkillHasItsDrawingAndItsPreview() throws {
        let directory = try XCTUnwrap(SkillsLocation.bundled(), "las skills van dentro de la app")
        let catalog = try SkillCatalog.load(from: directory)
        XCTAssertEqual(catalog.galeno.count, 18)
        // Todas las que tienen tarjeta, también las de terceros: ninguna sale con el símbolo genérico.
        for skill in catalog.cards {
            XCTAssertTrue(SkillIcon.hasDrawing(skill.id), "\(skill.id) no tiene dibujo")
            XCTAssertNotNil(skill.ask, skill.id)
            XCTAssertNotNil(skill.example, skill.id)
        }
        XCTAssertFalse(SkillIcon.hasDrawing("una-que-no-existe"), "una skill sin dibujo usa el símbolo genérico")
        XCTAssertEqual(
            catalog.groups.filter { !catalog.skills(in: $0).isEmpty }.count, 6,
            "los cuatro grupos nuestros, marketing y comercial")
    }

    // MARK: Las skills de Anthropic (marketing)

    /// Las de marketing viajan con la app, tienen tarjeta con su vista previa y dicen de quién son.
    func testTheMarketingSkillsShipWithTheirCreditAndPreview() throws {
        let directory = try XCTUnwrap(SkillsLocation.bundled())
        let catalog = try SkillCatalog.load(from: directory)
        let marketing = try XCTUnwrap(catalog.groups.first { $0.id == "marketing" })
        let cards = catalog.skills(in: marketing)

        XCTAssertEqual(cards.count, 10)
        XCTAssertEqual(catalog.cards.count, 44, "18 nuestras, 10 de marketing y 16 de comercial")
        let sales = try XCTUnwrap(catalog.groups.first { $0.id == "sales" })
        XCTAssertEqual(catalog.skills(in: sales).count, 17, "16 de Anthropic y /prospeccion, nuestra")
        XCTAssertEqual(catalog.missingFiles(in: directory), [], "cada una con su SKILL.md dentro de la app")
        for card in cards {
            XCTAssertEqual(card.source, .curated)
            XCTAssertTrue(["Anthropic", "Tribe AI"].contains(card.credit?.author ?? ""), card.id)
            XCTAssertEqual(card.credit?.sourceURL.host, "github.com")
            XCTAssertNotNil(card.ask, card.id)
            XCTAssertNotNil(card.example, card.id)
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: directory.appending(path: "curated/\(card.id)/LICENSE").path),
                "\(card.id): la licencia viaja con ella")
        }
    }

    /// De fábrica no vienen marcadas (son de otro rol); se marcan como cualquier otra, y cuentan en el total.
    func testAMarketingSkillIsTickedLikeAnyOtherAndInstalledFromItsOwnFolder() throws {
        let state = try stateAtSkills()
        guard case .loaded(let catalog) = state.skillCatalog else { return XCTFail("sin catálogo") }
        let plan = try XCTUnwrap(catalog.cards.first { $0.id == "campaign-plan" })
        XCTAssertFalse(state.isSkillSelected(plan.id, source: plan.source), "de fábrica solo las nuestras")

        state.toggleSkill(plan.id, source: plan.source)

        XCTAssertTrue(state.skills.contains(SelectedSkill(id: "campaign-plan", source: .curated)))
        XCTAssertFalse(state.isSkillSelected(plan.id, source: .galeno), "no se confunde con una nuestra")
    }

    /// Un agente generado con una de marketing la recibe entera: el `SKILL.md` adaptado y su licencia.
    func testAnAgentGetsTheMarketingSkillWithItsLicense() throws {
        let skills = try XCTUnwrap(SkillsLocation.bundled())
        let installer = AgentInstaller.sandboxed(skills: skills)
        addTeardownBlock { try? FileManager.default.removeItem(at: installer.agentsRoot.deletingLastPathComponent()) }

        let record = try installer.install(
            AgentConfig(
                agentName: "Mara", language: .spanish, projectDescription: "Marketing",
                connections: [ToolConnection(tool: .notion, status: .connected, sources: .everything)],
                skills: [
                    SelectedSkill(id: "acta", source: .galeno), SelectedSkill(id: "campaign-plan", source: .curated),
                ])
        ).record

        let installed = record.folder.appending(path: ".claude/skills/campaign-plan")
        let text = try String(contentsOf: installed.appending(path: "SKILL.md"), encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("---\nname: campaign-plan\n"))
        XCTAssertTrue(text.contains("Respond and produce all documents in the user's configured language."))
        XCTAssertTrue(text.contains("Apache-2.0"), "dice de dónde salió y con qué licencia")
        XCTAssertTrue(FileManager.default.fileExists(atPath: installed.appending(path: "LICENSE").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.folder.appending(path: ".claude/skills/acta/SKILL.md").path))
    }

    /// Todos los textos que la pantalla arma con `Localized.string` existen en los dos idiomas (si faltara uno se
    /// vería la clave).
    func testEveryStringTheScreenBuildsExistsInBothLanguages() {
        let keys = [
            "skills.count %lld %lld", "skills.missing %@", "skills.missing.meetings", "skills.list.or",
            "skills.preview.needs.meetings %@", "skills.preview.needs.tool %@", "skills.preview.writes.none",
            "skills.preview.writes.one %@", "skills.preview.writes.several %@", "skills.preview.writes.slack",
            "skills.preview.mark %@", "skills.preview.mark.plain", "skills.from.galeno", "skills.from.author %@ %@",
            "skills.credit.original", "skills.preview.how",
            "skills.preview.needs", "skills.preview.illustrative", "skills.demo.reads %@ %@",
            "skills.demo.placeholder %@", "skills.demo.replay", "skills.demo.agent",
            "skills.own.group", "skills.own.add", "skills.own.hint", "skills.own.remove", "skills.from.own",
            "skills.own.error.noSkillFile", "skills.own.error.invalidName", "skills.own.error.unreadable",
            "skills.own.error.duplicate %@",
        ]
        for locale in [es, en] {
            for key in keys {
                XCTAssertNotEqual(Localized.string(key, locale: locale), key, "\(key) en \(locale.identifier)")
            }
        }
    }

    // MARK: La demostración de la vista previa

    /// El resultado de ejemplo se escribe en el catálogo como líneas con una marca; aquí se vuelven bloques. Las filas
    /// de tabla seguidas forman una sola tabla.
    func testExampleLinesBecomeFormattedBlocks() {
        let blocks = SkillDoc.blocks([
            "# Acta · reunión", "## Decisiones", "- Se pospone el login.", "> Hola, Laura.",
            "| Épica | Trimestre |", "| Reagendar | T4 |", "Un párrafo.", "   ",
        ])
        XCTAssertEqual(
            blocks,
            [
                .title("Acta · reunión"), .section("Decisiones"), .bullet("Se pospone el login."), .quote("Hola, Laura."),
                .table([["Épica", "Trimestre"], ["Reagendar", "T4"]]), .paragraph("Un párrafo."),
            ])
        XCTAssertEqual(SkillDoc.blocks(["| a | b |", "texto", "| c | d |"]).count, 3, "una tabla interrumpida son dos")
        XCTAssertEqual(
            SkillDoc.plainText(["# Título", "| a | b |", "| c | d |"]), "Título. a, b. c, d", "VoiceOver lo lee de corrido")
    }

    /// Una pregunta larga no hace esperar: escribirla nunca pasa de 1,6 s.
    func testTypingNeverTakesLongerThanItsCap() {
        XCTAssertEqual(SkillDemoTiming.perCharacter(count: 10), .milliseconds(35))
        XCTAssertEqual(SkillDemoTiming.perCharacter(count: 80), .milliseconds(20))
        XCTAssertEqual(SkillDemoTiming.perCharacter(count: 0), .zero)
    }

    /// Cada skill empaquetada tiene un resultado con forma (título, sección, tabla o borrador) que cabe en la hoja.
    func testEveryBundledExampleIsAFormattedResultThatFits() throws {
        let catalog = try SkillCatalog.load(from: try XCTUnwrap(SkillsLocation.bundled()))
        for skill in catalog.galeno {
            let example = try XCTUnwrap(skill.example, skill.id)
            for language in [Language.spanish, .english] {
                let blocks = SkillDoc.blocks(example.output.lines(in: language))
                XCTAssertGreaterThanOrEqual(blocks.count, 2, skill.id)  // una tabla entera cuenta como un bloque
                XCTAssertTrue(
                    blocks.contains { block in
                        switch block {
                        case .title, .section, .table, .quote: true
                        case .bullet, .paragraph: false
                        }
                    }, "\(skill.id): sin formato")
                for case .table(let rows) in blocks {
                    XCTAssertTrue(Set(rows.map(\.count)).count == 1, "\(skill.id): filas de distinto ancho")
                    XCTAssertLessThanOrEqual(rows[0].count, 3, "\(skill.id): más de tres columnas no cabe")
                }
            }
        }
    }

    // MARK: Las flechas

    /// La lista es una sola rejilla de 3 columnas partida en grupos: ←/→ no salen de la fila; ↑/↓ pasan a la fila
    /// vecina, también de un grupo a otro, en la misma columna o en la última card si la fila es más corta.
    func testArrowsWalkTheGridAcrossGroups() {
        let rows = SkillGrid.rows([["a", "b", "c", "d"], ["e", "f", "g", "h", "i"]], columns: 3)
        XCTAssertEqual(rows, [["a", "b", "c"], ["d"], ["e", "f", "g"], ["h", "i"]])

        XCTAssertEqual(SkillGrid.neighbor(of: "a", .right, in: rows), "b")
        XCTAssertNil(SkillGrid.neighbor(of: "c", .right, in: rows), "no salta a la fila siguiente")
        XCTAssertNil(SkillGrid.neighbor(of: "a", .left, in: rows))
        XCTAssertEqual(SkillGrid.neighbor(of: "c", .down, in: rows), "d", "fila más corta: la última card")
        XCTAssertEqual(SkillGrid.neighbor(of: "d", .down, in: rows), "e", "pasa al grupo siguiente")
        XCTAssertEqual(SkillGrid.neighbor(of: "g", .down, in: rows), "i")
        XCTAssertEqual(SkillGrid.neighbor(of: "e", .up, in: rows), "d", "y vuelve al anterior")
        XCTAssertNil(SkillGrid.neighbor(of: "a", .up, in: rows))
        XCTAssertNil(SkillGrid.neighbor(of: "h", .down, in: rows))
        XCTAssertNil(SkillGrid.neighbor(of: "no-existe", .down, in: rows))
    }

    // MARK: ↩ en el paso

    /// Con una card enfocada o la vista previa abierta, ↩ es de la card (abre o no hace nada); «Siguiente» pasa a ⌘↩.
    /// En cualquier otro caso ↩ sigue siendo «Siguiente».
    func testReturnBelongsToTheStepOnlyWhileACardIsFocusedOrThePreviewIsOpen() throws {
        let elsewhere = WizardState()
        elsewhere.skillCardHasFocus = true
        elsewhere.previewedSkill = skill()
        XCTAssertFalse(elsewhere.returnBelongsToStep, "fuera del paso de skills no cuenta")

        let state = try stateAtSkills()
        XCTAssertEqual(state.step, .skills)
        XCTAssertFalse(state.returnBelongsToStep, "sin foco ni vista previa, ↩ es «Siguiente»")
        state.skillCardHasFocus = true
        XCTAssertTrue(state.returnBelongsToStep)
        state.skillCardHasFocus = false
        state.previewedSkill = skill()
        XCTAssertTrue(state.returnBelongsToStep)
        state.previewedSkill = nil
        XCTAssertFalse(state.returnBelongsToStep)
    }

    /// Marcar desde la vista previa es lo mismo que marcar la card: una sola selección, la del agente.
    func testTickingFromThePreviewChangesTheSameSelectionAsTheCard() throws {
        let state = try stateAtSkills()
        guard case .loaded(let catalog) = state.skillCatalog else { return XCTFail("sin catálogo") }
        let acta = try XCTUnwrap(catalog.galeno.first { $0.id == "acta" })
        let before = state.isSkillSelected(acta.id, source: .galeno)

        state.previewedSkill = acta
        state.toggleSkill(acta.id, source: .galeno)

        XCTAssertEqual(state.isSkillSelected(acta.id, source: .galeno), !before)
        XCTAssertEqual(state.previewedSkill, acta, "marcar no cierra la vista previa")
    }

    /// «Gestionar» sobre un agente con sus herramientas ya conectadas: «Tus herramientas» → «Skills», sin «Conectar».
    /// Todo en carpetas temporales, con las skills que viajan dentro de la app.
    private func stateAtSkills() throws -> WizardState {
        let skills = try XCTUnwrap(SkillsLocation.bundled())
        let installer = AgentInstaller.sandboxed(skills: skills)
        addTeardownBlock { try? FileManager.default.removeItem(at: installer.agentsRoot.deletingLastPathComponent()) }
        let record = try installer.install(
            AgentConfig(
                agentName: "Hera", language: .spanish, projectDescription: "Proyecto",
                connections: [ToolConnection(tool: .notion, status: .connected, sources: .everything)])
        ).record
        let installation = try XCTUnwrap(try installer.store.load())
        let services = ConnectServices(
            makeMCP: { _ in FakeMCP() }, whatsapp: FakeWhatsApp(), slack: FakeSlackSetup(), installer: installer,
            skillsDirectory: skills, fetchRealData: false)
        let state = WizardState(
            preferredLanguages: ["es"], claudeStatus: .found(version: "2.1.277", path: "/ruta/claude", loggedIn: true),
            connectServices: services, startingFrom: installation, editing: record.id)
        state.loadSkillCatalog()
        for _ in 0..<4 where state.step != .skills { state.next() }
        return state
    }
}
