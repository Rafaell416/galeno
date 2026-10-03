import SwiftUI

/// Paso 3: el agente (`docs/03` §3). Un nombre, el rol (en v0.0.1 solo Product
/// Manager) y una línea sobre el proyecto, que el agente completa en su primera
/// sesión.
struct AgentStepView: View {
    private enum Field { case name, project }

    @EnvironmentObject private var wizard: WizardState
    @FocusState private var focus: Field?
    /// El error del nombre solo se muestra después de pasar por el campo: no se
    /// le grita a alguien que todavía no empezó a escribir.
    @State private var nameWasEdited = false

    var body: some View {
        StepScaffold(step: .agent) {
            VStack(alignment: .leading, spacing: Space.s24) {
                nameField
                roleRow
                projectField
                if wizard.agentNameIssue == nil {
                    DopamineLine(key: "dopamine.agent")
                }
            }
        }
        .onAppear { focus = .name }
    }

    // MARK: Campos

    private var nameField: some View {
        VStack(alignment: .leading, spacing: Space.s8) {
            FieldLabel("agent.name.label")
            TextField("agent.name.label", text: $wizard.agentName, prompt: Text("agent.name.placeholder"))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .focused($focus, equals: .name)
                .frame(maxWidth: 360)
                .onChange(of: wizard.agentName) { _, name in
                    nameWasEdited = true
                    // Un nombre más largo que el tope no entra: así no hay que explicar nada.
                    if name.count > WizardState.maxAgentNameLength {
                        wizard.agentName = String(name.prefix(WizardState.maxAgentNameLength))
                    }
                }
                .accessibilityLabel(Text("agent.name.label"))
            if nameWasEdited, let issue = wizard.agentNameIssue {
                HStack(spacing: Space.s4) {
                    Image(systemName: "exclamationmark.circle")
                    Text(issue == .empty ? "agent.name.error.empty" : "agent.name.error.tooLong")
                }
                .font(.galenoCaption)
                .foregroundStyle(Color.seal700)
            }
        }
    }

    private var roleRow: some View {
        VStack(alignment: .leading, spacing: Space.s8) {
            FieldLabel("agent.role.label")
            // Un solo rol en v0.0.1: se muestra, no se elige.
            Text("agent.role.productManager")
                .font(.galenoBody)
                .foregroundStyle(Color.ink700)
                .padding(.horizontal, Space.s12)
                .padding(.vertical, Space.s4)
                .background(Color.parchment100, in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.parchment300, lineWidth: 1))
        }
    }

    private var projectField: some View {
        VStack(alignment: .leading, spacing: Space.s8) {
            FieldLabel("agent.project.label")
            TextField(
                "agent.project.label", text: $wizard.projectDescription,
                prompt: Text("agent.project.placeholder")
            )
            .textFieldStyle(.roundedBorder)
            .labelsHidden()
            .focused($focus, equals: .project)
            .onChange(of: wizard.projectDescription) { _, text in
                if text.count > WizardState.maxProjectDescriptionLength {
                    wizard.projectDescription = String(text.prefix(WizardState.maxProjectDescriptionLength))
                }
            }
            .accessibilityLabel(Text("agent.project.label"))
            HStack {
                Text("agent.project.hint")
                    .font(.galenoCaption)
                    .foregroundStyle(Color.ink700)
                Spacer()
                Text(verbatim: "\(wizard.projectDescription.count)/\(WizardState.maxProjectDescriptionLength)")
                    .font(.galenoCaption)
                    .foregroundStyle(Color.ink500)
                    .monospacedDigit()
            }
        }
    }
}

/// La etiqueta de un campo: versalitas, como los títulos de paso pero más chica.
private struct FieldLabel: View {
    let key: LocalizedStringKey
    init(_ key: LocalizedStringKey) { self.key = key }

    var body: some View {
        Text(key)
            .font(.galenoCaption.smallCaps())
            .kerning(1.2)
            .foregroundStyle(Color.ink700)
    }
}

#Preview {
    AgentStepView()
        .environmentObject(WizardState())
        .frame(width: WindowMetrics.width, height: 440)
        .background(Color.parchment50)
}
