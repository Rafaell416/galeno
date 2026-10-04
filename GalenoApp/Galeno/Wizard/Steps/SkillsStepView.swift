import GalenoCore
import SwiftUI

/// Paso 6: dos niveles en una sola pantalla (`docs/03` §3): las skills nuestras, todas marcadas de
/// fábrica, y las curadas de la comunidad, cada una con crédito a su autor y enlace a su GitHub.
/// "Trae la tuya" no existe en v0.0.1: no hay ninguna puerta por la que entre código sin revisar.
struct SkillsStepView: View {
    @EnvironmentObject private var wizard: WizardState

    var body: some View {
        StepScaffold(step: .skills, summarySize: 15, titleGap: 6, contentGap: 12) {
            switch wizard.skillCatalog {
            case .notLoaded:
                InkSpinner(size: 16)
            case .failed:
                NoticePanel(kind: .seal) {
                    Text("skills.failed")
                        .font(Typo.display(20))
                        .foregroundStyle(Color.ink900)
                    Button("skills.retry") { wizard.loadSkillCatalog() }
                        .buttonStyle(.inkInline)
                        .padding(.top, 4)
                }
            case .loaded(let catalog):
                SkillsContent(catalog: catalog)
            }
        }
        .onAppear { if wizard.skillCatalog == .notLoaded { wizard.loadSkillCatalog() } }
    }
}

private struct SkillsContent: View {
    @EnvironmentObject private var wizard: WizardState
    let catalog: SkillCatalog
    @Environment(\.galenoReduceMotion) private var reduceMotion
    /// La cascada en curso: pulsar otra vez la reemplaza, nada espera a que termine.
    @State private var cascade: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ours
            if !catalog.curated.isEmpty { curated }
        }
    }

    // MARK: Las nuestras

    private var ours: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                (Text("skills.ours.title").font(Typo.display(20)).foregroundColor(Color.ink900)
                    + Text(verbatim: "  ")
                    + Text("skills.ours.count \(selectedCount) \(catalog.galeno.count)")
                    .font(Typo.text(14)).foregroundColor(Color.ink500))
                    // El contador cuenta mientras los checks van cayendo.
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: Motion.micro), value: selectedCount)
                Spacer()
                Button("skills.all") { setAll(true) }
                Button("skills.none") { setAll(false) }
            }
            .buttonStyle(LinkTextStyle())
            .padding(.bottom, 4)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.parchment300).frame(height: 1) }
            .padding(.bottom, 8)

            // Tres columnas, como en el diseño. Si hay más de tres grupos, los que sobran van debajo
            // del que deja la columna más corta. La descripción de cada skill va como ayuda al
            // pasar el puntero.
            HStack(alignment: .top, spacing: 20) {
                ForEach(Array(columns.enumerated()), id: \.offset) { _, groups in
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(groups) { group in
                            VStack(alignment: .leading, spacing: 0) {
                                SmallCapsText(string: group.name.text(in: wizard.language), size: 12, tracking: 0.12)
                                    .foregroundStyle(Color.ink500)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.bottom, 4)
                                ForEach(catalog.skills(in: group)) { skill in
                                    OurSkillRow(skill: skill)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
    }

    /// Los grupos repartidos en tres columnas, en orden: cada uno va a la columna con menos skills.
    private var columns: [[SkillGroup]] {
        var columns: [[SkillGroup]] = [[], [], []]
        var heights = [0, 0, 0]
        for group in catalog.groups {
            let count = catalog.skills(in: group).count
            guard count > 0 else { continue }
            let target = heights.enumerated().min { $0.element < $1.element }?.offset ?? 0
            columns[target].append(group)
            heights[target] += count + 1
        }
        return columns
    }

    private var selectedCount: Int {
        catalog.galeno.filter { wizard.isSkillSelected($0.id, source: .galeno) }.count
    }

    /// Marca o desmarca todas en cascada de 30 ms, en el orden en que se ven (columna a columna).
    /// Con «Reducir movimiento» cambian todas a la vez.
    private func setAll(_ on: Bool) {
        let ordered = columns.flatMap { $0 }.flatMap { catalog.skills(in: $0) }
        let pending = ordered.filter { wizard.isSkillSelected($0.id, source: .galeno) != on }
        cascade?.cancel()
        if reduceMotion || pending.count < 2 {
            for skill in pending { wizard.toggleSkill(skill.id, source: .galeno) }
            return
        }
        cascade = Task {
            for skill in pending {
                if Task.isCancelled { return }
                wizard.toggleSkill(skill.id, source: .galeno)
                try? await Task.sleep(for: .milliseconds(30))
            }
        }
    }

    // MARK: Las curadas

    private var curated: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("skills.curated.title")
                    .font(Typo.display(18))
                    .foregroundStyle(Color.ink900)
                Text("skills.curated.hint")
                    .font(Typo.text(12.5))
                    .foregroundStyle(Color.ink500)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 200, alignment: .leading)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: 2),
                alignment: .leading, spacing: 4
            ) {
                ForEach(catalog.curated) { skill in
                    CuratedSkillRow(skill: skill)
                }
            }
        }
        .padding(.top, 8)
        .overlay(alignment: .top) { Rectangle().fill(Color.parchment300).frame(height: 1) }
        .padding(.top, 10)
    }
}

