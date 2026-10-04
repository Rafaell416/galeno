import GalenoCore
import SwiftUI

/// Paso 8: qué puede hacer el agente sin preguntar (`docs/03` §3).
///
/// Lo que sale hacia otras personas (un mensaje a Slack, un correo) **siempre** pide aprobación y
/// no se puede cambiar: `SendingRules` no tiene forma de expresar lo contrario. Lo único que se
/// decide aquí son las escrituras dentro del mundo del propio usuario.
struct RulesStepView: View {
    @EnvironmentObject private var wizard: WizardState

    var body: some View {
        StepScaffold(step: .rules) {
            VStack(alignment: .leading, spacing: Space.s16) {
                externalPanel
                internalSection
                Label("rules.memory", systemImage: "folder")
                    .font(.galenoCaption)
                    .foregroundStyle(Color.ink700)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Lo fijo: nada externo sin tu aprobación.
    private var externalPanel: some View {
        NoticePanel(kind: .moss) {
            Label {
                Text("rules.external.title")
                    .font(.galenoBody.weight(.semibold))
                    .foregroundStyle(Color.ink900)
            } icon: {
                Image(systemName: "lock.fill").foregroundStyle(Color.moss700)
            }
            Text("rules.external.body")
                .font(.galenoBody)
                .foregroundStyle(Color.ink700)
                .fixedSize(horizontal: false, vertical: true)
            let names = wizard.externalSendTools.map { $0.displayName(in: wizard.language) }
            if !names.isEmpty {
                Text("rules.external.tools \(names.joined(separator: ", "))")
                    .font(.galenoCaption)
                    .foregroundStyle(Color.ink500)
            }
            if wizard.connectedTools.contains(.whatsapp) {
                Text("rules.whatsapp")
                    .font(.galenoCaption)
                    .foregroundStyle(Color.ink500)
            }
        }
    }

    /// Lo que se puede decidir: crear y editar dentro de las herramientas del usuario.
    @ViewBuilder
    private var internalSection: some View {
        let writes = wizard.configurableWrites
        VStack(alignment: .leading, spacing: Space.s12) {
            Text("rules.internal.title")
                .font(.galenoBody.weight(.semibold))
                .foregroundStyle(Color.ink900)
            if writes.isEmpty {
                Text("rules.none")
                    .font(.galenoBody)
                    .foregroundStyle(Color.ink700)
            } else {
                Text("rules.internal.hint")
                    .font(.galenoCaption)
                    .foregroundStyle(Color.ink700)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(writes, id: \.self) { write in
                    WriteRuleRow(write: write)
                }
            }
        }
    }
}

private struct WriteRuleRow: View {
    @EnvironmentObject private var wizard: WizardState
    let write: InternalWrite

    var body: some View {
        HStack {
            Text(LocalizedStringKey("rules.write." + write.rawValue))
                .font(.galenoBody)
                .foregroundStyle(Color.ink900)
            Spacer()
            Picker(
                LocalizedStringKey("rules.write." + write.rawValue),
                selection: Binding(
                    get: { wizard.policy(for: write) },
                    set: { wizard.setPolicy($0, for: write) })
            ) {
                Text("rules.policy.ask").tag(ApprovalPolicy.ask)
                Text("rules.policy.allow").tag(ApprovalPolicy.allow)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 240)
        }
        .padding(Space.s12)
        .background(Color.parchment100, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.parchment300, lineWidth: 1))
    }
}

#Preview {
    let state = WizardState()
    state.toggle(.slack)
    state.toggle(.notion)
    return RulesStepView()
        .environmentObject(state)
        .frame(width: WindowMetrics.width, height: 520)
        .background(Color.parchment50)
}
