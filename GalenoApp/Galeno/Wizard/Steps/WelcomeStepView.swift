import GalenoCore
import SwiftUI

/// Paso 1: la portada (B1). A la izquierda el título, qué va a pasar, el idioma y tres certezas en
/// una tabla a filete; a la derecha, el retrato. El idioma se elige aquí y cambia toda la app en
/// caliente: `GalenoApp` pone `\.locale` según `wizard.language`.
struct WelcomeStepView: View {
    @EnvironmentObject private var wizard: WizardState
    @Environment(\.locale) private var locale
    @Environment(\.galenoReduceMotion) private var reduceMotion
    /// Si el anillo del retrato se traza: solo la primera vez que se ve el paso en la sesión.
    @State private var tracing: Bool?

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 32) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("step.welcome.heading")
                        .font(Typo.pageTitle)
                        .kerning(-0.18)
                        .foregroundStyle(Color.ink900)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 10)
                    Text("step.welcome.summary")
                        .font(Typo.body)
                        .lineSpacing(3)
                        .foregroundStyle(Color.ink700)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 18)
                    languagePicker
                        .padding(.bottom, 18)
                    facts
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                let traces = tracing ?? !wizard.hasShownPortraitTrace
                VStack(spacing: 10) {
                    PortraitMark(size: 168, doubleRing: true, tracesRing: traces).stamp()
                    SmallCapsText(
                        string: Localized.string("welcome.time", locale: locale), size: 12, tracking: 0.14
                    )
                    .foregroundStyle(Color.ink500)
                    // La etiqueta de tiempo aparece cuando termina el anillo.
                    .appearing(after: traces ? 0.9 : 0, duration: 0.2)
                }
                .onAppear {
                    tracing = traces
                    wizard.hasShownPortraitTrace = true
                }
                .frame(width: 188)
                .padding(.top, 4)
            }
            .padding(.horizontal, Space.s48)
            .padding(.top, 22)
            .padding(.bottom, Space.s16)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var languagePicker: some View {
        HStack(spacing: 14) {
            SmallCapsText(string: Localized.string("welcome.language.label", locale: locale), size: 13, tracking: 0.12)
                .foregroundStyle(Color.ink700)
            // El nombre en su propio idioma: se lee aunque la app esté en el otro.
            InkSegmented(
                selection: Binding(
                    get: { wizard.language },
                    set: { wizard.changeLanguage($0, animated: !reduceMotion) }),
                options: Language.allCases, padding: 16, fontSize: 15
            ) {
                language in
                Text(verbatim: language.nativeName)
            }
            .accessibilityLabel(Text("welcome.language.label"))
        }
    }

    /// Tres certezas, como una tabla: el rótulo en versalitas y el texto al lado. La tercera —lo
    /// que nunca pasa— lleva el rótulo en lacre.
    private var facts: some View {
        VStack(alignment: .leading, spacing: 8) {
            fact("welcome.need.title", "welcome.need.body", accent: false)
            fact("welcome.does.title", "welcome.does.body", accent: false)
            fact("welcome.never.title", "welcome.never.body", accent: true)
        }
        .padding(.top, 12)
        .overlay(alignment: .top) { Rectangle().fill(Color.parchment300).frame(height: 1) }
    }

    private func fact(_ title: String, _ body: LocalizedStringKey, accent: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            SmallCapsText(string: Localized.string(title, locale: locale), size: 15, tracking: 0.08)
                .foregroundStyle(accent ? Color.seal700 : Color.ink700)
                .frame(width: 150, alignment: .leading)
            Text(body)
                .font(Typo.list)
                .lineSpacing(1.5)
                .foregroundStyle(Color.ink900)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    WelcomeStepView()
        .environmentObject(WizardState())
        .frame(width: WindowMetrics.width, height: 440)
        .background(Color.parchment50)
}