/// Un enlace de texto en lacre, subrayado: «Marcar todas», «Cambiar».
struct LinkTextStyle: ButtonStyle {
    var size: CGFloat = 14

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.text(size, .medium))
            .foregroundStyle(Color.seal700)
            .underline()
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

private struct OurSkillRow: View {
    @EnvironmentObject private var wizard: WizardState
    let skill: CatalogSkill
    @State private var hovering = false

    var body: some View {
        let useful = skill.isUseful(with: wizard.connectedTools)
        Toggle(isOn: Binding(
            get: { wizard.isSkillSelected(skill.id, source: .galeno) },
            set: { _ in wizard.toggleSkill(skill.id, source: .galeno) })
        ) {
            VStack(alignment: .leading, spacing: 0) {
                (Text(verbatim: skill.name.text(in: wizard.language))
                    .font(Typo.text(13.5, .medium)).foregroundColor(Color.ink900)
                    + Text(verbatim: " /" + skill.id)
                    .font(.system(size: 11, design: .monospaced)).foregroundColor(hovering ? Color.ink900 : Color.ink500))
                    .fixedSize(horizontal: false, vertical: true)
                if !useful {
                    let names = skill.needsAny.map { $0.displayName(in: wizard.language) }.joined(separator: " / ")
                    Text("skills.needs \(names)")
                        .font(Typo.text(12))
                        .foregroundStyle(Color.ochre700)
                        // Al pasar el puntero se subraya lo que falta, sin tooltip del sistema.
                        .underline(hovering, color: Color.ochre700)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.inkCheckbox)
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: Motion.micro), value: hovering)
        .help(useful ? skill.summary.text(in: wizard.language) : "")
        .opacity(useful ? 1 : 0.5)
    }
}

/// Una skill de la comunidad: siempre con crédito y enlace a su autor. Sin su contenido todavía
/// (`available` en falso) se muestra con «Próximamente» y no se puede marcar.
private struct CuratedSkillRow: View {
    @EnvironmentObject private var wizard: WizardState
    let skill: CuratedSkill
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if skill.available {
                Toggle(isOn: Binding(
                    get: { wizard.isSkillSelected(skill.id, source: .curated) },
                    set: { _ in wizard.toggleSkill(skill.id, source: .curated) })
                ) { EmptyView() }
                .toggleStyle(.inkCheckbox)
                .fixedSize()
                .accessibilityLabel(Text(verbatim: skill.name.text(in: wizard.language)))
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: skill.name.text(in: wizard.language))
                        .font(Typo.text(13, .medium))
                        .foregroundStyle(Color.ink900)
                    if !skill.available {
                        SmallCapsLabel("skills.curated.soon", size: 11, tracking: 0.08)
                            .foregroundStyle(Color.ink500)
                            .padding(.horizontal, 5)
                            .overlay(Rectangle().strokeBorder(Color.parchment400, lineWidth: 1))
                    }
                }
                // El crédito es también el enlace al repositorio del autor.
                Link(destination: skill.sourceURL) {
                    Text("skills.curated.credit \(skill.author) \(skill.license)")
                        .font(Typo.text(12, italic: true))
                        // Al pasar el puntero el crédito pasa a `ink-700` y se subraya con firmeza.
                        .foregroundStyle(hovering ? Color.ink700 : Color.ink500)
                        .underline(true, color: hovering ? Color.ink700 : Color.parchment400)
                }
                .help(Text("skills.curated.view"))
            }
        }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: Motion.micro), value: hovering)
        .help(skill.summary.text(in: wizard.language))
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
