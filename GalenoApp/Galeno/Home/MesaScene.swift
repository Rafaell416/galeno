import AppKit
import GalenoCore
import SwiftUI

// La mesa del home (decisión de Rafa, 6 oct 2026): una ilustración fija en perspectiva —no una escena 3D— con una
// mesa larga vista en diagonal y, sentado a ella, el personaje de cada agente. Este archivo son las cuentas y el
// dibujo; la vista (`HomeTableView`) solo los coloca y escucha los clics.

/// Un asiento ocupado: qué agente, en cuál de los seis sitios, y en qué se distingue de otro del mismo rol.
struct MesaSeat: Identifiable, Equatable {
    let agent: HomeAgent
    /// 0 es el sitio más cercano (a la izquierda) y 5 el más lejano.
    let position: Int
    /// El segundo agente de un mismo rol. Con láminas todos miran al mismo lado y se distinguen por el nombre; la
    /// figura de línea de respaldo viste de oscuro.
    let alternate: Bool

    var id: UUID { agent.id }
}

/// Las cuentas de la mesa: dónde está cada cosa en un lienzo fijo, y a quién le toca cada sitio.
nonisolated enum Mesa {
    /// El lienzo: el ancho útil de la ventana fija (800 − 2 × 48) y lo que deja libre el home entre título y pie.
    static let size = CGSize(width: 704, height: 352)
    static let seatsPerTable = 6

    // El tablero, en sentido horario desde la esquina trasera cercana. Es un **paralelogramo**: los dos extremos
    // miden lo mismo y nada converge (corrección de Rafa, 6 oct 2026: con el extremo lejano más estrecho se leía como
    // un trapecio y la mesa se veía rara). Por eso tampoco encogen las figuras del fondo.
    // La mesa sube hacia la derecha y casi no se ladea: quien se sienta queda de frente, con su papel delante.
    // El fondo es bajo y muy ladeado —la mesa se ve más de lado que desde arriba—: la inclinación que eligió Rafa
    // entre tres (6 oct 2026).
    static let backNear = CGPoint(x: 52, y: 228)
    static let backFar = CGPoint(x: 616, y: 146)
    static let frontFar = CGPoint(x: 686, y: 194)
    static let frontNear = CGPoint(x: 122, y: 276)

    /// El orden en que se ocupan los sitios: del centro hacia los extremos, para que uno o dos agentes no queden
    /// arrinconados. Un agente no cambia de sitio cuando llega otro.
    static let fillOrder = [2, 3, 1, 4, 0, 5]

    /// Las mesas: de seis en seis. El séptimo agente se sienta solo en la segunda.
    @MainActor
    static func tables(for agents: [HomeAgent]) -> [[MesaSeat]] {
        var seen: [AgentRole: Int] = [:]
        var tables: [[MesaSeat]] = []
        for (index, agent) in agents.enumerated() {
            let slot = index % seatsPerTable
            if slot == 0 { tables.append([]) }
            let repeats = seen[agent.role, default: 0]
            seen[agent.role] = repeats + 1
            tables[tables.count - 1].append(
                MesaSeat(agent: agent, position: fillOrder[slot], alternate: repeats % 2 == 1))
        }
        return tables
    }

    /// Un punto del tablero: `u` va del extremo cercano (0) al lejano (1) y `v` del borde de atrás (0) al de delante (1).
    static func point(u: CGFloat, v: CGFloat) -> CGPoint {
        let back = lerp(backNear, backFar, u)
        let front = lerp(frontNear, frontFar, u)
        return lerp(back, front, v)
    }

    /// A lo largo del tablero, dónde cae el sitio `position`: repartidos, con un margen en cada extremo para que el
    /// objeto del primero y el papel del último queden dentro.
    static func along(_ position: Int) -> CGFloat { 0.06 + 0.88 * (CGFloat(position) + 0.5) / CGFloat(seatsPerTable) }

    /// Todas las figuras miden lo mismo: la mesa no tiene fuga, así que lo lejano no encoge.
    static func scale(_ position: Int) -> CGFloat { 0.95 }

    /// Los pies de la figura: un poco por debajo del borde de atrás, que el tablero tapa.
    static func origin(_ position: Int) -> CGPoint {
        let edge = point(u: along(position), v: 0)
        return CGPoint(x: edge.x, y: edge.y + 14 * scale(position))
    }

    /// La figura se dibuja en una caja de 100 × 150 con los pies abajo en el centro.
    static let figureBox = CGSize(width: 100, height: 150)

    /// Cuánto sobresale del borde de atrás la figura de línea, en sus unidades (de la cintura al sombrero).
    static let drawnRise: CGFloat = 116
    /// Cuánto se mete una lámina en el tablero desde el borde de atrás: se apoya en él. La ropa se disuelve hacia la
    /// madera en esa franja y las manos y el papel quedan encima (así viene preparada cada lámina).
    static let plateSink: CGFloat = 20
    /// El lienzo entero: ahí va la mesa cuando es una lámina (`mesa-tablero`).
    static let canvas = CGRect(origin: .zero, size: size)
    static let tableAsset = "mesa-tablero"

    /// Dónde va una lámina: centrada en su sitio, apoyada en el tablero.
    static func plateRect(_ position: Int, aspect: CGFloat, height: CGFloat) -> CGRect {
        let edge = point(u: along(position), v: 0), scale = scale(position)
        let size = CGSize(width: height * aspect * scale, height: height * scale)
        return CGRect(x: edge.x - size.width / 2, y: edge.y + plateSink * scale - size.height, width: size.width, height: size.height)
    }

    /// Dónde va el nombre: encima de la cabeza. `rise` es cuánto sobresale la figura del borde de atrás.
    static func labelAnchor(_ position: Int, rise: CGFloat = drawnRise) -> CGPoint {
        let edge = point(u: along(position), v: 0)
        return CGPoint(x: edge.x, y: edge.y - rise * scale(position) - 13)
    }

    /// Lo que responde al clic: la figura y su nombre.
    static func hitRect(_ position: Int, rise: CGFloat = drawnRise) -> CGRect {
        let origin = origin(position), scale = scale(position)
        let top = labelAnchor(position, rise: rise).y - 10
        return CGRect(x: origin.x - 40 * scale, y: top, width: 86 * scale, height: origin.y - top + 22 * scale)
    }

    static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    /// La cuesta del tablero: lo que sube por cada punto hacia la derecha (negativo: en pantalla, subir es restar).
    static let slope = (backFar.y - backNear.y) / (backFar.x - backNear.x)

    /// Cuánto se ha movido la mano que escribe en el instante `time`: recorre un renglón (2,2 s) con el temblor de
    /// la pluma y vuelve levantada (0,4 s). Cada sitio va desfasado para que no escriban a compás.
    static func writingOffset(time: TimeInterval, position: Int) -> CGSize {
        let phase = (time + Double(position) * 0.83).truncatingRemainder(dividingBy: 2.6)
        if phase < 2.2 {
            let x = -7 + 14 * phase / 2.2
            return CGSize(width: x, height: slope * x + sin(phase * 19) * 1.1)
        }
        let x = 7 - 14 * (phase - 2.2) / 0.4
        return CGSize(width: x, height: slope * x - 2.5)
    }
}

