import SwiftUI

/// La estructura que comparten las diez pantallas: el título en versalitas, una
/// línea de qué se hace en ese paso, y el contenido.
struct StepScaffold<Content: View>: View {
    let step: WizardStep
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s16) {
            Text(step.title)
                .font(Font.galenoTitle.smallCaps())
                .kerning(1.2)
                .foregroundStyle(Color.ink900)
            Text(step.summary)
                .font(.galenoBody)
                .foregroundStyle(Color.ink700)
                .fixedSize(horizontal: false, vertical: true)
            content
                .padding(.top, Space.s8)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, Space.s48)
        .padding(.vertical, Space.s32)
    }
}

/// El aviso de las pantallas que todavía no se construyen. Un panel de papel con
/// borde fino, sin sombra (`docs/04` §6).
struct UnderConstructionNote: View {
    var body: some View {
        Text("wizard.placeholder")
            .font(.galenoBody)
            .foregroundStyle(Color.ink500)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.s24)
            .background(Color.parchment100, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.parchment300, lineWidth: 1))
    }
}
