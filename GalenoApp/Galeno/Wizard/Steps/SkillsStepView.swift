import SwiftUI

/// Paso 7: ver `docs/03-especificacion-v0.0.1.md` §3. Por ahora es un
/// marcador con su título; se construye en su propio paso de la guía.
struct SkillsStepView: View {
    var body: some View {
        StepScaffold(step: .skills) {
            UnderConstructionNote()
        }
    }
}

#Preview {
    SkillsStepView()
        .frame(width: WindowMetrics.width, height: 400)
        .background(Color.parchment50)
}
