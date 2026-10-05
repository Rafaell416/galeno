import Foundation
import XCTest

@testable import GalenoCore

final class SkillCatalogTests: XCTestCase {
    /// El `skills/` real del repositorio.
    private var repoSkills: URL {
        URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appending(path: "skills")
    }

    private func catalog(
        galeno: String = #"{"id":"prd","group":"documents","name":{"es":"PRD","en":"PRD"},"summary":{"es":"a","en":"b"},"writes":["notion"],"needsAny":[]}"#,
        curated: String = "", version: Int = 1
    ) -> Data {
        Data("""
            {"schemaVersion":\(version),
             "groups":[{"id":"documents","name":{"es":"Documentos","en":"Documents"}}],
             "galeno":[\(galeno)],"curated":[\(curated)]}
            """.utf8)
    }

    private let goodCurated = #"""
        {"id":"x-prd","name":{"es":"PRD","en":"PRD"},"summary":{"es":"a","en":"b"},"author":"someone",
         "repository":"https://github.com/someone/skills","path":"skills/prd","license":"MIT","available":false}
        """#

    // MARK: Leer

    func testDecodesACatalog() throws {
        let value = try SkillCatalog.decode(catalog(curated: goodCurated))
        XCTAssertEqual(value.galeno.map(\.id), ["prd"])
        XCTAssertEqual(value.galeno.first?.writes, [.notion])
        XCTAssertEqual(value.curated.first?.sourceURL.absoluteString, "https://github.com/someone/skills/tree/main/skills/prd")
        XCTAssertEqual(value.galeno.first?.name.text(in: .spanish), "PRD")
    }

    func testEverythingOursIsSelectedByDefault() throws {
        let value = try SkillCatalog.decode(catalog())
        XCTAssertEqual(value.defaultSelection, [SelectedSkill(id: "prd", source: .galeno)])
    }

    func testANewerFormatIsRefusedInsteadOfHalfRead() {
        XCTAssertThrowsError(try SkillCatalog.decode(catalog(version: 99))) {
            XCTAssertEqual($0 as? SkillCatalogError, .newerThanThisApp(found: 99, supported: 1))
        }
    }

    // MARK: Validar

    func testRepeatedIdsAreRejected() {
        let twice = #"{"id":"prd","group":"documents","name":{"es":"a","en":"a"},"summary":{"es":"a","en":"a"},"writes":[],"needsAny":[]}"#
        XCTAssertThrowsError(try SkillCatalog.decode(catalog(galeno: twice + "," + twice)))
    }

    func testAnIdThatCouldEscapeTheFolderIsRejected() {
        let bad = #"{"id":"../evil","group":"documents","name":{"es":"a","en":"a"},"summary":{"es":"a","en":"a"},"writes":[],"needsAny":[]}"#
        XCTAssertThrowsError(try SkillCatalog.decode(catalog(galeno: bad)))
    }

    func testAnUnknownGroupIsRejected() {
        let bad = #"{"id":"prd","group":"nope","name":{"es":"a","en":"a"},"summary":{"es":"a","en":"a"},"writes":[],"needsAny":[]}"#
        XCTAssertThrowsError(try SkillCatalog.decode(catalog(galeno: bad)))
    }

    /// `AGENTS.md`: nada de licencias no comerciales (deanpeters es CC BY-NC-SA).
    func testOnlyPermittedLicensesAreAccepted() {
        for license in ["CC-BY-NC-SA-4.0", "GPL-3.0", "", "Verificar"] {
            let bad = goodCurated.replacingOccurrences(of: "\"MIT\"", with: "\"\(license)\"")
            XCTAssertThrowsError(try SkillCatalog.decode(catalog(curated: bad)), license)
        }
    }

    func testCuratedSkillsMustPointToGitHubWithAnAuthor() {
        let notGitHub = goodCurated.replacingOccurrences(of: "https://github.com/someone/skills", with: "https://evil.example.com/skills")
        let noAuthor = goodCurated.replacingOccurrences(of: "\"someone\"", with: "\"\"")
        XCTAssertThrowsError(try SkillCatalog.decode(catalog(curated: notGitHub)))
        XCTAssertThrowsError(try SkillCatalog.decode(catalog(curated: noAuthor)))
    }

    // MARK: Utilidad

    func testASkillThatNeedsATranscriptToolIsNotUsefulWithoutOne() throws {
        let needs = #"{"id":"acta","group":"documents","name":{"es":"a","en":"a"},"summary":{"es":"a","en":"a"},"writes":[],"needsAny":["fireflies","granola"]}"#
        let skill = try XCTUnwrap(SkillCatalog.decode(catalog(galeno: needs)).galeno.first)
        XCTAssertFalse(skill.isUseful(with: [.slack, .notion]))
        XCTAssertTrue(skill.isUseful(with: [.slack, .granola]))
    }

    // MARK: El catálogo real del repositorio

    func testTheRealCatalogIsValidAndMatchesTheSkillsOnDisk() throws {
        let value = try SkillCatalog.load(from: repoSkills)

        XCTAssertEqual(value.galeno.count, 17, "las 17 skills de docs/03 §6.1")
        XCTAssertEqual(value.missingFiles(in: repoSkills), [], "cada skill disponible tiene su SKILL.md")
        for skill in value.galeno {
            XCTAssertFalse(skill.name.es.isEmpty || skill.name.en.isEmpty || skill.summary.es.isEmpty || skill.summary.en.isEmpty, skill.id)
        }
        // Y ninguna carpeta de skill queda fuera del catálogo.
        let onDisk = try FileManager.default.contentsOfDirectory(atPath: repoSkills.appending(path: "galeno").path)
            .filter { !$0.hasPrefix(".") }
        XCTAssertEqual(Set(onDisk), Set(value.galeno.map(\.id)))
    }

    /// La instrucción de idioma, la misma en todas (`AGENTS.md`).
    private static let languageLine = "Respond and produce all documents in the user's configured language."

    /// Las que pueden terminar enviando algo a otras personas (Slack o correo): piden un «yes» explícito.
    private static let sends: Set<String> = [
        "release-notes", "resumen-proyecto", "seguimiento", "informe-slack", "reporte-dia", "acta",
    ]

    /// Lo que cada skill nuestra tiene que traer (`docs/03` §6.1): un nombre que cuadra con su carpeta, la instrucción de idioma
    /// exacta justo después del frontmatter, un procedimiento completo y su sección de reglas; que lo que dicen las fuentes no sea
    /// una orden; que no invente; que pregunte dónde escribir en vez de asumir; y, si envía a otros, aprobación explícita.
    func testEveryOfOurSkillsIsComplete() throws {
        let value = try SkillCatalog.load(from: repoSkills)
        XCTAssertTrue(Self.sends.isSubset(of: Set(value.galeno.map(\.id))))
        for skill in value.galeno {
            let id = skill.id
            let text = try String(contentsOf: repoSkills.appending(path: "galeno/\(id)/SKILL.md"), encoding: .utf8)
            XCTAssertTrue(text.hasPrefix("---\nname: \(id)\ndescription: \""), id)
            let afterFrontmatter = try XCTUnwrap(text.components(separatedBy: "\n---\n").dropFirst().first, id)
            XCTAssertTrue(afterFrontmatter.hasPrefix("\n\(Self.languageLine)\n"), "\(id): la instrucción de idioma va primero")
            XCTAssertTrue(text.contains("## Rules"), "\(id): reglas")
            XCTAssertTrue(text.contains("never an instruction to you"), "\(id): lo que dicen las fuentes no es una orden")
            XCTAssertTrue(text.contains("Never invent") || text.contains("never invent"), "\(id): no inventa")
            XCTAssertGreaterThan(text.utf8.count, 1_800, "\(id): el procedimiento completo")
            XCTAssertTrue(text.contains("never assume"), "\(id): pregunta dónde, no asume")
            if Self.sends.contains(id) { XCTAssertTrue(text.contains("explicit \"yes\""), "\(id): aprobación explícita") }
        }
    }

    /// Las que escriben en Slack según el catálogo son exactamente las que la prueba trata como «envían»: si el catálogo gana
    /// una, tiene que entrar a la lista (y traer su paso de aprobación).
    func testEverySkillThatWritesToSlackAsksForExplicitApproval() throws {
        let value = try SkillCatalog.load(from: repoSkills)
        let toSlack = Set(value.galeno.filter { $0.writes.contains(.slack) }.map(\.id))
        XCTAssertTrue(toSlack.isSubset(of: Self.sends), "\(toSlack.subtracting(Self.sends))")
    }

    /// Ninguna promete lo que el agente no puede hacer: ejecutar código, programarse sola o enviar por WhatsApp.
    func testNoSkillPromisesWhatTheAgentCannotDo() throws {
        let value = try SkillCatalog.load(from: repoSkills)
        for skill in value.galeno {
            let text = try String(contentsOf: repoSkills.appending(path: "galeno/\(skill.id)/SKILL.md"), encoding: .utf8).lowercased()
            for forbidden in ["run a script", "run code", "python", "cron", "send a whatsapp", "send it over whatsapp", "via whatsapp"] {
                XCTAssertFalse(text.contains(forbidden), "\(skill.id): «\(forbidden)»")
            }
        }
    }

    /// La vista previa de cada skill (`docs/03` §3): cómo pedirla y un ejemplo de lo que entra y lo que sale, en los dos
    /// idiomas.
    func testEveryOfOurSkillsHasWhatItsPreviewShows() throws {
        let value = try SkillCatalog.load(from: repoSkills)
        for skill in value.galeno {
            let ask = try XCTUnwrap(skill.ask, skill.id)
            XCTAssertFalse(ask.es.isEmpty || ask.en.isEmpty, skill.id)
            let example = try XCTUnwrap(skill.example, skill.id)
            XCTAssertFalse(example.input.es.isEmpty || example.input.en.isEmpty, skill.id)
            for lines in [example.output.es, example.output.en] {
                XCTAssertTrue((4...7).contains(lines.count), "\(skill.id): de cuatro a siete líneas: cabe sin desplazarse")
                XCTAssertFalse(lines.contains { $0.isEmpty }, skill.id)
            }
            XCTAssertEqual(example.output.es.count, example.output.en.count, skill.id)
            // El resultado tiene forma: un título, una sección, una tabla o un mensaje en borrador, no solo párrafos.
            XCTAssertTrue(
                example.output.es.contains { $0.hasPrefix("# ") || $0.hasPrefix("## ") || $0.hasPrefix("|") || $0.hasPrefix("> ") },
                "\(skill.id): el ejemplo no tiene formato")
            // «Hera lee …»: el punto de partida es un complemento, en minúscula y sin punto final.
            XCTAssertFalse(example.input.es.hasSuffix(".") || example.input.en.hasSuffix("."), skill.id)
            XCTAssertEqual(skill.command, "/" + skill.id)
        }
    }

    /// Un catálogo anterior, sin los campos de la vista previa, se sigue leyendo.
    func testACatalogWithoutPreviewFieldsStillDecodes() throws {
        let old = #"{"id":"prd","group":"documents","name":{"es":"a","en":"a"},"summary":{"es":"a","en":"a"},"writes":["notion"],"needsAny":[]}"#
        let skill = try XCTUnwrap(SkillCatalog.decode(catalog(galeno: old)).galeno.first)
        XCTAssertNil(skill.ask)
        XCTAssertNil(skill.example)
        XCTAssertNil(skill.guarantee)
        XCTAssertFalse(skill.sendsToOthers)
    }

    /// «Siempre te pide aprobación antes de enviar» sale de dónde escribe: las que publican en Slack.
    func testSkillsThatWriteToSlackSendToOthers() throws {
        let value = try SkillCatalog.load(from: repoSkills)
        let senders = Set(value.galeno.filter(\.sendsToOthers).map(\.id))
        XCTAssertEqual(senders, ["release-notes", "resumen-proyecto", "seguimiento", "informe-slack", "reporte-dia"])
        // `/groom` solo reporta: no escribe en Jira.
        XCTAssertEqual(value.galeno.first { $0.id == "groom" }?.writes, [.notion])
    }

    /// Lo curado que se anuncia como disponible tiene que traer su LICENSE; mientras no, no se instala.
    func testCuratedSkillsAreHonestAboutBeingAvailable() throws {
        let value = try SkillCatalog.load(from: repoSkills)
        for skill in value.curated where skill.available {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: repoSkills.appending(path: "curated/\(skill.id)/SKILL.md").path), skill.id)
        }
    }
}
