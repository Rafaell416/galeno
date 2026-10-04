import SwiftUI

// Los gestos de movimiento de B1 (`docs/05` §A): discretos, como pasar una página. Cada uno
// tiene su alternativa con «Reducir movimiento»: el cambio ocurre, sin recorrido.

/// Las duraciones del sistema de movimiento (`docs/04` §12): micro 120–200 ms, entrada 300 ms,
/// trazo 500–800 ms. Nada pasa de 900 ms salvo lo indeterminado.
enum Motion {
    static let micro: Double = 0.15
    static let enter: Double = 0.30
    static let trace: Double = 0.70
    static let write: Double = 0.80
    static let stagger: Double = 0.08
    static let cascade: Double = 0.03

    static func ease(_ duration: Double) -> Animation { .easeOut(duration: duration) }
}

extension AnyTransition {
    /// «Pasar página» (300 ms): la pantalla actual sale subiendo 4 pt y la nueva entra desde 4 pt más abajo.
    static var pageTurn: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 4)),
            removal: .opacity.combined(with: .offset(y: -4)))
    }
}

extension Animation {
    /// La curva común de B1 para los cambios de pantalla.
    static var pageTurn: Animation { .easeOut(duration: Motion.enter) }
}

/// La palomita, en las proporciones del círculo de 72 pt del diseño (22,37 → 31,5,46,5 → 51,27).
struct CheckMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.306, y: rect.minY + rect.height * 0.514))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.4375, y: rect.minY + rect.height * 0.646))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.708, y: rect.minY + rect.height * 0.375))
        return path
    }
}

/// Un trazo que se dibuja (`trim`): círculo, palomita o línea. Con «Reducir movimiento» aparece completo
/// con un fundido de 150 ms.
struct TracedShape<S: Shape>: View {
    let shape: S
    var lineWidth: CGFloat = 1.5
    var color: Color
    var duration: Double
    var delay: Double = 0

    @Environment(\.galenoReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0

    var body: some View {
        shape.trim(from: 0, to: reduceMotion ? 1 : progress)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .opacity(reduceMotion ? Double(progress) : 1)
            .onAppear {
                withAnimation(.easeOut(duration: reduceMotion ? Motion.micro : duration).delay(reduceMotion ? 0 : delay)) {
                    progress = 1
                }
            }
    }
}

/// Aparece con un fundido después de `delay` (y, si se pide, subiendo desde `offset` pt). Con «Reducir
/// movimiento» aparece ya, en 150 ms y sin desplazarse. No bloquea nada: lo que está debajo se puede usar.
struct AppearAfter: ViewModifier {
    var delay: Double
    var duration: Double = Motion.enter
    var offset: CGFloat = 0

    @Environment(\.galenoReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : offset)
            .onAppear {
                withAnimation(.easeOut(duration: reduceMotion ? Motion.micro : duration).delay(reduceMotion ? 0 : delay)) {
                    shown = true
                }
            }
    }
}

extension View {
    func appearing(after delay: Double, duration: Double = Motion.enter, offset: CGFloat = 0) -> some View {
        modifier(AppearAfter(delay: delay, duration: duration, offset: offset))
    }

    /// Entrada escalonada: el elemento `index` entra `step` s después del anterior. Solo los primeros
    /// `limit` se escalonan; el resto entra junto con el último.
    func staggered(_ index: Int, step: Double = Motion.stagger, limit: Int = 6, base: Double = 0) -> some View {
        appearing(after: base + Double(min(index, limit)) * step)
    }
}

/// Una cifra que cuenta de 0 al valor real, con el rodillo de dígitos del sistema. El valor es siempre un
/// dato recibido; con «Reducir movimiento» se muestra directo.
struct CountingNumber: View {
    let value: Int
    var duration: Double = 0.6
    var delay: Double = 0

    @Environment(\.galenoReduceMotion) private var reduceMotion
    @State private var shown = 0

