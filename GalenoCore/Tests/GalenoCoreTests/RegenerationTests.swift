import Foundation
import XCTest

@testable import GalenoCore

/// Regenerar sobre una carpeta que ya tiene config deja exactamente lo que
/// dice el `AgentConfig`, sin tocar `memoria/`, y un error no la deja a medias.
final class RegenerationTests: GeneratorTestCase {
    private let hookPath = ".claude/hooks/require-external-approval.sh"

    /// La config de partida: tres skills y Slack conectado (así hay hook).
    private var configA: AgentConfig { GeneratorFixtures.spanishThreeTools }

    /// La misma, pero con una sola skill y Slack saltado: ya no hay a qué
    /// aplicarle el hook.
    private var configB: AgentConfig {
        var config = GeneratorFixtures.spanishThreeTools
        config.skills = [SelectedSkill(id: "prd", source: .galeno)]
        for index in config.connections.indices where config.connections[index].tool == .slack {
            config.connections[index].status = .skipped
        }
        return config
    }

    /// Cada archivo de una carpeta con su contenido, y cada carpeta (con una
    /// barra al final): una carpeta vacía de más también es una diferencia.
    private func tree(of folder: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        let base = folder.standardizedFileURL.path
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(
                at: folder, includingPropertiesForKeys: [.isDirectoryKey]))
        for case let url as URL in enumerator {
            let relative = String(url.standardizedFileURL.path.dropFirst(base.count + 1))
            if relative.hasSuffix(".DS_Store") { continue }
            if try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
                result[relative + "/"] = Data()
            } else {
                result[relative] = try Data(contentsOf: url)
            }
        }
        return result
    }

    // MARK: - Lo que queda

    /// La propiedad central: regenerar A → B deja lo mismo, archivo por
    /// archivo, que generar B en una carpeta nueva.
    func testRegeneratingAToBLeavesTheSameTreeAsGeneratingBFresh() throws {
        try generate(configA)
        try generate(configB)

        let fresh = destination.appending(path: "nueva", directoryHint: .isDirectory)
        try ConfigGenerator().generate(configB, into: fresh, options: SnapshotSupport.options)

        let regenerated = try tree(of: destination).filter {
            $0.key != "nueva/" && !$0.key.hasPrefix("nueva/")
        }
        let expected = try tree(of: fresh)
        XCTAssertEqual(Set(regenerated.keys), Set(expected.keys))
        for (path, data) in expected {
            XCTAssertEqual(regenerated[path], data, "\(path) no quedó igual que en una carpeta nueva")
        }
    }

    func testUnselectedSkillsAreRemovedAndSelectedOnesAreKept() throws {
        try generate(configA)
        XCTAssertTrue(exists(".claude/skills/acta/SKILL.md"))

        let result = try generate(configB)

        XCTAssertFalse(exists(".claude/skills/acta"))
        XCTAssertFalse(exists(".claude/skills/informe-slack"))
        XCTAssertTrue(exists(".claude/skills/prd/SKILL.md"))
        XCTAssertTrue(exists(".claude/skills/prd/template.md"))
        XCTAssertTrue(result.removedFiles.contains(".claude/skills/acta/SKILL.md"))
        XCTAssertTrue(result.removedFiles.contains(".claude/skills/informe-slack/SKILL.md"))
        XCTAssertFalse(result.removedFiles.contains { $0.hasPrefix(".claude/skills/prd/") })
    }

    /// `.claude/` es de Galeno: una skill que alguien puso a mano también se
    /// quita, y el resultado lo dice para que la app pueda avisar.
    func testASkillPutThereByHandIsRemovedAndReported() throws {
        try generate(configA)
        let mine = destination.appending(path: ".claude/skills/mia", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: mine, withIntermediateDirectories: true)
        try Data("mi skill".utf8).write(to: mine.appending(path: "SKILL.md"))

        let result = try generate(configA)

        XCTAssertFalse(exists(".claude/skills/mia"))
        XCTAssertEqual(result.removedFiles, [".claude/skills/mia/SKILL.md"])
    }

    /// Solo se quitan carpetas: un archivo suelto en `.claude/skills/` se queda.
    func testALooseFileInTheSkillsFolderIsLeftAlone() throws {
        try generate(configA)
        try Data("notas".utf8).write(to: destination.appending(path: ".claude/skills/NOTAS.txt"))

        try generate(configB)

        XCTAssertEqual(try contents(of: ".claude/skills/NOTAS.txt"), "notas")
    }

    func testTheApprovalHookIsRemovedWhenNothingCanLeaveAndComesBack() throws {
        try generate(configA)
        XCTAssertTrue(exists(hookPath))

        // Sin Slack y sin WhatsApp. WhatsApp lleva hook aunque solo lea: tiene su lista de lecturas, y lo
        // que no esté en ella (el envío) pregunta siempre.
        var nothingToApprove = configB
        for index in nothingToApprove.connections.indices
        where nothingToApprove.connections[index].tool == .whatsapp {
            nothingToApprove.connections[index].status = .skipped
        }
        let result = try generate(nothingToApprove)
        XCTAssertFalse(exists(hookPath))
        XCTAssertTrue(result.removedFiles.contains(hookPath))
        XCTAssertFalse(try contents(of: ".claude/settings.json").contains("hooks"))

        try generate(configA)
        XCTAssertTrue(exists(hookPath))
    }

    func testTheMemorySurvivesRegeneratingAndItsFilesAreNeverReportedAsRemoved() throws {
        try generate(configA)
        try Data("lo que aprendió\n".utf8).write(to: destination.appending(path: "memoria/proyecto.md"))

        let result = try generate(configB)

        XCTAssertEqual(try contents(of: "memoria/proyecto.md"), "lo que aprendió\n")
        XCTAssertFalse(result.removedFiles.contains { $0.hasPrefix("memoria/") })
    }

    /// Quitar todas las skills tampoco deja una carpeta `skills/` vacía.
    func testRemovingEverySkillLeavesTheSameTreeAsAFreshFolder() throws {
        var none = configB
        none.skills = []
        try generate(configA)
        try generate(none)

        let fresh = destination.appending(path: "nueva", directoryHint: .isDirectory)
        try ConfigGenerator().generate(none, into: fresh, options: SnapshotSupport.options)

        let regenerated = try tree(of: destination).filter { !$0.key.hasPrefix("nueva") }
        XCTAssertEqual(Set(regenerated.keys), Set(try tree(of: fresh).keys))
    }

    func testTheFirstGenerationAndARepeatedOneRemoveNothing() throws {
        XCTAssertEqual(try generate(configA).removedFiles, [])
        XCTAssertEqual(try generate(configA).removedFiles, [])
    }

    // MARK: - Un error no deja la carpeta a medias

    private func assertAFailedRegenerationChangesNothing(
        _ broken: AgentConfig, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        try generate(configA)
        // Una nota del agente y un archivo ajeno: tampoco se tocan.
        try Data("nota\n".utf8).write(to: destination.appending(path: "memoria/nota.md"))
        let before = try tree(of: destination)

        XCTAssertThrowsError(try generate(broken), file: file, line: line)

        XCTAssertEqual(try tree(of: destination), before, "la carpeta cambió", file: file, line: line)
    }

    func testAMissingSkillLeavesTheFolderUntouched() throws {
        var broken = configB
        broken.skills.append(SelectedSkill(id: "no-existe", source: .galeno))
        try assertAFailedRegenerationChangesNothing(broken)
    }

    func testAnUnsafeSkillIdLeavesTheFolderUntouched() throws {
        var broken = configB
        broken.skills = [SelectedSkill(id: "../afuera", source: .galeno)]
        try assertAFailedRegenerationChangesNothing(broken)
    }

    /// Antes, `.mcp.json` fallaba después de que `AGENTS.md` y `settings.json`
    /// ya se habían reescrito.
    func testAMissingOAuthClientLeavesTheFolderUntouched() throws {
        var broken = configA
        broken.agentName = "Otro nombre"
        for index in broken.connections.indices where broken.connections[index].tool == .slack {
            broken.connections[index].oauthClientID = nil
        }
        try assertAFailedRegenerationChangesNothing(broken)
    }

    func testAFailedFirstGenerationDoesNotEvenCreateTheFolder() throws {
        var broken = configA
        broken.skills.append(SelectedSkill(id: "no-existe", source: .galeno))
        let target = destination.appending(path: "no-debe-existir", directoryHint: .isDirectory)

        XCTAssertThrowsError(
            try ConfigGenerator().generate(broken, into: target, options: SnapshotSupport.options))

        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
    }
}
