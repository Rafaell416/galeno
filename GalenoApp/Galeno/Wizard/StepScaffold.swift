import SwiftUI

/// La estructura que comparten las pantallas con título (B1): el título en Cormorant con el punto de
/// lacre —el único acento de la pantalla—, una línea de qué se hace en ese paso, y el contenido.
/// La bienvenida, «Escribiendo» y «Listo» se arman aparte.
struct StepScaffold<Content: View, Trailing: View>: View {
    @EnvironmentObject private var wizard: WizardState
    let step: WizardStep
    /// Tamaño del resumen: 16 en los primeros pasos, 15 donde la pantalla va más cargada.
    var summarySize: CGFloat = 15
    /// Del título al resumen, y del resumen al contenido (medidas del diseño, por pantalla).
    var titleGap: CGFloat = 6
    var contentGap: CGFloat = 14
    /// Algo breve a la derecha del título (por ejemplo, el recuento de herramientas del paso 4).
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    init(
        step: WizardStep, summarySize: CGFloat = 15, titleGap: CGFloat = 6, contentGap: CGFloat = 14,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) {
        self.step = step
        self.summarySize = summarySize
        self.titleGap = titleGap
        self.contentGap = contentGap
        self.trailing = trailing()
        self.content = content()
    }

    /// El nombre del agente, desde que se escribe en el paso 3.
    private var agentName: String { wizard.agentName.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        // En un `ScrollView` para que un paso nunca pueda empujar la cabecera ni los botones fuera
        // de la ventana fija de 720×560: si el contenido no cupiera, se desplaza en vez de
        // desbordar. Los pasos se diseñan para caber sin desplazarse.
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    StepTitle(text: Text(step.title))
                        // El sello de sección cuelga en el margen, como el ornamento de un impreso: el
                        // título sigue alineado con el contenido.
                        .overlay(alignment: .leading) {
                            if let glyph = step.glyph {
                                GlyphView(glyph: glyph, size: 22, color: .ink500).offset(x: -33, y: 2)
                            }
                        }
                    Spacer(minLength: Space.s16)
                    trailing
                }
                .padding(.bottom, titleGap)
                summary
                    .font(Typo.text(summarySize))
                    .lineSpacing(summarySize == 16 ? 3 : 2)
                    .foregroundStyle(Color.ink700)
                    .frame(maxWidth: summarySize == 16 ? 560 : .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, contentGap)
                content
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, Space.s48)
            .padding(.top, 22)
            .padding(.bottom, Space.s16)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    /// La línea de qué se hace en el paso. Desde «Skills» habla del agente por su nombre.
    private var summary: Text {
        switch step {
        case .skills:
            Text("step.skills.summary \(agentName)") + Text(verbatim: " ")
                + Text("skills.what").foregroundColor(Color.ink500)
        case .rules: Text("step.rules.summary \(agentName)")
        case .review where wizard.mode == .edit: Text("step.review.summary.edit")
        default: Text(step.summary)
        }
    }
}

/// Un título de pantalla: Cormorant 32 con el punto final en lacre.
struct StepTitle: View {
    let text: Text
    var size: CGFloat = 32

    @Environment(\.galenoReduceMotion) private var reduceMotion
    @State private var dotShown = false

    /// El título entra con la página; el punto final, en lacre, 200 ms después (150 ms de fundido).
    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 0) {
            text.foregroundStyle(Color.ink900)
            Text(verbatim: ".")
                .foregroundStyle(Color.seal700)
                .opacity(dotShown ? 1 : 0)
        }
        .font(Typo.display(size))
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            withAnimation(.easeOut(duration: Motion.micro).delay(reduceMotion ? 0 : 0.2)) { dotShown = true }
        }
    }
}

/// Un aviso con borde izquierdo de 3 pt y fondo tenue, sin sombra ni esquinas redondas (B1).
/// `moss` para lo que salió bien, `seal` para lo que pide atención, `ochre` para lo que conviene saber.
struct NoticePanel<Content: View>: View {
    enum Kind { case moss, seal, ochre }

    let kind: Kind
    @ViewBuilder var content: Content

    private var edge: Color {
        switch kind {
        case .moss: .moss700
        case .seal: .seal700
        case .ochre: .ochre700
        }
    }

    private var fill: Color {
        switch kind {
        case .moss: .moss100
        case .seal: .seal100
        case .ochre: .parchment100
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(edge).frame(width: 3)
            VStack(alignment: .leading, spacing: Space.s4) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        // Sin esto el borde de color (un `Rectangle`, flexible) estira el aviso a todo el alto.
        .fixedSize(horizontal: false, vertical: true)
        .background(fill)
    }
}

/// Un número de lista en Cormorant, en tinta suave, y su texto (los pasos de instalar y del QR).
struct NumberedLine<Content: View>: View {
    let number: Int
    var numberWidth: CGFloat = 28
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s12) {
            Text(verbatim: "\(number)")
                .font(Typo.display(18))
                .foregroundStyle(Color.ink500)
                .frame(width: numberWidth, alignment: .leading)
            content
        }
    }
}
