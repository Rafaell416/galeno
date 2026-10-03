import AppKit
import SwiftUI

/// Los tokens de `docs/04-design-system.md` §10, con su versión de modo oscuro
/// ("el libro de noche": gris-verdoso, no negro puro). Cada color cambia solo
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
    static let parchment50 = dynamic(light: 0xF3EEE2, dark: 0x262E30)
    static let parchment100 = dynamic(light: 0xEEE7D8, dark: 0x2D3537)
    static let parchment300 = dynamic(light: 0xD8D1C1, dark: 0x3C4648)

    // Tinta (texto y trazo)
    static let ink900 = dynamic(light: 0x2E2D2A, dark: 0xEEE7D8)
    static let ink700 = dynamic(light: 0x63655E, dark: 0xB5B0A5)
    static let ink500 = dynamic(light: 0x8C877C, dark: 0x8C877C)

    // Acento (uno solo) y estados
    static let seal700 = dynamic(light: 0x8B3A3A, dark: 0xB85C5C)
    static let moss700 = dynamic(light: 0x4F6F5B, dark: 0x7FA38C)
}

/// New York, el serif del sistema, para todo el texto. Sin fuentes embebidas.
extension Font {
    static let galenoTitle = Font.system(.title, design: .serif).weight(.semibold)
    static let galenoBody = Font.system(.body, design: .serif)
    static let galenoCaption = Font.system(.caption, design: .serif)
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