/// El dibujo de la mesa, en tres capas que la vista apila: las figuras, el tablero (que les tapa la cintura) y lo
/// que hay encima del tablero (el papel, el objeto de cada sitio y el brazo que escribe).
///
/// Las figuras de aquí son **provisionales**: dibujos propios de línea, hasta que entren las láminas de cada
/// personaje (`Persona.figure`).
enum MesaDrawing {
    struct Ink {
        var line: Color = .ink700
        var strong: Color = .ink900
        var faint: Color = .parchment400
        var paper: Color = .parchment50
        var shade: Color = .parchment100
        var deep: Color = .parchment200
    }

    // MARK: El tablero

    /// ¿Hay lámina de la mesa en el catálogo? Si no, se dibuja a línea.
    static var hasTablePlate: Bool { NSImage(named: Mesa.tableAsset) != nil }

    /// La mesa: la lámina de madera (la mesa que generó Rafa, recolocada en esta perspectiva) o, si falta, el dibujo
    /// de línea. `dimmed` la apaga un poco: en oscuro, las luces de un grabado deslumbran.
    static func table(_ context: inout GraphicsContext, dimmed: Bool = false, ink: Ink = Ink()) {
        if hasTablePlate {
            var layer = context
            layer.opacity = dimmed ? 0.88 : 1
            layer.draw(layer.resolve(Image(Mesa.tableAsset)), in: Mesa.canvas)
            return
        }
        let drop: CGFloat = 12, dropFar: CGFloat = 12
        let nearDown = CGPoint(x: Mesa.frontNear.x, y: Mesa.frontNear.y + drop)
        let farDown = CGPoint(x: Mesa.frontFar.x, y: Mesa.frontFar.y + dropFar)
        let backDown = CGPoint(x: Mesa.backNear.x, y: Mesa.backNear.y + drop)

        // La sombra en el suelo: un rayado corto, como en un grabado.
        var hatch = Path()
        for step in 0..<34 {
            let u = CGFloat(step) / 33
            let base = Mesa.lerp(CGPoint(x: 100, y: 338), CGPoint(x: 680, y: 256), u)
            hatch.move(to: base)
            hatch.addLine(to: CGPoint(x: base.x + 13 - 4 * u, y: base.y - 8 + 2 * u))
        }
        context.stroke(hatch, with: .color(ink.faint), lineWidth: 0.75)

        // Las patas que se ven: las dos de delante y la de atrás del lado cercano.
        leg(&context, top: CGPoint(x: Mesa.backNear.x + 3, y: backDown.y - 2), height: 50, width: 8, ink: ink)
        leg(&context, top: CGPoint(x: Mesa.frontFar.x - 11, y: farDown.y - 2), height: 50, width: 8, ink: ink)
        leg(&context, top: CGPoint(x: Mesa.frontNear.x + 4, y: nearDown.y - 2), height: 50, width: 8, ink: ink)

        // El canto: el lado cercano y el frente.
        let side = quad(Mesa.backNear, Mesa.frontNear, nearDown, backDown)
        context.fill(side, with: .color(ink.deep))
        context.stroke(side, with: .color(ink.line), lineWidth: 1.25)
        let front = quad(Mesa.frontNear, Mesa.frontFar, farDown, nearDown)
        context.fill(front, with: .color(ink.shade))
        context.stroke(front, with: .color(ink.line), lineWidth: 1.25)

        // El tablero, opaco: tapa la cintura de las figuras.
        let top = quad(Mesa.backNear, Mesa.backFar, Mesa.frontFar, Mesa.frontNear)
        context.fill(top, with: .color(ink.paper))
        var grain = Path()
        for v in [0.3, 0.52, 0.76] as [CGFloat] {
            grain.move(to: Mesa.point(u: 0.015, v: v))
            grain.addLine(to: Mesa.point(u: 0.985, v: v))
        }
        context.stroke(grain, with: .color(ink.faint), lineWidth: 0.75)
        context.stroke(top, with: .color(ink.line), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
    }

    private static func leg(_ context: inout GraphicsContext, top: CGPoint, height: CGFloat, width: CGFloat, ink: Ink) {
        let path = quad(
            top, CGPoint(x: top.x + width, y: top.y - width * 0.2),
            CGPoint(x: top.x + width * 0.8, y: top.y + height - width * 0.2), CGPoint(x: top.x + width * 0.2, y: top.y + height))
        context.fill(path, with: .color(ink.shade))
        context.stroke(path, with: .color(ink.line), lineWidth: 1.25)
    }

    private static func quad(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Path {
        var path = Path()
        path.move(to: a)
        path.addLine(to: b); path.addLine(to: c); path.addLine(to: d)
        path.closeSubpath()
        return path
    }

    // MARK: La figura

    /// Pasa de la caja de la figura (100 × 150, pies abajo en el centro) al lienzo.
    struct Frame {
        let origin: CGPoint
        let scale: CGFloat

        init(position: Int) {
            origin = Mesa.origin(position)
            scale = Mesa.scale(position)
        }

        func callAsFunction(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + scale * (x - 50), y: origin.y + scale * (y - 150))
        }
    }

    /// El busto: cuerpo, cabeza y lo que distingue a cada personaje. `missing` es el agente sin carpeta: solo la
    /// silueta, a trazos.
    static func figure(
        _ context: inout GraphicsContext, role: AgentRole, frame f: Frame, highlighted: Bool = false, missing: Bool = false,
        dark: Bool = false, ink: Ink = Ink()
    ) {
        let s = f.scale
        let line = highlighted ? ink.strong : ink.line
        let width = max(1, 1.3 * s)
        let stroke = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: missing ? [3, 3] : [])

        var body = Path()
        // Baja más allá de la cintura: el tablero, que va en cuesta, tapa lo que sobra.
        body.move(to: f(16, 182))
        body.addCurve(to: f(25, 90), control1: f(14, 130), control2: f(17, 100))
        body.addQuadCurve(to: f(42, 75), control: f(31, 80))
        body.addLine(to: f(60, 75))
        body.addQuadCurve(to: f(77, 90), control: f(71, 80))
        body.addCurve(to: f(86, 182), control1: f(85, 100), control2: f(88, 130))
        body.closeSubpath()
        context.fill(body, with: .color(dark && !missing ? ink.deep : ink.paper))
        context.stroke(body, with: .color(missing ? ink.faint : line), style: stroke)

        var head = Path()
        let center = f(51, 50.5)
        head.addEllipse(in: CGRect(x: center.x - 14 * s, y: center.y - 17.5 * s, width: 28 * s, height: 35 * s))
        context.fill(head, with: .color(ink.paper))
        context.stroke(head, with: .color(missing ? ink.faint : line), style: stroke)
        guard !missing else { return }

        var face = Path()
        face.move(to: f(45, 49)); face.addLine(to: f(49, 49))
        face.move(to: f(55, 49)); face.addLine(to: f(59, 49))
        face.move(to: f(53.5, 50)); face.addLine(to: f(55.5, 58)); face.addLine(to: f(52.5, 59))
        context.stroke(face, with: .color(line), style: StrokeStyle(lineWidth: max(0.8, s), lineCap: .round, lineJoin: .round))

        switch role {
        case .productManager: galen(&context, f, line: line, ink: ink, stroke: stroke)
        case .marketing: wedgwood(&context, f, line: line, ink: ink, stroke: stroke)
        case .sales: polo(&context, f, line: line, ink: ink, stroke: stroke)
        }
    }

