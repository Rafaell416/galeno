import SwiftUI

/// Paso 3: el agente (B1). Un nombre, el rol (en v0.0.1 solo Product Manager) y una línea sobre el
/// proyecto; a la derecha, su ex libris, que se va llenando con lo que se escribe.
struct AgentStepView: View {
    @EnvironmentObject private var wizard: WizardState
    @Environment(\.locale) private var locale
    /// El error del nombre solo se muestra después de pasar por el campo: no se
    /// le grita a alguien que todavía no empezó a escribir.
    @State private var nameWasEdited = false
    @State private var showsContext = false
    @Environment(\.galenoReduceMotion) private var reduceMotion

    private var trimmedName: String { wizard.agentName.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        StepScaffold(step: .agent, summarySize: 16, titleGap: 8, contentGap: 18) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 28) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 24) {
                            nameField.frame(maxWidth: .infinity, alignment: .leading)
                            roleField.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        projectField
                    }
                    SealView(name: trimmedName)
                        .padding(.top, 26)
                        .frame(width: 150)
                }

                // Cómo le va a hablar: ponerle voz al nombre antes de seguir.
                // Con el nombre vacío queda un hueco subrayado donde iría; con nombre, el texto se actualiza
                // por carácter, sin parpadear, y el color pasa de gris a tinta en 150 ms.
                Text(previewPhrase)
                .font(Typo.display(18, italic: true))
                .foregroundStyle(trimmedName.isEmpty ? Color.ink500 : Color.ink700)
                .animation(.easeOut(duration: Motion.micro), value: trimmedName.isEmpty)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
                .overlay(alignment: .top) { Rectangle().fill(Color.parchment300).frame(height: 1) }
                .padding(.top, 14)
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

    private var counterColor: Color {
        let count = wizard.projectDescription.count
        if count >= WizardState.maxProjectDescriptionLength { return .seal700 }
        return count >= 120 ? .ochre700 : .ink500
    }

    private var roleField: some View {
        VStack(alignment: .leading, spacing: 0) {
            label("agent.role.label")
            // Un solo rol en v0.0.1: se muestra, no se elige.
            Text("agent.role.productManager")
                .font(Typo.text(17))
                .foregroundStyle(Color.ink900)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .overlay(alignment: .bottom) { Rectangle().fill(Color.parchment400).frame(height: 1.5) }
                // Fijo a propósito: sin hover ni cursor de texto, para que se note que no se edita.
                .allowsHitTesting(false)
            hint(Text("agent.role.hint"))
        }
    }

    private var projectField: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Junto al rótulo, para quien ya habló de este proyecto en claude.ai: traer ese contexto
            // (ver `ContextSheet`).
            HStack(alignment: .firstTextBaseline) {
                label("agent.project.label")
                Spacer(minLength: Space.s12)
                Button { showsContext = true } label: {
                    if wizard.contextItems.isEmpty {
                        Text("context.link")
                    } else {
                        Text("context.link.count \(wizard.contextItems.count)")
                    }
                }
                // Tinta, no lacre: el acento ya está en el título de esta pantalla.
                .buttonStyle(.plain)
                .font(Typo.text(13, .medium))
                .foregroundStyle(Color.ink700)
                .underline()
            }
            RuleTextField(
                "agent.project.label", text: $wizard.projectDescription, prompt: "agent.project.placeholder",
                font: Typo.text(17), lines: 3
            )
            .onChange(of: wizard.projectDescription) { _, text in
                if text.count > WizardState.maxProjectDescriptionLength {
                    wizard.projectDescription = String(text.prefix(WizardState.maxProjectDescriptionLength))
                }
            }
            HStack(alignment: .firstTextBaseline) {
                hint(trimmedName.isEmpty ? Text("agent.project.hint") : Text("agent.project.hint \(trimmedName)"))
                Spacer()
                // Desde 120 pasa a ocre; en el tope, a lacre, y el campo deja de aceptar.
                Text(verbatim: "\(wizard.projectDescription.count)/\(WizardState.maxProjectDescriptionLength)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(counterColor)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.1), value: wizard.projectDescription.count)
                    .padding(.top, 6)
            }
        }
        .sheet(isPresented: $showsContext) { ContextSheet() }
    }
}

#Preview {
    AgentStepView()
        .environmentObject(WizardState())
        .frame(width: WindowMetrics.width, height: 440)
        .background(Color.parchment50)
}