    var body: some View {
        Text(verbatim: "\(shown)")
            .contentTransition(.numericText(countsDown: false))
            .monospacedDigit()
            .task(id: value) {
                if reduceMotion { shown = value; return }
                let steps = min(max(value, 1), 24)
                try? await Task.sleep(for: .seconds(delay))
                for step in 1...steps {
                    try? await Task.sleep(for: .seconds(duration / Double(steps)))
                    if Task.isCancelled { return }
                    withAnimation(.easeOut(duration: 0.08)) { shown = value * step / steps }
                }
                shown = value
            }
    }
}

/// «Escribir» (800 ms): un filete que se traza de izquierda a derecha bajo el renglón en curso.
struct WriteUnderline: View {
    var color: Color = .ink900
    var duration: Double = Motion.write
    /// Un trazo parado a medias (cuando algo falla): se queda donde iba y cambia de color.
    var stopped = false
    /// El paso terminó antes que el trazo: salta al final (nada espera a la animación) y se desvanece.
    var finished = false

    @Environment(\.galenoReduceMotion) private var reduceMotion
    @State private var fraction: CGFloat = 0
    @State private var startedAt = Date()
    @State private var faded = false

    private var effectiveDuration: Double { reduceMotion ? Motion.micro : duration }

    var body: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(color)
                .frame(width: proxy.size.width * fraction, height: 1)
        }
        .frame(height: 1)
        .opacity(faded ? 0 : 1)
        .onAppear { start() }
        .onChange(of: stopped) { _, isStopped in if isStopped { freeze() } }
        .onChange(of: finished) { _, isFinished in if isFinished { finish() } }
        .accessibilityHidden(true)
    }

    private func start() {
        startedAt = Date()
        if finished {
            // Ya estaba terminado al aparecer: no hay nada que trazar.
            faded = true
        } else if stopped {
            freeze()
        } else {
            withAnimation(.easeOut(duration: effectiveDuration)) { fraction = 1 }
        }
    }

    /// Cuánto llevaba trazado en este instante (la misma curva de salida suave, aproximada).
    private func currentFraction() -> CGFloat {
        let t = min(max(Date().timeIntervalSince(startedAt) / effectiveDuration, 0), 1)
        return CGFloat(1 - (1 - t) * (1 - t))
    }

    /// Para el trazo donde iba: un cambio sin animación cancela la que estaba en curso. Deja siempre un
    /// tramo visible, para que se vea dónde se cortó aunque fallara nada más empezar.
    private func freeze() {
        let reached = max(currentFraction(), 0.15)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { fraction = reached }
    }

    private func finish() {
        withAnimation(.easeOut(duration: 0.12)) { fraction = 1 }
        withAnimation(.easeOut(duration: 0.2).delay(0.12)) { faded = true }
    }
}

/// «Tinta que corre» (1,4 s, en bucle): una barra indeterminada con un trazo de tinta que avanza.
/// El sincronizado de WhatsApp no da progreso real, y la barra no finge darlo.
struct InkRunBar: View {
    @Environment(\.galenoReduceMotion) private var reduceMotion
    @State private var phase = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.parchment300)
                if reduceMotion {
                    Rectangle().fill(Color.ink900.opacity(0.5))
                } else {
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [.clear, Color.ink900, .clear], startPoint: .leading, endPoint: .trailing))
                        .frame(width: proxy.size.width * 0.4)
                        .offset(x: phase ? proxy.size.width : -proxy.size.width * 0.4)
                        .animation(.linear(duration: 1.4).repeatForever(autoreverses: false), value: phase)
                }
            }
            .clipped()
        }
        .frame(height: 3)
        .onAppear { phase = true }
        .accessibilityHidden(true)
    }
}

/// «Posar el sello» (250 ms): el sello entra un poco grande y se asienta.
struct StampModifier: ViewModifier {
    @Environment(\.galenoReduceMotion) private var reduceMotion
    @State private var placed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(placed || reduceMotion ? 1 : 1.04)
            .opacity(placed || reduceMotion ? 1 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: placed)
            .onAppear { placed = true }
    }
}

extension View {
    func stamp() -> some View { modifier(StampModifier()) }
}