    /// Galeno: bonete, barba rizada y toga de solapas anchas.
    private static func galen(_ context: inout GraphicsContext, _ f: Frame, line: Color, ink: Ink, stroke: StrokeStyle) {
        var cap = Path()
        cap.move(to: f(36.5, 47))
        cap.addCurve(to: f(65.5, 47), control1: f(35, 23), control2: f(67, 23))
        cap.addQuadCurve(to: f(36.5, 47), control: f(51, 40))
        context.fill(cap, with: .color(ink.shade))
        context.stroke(cap, with: .color(line), style: stroke)

        var beard = Path()
        beard.move(to: f(37.5, 56))
        beard.addCurve(to: f(51, 92), control1: f(35, 75), control2: f(43, 90))
        beard.addCurve(to: f(64.5, 56), control1: f(59, 90), control2: f(67, 75))
        beard.addCurve(to: f(37.5, 56), control1: f(60, 67), control2: f(42, 67))
        context.fill(beard, with: .color(ink.paper))
        context.stroke(beard, with: .color(line), style: stroke)
        var curls = Path()
        for (x, y) in [(44, 72), (51, 76), (58, 72), (47, 83), (55, 83)] as [(CGFloat, CGFloat)] {
            curls.move(to: f(x - 2.5, y))
            curls.addQuadCurve(to: f(x + 2.5, y), control: f(x, y + 4))
        }
        context.stroke(curls, with: .color(line), style: StrokeStyle(lineWidth: max(0.8, f.scale), lineCap: .round))

        var robe = Path()
        robe.move(to: f(40, 78)); robe.addLine(to: f(33, 104)); robe.addLine(to: f(47, 132))
        robe.move(to: f(62, 78)); robe.addLine(to: f(69, 104)); robe.addLine(to: f(55, 132))
        robe.move(to: f(47, 132)); robe.addLine(to: f(46, 182))
        robe.move(to: f(55, 132)); robe.addLine(to: f(56, 182))
        context.stroke(robe, with: .color(line), style: stroke)
    }

