import SwiftUI

/// Paso 8: ver `docs/03-especificacion-v0.0.1.md` §3. Por ahora es un
/// marcador con su título; se construye en su propio paso de la guía.
struct RulesStepView: View {
    var body: some View {
        StepScaffold(step: .rules) {
            UnderConstructionNote()
        }
    }
}

#Preview {
    RulesStepView()
        .frame(width: WindowMetrics.width, height: 400)
        .background(Color.parchment50)
}
