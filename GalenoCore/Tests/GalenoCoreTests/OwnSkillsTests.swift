import XCTest

@testable import GalenoCore

/// Las skills propias del usuario (`docs/03` §6.3): cómo se nombran y qué dicen de sí mismas.
final class OwnSkillsTests: XCTestCase {
    func testAnIdentifierComesFromAFileOrFolderName() {
        XCTAssertEqual(OwnSkills.identifier(from: "Mi Skill de Ventas.md"), "mi-skill-de-ventas")
        XCTAssertEqual(OwnSkills.identifier(from: "Prospección  Semanal"), "prospeccion-semanal")
        XCTAssertEqual(OwnSkills.identifier(from: "cierre_mes (v2)"), "cierre-mes-v2")
        XCTAssertEqual(OwnSkills.identifier(from: "SKILL.md"), "skill")
        XCTAssertEqual(OwnSkills.identifier(from: "../.ssh"), "ssh", "un nombre nunca sale de la carpeta")
        XCTAssertEqual(OwnSkills.identifier(from: "¿?"), "")
        for name in ["Mi Skill de Ventas.md", "Prospección  Semanal", "cierre_mes (v2)"] {
            XCTAssertNoThrow(try OwnSkills.validate(OwnSkills.identifier(from: name)), name)
        }
    }

    func testTheFrontmatterGivesTheNameAndTheDescription() {
        let text = """
            ---
            name: cierre-semana
            description: "Cierra la semana: qué vendí, qué quedó abierto."
            ---

            # Cierre

            Primero lee el pipeline.
            """
        let skill = OwnSkills.describe(id: "cierre-semana", skillText: text)
        XCTAssertEqual(skill.name, "cierre-semana")
        XCTAssertEqual(skill.summary, "Cierra la semana: qué vendí, qué quedó abierto.")
    }

    /// Sin frontmatter (un `.md` escrito a mano) el id hace de nombre y el primer párrafo, de descripción.
    func testWithoutFrontmatterTheFirstParagraphDescribesIt() {
        let skill = OwnSkills.describe(id: "notas", skillText: "# Mis notas\n\nResume la reunión en tres líneas.\n\nLuego…")
        XCTAssertEqual(skill.name, "notas")
        XCTAssertEqual(skill.summary, "Resume la reunión en tres líneas.")
        XCTAssertEqual(OwnSkills.describe(id: "vacia", skillText: "").summary, "")
    }

    /// Lo que hay en `skills-propias/`: solo subcarpetas con `SKILL.md` y un nombre válido, por orden.
    func testListingTheAgentFolderFindsOnlyRealSkills() throws {
        let agent = FileManager.default.temporaryDirectory.appending(path: "own-skills-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: agent) }
        let root = OwnSkills.directory(in: agent)
        for id in ["zeta", "alfa"] {
            try FileManager.default.createDirectory(at: root.appending(path: id), withIntermediateDirectories: true)
            try "---\nname: \(id)\n---\n".write(to: root.appending(path: "\(id)/SKILL.md"), atomically: true, encoding: .utf8)
        }
        try FileManager.default.createDirectory(at: root.appending(path: "sin-skill"), withIntermediateDirectories: true)
        try "suelto".write(to: root.appending(path: "suelto.md"), atomically: true, encoding: .utf8)

        XCTAssertEqual(OwnSkills.list(in: agent).map(\.id), ["alfa", "zeta"])
        XCTAssertEqual(OwnSkills.list(in: FileManager.default.temporaryDirectory.appending(path: "no-existe")), [])
    }
}
