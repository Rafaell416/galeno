import GalenoCore
import SwiftUI

/// Paso 7: dos niveles en una sola pantalla (`docs/03` §3): las skills nuestras, todas marcadas de
/// fábrica, y las curadas de la comunidad, cada una con crédito a su autor y enlace a su GitHub.
/// "Trae la tuya" no existe en v0.0.1: no hay ninguna puerta por la que entre código sin revisar.
struct SkillsStepView: View {
    @EnvironmentObject private var wizard: WizardState

    var body: some View {
        StepScaffold(step: .skills) {
            switch wizard.skillCatalog {
            case .notLoaded:
                ProgressView().controlSize(.small)
            case .failed:
                NoticePanel(kind: .seal) {
                    Text("skills.failed")
                        .font(.galenoBody.weight(.semibold))
                        .foregroundStyle(Color.ink900)
                    Button("skills.retry") { wizard.loadSkillCatalog() }
                        .buttonStyle(.bordered)
                }
            case .loaded(let catalog):
                SkillsContent(catalog: catalog)
            }
        }
        .tint(Color.moss700)
        .onAppear { if wizard.skillCatalog == .notLoaded { wizard.loadSkillCatalog() } }
    }
}

private struct SkillsContent: View {
    @EnvironmentObject private var wizard: WizardState
    let catalog: SkillCatalog

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s24) {
            ours
            if !catalog.curated.isEmpty { curated }
        }
    }

    // MARK: Las nuestras

    private var ours: some View {
        VStack(alignment: .leading, spacing: Space.s12) {
            HStack(alignment: .firstTextBaseline) {
                Text("skills.ours.title")
                    .font(.galenoBody.weight(.semibold))
                    .foregroundStyle(Color.ink900)
                Text("skills.ours.count \(selectedCount) \(catalog.galeno.count)")
                    .font(.galenoCaption)
                    .foregroundStyle(Color.ink500)
                Spacer()
                Button("skills.all") { setAll(true) }
                Button("skills.none") { setAll(false) }
            }
            .buttonStyle(.link)
            .font(.galenoCaption)
            .foregroundStyle(Color.ink700)

            Text("skills.ours.hint")
                .font(.galenoCaption)
                .foregroundStyle(Color.ink700)

            ForEach(catalog.groups) { group in
                let skills = catalog.skills(in: group)
                if !skills.isEmpty {
                    VStack(alignment: .leading, spacing: Space.s8) {
                        Text(verbatim: group.name.text(in: wizard.language))
                            .font(.galenoCaption.smallCaps())
                            .kerning(1)
                            .foregroundStyle(Color.ink500)
                        ForEach(skills) { skill in
                            OurSkillRow(skill: skill)
                        }
                    }
                }
            }
        }
    }

    private var selectedCount: Int {
        catalog.galeno.filter { wizard.isSkillSelected($0.id, source: .galeno) }.count
    }

    private func setAll(_ on: Bool) {
        for skill in catalog.galeno where wizard.isSkillSelected(skill.id, source: .galeno) != on {
            wizard.toggleSkill(skill.id, source: .galeno)
        }
    }

    // MARK: Las curadas

    private var curated: some View {
        VStack(alignment: .leading, spacing: Space.s12) {
            Text("skills.curated.title")
                .font(.galenoBody.weight(.semibold))
                .foregroundStyle(Color.ink900)
            Text("skills.curated.hint")
                .font(.galenoCaption)
                .foregroundStyle(Color.ink700)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(catalog.curated) { skill in
                CuratedSkillRow(skill: skill)
            }
        }
    }
}

private struct OurSkillRow: View {
    @EnvironmentObject private var wizard: WizardState
    let skill: CatalogSkill

    var body: some View {
        let useful = skill.isUseful(with: wizard.connectedTools)
        Toggle(isOn: Binding(
            get: { wizard.isSkillSelected(skill.id, source: .galeno) },
            set: { _ in wizard.toggleSkill(skill.id, source: .galeno) })
        ) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.s8) {
                    Text(verbatim: skill.name.text(in: wizard.language))
                        .font(.galenoBody.weight(.medium))
                        .foregroundStyle(Color.ink900)
                    Text(verbatim: "/" + skill.id)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color.ink500)
                }
                Text(verbatim: skill.summary.text(in: wizard.language))
                    .font(.galenoCaption)
                    .foregroundStyle(Color.ink700)
                    .fixedSize(horizontal: false, vertical: true)
                if !useful {
                    let names = skill.needsAny.map { $0.displayName(in: wizard.language) }.joined(separator: " / ")
                    Text("skills.needs \(names)")
                        .font(.galenoCaption)
                        .foregroundStyle(Color.ink500)
                }
            }
        }
        .toggleStyle(.checkbox)
        .opacity(useful ? 1 : 0.7)
    }
}

/// Una skill de la comunidad: siempre con crédito y enlace. Sin su contenido todavía (`available`
/// en falso) se muestra pero no se puede marcar.
private struct CuratedSkillRow: View {
    @EnvironmentObject private var wizard: WizardState
    let skill: CuratedSkill

    var body: some View {
        Toggle(isOn: Binding(
            get: { wizard.isSkillSelected(skill.id, source: .curated) },
            set: { _ in wizard.toggleSkill(skill.id, source: .curated) })
        ) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.s8) {
                    Text(verbatim: skill.name.text(in: wizard.language))
                        .font(.galenoBody.weight(.medium))
                        .foregroundStyle(Color.ink900)
                    if !skill.available {
                        Text("skills.curated.soon")
                            .font(.galenoCaption)
                            .foregroundStyle(Color.ink500)
                            .padding(.horizontal, Space.s8)
                            .overlay(Capsule().stroke(Color.parchment300, lineWidth: 1))
                    }
                }
                Text(verbatim: skill.summary.text(in: wizard.language))
                    .font(.galenoCaption)
                    .foregroundStyle(Color.ink700)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Space.s8) {
                    Text("skills.curated.credit \(skill.author) \(skill.license)")
                        .font(.galenoCaption)
                        .foregroundStyle(Color.ink500)
                    Link("skills.curated.view", destination: skill.sourceURL)
                        .font(.galenoCaption)
                }
            }
        }
        .toggleStyle(.checkbox)
        .disabled(!skill.available)
        .opacity(skill.available ? 1 : 0.75)
    }
}

#Preview {
    let state = WizardState()
    state.setConnectionStatus(.slack, .connected)
    return SkillsStepView()
        .environmentObject(state)
        .frame(width: WindowMetrics.width, height: 520)
        .background(Color.parchment50)
}