/// Entra con un fundido y asentándose desde una escala de 1,04 (la opción recomendada, 5.13). Con
/// «Reducir movimiento», solo opacidad.
struct SettleIn: ViewModifier {
    var delay: Double
    @Environment(\.galenoReduceMotion) private var reduceMotion
    @State private var settled = false

    func body(content: Content) -> some View {
        content
            .opacity(settled ? 1 : 0)
            .scaleEffect(settled || reduceMotion ? 1 : 1.04)
            .onAppear {
                withAnimation(.easeOut(duration: reduceMotion ? Motion.micro : 0.25).delay(reduceMotion ? 0 : delay)) {
                    settled = true
                }
            }
    }
}

extension View {
    func settling(after delay: Double) -> some View { modifier(SettleIn(delay: delay)) }

    /// Un barrido de revelado de izquierda a derecha, como si se imprimiera (la lámina, 5.26).
    func revealed(duration: Double = 0.9) -> some View { modifier(RevealSweep(duration: duration)) }
}

struct RevealSweep: ViewModifier {
    var duration: Double
    @Environment(\.galenoReduceMotion) private var reduceMotion
    @State private var fraction: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .mask(alignment: .leading) {
                GeometryReader { proxy in
                    Rectangle().frame(width: proxy.size.width * (reduceMotion ? 1 : fraction))
                }
            }
            .opacity(reduceMotion ? Double(fraction) : 1)
            .onAppear {
                withAnimation(.easeOut(duration: reduceMotion ? Motion.micro : duration)) { fraction = 1 }
            }
    }
}

/// Una cifra que sube de uno en uno hacia el valor que va llegando (los chats que encuentra la
/// sincronización): nunca salta de 0 a 31. `text` pone la cifra dentro de su frase.
struct ChasingNumber: View {
    let target: Int
    let text: (Int) -> Text
    @Environment(\.galenoReduceMotion) private var reduceMotion
    @State private var shown = 0

    var body: some View {
        text(shown)
            .contentTransition(.numericText())
            .monospacedDigit()
            .task(id: target) {
                if reduceMotion { shown = target; return }
                while shown < target {
                    try? await Task.sleep(for: .milliseconds(80))
                    if Task.isCancelled { return }
                    withAnimation(.easeOut(duration: 0.08)) { shown += max(1, (target - shown) / 12) }
                }
                shown = target
            }
    }
}

/// Un espiral de espera en tinta: 28 pt (o el tamaño que se pida), un arco sobre un anillo suave.
struct InkSpinner: View {
    var size: CGFloat = 28
    @Environment(\.galenoReduceMotion) private var reduceMotion
    @State private var turning = false

    var body: some View {
        Circle()
            .strokeBorder(Color.ink300, lineWidth: 1.5)
            .overlay(
                Circle().trim(from: 0, to: 0.25)
                    .stroke(Color.ink900, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .rotationEffect(.degrees(turning ? 360 : 0))
                    .animation(reduceMotion ? nil : .linear(duration: 1).repeatForever(autoreverses: false), value: turning)
            )
            .frame(width: size, height: size)
            // Con «Reducir movimiento» el anillo no gira: se queda quieto con tres puntos.
            .overlay {
                if reduceMotion && size >= 16 {
                    Text(verbatim: "···").font(.system(size: size * 0.5)).foregroundStyle(Color.ink700)
                }
            }
            .onAppear { turning = true }
            .accessibilityHidden(true)
    }
}

/// El anillo de 12 pt de «cargando» dentro de un botón: primero se traza (400 ms) y luego gira
/// (900 ms por vuelta). Con «Reducir movimiento» queda quieto, cerrado a tres cuartos.
struct LoadingRing: View {
    var color: Color
    var size: CGFloat = 12

    @Environment(\.galenoReduceMotion) private var reduceMotion
    @State private var drawn: CGFloat = 0
    @State private var turns = false

    var body: some View {
        Circle()
            .trim(from: 0, to: reduceMotion ? 0.75 : drawn * 0.75)
            .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(turns ? 360 : 0))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 0.4)) { drawn = 1 }
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false).delay(0.4)) { turns = true }
            }
            .accessibilityHidden(true)
    }
}
