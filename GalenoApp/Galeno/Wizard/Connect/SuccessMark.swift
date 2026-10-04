import SwiftUI

/// «Trazar»: el check de éxito, un círculo (700 ms) y una palomita (500 ms) que se dibujan con trazo, sin
/// rebotes ni confeti (`docs/04` §8). Con "Reducir movimiento" aparece ya dibujado.
struct SuccessMark: View {
    var size: CGFloat = 56
    /// `false` cuando no hay nada que celebrar («ya estaba conectado»): aparece completo, con un fundido.
    var traced = true
    /// Cuánto tarda el círculo y cuándo empieza la palomita (el paso 2 los acorta: 300 + 500 ms).
    var circleDuration: Double = Motion.trace
    var checkDelay: Double = 0.5

    @Environment(\.galenoReduceMotion) private var reduceMotion
    @State private var drawn = false

    var body: some View {
        ZStack {
            // Trazo fino, como en el diseño: 1,5 pt el círculo y algo más la palomita.
            Circle()
                .inset(by: 0.75)
                .trim(from: 0, to: drawn || !traced ? 1 : 0)
                .stroke(Color.moss700, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion || !traced ? nil : .easeOut(duration: circleDuration), value: drawn)
            CheckMark()
                .trim(from: 0, to: drawn || !traced ? 1 : 0)
                .stroke(
                    Color.moss700,
                    style: StrokeStyle(lineWidth: size >= 48 ? 2.2 : 1.8, lineCap: .round, lineJoin: .round)
                )
                .animation(reduceMotion || !traced ? nil : .easeOut(duration: 0.5).delay(checkDelay), value: drawn)
        }
        .frame(width: size, height: size)
        .opacity(traced || drawn ? 1 : 0)
        .animation(.easeOut(duration: Motion.enter), value: drawn)
        .onAppear { drawn = true }
        .accessibilityHidden(true)
    }
}

#Preview {
    SuccessMark(size: 96)
        .padding(48)
        .background(Color.parchment50)
}
