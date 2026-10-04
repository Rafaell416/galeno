import SwiftUI

/// Los glifos propios de Galeno (`docs/04` §12): ocho dibujos de línea a 1,5 pt sobre una cuadrícula de
/// 24, hechos por nosotros (no son SF Symbols ni vienen de ninguna colección). Sirven de sello de
/// sección junto al título de algunos pasos; nunca van en la misma fila que un SF Symbol.
enum Glyph: String, CaseIterable {
    /// El rollo abierto: lo que el agente lee.
    case rollo
    /// El códice abierto: lo que el agente lee.
    case codice
    /// La pluma: lo que el agente escribe.
    case pluma
    /// La lente sobre un texto: revisar.
    case lente
    /// El bastón de Asclepio (una sola serpiente; el de dos es el caduceo de Hermes): las reglas, el cuidado.
    case baston
    /// El sello ex libris: el agente, con su nombre.
    case sello
    /// La columnata: el orden.
    case columnata
    /// El mortero: las herramientas.
    case mortero
}

/// El trazo de un glifo. Las coordenadas están en la cuadrícula de 24 y se escalan al marco.
struct GlyphShape: Shape {
    let glyph: Glyph

    func path(in rect: CGRect) -> Path {
        let unit = min(rect.width, rect.height) / 24
        let originX = rect.midX - 12 * unit
        let originY = rect.midY - 12 * unit
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: originX + x * unit, y: originY + y * unit) }

        var path = Path()
        func line(_ points: (CGFloat, CGFloat)...) {
            path.move(to: point(points[0].0, points[0].1))
            for next in points.dropFirst() { path.addLine(to: point(next.0, next.1)) }
        }
        func curve(to end: (CGFloat, CGFloat), _ first: (CGFloat, CGFloat), _ second: (CGFloat, CGFloat)) {
            path.addCurve(
                to: point(end.0, end.1), control1: point(first.0, first.1), control2: point(second.0, second.1))
        }
        func circle(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat) {
            path.addEllipse(
                in: CGRect(
                    x: originX + (x - radius) * unit, y: originY + (y - radius) * unit,
                    width: 2 * radius * unit, height: 2 * radius * unit))
        }
        /// Un punto: un trazo sin longitud, que la punta redonda convierte en un círculo del grosor de la línea.
        func dot(_ x: CGFloat, _ y: CGFloat) { line((x, y), (x + 0.01, y)) }
        func roundedRect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ radius: CGFloat) {
            path.addRoundedRect(
                in: CGRect(x: originX + x * unit, y: originY + y * unit, width: width * unit, height: height * unit),
                cornerSize: CGSize(width: radius * unit, height: radius * unit))
        }

        switch glyph {
        case .rollo:
            // Dos varillas y el papel tendido entre ellas, con dos renglones.
            roundedRect(3, 4, 4, 16, 2)
            roundedRect(17, 4, 4, 16, 2)
            line((7, 6.5), (17, 6.5))
            line((7, 17.5), (17, 17.5))
            line((9.75, 10.25), (14.25, 10.25))
            line((9.75, 13.75), (14.25, 13.75))

        case .codice:
            // Un libro abierto: dos páginas que caen desde el lomo.
            path.move(to: point(12, 7))
            curve(to: (3, 6), (10, 5.2), (6, 5))
            path.addLine(to: point(3, 18))
            curve(to: (12, 19.5), (6, 17.2), (10, 17.6))
            path.move(to: point(12, 7))
            curve(to: (21, 6), (14, 5.2), (18, 5))
            path.addLine(to: point(21, 18))
            curve(to: (12, 19.5), (18, 17.2), (14, 17.6))
            line((12, 7), (12, 19.5))

        case .pluma:
            // La pluma en diagonal: la barba en forma de hoja y el cañón hasta la punta.
            path.move(to: point(20, 4))
            curve(to: (9, 15), (13.5, 4), (8.5, 9.5))
            curve(to: (20, 4), (14.5, 15.5), (20, 10.5))
            line((16, 8), (4, 20))
            // Un corte en la barba, para que se lea pluma y no hoja.
            line((16.55, 12.15), (14.4, 11.3))

        case .lente:
            // Una lente sobre dos renglones.
            circle(10.5, 10.5, 6.5)
            line((15.25, 15.25), (21, 21))
            line((7.75, 9.25), (13.25, 9.25))
            line((7.75, 12.25), (11.5, 12.25))

        case .baston:
            // La vara y una sola serpiente que la rodea, con la cabeza arriba.
            line((12, 2.75), (12, 21.5))
            path.move(to: point(9.2, 6.3))
            curve(to: (15.5, 8.4), (9.2, 4.2), (15.5, 4.9))
            curve(to: (8.5, 13), (15.5, 11.4), (8.5, 10.4))
            curve(to: (15.5, 17.4), (8.5, 15.6), (15.5, 14.9))
            curve(to: (12, 20.25), (15.5, 19.3), (13.6, 20.25))
            circle(8.5, 7.2, 0.9)

        case .sello:
            // El ex libris: doble anillo y el ornamento «· · ·».
            circle(12, 12, 9.25)
            circle(12, 12, 6.25)
            dot(9.25, 12)
            dot(12, 12)
            dot(14.75, 12)

        case .columnata:
            // Frontón, tres columnas, basa y escalón.
            path.move(to: point(3, 8))
            path.addLine(to: point(12, 3))
            path.addLine(to: point(21, 8))
            path.closeSubpath()
            line((6.5, 8), (6.5, 18.25))
            line((12, 8), (12, 18.25))
            line((17.5, 8), (17.5, 18.25))
            line((4, 18.25), (20, 18.25))
            line((2.5, 21.25), (21.5, 21.25))

        case .mortero:
            // El cuenco con su pie y la mano que asoma.
            line((4, 11), (20, 11))
            path.move(to: point(5.5, 11))
            curve(to: (12, 19), (5.5, 15.5), (8, 19))
            curve(to: (18.5, 11), (16, 19), (18.5, 15.5))
            line((12, 19), (12, 21.5))
            line((8.5, 21.5), (15.5, 21.5))
            line((12.75, 11), (18.4, 4.1))
            circle(19, 3.4, 0.9)
        }
        return path
    }
}

extension WizardStep {
    /// El sello de sección que acompaña al título del paso, si lo tiene. Los pasos con imagen propia (el
    /// retrato de la portada, el ex libris de «Tu agente») no llevan glifo.
    var glyph: Glyph? {
        switch self {
        case .tools: .mortero
        case .skills: .pluma
        case .rules: .baston
        case .review: .lente
        default: nil
        }
    }
}

/// Un glifo dibujado: trazo de 1,5 pt a su tamaño final (también a 48 pt, donde se ve más fino), puntas
/// redondas y sin relleno. Siempre decorativo.
struct GlyphView: View {
    let glyph: Glyph
    var size: CGFloat = 24
    var color: Color = .ink700

    var body: some View {
        GlyphShape(glyph: glyph)
            .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: 20) {
        ForEach(Glyph.allCases, id: \.self) { glyph in
            VStack(spacing: 10) {
                GlyphView(glyph: glyph, size: 48)
                GlyphView(glyph: glyph)
            }
        }
    }
    .padding(32)
    .background(Color.parchment50)
}
