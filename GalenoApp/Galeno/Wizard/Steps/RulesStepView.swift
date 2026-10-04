import GalenoCore
import SwiftUI

/// Paso 7: el pacto con el agente (`docs/03` §3), como una tabla a filetes (B1).
///
/// Lo que sale hacia otras personas (un mensaje a Slack, un correo) **siempre** pide aprobación y
/// no se puede cambiar: `SendingRules` no tiene forma de expresar lo contrario. Lo único que se
/// decide aquí son las escrituras dentro del mundo del propio usuario.
struct RulesStepView: View {
    @EnvironmentObject private var wizard: WizardState
    @Environment(\.locale) private var locale

    private var agentName: String { wizard.agentName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasNever: Bool { wizard.connectedTools.contains(.whatsapp) }

    var body: some View {
        StepScaffold(step: .rules, summarySize: 15, titleGap: 6, contentGap: 14) {
            VStack(alignment: .leading, spacing: 0) {
                if hasNever {
                    PactRow(label: "rules.never.label", accent: true, heavy: true) { neverContent }
                }
                PactRow(label: "rules.always.label", accent: true, heavy: !hasNever) { alwaysContent }
                PactRow(label: "rules.you.label", accent: false, heavy: false) { youContent }
            }
        }
    }

    private func lead(_ title: LocalizedStringKey, _ body: Text, bodyColor: Color = .ink900) -> some View {
        (Text(title).font(Typo.text(15, .semibold)).foregroundColor(Color.ink900)
            + Text(verbatim: ". ").font(Typo.text(15, .semibold)).foregroundColor(Color.ink900)
            + body.foregroundColor(bodyColor))
            .font(Typo.list)
            .lineSpacing(1.5)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Lo que nunca pasa: WhatsApp no tiene código de envío.
    private var neverContent: some View {
        lead("rules.never.title", Text("rules.never.body \(agentName)"))
    }

    /// Lo fijo: nada externo sin tu aprobación.
    private var alwaysContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            lead("rules.external.title", Text("rules.external.body"))
            let names = wizard.externalSendTools.map { $0.displayName(in: wizard.language) }
            if !names.isEmpty {
                Text("rules.external.tools \(names.joined(separator: ", "))")
                    .font(Typo.text(13))
                    .foregroundStyle(Color.ink500)
            }
        }
    }

    /// Lo que se puede decidir: crear y editar dentro de las herramientas del usuario.
    @ViewBuilder
    private var youContent: some View {
        let writes = wizard.configurableWrites
        VStack(alignment: .leading, spacing: 0) {
            lead(
                "rules.internal.title",
                Text(writes.isEmpty ? "rules.none" : "rules.internal.hint"), bodyColor: .ink700)
            if !writes.isEmpty {
                VStack(spacing: 8) {
                    ForEach(writes, id: \.self) { write in
                        WriteRuleRow(write: write)
                    }
                }
                .padding(.top, 10)
            }
            Text("rules.memory")
                .font(Typo.text(13))
                .foregroundStyle(Color.ink500)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
                // Entra la última, 240 ms después del resto.
                .appearing(after: 0.24)
        }
    }
}

/// Una fila de la tabla del pacto: el rótulo a la izquierda (110 pt) y el contenido a la derecha.
/// La primera lleva el filete grueso de tinta; las demás, uno fino.
private struct PactRow<Content: View>: View {
    let label: String
    let accent: Bool
    let heavy: Bool
    @ViewBuilder var content: Content
    @Environment(\.locale) private var locale

    var body: some View {
        // Cada columna lleva su propio filete: entre el rótulo y el contenido queda un claro.
        HStack(alignment: .top, spacing: 20) {
            SmallCapsText(string: Localized.string(label, locale: locale), size: 13, tracking: 0.12)
                .foregroundStyle(accent ? Color.seal700 : Color.ink700)
                .padding(.vertical, 10)
                .frame(width: 110, alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .top)
                .overlay(alignment: .top) { rule }
            content
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) { rule }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

extension PactRow {
    fileprivate var rule: some View {
        Rectangle()
            .fill(heavy ? Color.ink900 : Color.parchment300)
            .frame(height: heavy ? 1.5 : 1)
    }
}

extension InternalWrite {
    /// El nombre de la herramienta donde escribe (los nombres propios no se traducen).
    var toolDisplayName: String {
        switch self {
        case .notion: "Notion"
        case .jira: "Jira"
        case .googleDocs: "Google Docs"
        case .googleSheets: "Google Sheets"
        case .claudeDesign: "Claude Design"
        }
    }
}

private struct WriteRuleRow: View {
    @EnvironmentObject private var wizard: WizardState
    let write: InternalWrite
    /// Al elegir «Sin preguntar» se dice, un momento, qué significa.
    @State private var showsNote = false

    private var toolName: String { write.toolDisplayName }

    var body: some View {
        HStack(alignment: .center, spacing: Space.s12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(LocalizedStringKey("rules.write." + write.rawValue))
                    .font(Typo.list)
                    .foregroundStyle(Color.ink900)
                if showsNote {
                    Text("rules.allowNote \(wizard.agentName.trimmingCharacters(in: .whitespacesAndNewlines)) \(toolName)")
                        .font(Typo.text(13))
                        .foregroundStyle(Color.seal700)
                        .transition(.pageTurn)
                }
            }
            Spacer(minLength: 0)
            InkSegmented(
                selection: Binding(
                    get: { wizard.policy(for: write) },
                    set: { policy in
                        wizard.setPolicy(policy, for: write)
                        showsNote = policy == .allow
                    }),
                options: [ApprovalPolicy.ask, ApprovalPolicy.allow], accented: [.allow]
            ) { policy in
                Text(policy == .ask ? "rules.policy.ask" : "rules.policy.allow")
            }
            .accessibilityLabel(Text(LocalizedStringKey("rules.write." + write.rawValue)))
        }
        .animation(.pageTurn, value: showsNote)
        .task(id: showsNote) {
            guard showsNote else { return }
            try? await Task.sleep(for: .seconds(3))
            showsNote = false
        }
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
