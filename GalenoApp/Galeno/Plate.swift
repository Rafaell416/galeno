import AppKit
import SwiftUI

/// Una lámina de grabado de línea (`docs/05` §A, «Ilustraciones»): una imagen en un solo tono de tinta,
/// siempre decorativa. Va como imagen plantilla del catálogo de assets y toma el color de la tinta.
///
/// Mientras no haya arte, en Debug se ve un recuadro rayado con su leyenda, para que se note qué
/// falta; en Release no se dibuja nada y la pantalla se sostiene sola con el texto.
struct Plate: View {
    /// El nombre en `Assets.xcassets` (por ejemplo `plate-columnata`).
    let asset: String
    /// Qué debe mostrar el grabado: la leyenda del marcador.
    let caption: String
    var size = CGSize(width: 220, height: 120)
    /// Un grabado con figuras y medios tonos. En oscuro no se invierte —un rostro en negativo no se lee—:
    /// se muestra como una estampa sobre su papel, igual que el retrato. Los de pura línea (la columnata)
    /// sí se invierten, como tiza sobre pizarra.
    var printOnPaper = false

    @Environment(\.colorScheme) private var colorScheme

    /// El papel y la tinta de la estampa no cambian con el modo oscuro.
    private static let paper = Color(red: 0xF3 / 255, green: 0xEE / 255, blue: 0xE2 / 255)
    private static let printInk = Color(red: 0x63 / 255, green: 0x65 / 255, blue: 0x5E / 255)

    /// La misma viñeta ovalada que traen las láminas en su canal alfa: llena hasta el 60 % del radio y
    /// disuelta hasta el borde.
    private static let vignette = EllipticalGradient(
        stops: [
            .init(color: .black, location: 0), .init(color: .black, location: 0.6),
            .init(color: .black.opacity(0.84), location: 0.7), .init(color: .black.opacity(0.5), location: 0.8),
            .init(color: .black.opacity(0.16), location: 0.9), .init(color: .clear, location: 1),
        ],
        center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)

    var body: some View {
        if NSImage(named: asset) != nil {
            let onPaper = printOnPaper && colorScheme == .dark
            Image(asset)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(onPaper ? Self.printInk : Color.ink700)
                .frame(width: size.width, height: size.height)
                .background { if onPaper { Self.paper.mask(Self.vignette) } }
                .accessibilityHidden(true)
        } else {
            #if DEBUG
            placeholder
            #endif
        }
    }

    #if DEBUG
    private var placeholder: some View {
        ZStack(alignment: .bottom) {
            Canvas { context, canvas in
                var x: CGFloat = -canvas.height
                while x < canvas.width {
                    var line = Path()
                    line.move(to: CGPoint(x: x, y: canvas.height))
                    line.addLine(to: CGPoint(x: x + canvas.height, y: 0))
                    context.stroke(line, with: .color(Color.parchment200), lineWidth: 1)
                    x += 10
                }
            }
            Text(verbatim: "LÁMINA · " + caption)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.ink500)
                .multilineTextAlignment(.center)
                .padding(6)
        }
        .frame(width: size.width, height: size.height)
        .overlay(Rectangle().strokeBorder(Color.parchment400, lineWidth: 1))
        .accessibilityHidden(true)
    }
    #endif
}

/// El retrato de Galeno: la litografía de Vigneron (dominio público), en grises, recortada en círculo
/// sobre un disco de pergamino —también en oscuro: el grabado siempre va sobre su papel— con un
/// anillo fino de tinta. El grande de la bienvenida lleva además un segundo anillo, separado 3 pt.
struct PortraitMark: View {
    /// El retrato en `Assets.xcassets`: el de Galeno, o el del personaje de otro rol (`Persona.portrait`).
    var asset = "retrato-galeno"
    var size: CGFloat = 56
    var doubleRing = false
    /// El anillo exterior se traza en sentido horario, desde arriba (700 ms tras 200 ms), en vez de aparecer.
    var tracesRing = false

    /// El papel y la tinta del grabado no cambian con el modo oscuro.
    private static let paper = Color(red: 0xF3 / 255, green: 0xEE / 255, blue: 0xE2 / 255)
    private static let ink = Color(red: 0x2E / 255, green: 0x2D / 255, blue: 0x2A / 255)
    private static let outer = Color(red: 0x8C / 255, green: 0x87 / 255, blue: 0x7C / 255)

    static var isAvailable: Bool { NSImage(named: "retrato-galeno") != nil }

    var body: some View {
        if NSImage(named: asset) != nil {
            Image(asset)
                .resizable()
                .scaledToFill()
                .saturation(0)
                .contrast(1.05)
                .blendMode(.multiply)
                .frame(width: size, height: size)
                .background(Self.paper)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Self.ink, lineWidth: 1))
                .padding(doubleRing ? 4 : 0)
                .background { if doubleRing { Circle().fill(Self.paper) } }
                .overlay {
                    if doubleRing {
                        if tracesRing {
                            TracedShape(
                                shape: Circle().inset(by: 0.5).rotation(.degrees(-90)), lineWidth: 1, color: Self.outer,
                                duration: 0.7, delay: 0.2)
                        } else {
                            Circle().strokeBorder(Self.outer, lineWidth: 1)
                        }
                    }
                }
                .compositingGroup()
                .accessibilityHidden(true)
        }
    }
}
