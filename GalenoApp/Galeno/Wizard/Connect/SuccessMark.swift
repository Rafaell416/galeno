import SwiftUI

/// El check de éxito: un círculo y una palomita que se dibujan con trazo, sin
/// rebotes ni confeti (`docs/04` §8). Con "Reducir movimiento" aparece ya dibujado.
struct SuccessMark: View {
    var size: CGFloat = 56

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: drawn ? 1 : 0)
                .stroke(Color.moss700, style: StrokeStyle(lineWidth: size / 18, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: drawn)
            CheckShape()
                .trim(from: 0, to: drawn ? 1 : 0)
                .stroke(
                    Color.moss700,
                    style: StrokeStyle(lineWidth: size / 14, lineCap: .round, lineJoin: .round)
                )
                .padding(size * 0.28)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.3).delay(0.3), value: drawn)
        }
        .frame(width: size, height: size)
        .onAppear { drawn = true }
        .accessibilityHidden(true)
    }
}

private struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.55))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY - rect.height * 0.08))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.08))
        return path
    }
}

#Preview {
    SuccessMark(size: 96)
        .padding(48)
        .background(Color.parchment50)
}
