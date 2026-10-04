import AppKit
import SwiftUI

/// Los tokens de `docs/04-design-system.md` §10, con su versión de modo oscuro
/// ("el libro de noche": negro cálido de Claude Code desktop, `#141413`, sin tinte azul ni verde). Cada color cambia solo
/// con la apariencia del sistema.
extension Color {
    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        func ns(_ hex: UInt32) -> NSColor {
            NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1)
        }
        return Color(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? ns(dark) : ns(light)
            })
    }

    // Pergamino (fondos)
    static let parchment50 = dynamic(light: 0xF3EEE2, dark: 0x141413)
    static let parchment100 = dynamic(light: 0xEEE7D8, dark: 0x1D1D1B)
    static let parchment200 = dynamic(light: 0xE7E0D1, dark: 0x252523)
    static let parchment300 = dynamic(light: 0xD8D1C1, dark: 0x302F2C)
    static let parchment400 = dynamic(light: 0xD0CBBC, dark: 0x42413D)

    // Tinta (texto y trazo)
    static let ink900 = dynamic(light: 0x2E2D2A, dark: 0xEEE7D8)
    static let ink700 = dynamic(light: 0x63655E, dark: 0xB5B0A5)
    static let ink500 = dynamic(light: 0x8C877C, dark: 0x8C877C)
    static let ink300 = dynamic(light: 0xB5B0A5, dark: 0x5E5C56)
    /// Texto sobre un fondo `ink900` (el botón primario): el papel en claro, el fondo en oscuro.
    static let onInk = dynamic(light: 0xF3EEE2, dark: 0x141413)

    // Acento (uno solo) y estados
    static let seal700 = dynamic(light: 0x8B3A3A, dark: 0xB85C5C)
    static let seal100 = dynamic(light: 0xF0E3E0, dark: 0x2B1F1E)
    static let moss700 = dynamic(light: 0x4F6F5B, dark: 0x7FA38C)
    static let moss100 = dynamic(light: 0xE6EEE8, dark: 0x1F2923)
    /// Fondo del botón primario mientras se pulsa: un punto más hondo que la tinta.
    static let inkPressed = dynamic(light: 0x1C1B19, dark: 0xD9D2C2)
    static let ochre700 = dynamic(light: 0x9A7B2F, dark: 0xC9A552)
}

/// Los nombres que ya usan las pantallas, ahora sobre la escala de B1 (`Typo`): EB Garamond para
/// el texto y Cormorant Garamond para los títulos.
extension Font {
    static var galenoTitle: Font { Typo.display(26) }
    static var galenoBody: Font { Typo.body }
    static var galenoBodyMedium: Font { Typo.text(16, .medium) }
    static var galenoBodyStrong: Font { Typo.text(16, .semibold) }
    static var galenoCaption: Font { Typo.note }
}

/// La escala de espacio de `docs/04` §5.
enum Space {
    static let s4: CGFloat = 4
    static let s8: CGFloat = 8
    static let s12: CGFloat = 12
    static let s16: CGFloat = 16
    static let s24: CGFloat = 24
    static let s32: CGFloat = 32
    static let s48: CGFloat = 48
}
