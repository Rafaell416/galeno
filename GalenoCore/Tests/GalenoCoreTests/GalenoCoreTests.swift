import XCTest

@testable import GalenoCore

/// Pruebas del motor. Vacías por ahora: el motor se implementa en la Fase 2.
final class GalenoCoreTests: XCTestCase {
    func testVersion() {
        XCTAssertEqual(GalenoCore.version, "0.0.1")
    }
}
