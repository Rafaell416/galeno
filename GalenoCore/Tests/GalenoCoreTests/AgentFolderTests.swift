import Foundation
import XCTest

@testable import GalenoCore

final class AgentFolderTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appending(path: "galeno-folders/\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
        try super.tearDownWithError()
    }

    // MARK: - Saneado

    func testSanitizingTable() {
        let cases: [(String, String)] = [
            ("Aurora", "Aurora"),
            ("Cliente A/B: ventas", "Cliente A B ventas"),
            (#"mi\ruta"#, "mi ruta"),
            ("  ..oculta  ", "oculta"),
            ("..", "Agente"),
            (".", "Agente"),
            ("", "Agente"),
            ("   ", "Agente"),
            ("a\nb\tc", "a b c"),
            ("\u{0}x\u{7}", "x"),
            ("Hipócrates Ñandú", "Hipócrates Ñandú"),
            ("Mi  agente   favorito", "Mi agente favorito"),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(AgentFolder.sanitized(input), expected, "\"\(input.debugDescription)\"")
        }
    }

    /// Un acento escrito como letra + marca (lo que produce a veces el
    /// teclado o un copiar-pegar) queda como un solo carácter.
    func testAccentsAreComposed() {
        XCTAssertEqual(AgentFolder.sanitized("Cafe\u{301}"), "Café")
    }

    func testLongNamesAreCutAndNeverEndInASpace() {
        let long = String(repeating: "a", count: 100)
        XCTAssertEqual(AgentFolder.sanitized(long).count, AgentFolder.maximumNameLength)

        let cutAtASpace = String(repeating: "a", count: AgentFolder.maximumNameLength - 1) + " bbbb"
        let result = AgentFolder.sanitized(cutAtASpace)
        XCTAssertFalse(result.hasSuffix(" "))
        XCTAssertLessThanOrEqual(result.count, AgentFolder.maximumNameLength)
    }

    func testASanitizedNameIsNeverAPathThatEscapes() {
        for dangerous in ["../../etc", "/etc/passwd", "~/x", "a/../b", "...."] {
            let name = AgentFolder.sanitized(dangerous)
            XCTAssertFalse(name.contains("/"), name)
            XCTAssertFalse(name.hasPrefix("."), name)
            XCTAssertFalse(name.isEmpty)
        }
    }

    // MARK: - Sin colisiones

    func testTheFolderIsUnderTheRootWithTheSanitizedName() {
        let folder = AgentFolder.uniqueFolder(for: "Cliente A/B", in: root)
        XCTAssertEqual(folder, root.appending(path: "Cliente A B", directoryHint: .isDirectory))
    }

    func testAnotherAgentsFolderIsNotReusedEvenWithDifferentCase() {
        let taken = [root.appending(path: "aurora", directoryHint: .isDirectory)]
        let folder = AgentFolder.uniqueFolder(for: "Aurora", in: root, avoiding: taken)
        XCTAssertEqual(folder.lastPathComponent, "Aurora 2")
    }

    /// El sistema de archivos de macOS no distingue la forma Unicode de un
    /// acento, así que `Café` en una forma y en la otra son la misma carpeta.
    func testComposedAndDecomposedAccentsCollide() {
        let taken = [root.appending(path: "Cafe\u{301}", directoryHint: .isDirectory)]
        let folder = AgentFolder.uniqueFolder(for: "Café", in: root, avoiding: taken)
        XCTAssertEqual(folder.lastPathComponent, "Café 2")
    }

    /// Una carpeta que ya existe en disco y no es de ningún agente tampoco se pisa.
    func testAFolderThatAlreadyExistsOnDiskIsNotReused() throws {
        try FileManager.default.createDirectory(
            at: root.appending(path: "Aurora"), withIntermediateDirectories: true)

        let folder = AgentFolder.uniqueFolder(for: "Aurora", in: root)

        XCTAssertEqual(folder.lastPathComponent, "Aurora 2")
    }

    func testNumbersKeepCountingPastEveryTakenOne() throws {
        try FileManager.default.createDirectory(
            at: root.appending(path: "Aurora"), withIntermediateDirectories: true)
        let taken = [root.appending(path: "Aurora 2", directoryHint: .isDirectory)]

        let folder = AgentFolder.uniqueFolder(for: "Aurora", in: root, avoiding: taken)

        XCTAssertEqual(folder.lastPathComponent, "Aurora 3")
    }

    func testAFolderElsewhereDoesNotCollide() {
        let elsewhere = FileManager.default.temporaryDirectory
            .appending(path: "otra-parte/Aurora", directoryHint: .isDirectory)
        let folder = AgentFolder.uniqueFolder(for: "Aurora", in: root, avoiding: [elsewhere])
        XCTAssertEqual(folder.lastPathComponent, "Aurora")
    }

    func testTheDefaultRootIsGaleno() {
        XCTAssertEqual(AgentFolder.defaultRoot.lastPathComponent, "Galeno")
        XCTAssertEqual(
            AgentFolder.defaultRoot.deletingLastPathComponent().path,
            FileManager.default.homeDirectoryForCurrentUser.path)
    }
}
