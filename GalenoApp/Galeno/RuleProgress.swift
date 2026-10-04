import SwiftUI

/// El filete de B1: una línea de 1 pt en `parchment-300` con un trazo de 3 pt de `ink-900` que
/// avanza. Es el progreso del wizard; no lleva color (`docs/04` §6).
struct RuleProgress: View {
    /// De 0 a 1.
    let value: Double
    @Environment(\.galenoReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.parchment300).frame(height: 1)
                Rectangle().fill(Color.ink900)
                    .frame(width: proxy.size.width * min(max(value, 0), 1), height: 3)
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 3)
        // «Pasar página»: la barra avanza 300 ms después del cambio de pantalla, no a la vez.
        .animation(reduceMotion ? nil : .easeOut(duration: Motion.enter).delay(Motion.enter), value: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("wizard.progress.label"))
        .accessibilityValue(Text(Int((value * 100).rounded()).formatted(.percent.scale(1))))
    }
}
