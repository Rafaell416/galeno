import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// El ex libris del agente (B1 · paso 3): un sello redondo de doble anillo con su nombre, su rol y
/// la fecha. Es tipográfico —sin lacre dibujado ni textura— y sirve de identidad del agente: se ve
/// en el paso 3 y se exporta como icono de la app de Slack.
///
/// Mientras no hay nombre se ve tenue. `fixedLight` lo dibuja siempre en papel claro, para exportarlo.
struct SealView: View {
    let name: String
    var fixedLight = false
    @Environment(\.locale) private var locale

    private var paper: Color { Color(red: 0xF3 / 255, green: 0xEE / 255, blue: 0xE2 / 255) }
    private func ink(_ dynamic: Color, light: UInt32) -> Color {
        fixedLight
            ? Color(red: Double((light >> 16) & 0xFF) / 255, green: Double((light >> 8) & 0xFF) / 255, blue: Double(light & 0xFF) / 255)
            : dynamic
    }

    private var date: String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("MMMyyyy")
        return formatter.string(from: Date())
    }

    var body: some View {
        let ink900 = ink(.ink900, light: 0x2E2D2A)
        let ink700 = ink(.ink700, light: 0x63655E)
        let ink500 = ink(.ink500, light: 0x8C877C)
        let seal = ink(.seal700, light: 0x8B3A3A)
        VStack(spacing: 0) {
            SmallCapsText(string: Localized.string("agent.seal.exlibris", locale: locale), size: 10, tracking: 0.14)
                .foregroundStyle(ink500)
            Text(verbatim: name.isEmpty ? "·" : name)
                .font(Typo.display(20))
                .kerning(0.8)
                .foregroundStyle(ink900)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 118)
                .padding(.vertical, 4)
                // Cada carácter tecleado aparece con un fade corto (120 ms).
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.12), value: name)
            Text(verbatim: "· · ·")
                .font(Typo.text(10))
                .kerning(4)
                .foregroundStyle(seal)
            Text("agent.role.productManager")
                .font(Typo.text(10))
                .foregroundStyle(ink700)
                .lineLimit(1)
                .padding(.top, 3)
            Text(verbatim: date)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(ink500)
                .padding(.top, 1)
        }
        .frame(width: 140, height: 140)
        .overlay(Circle().strokeBorder(ink900, lineWidth: 1))
        .padding(4)
        .overlay(Circle().strokeBorder(ink500, lineWidth: 1))
        .opacity(name.isEmpty && !fixedLight ? 0.4 : 1)
        .animation(.easeOut(duration: 0.2), value: name.isEmpty)
        .accessibilityHidden(true)
    }
}

/// El sello como imagen para el icono de la app de Slack: un cuadrado de 1024 px (Slack pide de 512
/// a 2000), sobre papel claro, con el sello centrado.
@MainActor
enum SealIcon {
    static let pixels: CGFloat = 1024

    static func png(for name: String, locale: Locale) -> Data? {
        let side: CGFloat = 200
        let view = ZStack {
            Color(red: 0xF3 / 255, green: 0xEE / 255, blue: 0xE2 / 255)
            SealView(name: name, fixedLight: true).scaleEffect(1.15)
        }
        .frame(width: side, height: side)
        .environment(\.locale, locale)
        let renderer = ImageRenderer(content: view)
        renderer.scale = pixels / side
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff)
        else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// Pregunta dónde guardarlo (con el nombre ya puesto) y lo escribe. Devuelve si se guardó.
    @discardableResult
    static func saveWithPanel(for name: String, locale: Locale) -> Bool {
        guard let data = png(for: name, locale: locale) else { return false }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(name.isEmpty ? "Galeno" : name)-ex-libris.png"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}
