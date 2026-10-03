import GalenoCore
import SwiftUI

/// Paso 1: idioma y bienvenida (`docs/03` §3). El idioma se elige aquí y cambia
/// toda la app en caliente: `GalenoApp` pone `\.locale` según `wizard.language`.
struct WelcomeStepView: View {
    @EnvironmentObject private var wizard: WizardState

    var body: some View {
        StepScaffold(step: .welcome) {
            VStack(alignment: .leading, spacing: Space.s24) {
                languagePicker

                VStack(alignment: .leading, spacing: Space.s16) {
                    InfoRow(symbol: "person.text.rectangle", title: "welcome.what.title", message: "welcome.what.body")
                    InfoRow(symbol: "square.grid.2x2", title: "welcome.setup.title", message: "welcome.setup.body")
                    InfoRow(symbol: "clock", title: "welcome.time.title", message: "welcome.time.body")
                }

                DopamineLine(key: "dopamine.welcome")
            }
        }
    }

    private var languagePicker: some View {
        VStack(alignment: .leading, spacing: Space.s8) {
            Text("welcome.language.label")
                .font(.galenoCaption.smallCaps())
                .kerning(1.2)
                .foregroundStyle(Color.ink700)
            Picker("welcome.language.label", selection: $wizard.language) {
                ForEach(Language.allCases, id: \.self) { language in
                    // El nombre en su propio idioma: se lee aunque la app esté en el otro.
                    Text(verbatim: language.nativeName).tag(language)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 280, alignment: .leading)
        }
    }
}

/// Un símbolo, un título corto y una frase.
private struct InfoRow: View {
    let symbol: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: Space.s16) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(Color.ink700)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.s4) {
                Text(title)
                    .font(.galenoBody.weight(.semibold))
                    .foregroundStyle(Color.ink900)
                Text(message)
                    .font(.galenoBody)
                    .foregroundStyle(Color.ink700)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    WelcomeStepView()
        .environmentObject(WizardState())
        .frame(width: WindowMetrics.width, height: 440)
        .background(Color.parchment50)
}