    /// Wedgwood: peluca con rizos a los lados, corbata de lazo y casaca.
    private static func wedgwood(_ context: inout GraphicsContext, _ f: Frame, line: Color, ink: Ink, stroke: StrokeStyle) {
        var wig = Path()
        wig.move(to: f(34.5, 62))
        wig.addCurve(to: f(51, 28), control1: f(29, 44), control2: f(37, 28))
        wig.addCurve(to: f(67.5, 62), control1: f(65, 28), control2: f(73, 44))
        wig.addQuadCurve(to: f(51, 39), control: f(63, 41))
        wig.addQuadCurve(to: f(34.5, 62), control: f(39, 41))
        context.fill(wig, with: .color(ink.paper))
        context.stroke(wig, with: .color(line), style: stroke)
        var rolls = Path()
        for (x, y) in [(33.5, 60), (34, 67), (68.5, 60), (68, 67)] as [(CGFloat, CGFloat)] {
            let center = f(x, y)
            rolls.addEllipse(in: CGRect(x: center.x - 5 * f.scale, y: center.y - 3.2 * f.scale, width: 10 * f.scale, height: 6.4 * f.scale))
        }
        context.fill(rolls, with: .color(ink.paper))
        context.stroke(rolls, with: .color(line), style: stroke)

        var mouth = Path()
        mouth.move(to: f(48, 64)); mouth.addQuadCurve(to: f(56, 64), control: f(52, 66))
        context.stroke(mouth, with: .color(line), style: StrokeStyle(lineWidth: max(0.8, f.scale), lineCap: .round))

        var cravat = Path()
        cravat.move(to: f(45, 73)); cravat.addLine(to: f(43, 92)); cravat.addLine(to: f(51, 101))
        cravat.addLine(to: f(59, 92)); cravat.addLine(to: f(57, 73)); cravat.closeSubpath()
        context.fill(cravat, with: .color(ink.paper))
        context.stroke(cravat, with: .color(line), style: stroke)
        var folds = Path()
        folds.move(to: f(48, 76)); folds.addLine(to: f(49, 94))
        folds.move(to: f(54, 76)); folds.addLine(to: f(53, 94))
        folds.move(to: f(45, 80)); folds.addLine(to: f(57, 80))
        context.stroke(folds, with: .color(line), style: StrokeStyle(lineWidth: max(0.8, f.scale), lineCap: .round))

        var coat = Path()
        coat.move(to: f(39, 80)); coat.addLine(to: f(34, 110)); coat.addLine(to: f(47, 138)); coat.addLine(to: f(47, 182))
        coat.move(to: f(63, 80)); coat.addLine(to: f(68, 110)); coat.addLine(to: f(55, 138)); coat.addLine(to: f(55, 182))
        context.stroke(coat, with: .color(line), style: stroke)
        var buttons = Path()
        for y in [112, 122, 132] as [CGFloat] {
            let center = f(51, y)
            buttons.addEllipse(in: CGRect(x: center.x - 1.2 * f.scale, y: center.y - 1.2 * f.scale, width: 2.4 * f.scale, height: 2.4 * f.scale))
        }
        context.fill(buttons, with: .color(line))
    }

