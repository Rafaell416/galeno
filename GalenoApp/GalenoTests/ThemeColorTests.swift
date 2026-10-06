import AppKit
import SwiftUI
import XCTest

@testable import Galeno

/// Los colores del tema cambian con la apariencia, y SwiftUI los resuelve **fuera del hilo principal** (el renderizado
/// asíncrono de macOS 15 corre en `com.apple.SwiftUI.DisplayLink`). Si el cierre que los calcula hereda el aislamiento
/// del actor principal, Swift lo comprueba al ejecutarlo y la app se cae al pasar a la segunda pantalla (demo con
/// Aquiles, 5 oct 2026: `EXC_BREAKPOINT` en `Color.dynamic(light:dark:)`).
final class ThemeColorTests: XCTestCase {
    func testTheThemeColorsResolveOffTheMainThread() {
        let colors: [Color] = [
            .parchment50, .parchment100, .parchment200, .parchment300, .parchment400,
            .ink900, .ink700, .ink500, .ink300, .onInk, .seal700, .seal100, .moss700, .ochre700,
        ]
        // La conversión a NSColor se hace en el hilo principal, como SwiftUI; la resolución, fuera.
        let platformColors = colors.map { NSColor($0) }
        let finished = expectation(description: "resueltos fuera del hilo principal")
        var resolvedOffMain = 0
        DispatchQueue.global(qos: .userInteractive).async {
            XCTAssertFalse(Thread.isMainThread)
            for appearance in [NSAppearance(named: .aqua)!, NSAppearance(named: .darkAqua)!] {
                appearance.performAsCurrentDrawingAppearance {
                    for color in platformColors where color.usingColorSpace(.sRGB) != nil { resolvedOffMain += 1 }
                }
            }
            finished.fulfill()
        }
        wait(for: [finished], timeout: 10)
        XCTAssertEqual(resolvedOffMain, colors.count * 2)
    }

    func testLightAndDarkGiveDifferentColors() {
        let ink = NSColor(Color.ink900)
        func hex(_ appearance: NSAppearance.Name) -> UInt32 {
            var value: UInt32 = 0
            NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
                let c = ink.usingColorSpace(.sRGB)!
                value = (UInt32((c.redComponent * 255).rounded()) << 16) | (UInt32((c.greenComponent * 255).rounded()) << 8)
                    | UInt32((c.blueComponent * 255).rounded())
            }
            return value
        }
        XCTAssertEqual(hex(.aqua), 0x2E2D2A)
        XCTAssertEqual(hex(.darkAqua), 0xEEE7D8)
    }
}
