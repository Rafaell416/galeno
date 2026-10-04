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

    /// Lo que la skill dice de sí misma tiene que cuadrar con su carpeta, y llevar la instrucción
    /// de idioma que exige `AGENTS.md`.
    func testEveryOfOurSkillsHasAMatchingNameAndTheLanguageInstruction() throws {
        let value = try SkillCatalog.load(from: repoSkills)
        for skill in value.galeno {
            let text = try String(contentsOf: repoSkills.appending(path: "galeno/\(skill.id)/SKILL.md"), encoding: .utf8)
            XCTAssertTrue(text.hasPrefix("---\nname: \(skill.id)\n"), skill.id)
            XCTAssertTrue(text.contains("Reply in the user's language"), skill.id)
            XCTAssertTrue(text.contains("description: \""), skill.id)
        }
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