    /// Marco Polo: sombrero de paño caído, barba cerrada, cuello de piel y cadena.
    private static func polo(_ context: inout GraphicsContext, _ f: Frame, line: Color, ink: Ink, stroke: StrokeStyle) {
        var hat = Path()
        hat.move(to: f(35.5, 47))
        hat.addCurve(to: f(48, 23), control1: f(31, 34), control2: f(37, 23))
        hat.addCurve(to: f(71, 39), control1: f(61, 20), control2: f(72, 26))
        hat.addCurve(to: f(75, 72), control1: f(77, 49), control2: f(80, 63))
        hat.addQuadCurve(to: f(66, 58), control: f(68, 69))
        hat.addQuadCurve(to: f(35.5, 47), control: f(52, 40))
        context.fill(hat, with: .color(ink.shade))
        context.stroke(hat, with: .color(line), style: stroke)
        var folds = Path()
        folds.move(to: f(42, 31)); folds.addQuadCurve(to: f(64, 33), control: f(53, 27))
        folds.move(to: f(69, 44)); folds.addQuadCurve(to: f(72, 64), control: f(74, 54))
        context.stroke(folds, with: .color(line), style: StrokeStyle(lineWidth: max(0.8, f.scale), lineCap: .round))

        var beard = Path()
        beard.move(to: f(36.5, 55))
        beard.addCurve(to: f(51, 95), control1: f(33, 77), control2: f(42, 93))
        beard.addCurve(to: f(65.5, 55), control1: f(60, 93), control2: f(69, 77))
        beard.addCurve(to: f(36.5, 55), control1: f(60, 65), control2: f(42, 65))
        context.fill(beard, with: .color(line))

        var collar = Path()
        collar.move(to: f(38, 79)); collar.addLine(to: f(50, 118)); collar.addLine(to: f(62, 79))
        collar.move(to: f(28, 88)); collar.addLine(to: f(50, 136)); collar.addLine(to: f(72, 88))
        context.stroke(collar, with: .color(line), style: stroke)
        var fur = Path()
        for step in 1..<7 {
            let t = CGFloat(step) / 7
            fur.move(to: Mesa.lerp(f(38, 79), f(50, 118), t)); fur.addLine(to: Mesa.lerp(f(28, 88), f(50, 136), t))
            fur.move(to: Mesa.lerp(f(62, 79), f(50, 118), t)); fur.addLine(to: Mesa.lerp(f(72, 88), f(50, 136), t))
        }
        context.stroke(fur, with: .color(line), style: StrokeStyle(lineWidth: max(0.7, 0.8 * f.scale), lineCap: .round))
    }

