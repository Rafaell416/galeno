import Foundation
import XCTest

@testable import GalenoCore

/// Compara el árbol completo que genera el motor contra los esperados en
/// `Tests/Snapshots/`. Atrapa cualquier cambio de contenido, y también un
/// archivo de más o de menos.
final class SnapshotTests: GeneratorTestCase {
    func testSpanishThreeTools() throws {
        try generate(GeneratorFixtures.spanishThreeTools)
        try SnapshotSupport.assertMatchesSnapshot(generated: destination, named: "pm-es-3-tools")
    }

    func testEnglishEightTools() throws {
        try generate(GeneratorFixtures.englishEightTools)
        try SnapshotSupport.assertMatchesSnapshot(generated: destination, named: "pm-en-8-tools")
    }

    /// Generar dos veces sobre la misma carpeta debe dar exactamente lo mismo.
    /// La app puede volver a correr el wizard sobre una carpeta ya configurada.
    func testGeneratingTwiceIsIdempotent() throws {
        let config = GeneratorFixtures.englishEightTools

        let first = try generate(config)
        let firstContents = try SnapshotSupport.filePaths(in: destination).map {
            try contents(of: $0)
        }

        let second = try generate(config)
        let secondContents = try SnapshotSupport.filePaths(in: destination).map {
            try contents(of: $0)
        }

        XCTAssertEqual(first, second)
        XCTAssertEqual(firstContents, secondContents)
    }
}
