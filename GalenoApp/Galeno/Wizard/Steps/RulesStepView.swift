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
    private var hasNever: Bool { wizard.whatsAppIsReadOnly }

    var body: some View {
        StepScaffold(step: .rules, summarySize: 15, titleGap: 6, contentGap: 14) {
            VStack(alignment: .leading, spacing: 0) {
                if hasNever {
                    PactRow(label: "rules.never.label", accent: true, heavy: true) { neverContent }
                }
                PactRow(label: "rules.always.label", accent: true, heavy: !hasNever) { alwaysContent }
                if !readsFreely.isEmpty {
                    PactRow(label: "rules.reads.label", accent: false, heavy: false) { readsContent }
                }
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

    /// Lo que nunca pasa en un agente que tiene WhatsApp solo para leer (el envío sin aceptar).
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
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Las herramientas que el agente lee sin pedir permiso, según las reglas que el motor va a escribir.
    private var readsFreely: [Tool] { wizard.makeConfig().toolsReadingWithoutAsking }

    /// Lo que no pregunta: leer lo conectado (petición de Rafa, 4 oct 2026: que las reglas de lectura se vean).
    private var readsContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            lead("rules.reads.title", Text("rules.reads.body \(agentName)"))
            Text("rules.external.tools \(readsFreely.map { $0.displayName(in: wizard.language) }.joined(separator: ", "))")
                .font(Typo.text(13))
                .foregroundStyle(Color.ink500)
                .fixedSize(horizontal: false, vertical: true)
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
                        WriteRuleRow(
                            write: write, agentName: agentName, policy: wizard.policy(for: write),
                            onChange: { wizard.setPolicy($0, for: write) })
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

/// Una escritura que se puede decidir: qué hace, **qué significa lo elegido** (una frase que siempre está a la vista y
/// cambia con la opción) y dos opciones con nombre propio, una bajo la otra. Reemplaza al selector «Preguntarme /
/// Sin preguntar» (6 oct 2026, petición de Rafa: no se entendía qué quería decir cada lado ni cuál venía puesto).
///
/// También la usa el detalle del agente (`AgentDetailView`), que aplica el cambio al momento.
struct WriteRuleRow: View {
    @Environment(\.galenoReduceMotion) private var reduceMotion
    let write: InternalWrite
    let agentName: String
    let policy: ApprovalPolicy
    let onChange: (ApprovalPolicy) -> Void

    private var toolName: String { write.toolDisplayName }

    var body: some View {
        HStack(alignment: .top, spacing: Space.s16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey("rules.write." + write.rawValue))
                    .font(Typo.list)
                    .foregroundStyle(Color.ink900)
                // Lo que pasa con lo elegido, siempre: sin esto había que adivinarlo.
                Group {
                    // De fábrica las escrituras internas van sin preguntar: la frase no alarma, solo dice lo que pasa.
                    if policy == .allow {
                        Text("rules.allowNote \(agentName) \(toolName)").foregroundStyle(Color.ink700)
                    } else {
                        Text("rules.askNote \(agentName) \(toolName)").foregroundStyle(Color.ink500)
                    }
                }
                .id(policy)
                .transition(.opacity)
                .font(Typo.text(13))
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 6) {
                PolicyOption(title: "rules.policy.ask", isOn: policy == .ask) { onChange(.ask) }
                PolicyOption(title: "rules.policy.allow", isOn: policy == .allow) { onChange(.allow) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(LocalizedStringKey("rules.write." + write.rawValue)))
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: policy)
    }
}

/// Una de las dos opciones: un círculo de 14 pt —relleno de tinta si es la elegida— y su nombre. Se elige entre dos, y
/// el círculo lo dice sin explicación.
private struct PolicyOption: View {
    let title: LocalizedStringKey
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .strokeBorder(isOn ? Color.ink900 : Color.ink700, lineWidth: 1.5)
                    .background(Circle().fill(isOn ? Color.ink900 : Color.clear).padding(4))
                    .frame(width: 16, height: 16)
                Text(title)
                    .font(Typo.text(14, isOn ? .medium : .regular))
                    .foregroundStyle(isOn ? Color.ink900 : Color.ink700)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
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