    // MARK: La lámina

    /// La figura de un personaje como lámina (`Persona.figure`): apoyada en el tablero, con las manos y el papel
    /// encima. Lo único que se mueve al escribir es la mano: un recorte ovalado de la misma imagen, desplazado
    /// `hand`. Todas miran al mismo lado (`FigurePlate.mirrored`).
    static func plate(
        _ context: inout GraphicsContext, persona: Persona, position: Int, hand: CGSize = .zero, dimmed: Bool = false
    ) {
        let rect = Mesa.plateRect(position, aspect: persona.plate.aspect, height: persona.plate.height)
        let mirrored = persona.plate.mirrored
        var layer = context
        layer.opacity = dimmed ? 0.88 : 1
        if mirrored {
            // Se refleja sobre su propio eje: la mano cambia de lado con ella.
            layer.translateBy(x: rect.midX, y: 0)
            layer.scaleBy(x: -1, y: 1)
            layer.translateBy(x: -rect.midX, y: 0)
        }
        let image = layer.resolve(Image(persona.figure))
        layer.draw(image, in: rect)
        guard hand != .zero else { return }
        let spot = persona.plate.hand
        let oval = CGRect(
            x: rect.minX + spot.minX * rect.width, y: rect.minY + spot.minY * rect.height,
            width: spot.width * rect.width, height: spot.height * rect.height)
        var moving = layer
        moving.clip(to: Path(ellipseIn: oval))
        let scale = Mesa.scale(position) * 0.2
        moving.draw(image, in: rect.offsetBy(dx: (mirrored ? -1 : 1) * hand.width * scale, dy: hand.height * scale))
    }

    // MARK: Encima del tablero

