import Foundation
import XCTest

@testable import GalenoCore

/// Arnés de snapshots.
///
/// Las carpetas viven fuera del target de pruebas, así que se localizan con
/// `#filePath` en vez de empaquetarlas como recursos de SwiftPM.
enum SnapshotSupport {
    /// `GalenoCore/Tests/`
    static let testsDirectory = URL(filePath: #filePath)
        .deletingLastPathComponent()  // GalenoCoreTests/
        .deletingLastPathComponent()  // Tests/

    static let snapshotsDirectory = testsDirectory.appending(
        path: "Snapshots", directoryHint: .isDirectory)

    static let skillsFixtureDirectory = testsDirectory.appending(
        path: "Fixtures/skills", directoryHint: .isDirectory)

    /// Con `GALENO_RECORD_SNAPSHOTS=1` se reescriben los esperados en vez de
    /// compararlos. La prueba falla igual, para que nadie deje el modo puesto.
    static var isRecording: Bool {
        ProcessInfo.processInfo.environment["GALENO_RECORD_SNAPSHOTS"] == "1"
    }

    /// La ruta del binario del bridge que se usa en las pruebas. Fija, para que
    /// el snapshot no dependa de la máquina.
    static let whatsAppBridgePath = "/Applications/Galeno.app/Contents/Resources/galeno-whatsapp"

    static var options: ConfigGenerator.Options {
        ConfigGenerator.Options(
            skillsDirectory: skillsFixtureDirectory,
            whatsAppBridgePath: whatsAppBridgePath
        )
    }

    /// Las rutas relativas de todos los archivos de una carpeta, ordenadas.
    static func filePaths(in directory: URL) throws -> [String] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.path) else { return [] }

        let base = directory.standardizedFileURL.path
        var paths: [String] = []

        guard
            let enumerator = fileManager.enumerator(
                at: directory, includingPropertiesForKeys: [.isRegularFileKey])
        else { return [] }

        for case let url as URL in enumerator {
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
            else { continue }
            // .DS_Store y compañía no son parte del snapshot.
            if url.lastPathComponent.hasPrefix(".DS_Store") { continue }
            let path = url.standardizedFileURL.path
            paths.append(String(path.dropFirst(base.count + 1)))
        }

        return paths.sorted()
    }

    /// Compara el árbol generado contra el esperado, o lo graba.
    static func assertMatchesSnapshot(
        generated: URL,
        named name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let expected = snapshotsDirectory.appending(path: name, directoryHint: .isDirectory)
        let fileManager = FileManager.default

        if isRecording {
            if fileManager.fileExists(atPath: expected.path) {
                try fileManager.removeItem(at: expected)
            }
            try fileManager.createDirectory(
                at: expected.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.copyItem(at: generated, to: expected)
            XCTFail(
                """
                Snapshot "\(name)" grabado. Quita GALENO_RECORD_SNAPSHOTS y revisa el diff \
                antes de commitear.
                """,
                file: file, line: line
            )
            return
        }

        guard fileManager.fileExists(atPath: expected.path) else {
            XCTFail(
                """
                No existe el snapshot "\(name)". Grábalo con:
                GALENO_RECORD_SNAPSHOTS=1 swift test --package-path GalenoCore
                """,
                file: file, line: line
            )
            return
        }

        // Primero la lista de archivos: así un archivo de más o de menos falla
        // con un mensaje claro, en vez de pasar inadvertido.
        let generatedPaths = try filePaths(in: generated)
        let expectedPaths = try filePaths(in: expected)
        guard generatedPaths == expectedPaths else {
            let extra = Set(generatedPaths).subtracting(expectedPaths).sorted()
            let missing = Set(expectedPaths).subtracting(generatedPaths).sorted()
            XCTFail(
                """
                La lista de archivos de "\(name)" no coincide.
                  De más:   \(extra.isEmpty ? "—" : extra.joined(separator: ", "))
                  Faltan:   \(missing.isEmpty ? "—" : missing.joined(separator: ", "))
                """,
                file: file, line: line
            )
            return
        }

        for path in expectedPaths {
            let actual = try String(
                contentsOf: generated.appending(path: path), encoding: .utf8)
            let wanted = try String(
                contentsOf: expected.appending(path: path), encoding: .utf8)
            if actual != wanted {
                XCTFail(
                    """
                    "\(name)/\(path)" cambió.

                    --- esperado ---
                    \(wanted)
                    --- generado ---
                    \(actual)
                    --- fin ---

                    Si el cambio es correcto, regrábalo:
                    GALENO_RECORD_SNAPSHOTS=1 swift test --package-path GalenoCore
                    """,
                    file: file, line: line
                )
            }
        }
    }
}

/// Un caso base que da una carpeta temporal limpia por prueba.
class GeneratorTestCase: XCTestCase {
    var destination: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        destination = FileManager.default.temporaryDirectory
            .appending(path: "galeno-tests/\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let destination, FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        destination = nil
        try super.tearDownWithError()
    }

    @discardableResult
    func generate(_ config: AgentConfig) throws -> GenerationResult {
        try ConfigGenerator().generate(
            config, into: destination, options: SnapshotSupport.options)
    }

    func contents(of relativePath: String) throws -> String {
        try String(contentsOf: destination.appending(path: relativePath), encoding: .utf8)
    }

    func exists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: destination.appending(path: relativePath).path)
    }
}
