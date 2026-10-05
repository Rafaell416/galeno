import GalenoCore
import SwiftUI

/// Paso 8: todo lo que se decidió, en una página (B1). Nada se escribe hasta pulsar «Escribir a …»;
/// cada bloque lleva un «Cambiar» que vuelve a su paso.
struct ReviewStepView: View {
    @EnvironmentObject private var wizard: WizardState
    @Environment(\.locale) private var locale

    private var agentName: String { wizard.agentName.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        StepScaffold(step: .review, summarySize: 15, titleGap: 6, contentGap: 14) {
            VStack(spacing: 12) {
                // «Gestionar»: Galeno es el dueño de la config. Se dice antes de guardar, no después.
                if wizard.mode == .edit {
                    NoticePanel(kind: .ochre) {
                        Text("review.edit.warning \(agentName)")
                            .font(Typo.text(14))
                            .foregroundStyle(Color.ink900)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack(alignment: .top, spacing: 20) {
                    toolsCard
                    skillsCard
                }
                rulesCard
            }
        }
        .onAppear { if wizard.skillCatalog == .notLoaded { wizard.loadSkillCatalog() } }
    }

    // MARK: Herramientas

    private var laterTools: [Tool] {
        wizard.selectedTools.filter { !wizard.connectedTools.contains($0) && $0 != .googleMeet }
    }

    private var toolsCard: some View {
        ReviewCard(title: Localized.string("review.tools", locale: locale), accent: false) {
            wizard.jump(to: .tools)
        } content: {
            FlowLayout(spacing: 6, lineSpacing: 6, itemSpacing: 14) {
                ForEach(wizard.connectedTools) { tool in
                    HStack(spacing: 6) {
                        ToolIcon(tool: tool, size: 16, color: Color.ink700)
                        Text(verbatim: tool.displayName(in: wizard.language))
                            .font(Typo.list)
                            .foregroundStyle(Color.ink900)
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 6)
            let later = laterTools.map { $0.displayName(in: wizard.language) }.joined(separator: ", ")
            (later.isEmpty
                ? Text("review.later \(Localized.string("review.none", locale: locale))")
                : Text("review.later \(later)"))
                .font(Typo.text(13))
                .foregroundStyle(Color.ink500)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Skills

    private var selectedSkillNames: [String] {
        guard case .loaded(let catalog) = wizard.skillCatalog else { return [] }
        return catalog.cards
            .filter { wizard.isSkillSelected($0.id, source: $0.source) }
            .map { $0.name.text(in: wizard.language) }
    }

    private var skillsCard: some View {
        let names = selectedSkillNames
        let total: Int = {
            if case .loaded(let catalog) = wizard.skillCatalog { return catalog.cards.count }
            return names.count
        }()
        // Al crear un agente las skills las trae el rol: se cambia el rol, no la lista. En «Gestionar» sí se editan.
        let creating = wizard.mode != .edit
        let title =
            creating
            ? Localized.string("review.role", locale: locale) + " · " + wizard.role.title(in: wizard.language) + " · "
                + Localized.string("review.role.skills %lld", names.count, locale: locale)
            : Localized.string("review.skills", locale: locale) + " · "
                + Localized.string("skills.ours.count %lld %lld", names.count, total, locale: locale)
        return ReviewCard(title: title, accent: false) {
            wizard.jump(to: creating ? .role : .skills)
        } content: {
            Text(verbatim: names.prefix(6).joined(separator: " · ") + (names.count > 6 ? " …" : ""))
                .font(Typo.list)
                .lineSpacing(1.5)
                .foregroundStyle(Color.ink900)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
    }

    // MARK: Reglas

    private var rulesCard: some View {
        ReviewCard(title: Localized.string("review.rules", locale: locale), accent: true) {
            wizard.jump(to: .rules)
        } content: {
            VStack(alignment: .leading, spacing: 3) {
                if wizard.connectedTools.contains(.whatsapp) {
                    bullet(Text("rules.never.label") + Text(verbatim: ": ") + Text("rules.never.title"))
                }
                bullet(Text("rules.always.label") + Text(verbatim: ": ") + Text("rules.external.title"))
                ForEach(wizard.configurableWrites, id: \.self) { write in
                    bullet(
                        Text(LocalizedStringKey("rules.write." + write.rawValue)) + Text(verbatim: ": ")
                            + Text(wizard.policy(for: write) == .allow ? "rules.policy.allow" : "rules.policy.ask"))
                }
            }
            .padding(.top, 8)
        }
    }

    private func bullet(_ text: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(verbatim: "·").foregroundStyle(Color.ink500).frame(width: 14, alignment: .leading)
            text.foregroundStyle(Color.ink900).fixedSize(horizontal: false, vertical: true)
        }
        .font(Typo.list)
    }
}

/// Una tarjeta de «Revisión»: rótulo en versalitas, «Cambiar» en lacre y el contenido debajo.
/// La de las reglas va destacada: filete de 1,5 pt en tinta, fondo de papel y rótulo en lacre.
private struct ReviewCard<Content: View>: View {
    let title: String
    let accent: Bool
    let onChange: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                SmallCapsText(string: title, size: 12, tracking: 0.12)
                    .foregroundStyle(accent ? Color.seal700 : Color.ink500)
                Spacer()
                Button("review.change", action: onChange)
                    .buttonStyle(LinkTextStyle())
            }
            content
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(accent ? Color.parchment100 : Color.clear, in: RoundedRectangle(cornerRadius: Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card)
                .strokeBorder(accent ? Color.ink900 : Color.parchment300, lineWidth: accent ? 1.5 : 1)
        )
    }
}

#Preview {
    let state = WizardState()
    state.agentName = "Hera"
    state.toggle(.slack)
    state.toggle(.notion)
    return ReviewStepView()
        .environmentObject(state)
        .frame(width: WindowMetrics.width, height: 480)
        .background(Color.parchment50)
}
