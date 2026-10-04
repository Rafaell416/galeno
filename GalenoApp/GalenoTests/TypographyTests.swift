import AppKit
import XCTest

@testable import Galeno

/// Las fuentes del rediseño: que carguen por su nombre PostScript y que pesen poco.
@MainActor
final class TypographyTests: XCTestCase {
    func testTheBundledFontsAreFound() {
        XCTAssertTrue(GalenoFonts.registerBundledFonts())
    }

    func testEveryPostScriptNameOfTheScaleLoads() {
        for name in GalenoFonts.postScriptNames {
            XCTAssertTrue(GalenoFonts.isAvailable(name), "\(name) no carga: la escala caería a New York")
        }
    }

    func testTheNamedInstancesHaveTheirOwnWeight() throws {
        func weight(_ name: String) throws -> CGFloat {
            let font = try XCTUnwrap(NSFont(name: name, size: 16), name)
            let traits = font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
            return try XCTUnwrap(traits?[.weight] as? CGFloat, name)
        }
        let regular = try weight("EBGaramond-Regular")
        let medium = try weight("EBGaramond-Medium")
        let semibold = try weight("EBGaramond-SemiBold")
        XCTAssertLessThan(regular, medium)
        XCTAssertLessThan(medium, semibold)
    }

    func testSmallCapsChangeTheGlyphs() throws {
        let base = try XCTUnwrap(NSFont(name: "EBGaramond-Medium", size: 13))
        let descriptor = base.fontDescriptor.addingAttributes([
            .featureSettings: [
                [
                    NSFontDescriptor.FeatureKey.typeIdentifier: kLowerCaseType,
                    NSFontDescriptor.FeatureKey.selectorIdentifier: kLowerCaseSmallCapsSelector,
                ]
            ]
        ])
        let smallCaps = try XCTUnwrap(NSFont(descriptor: descriptor, size: 13))
        func width(_ font: NSFont) -> CGFloat {
            ("paso" as NSString).size(withAttributes: [.font: font]).width
        }
        XCTAssertGreaterThan(width(smallCaps), width(base))
    }

    func testTheEmbeddedFontsStayLight() throws {
        // Las pruebas corren dentro de la app anfitriona: `Bundle.main` es `Galeno.app`.
        let urls =
            (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? [])
            + (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [])
        let total = urls.reduce(0) { sum, url in
            sum + ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        XCTAssertEqual(urls.count, 4)
        XCTAssertLessThan(total, 1_200_000, "el diseño estima ≈1,2 MB como tope")
    }
}
