import AppKit
import XCTest

@testable import Galeno

/// El grano del rediseño: encendido de fábrica, apagable por bandera y con un mosaico estable.
@MainActor
final class GrainTests: XCTestCase {
    private let suite = "GrainTests"

    func testItIsOnByDefault() {
        UserDefaults.standard.removeObject(forKey: Grain.defaultsKey)
        XCTAssertTrue(Grain.isEnabled)
    }

    func testTheFlagTurnsItOff() {
        UserDefaults.standard.set(false, forKey: Grain.defaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: Grain.defaultsKey) }
        XCTAssertFalse(Grain.isEnabled)
    }

    func testTheTilesAre200PixelsAndNotBlank() throws {
        for tile in [Grain.lightTile, Grain.darkTile] {
            let rep = try XCTUnwrap(tile.representations.first as? NSBitmapImageRep)
            XCTAssertEqual(rep.pixelsWide, 200)
            XCTAssertEqual(rep.pixelsHigh, 200)
            let data = try XCTUnwrap(rep.bitmapData)
            let alphaSum = stride(from: 3, to: 200 * 200 * 4, by: 4).reduce(0) { $0 + Int(data[$1]) }
            XCTAssertGreaterThan(alphaSum, 0, "el mosaico no debe estar vacío")
        }
    }
}
