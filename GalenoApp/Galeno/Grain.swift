import AppKit
import SwiftUI

/// El grano de papel de B1: un ruido muy tenue (5 % en claro, 7 % en oscuro) sobre toda la ventana.
/// Es lo único "de textura" que admite el diseño; se apaga con
/// `defaults write com.galeno.Galeno GalenoGrainEnabled -bool NO`.
enum Grain {
    static let defaultsKey = "GalenoGrainEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true
    }

    /// El mosaico de 200×200 px: puntos de tinta con opacidad al azar. Se genera una vez, con una
    /// semilla fija para que el grano no cambie de una vez a otra.
    static let lightTile = makeTile(white: false)
    static let darkTile = makeTile(white: true)

    private static func makeTile(white: Bool) -> NSImage {
        let side = 200
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: side * 4, bitsPerPixel: 32),
            let data = rep.bitmapData
        else { return NSImage() }
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        for i in 0..<(side * side) {
            // xorshift64: determinista y sin dependencias.
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            let alpha = UInt8(truncatingIfNeeded: state >> 24)
            let value: UInt8 = white ? 255 : 0
            data[i * 4] = value.premultiplied(by: alpha)
            data[i * 4 + 1] = value.premultiplied(by: alpha)
            data[i * 4 + 2] = value.premultiplied(by: alpha)
            data[i * 4 + 3] = alpha
        }
        let image = NSImage(size: NSSize(width: side, height: side))
        image.addRepresentation(rep)
        return image
    }
}

private extension UInt8 {
    func premultiplied(by alpha: UInt8) -> UInt8 { UInt8((UInt16(self) * UInt16(alpha)) / 255) }
}

/// El grano, listo para ponerlo encima de una vista. No intercepta clics ni lo lee VoiceOver.
struct GrainOverlay: View {
    @Environment(\.colorScheme) private var scheme
    @AppStorage(Grain.defaultsKey) private var enabled = true

    var body: some View {
        if enabled {
            Image(nsImage: scheme == .dark ? Grain.darkTile : Grain.lightTile)
                .resizable(resizingMode: .tile)
                .opacity(scheme == .dark ? 0.07 : 0.05)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
