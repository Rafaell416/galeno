import GalenoCore
import XCTest

@testable import Galeno

final class ContextImporterTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "galeno-context-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func write(_ name: String, _ contents: String) throws -> URL {
        let url = directory.appending(path: name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testReadsMarkdownAndPlainText() throws {
        let md = try ContextImporter.load(try write("resumen.md", "# Proyecto\nLanzamos en noviembre."))
        XCTAssertEqual(md.title, "resumen.md")
        XCTAssertTrue(md.text.contains("Lanzamos en noviembre."))
        XCTAssertEqual(try ContextImporter.load(try write("nota.txt", "hola")).text, "hola")
    }

    func testRefusesWhatItCannotReadAsText() throws {
        XCTAssertThrowsError(try ContextImporter.load(try write("app.sh", "rm -rf /"))) {
            XCTAssertEqual($0 as? ContextImporter.Failure, .unsupported)
        }
        XCTAssertThrowsError(try ContextImporter.load(try write("hoja.xlsx", "x"))) {
            XCTAssertEqual($0 as? ContextImporter.Failure, .unsupported)
        }
    }

    func testRefusesAFileThatIsTooLarge() throws {
        let big = String(repeating: "a", count: ContextImporter.maxFileBytes + 1)
        XCTAssertThrowsError(try ContextImporter.load(try write("enorme.txt", big))) {
            XCTAssertEqual($0 as? ContextImporter.Failure, .tooLarge)
        }
    }
}