    /// El objeto del sitio y, para la figura de línea, el papel y el brazo con la pluma. `hand` es cuánto se ha movido
    /// la mano (escribiendo). Una lámina trae su propio papel y su propia mano: `writes` va en falso, y sobre la mesa
    /// de madera no se dibuja nada a línea.
    static func desk(
        _ context: inout GraphicsContext, position: Int, frame f: Frame, hand: CGSize = .zero, highlighted: Bool = false,
        dark: Bool = false, writes: Bool = true, ink: Ink = Ink()
    ) {
        let s = f.scale, t = Mesa.along(position)
        let line = highlighted ? ink.strong : ink.line
        guard writes else {
            if !hasTablePlate {
                object(&context, kind: position, at: Mesa.point(u: t - 0.07, v: 0.46), scale: s, line: line, ink: ink)
            }
            return
        }

        // El papel: una hoja apoyada, con sus renglones.
        var sheet = Path()
        sheet.move(to: Mesa.point(u: t - 0.045, v: 0.2))
        sheet.addLine(to: Mesa.point(u: t + 0.04, v: 0.2)); sheet.addLine(to: Mesa.point(u: t + 0.04, v: 0.82)); sheet.addLine(to: Mesa.point(u: t - 0.045, v: 0.82))
        sheet.closeSubpath()
        context.fill(sheet, with: .color(ink.paper))
        context.stroke(sheet, with: .color(line), style: StrokeStyle(lineWidth: max(0.9, s), lineJoin: .round))
        var written = Path()
        for v in [0.32, 0.44, 0.56] as [CGFloat] {
            written.move(to: Mesa.point(u: t - 0.034, v: v))
            written.addLine(to: Mesa.point(u: t + (v > 0.5 ? 0.0 : 0.03), v: v))
        }
        context.stroke(written, with: .color(ink.faint), lineWidth: max(0.75, 0.8 * s))

        object(&context, kind: position, at: Mesa.point(u: t - 0.088, v: 0.5), scale: s, line: line, ink: ink)

        // El brazo que escribe: del hombro al codo y a la mano, como una manga (trazo ancho con su contorno).
        let rest = Mesa.point(u: t + 0.018, v: 0.52)
        let grip = CGPoint(x: rest.x + hand.width * s, y: rest.y + hand.height * s)
        var sleeve = Path()
        sleeve.move(to: f(76, 95))
        sleeve.addQuadCurve(to: f(90, 134), control: f(91, 110))
        sleeve.addLine(to: CGPoint(x: grip.x + 5 * s, y: grip.y - 4 * s))
        let round = StrokeStyle(lineWidth: 13 * s, lineCap: .round, lineJoin: .round)
        context.stroke(sleeve, with: .color(line), style: StrokeStyle(lineWidth: 13 * s + 2 * max(1, 1.3 * s), lineCap: .round, lineJoin: .round))
        context.stroke(sleeve, with: .color(dark ? ink.deep : ink.paper), style: round)

        var fist = Path()
        fist.addEllipse(in: CGRect(x: grip.x - 3.5 * s, y: grip.y - 6 * s, width: 9 * s, height: 7.5 * s))
        context.fill(fist, with: .color(ink.paper))
        context.stroke(fist, with: .color(line), lineWidth: max(0.9, s))

        // La pluma: el cañón desde la punta y la barba arriba.
        let tip = CGPoint(x: grip.x - 1 * s, y: grip.y + 2.5 * s)
        let top = CGPoint(x: tip.x + 13 * s, y: tip.y - 36 * s)
        var shaft = Path()
        shaft.move(to: tip); shaft.addLine(to: top)
        context.stroke(shaft, with: .color(line), style: StrokeStyle(lineWidth: max(0.9, s), lineCap: .round))
        let low = Mesa.lerp(tip, top, 0.38)
        var feather = Path()
        feather.move(to: low)
        feather.addQuadCurve(to: top, control: CGPoint(x: low.x + 12 * s, y: low.y - 12 * s))
        feather.addQuadCurve(to: low, control: CGPoint(x: top.x - 7 * s, y: top.y + 10 * s))
        context.fill(feather, with: .color(ink.paper))
        context.stroke(feather, with: .color(line), style: StrokeStyle(lineWidth: max(0.9, s), lineJoin: .round))
    }

