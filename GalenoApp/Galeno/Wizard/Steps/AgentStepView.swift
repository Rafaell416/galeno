import GalenoCore
import SwiftUI

/// Paso 3: el nombre, y nada más (rediseño «Activación»). El rol ya se eligió en el paso 1, y la descripción
/// del proyecto y los archivos de contexto salieron de aquí: son opcionales y van en la pantalla siguiente (`ContextStepView`).
/// A la derecha, su ex libris, que se va llenando con lo que se escribe.
struct AgentStepView: View {
    @EnvironmentObject private var wizard: WizardState
    @Environment(\.locale) private var locale
    /// El error del nombre solo se muestra después de pasar por el campo: no se
    /// le grita a alguien que todavía no empezó a escribir.
    @State private var nameWasEdited = false
    @Environment(\.galenoReduceMotion) private var reduceMotion

    private var trimmedName: String { wizard.agentName.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        StepScaffold(step: .agent, summarySize: 16, titleGap: 8, contentGap: 22) {
            HStack(alignment: .top, spacing: 36) {
                VStack(alignment: .leading, spacing: 0) {
                    nameField
                    // Cómo le va a hablar: ponerle voz al nombre antes de seguir. Con el nombre vacío queda un
                    // hueco subrayado donde iría; con nombre, el texto se actualiza por carácter, sin parpadear.
                    Text(previewPhrase)
                        .font(Typo.display(20, italic: true))
                        .foregroundStyle(trimmedName.isEmpty ? Color.ink500 : Color.ink700)
                        .animation(.easeOut(duration: Motion.micro), value: trimmedName.isEmpty)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 12)
                        .overlay(alignment: .top) { Rectangle().fill(Color.parchment300).frame(height: 1) }
                        .padding(.top, 20)
                }
                .frame(maxWidth: 420, alignment: .leading)
                SealView(name: trimmedName, role: wizard.role)
                    .frame(width: 150)
                    .padding(.top, 6)
                Spacer(minLength: 0)
            }
        }
    }

    private var previewPhrase: AttributedString {
        let gap = "\u{2003}\u{2003}\u{2003}\u{2003}"
        let name = trimmedName.isEmpty ? gap : trimmedName
        var phrase = AttributedString(Localized.string("agent.preview %@", name, locale: locale))
        if trimmedName.isEmpty, let range = phrase.range(of: gap) {
            phrase[range].underlineStyle = .single
        }
        return phrase
    }

    // MARK: Campos

    private func label(_ key: String) -> some View {
        SmallCapsText(string: Localized.string(key, locale: locale), size: 13, tracking: 0.12)
            .foregroundStyle(Color.ink700)
            .padding(.bottom, 4)
    }

    private func hint(_ text: Text, color: Color = .ink500) -> some View {
        text
            .font(Typo.text(13))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 6)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 0) {
            label("agent.name.label")
            RuleTextField(
                "agent.name.label", text: $wizard.agentName, prompt: "agent.name.placeholder",
                font: Typo.display(26), autofocus: true, isError: nameWasEdited && wizard.agentNameIssue != nil
            )
            .onChange(of: wizard.agentName) { _, name in
                nameWasEdited = true
                // Un nombre más largo que el tope no entra: así no hay que explicar nada.
                if name.count > WizardState.maxAgentNameLength {
                    wizard.agentName = String(name.prefix(WizardState.maxAgentNameLength))
                }
            }
            // El mensaje de error entra (+4 pt → 0, fade) y se va al corregir.
            Group {
                if nameWasEdited, let issue = wizard.agentNameIssue {
                    hint(
                        Text(issue == .empty ? "agent.name.error.empty" : "agent.name.error.tooLong"),
                        color: .seal700)
                        .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 4)))
                } else {
                    hint(Text("agent.name.hint"))
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: Motion.micro), value: wizard.agentNameIssue == nil)
        }
    }

}

#Preview {
    AgentStepView()
        .environmentObject(WizardState())
        .frame(width: WindowMetrics.width, height: 440)
        .background(Color.parchment50)
}
