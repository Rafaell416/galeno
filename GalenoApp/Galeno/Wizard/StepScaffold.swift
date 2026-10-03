import SwiftUI

/// La estructura que comparten las diez pantallas: el título en versalitas, una
/// línea de qué se hace en ese paso, y el contenido.
struct StepScaffold<Content: View>: View {
    let step: WizardStep
    @ViewBuilder var content: Content

    var body: some View {
        // En un `ScrollView` para que un paso nunca pueda empujar la barra de
        // progreso ni los botones fuera de la ventana fija de 720×560: si el
        // contenido no cupiera, se desplaza en vez de desbordar. Los pasos se
        // diseñan para caber sin desplazarse.
        ScrollView {
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
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, Space.s48)
            .padding(.vertical, Space.s32)
        }
        .scrollBounceBehavior(.basedOnSize)
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

/// Un aviso con borde izquierdo de 3 px, fondo de papel y sin sombra
/// (`docs/04` §5). `moss` para lo que salió bien, `seal` para lo que pide atención.
struct NoticePanel<Content: View>: View {
    enum Kind { case moss, seal }

    let kind: Kind
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(kind == .moss ? Color.moss700 : Color.seal700)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: Space.s8) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.s16)
        }
        // Sin esto el borde de color (un `Rectangle`, flexible) estira el aviso a todo el alto.
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.parchment100)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.parchment300, lineWidth: 1))
    }
}

/// El texto de dopamina que Rafa escribe después. Mientras tanto muestra la
/// clave marcada `TODO(dopamina)`, a la vista a propósito para no olvidarla
/// (`grep -rn "TODO(dopamina)" GalenoApp` las lista).
struct DopamineLine: View {
    let key: LocalizedStringKey

    var body: some View {
        Text(key)
            .font(.galenoCaption)
            .italic()
            .foregroundStyle(Color.ink500)
    }
}