    /// Un objeto pequeño junto al papel, distinto en cada sitio: tintero, libros, vela, rollo, reloj de arena y copa.
    private static func object(
        _ context: inout GraphicsContext, kind: Int, at base: CGPoint, scale s: CGFloat, line: Color, ink: Ink
    ) {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: base.x + x * s, y: base.y + y * s) }
        func oval(_ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> CGRect {
            CGRect(x: base.x + (x - rx) * s, y: base.y + (y - ry) * s, width: 2 * rx * s, height: 2 * ry * s)
        }
        var fill = Path(), strokeOnly = Path()
        switch kind % 6 {
        case 0:  // tintero
            fill.move(to: p(-6, 0)); fill.addLine(to: p(6, 0)); fill.addLine(to: p(4.5, -9)); fill.addLine(to: p(-4.5, -9)); fill.closeSubpath()
            fill.addEllipse(in: oval(0, -9, 4.5, 1.8))
        case 1:  // dos libros
            fill.move(to: p(-9, 0)); fill.addLine(to: p(7, -3)); fill.addLine(to: p(7, -7)); fill.addLine(to: p(-9, -4)); fill.closeSubpath()
            fill.move(to: p(-9, -4)); fill.addLine(to: p(7, -7)); fill.addLine(to: p(11, -10)); fill.addLine(to: p(-4, -7.5)); fill.closeSubpath()
            fill.move(to: p(-7, -7.6)); fill.addLine(to: p(7, -10.4)); fill.addLine(to: p(7, -14)); fill.addLine(to: p(-7, -11.2)); fill.closeSubpath()
            fill.move(to: p(-7, -11.2)); fill.addLine(to: p(7, -14)); fill.addLine(to: p(10.5, -16.6)); fill.addLine(to: p(-3, -14.2)); fill.closeSubpath()
        case 2:  // vela
            fill.addEllipse(in: oval(0, 0, 6.5, 2.4))
            fill.addRect(CGRect(origin: p(-2, -15), size: CGSize(width: 4 * s, height: 15 * s)))
            strokeOnly.move(to: p(0, -16)); strokeOnly.addQuadCurve(to: p(0, -24), control: p(4, -19))
            strokeOnly.addQuadCurve(to: p(0, -16), control: p(-3.5, -19))
        case 3:  // rollo
            fill.move(to: p(-10, -1)); fill.addLine(to: p(8, -5)); fill.addLine(to: p(8, -11)); fill.addLine(to: p(-10, -7)); fill.closeSubpath()
            fill.addEllipse(in: oval(-10, -4, 2.2, 3.1))
            fill.addEllipse(in: oval(8, -8, 2.2, 3.1))
        case 4:  // reloj de arena
            fill.move(to: p(-5, 0)); fill.addLine(to: p(5, 0)); fill.addLine(to: p(0.8, -8.5)); fill.addLine(to: p(5, -17)); fill.addLine(to: p(-5, -17)); fill.addLine(to: p(-0.8, -8.5)); fill.closeSubpath()
            strokeOnly.move(to: p(-6.5, 0)); strokeOnly.addLine(to: p(6.5, 0))
            strokeOnly.move(to: p(-6.5, -17)); strokeOnly.addLine(to: p(6.5, -17))
        default:  // copa
            fill.move(to: p(-5, -13)); fill.addQuadCurve(to: p(5, -13), control: p(0, -2)); fill.closeSubpath()
            fill.addEllipse(in: oval(0, -13, 5, 1.8))
            fill.addEllipse(in: oval(0, 0, 4.5, 1.7))
            strokeOnly.move(to: p(0, -7.5)); strokeOnly.addLine(to: p(0, -0.5))
        }
        let style = StrokeStyle(lineWidth: max(0.9, s), lineCap: .round, lineJoin: .round)
        context.fill(fill, with: .color(ink.paper))
        context.stroke(fill, with: .color(line), style: style)
        context.stroke(strokeOnly, with: .color(line), style: style)
    }
}
