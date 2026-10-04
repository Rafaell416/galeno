import AppKit
import SwiftUI
import XCTest

@testable import Galeno

/// Ajustes (apariencia, menos movimiento, sonido) y el sello que se exporta como icono de Slack.
@MainActor
final class PreferencesAndSealTests: XCTestCase {
    func testTheAppearanceChoicesMapToTheSystemAppearances() {
        XCTAssertNil(AppearanceChoice.system.nsAppearance, "«Sistema» deja que mande el sistema")
        XCTAssertEqual(AppearanceChoice.light.nsAppearance?.name, .aqua)
        XCTAssertEqual(AppearanceChoice.dark.nsAppearance?.name, .darkAqua)
    }

    func testSoundsAreOnByDefaultAndOneSwitchSilencesThem() {
        let saved = UserDefaults.standard.object(forKey: Prefs.sounds)
        defer { UserDefaults.standard.set(saved, forKey: Prefs.sounds) }

        UserDefaults.standard.removeObject(forKey: Prefs.sounds)
        XCTAssertTrue(Sounds.isEnabled, "encendidos de fábrica")
        UserDefaults.standard.set(false, forKey: Prefs.sounds)
        XCTAssertFalse(Sounds.isEnabled, "el interruptor de Ajustes los calla")
    }

    func testThereAreExactlyThreeSoundsAndTheyAreShortAndQuiet() throws {
        XCTAssertEqual(Sounds.Cue.allCases.map(\.rawValue).sorted(), ["conexion", "fallo", "sello"], "no se añaden otros")
        for cue in Sounds.Cue.allCases {
            let url = try XCTUnwrap(Sounds.url(for: cue), "\(cue) no está en el bundle")
            let sound = try XCTUnwrap(NSSound(contentsOf: url, byReference: true))
            XCTAssertLessThanOrEqual(sound.duration, 0.45, "\(cue): ≤ 450 ms")
        }
        XCTAssertLessThanOrEqual(Sounds.volume, 0.3, "a volumen bajo")
    }

    func testEveryGlyphDrawsSomethingInsideItsFrame() {
        let frame = CGRect(x: 0, y: 0, width: 24, height: 24)
        for glyph in Glyph.allCases {
            let bounds = GlyphShape(glyph: glyph).path(in: frame).boundingRect
            XCTAssertFalse(bounds.isEmpty, "\(glyph) no dibuja nada")
            XCTAssertTrue(frame.insetBy(dx: 1, dy: 1).contains(bounds), "\(glyph) se sale de su cuadrícula: \(bounds)")
        }
    }

    func testOnlyStepsWithoutTheirOwnImageCarryASectionGlyph() {
        XCTAssertEqual(WizardStep.tools.glyph, .mortero)
        XCTAssertEqual(WizardStep.skills.glyph, .pluma)
        XCTAssertEqual(WizardStep.rules.glyph, .baston)
        XCTAssertEqual(WizardStep.review.glyph, .lente)
        for step in [WizardStep.welcome, .detection, .agent, .connect, .generating, .done] {
            XCTAssertNil(step.glyph, "\(step)")
        }
    }

    func testTheSealExportsAsASquarePNGInSlacksRange() throws {
        let data = try XCTUnwrap(SealIcon.png(for: "Hera", locale: Locale(identifier: "es")))
        let rep = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(rep.pixelsWide, rep.pixelsHigh, "cuadrado")
        XCTAssertTrue((512...2000).contains(rep.pixelsWide), "Slack pide de 512 a 2000 px")
    }

    func testTheHelpHasThreeQuestionsForEveryStepExceptWriting() throws {
        for language in ["es", "en"] {
            let bundle = try XCTUnwrap(
                Bundle(path: try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))))
            for step in WizardStep.allCases where step != .generating {
                for index in 1...3 {
                    for part in ["q", "a"] {
                        let key = "help.\(step.slug).\(index).\(part)"
                        let text = bundle.localizedString(forKey: key, value: "⟂", table: nil)
                        XCTAssertNotEqual(text, "⟂", "\(key) no está en \(language)")
                    }
                }
            }
        }
    }
}
