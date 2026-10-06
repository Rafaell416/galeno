import GalenoCore
import SwiftUI

/// Paso 6 (y «Gestionar» → Skills): las skills como cards, en una lista por grupos que se desplaza (`docs/03` §3;
/// diseño «Galeno B1 Skills», variante «scroll»). Se elige de un catálogo común **para este agente**: todas las nuestras vienen marcadas. Al pasar el cursor
/// por una card aparece «Vista previa», que abre una hoja con cómo pedirla, un ejemplo y qué necesita.
/// «Trae la tuya» no existe en v0.0.1: no hay ninguna puerta por la que entre código sin revisar.
struct SkillsStepView: View {
    @EnvironmentObject private var wizard: WizardState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch wizard.skillCatalog {
            case .notLoaded:
                header(catalog: nil)
                InkSpinner(size: 16).padding(.top, 16)
            case .failed:
                header(catalog: nil)
                NoticePanel(kind: .seal) {
                    Text("skills.failed")
                        .font(Typo.display(20))
                        .foregroundStyle(Color.ink900)
                    Button("skills.retry") { wizard.loadSkillCatalog() }
                        .buttonStyle(.inkInline)
                        .padding(.top, 4)
                }
                .padding(.top, 16)
            case .loaded(let catalog):
                SkillsContent(catalog: catalog) { header(catalog: catalog) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, Space.s48)
        .padding(.top, 22)
        .onAppear { if wizard.skillCatalog == .notLoaded { wizard.loadSkillCatalog() } }
        .onDisappear {
            wizard.previewedSkill = nil
            wizard.skillCardHasFocus = false
        }
    }

    /// El título con su punto de lacre —el único de la pantalla— y, a la derecha, lo que vale para todo el
    /// catálogo: cuántas hay marcadas, «Todas» y «Ninguna». Sin catálogo todavía, solo el título.
    @ViewBuilder
    private func header(catalog: SkillCatalog?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            StepTitle(text: Text(WizardStep.skills.title))
                .overlay(alignment: .leading) {
                    if let glyph = WizardStep.skills.glyph {
                        GlyphView(glyph: glyph, size: 22, color: .ink500).offset(x: -33, y: 2)
                    }
                }
            Spacer(minLength: Space.s16)
            if let catalog { SkillsTotals(catalog: catalog) }
        }
    }
}

/// «17 de 17 · Todas · Ninguna»: lo que vale para todo el catálogo.
private struct SkillsTotals: View {
    @EnvironmentObject private var wizard: WizardState
    let catalog: SkillCatalog
    @Environment(\.galenoReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
    /// La cascada en curso: pulsar otra vez la reemplaza, nada espera a que termine.
    @State private var cascade: Task<Void, Never>?

    /// Solo lo que esta pantalla enseña: las skills de los grupos del rol.
    private var visible: [CatalogSkill] { wizard.visibleSkills(in: catalog) }

    private var selectedCount: Int {
        visible.filter { wizard.isSkillSelected($0.id, source: $0.source) }.count
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(verbatim: Localized.string("skills.count %lld %lld", selectedCount, visible.count, locale: locale))
                .font(Typo.text(14))
                .foregroundStyle(Color.ink700)
                // El contador cuenta mientras los checks van cayendo.
                .contentTransition(.numericText())
                .animation(.easeOut(duration: Motion.micro), value: selectedCount)
            Button("skills.all") { setAll(true) }
            Button("skills.none") { setAll(false) }
        }
        .buttonStyle(InkLinkStyle(size: 14))
    }

    /// Marca o desmarca todas en cascada de 30 ms, en el orden del catálogo. Con «Reducir movimiento» cambian
    /// todas a la vez.
    private func setAll(_ on: Bool) {
        let pending = visible.filter { wizard.isSkillSelected($0.id, source: $0.source) != on }
        cascade?.cancel()
        if reduceMotion || pending.count < 2 {
            for skill in pending { wizard.toggleSkill(skill.id, source: skill.source) }
            return
        }
        cascade = Task {
            for skill in pending {
                if Task.isCancelled { return }
                wizard.toggleSkill(skill.id, source: skill.source)
                try? await Task.sleep(for: .milliseconds(30))
            }
        }
    }
}

private struct SkillsContent<Header: View>: View {
    @EnvironmentObject private var wizard: WizardState
    let catalog: SkillCatalog
    @ViewBuilder var header: Header
    @Environment(\.galenoReduceMotion) private var reduceMotion

    /// El foco del teclado: el id de una skill.
    @FocusState private var focused: String?
    private static var columns: Int { 3 }

    /// Los grupos de este agente (los de su rol, más cualquiera con una skill ya marcada), con alguna skill.
    private var groups: [SkillGroup] {
        wizard.visibleSkillGroups(in: catalog).filter { !catalog.skills(in: $0).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            // Todo el catálogo en una sola lista (variante «scroll» del diseño, la que eligió Rafa): el rótulo de
            // cada grupo se queda arriba mientras se desplazan sus cards.
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(groups) { group in
                            Section {
                                grid(for: group)
                                    .padding(.bottom, 14)
                            } header: {
                                groupHeader(group)
                                    .padding(.bottom, 8)
                            }
                        }
                    }
                    .padding(.trailing, 10)  // sitio para la barra de desplazamiento
                    .padding(.bottom, 12)
                }
                .onChange(of: focused) { _, now in
                    wizard.skillCardHasFocus = now != nil
                    // La card con el foco siempre queda a la vista.
                    guard let now else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: Motion.micro)) { proxy.scrollTo(now) }
                }
            }
            .padding(.top, 8)
        }
        .onMoveCommand(perform: move)
    }

    /// El rótulo de un grupo, fijo arriba: su nombre en versalitas y su «marcadas/total».
    private func groupHeader(_ group: SkillGroup) -> some View {
        let skills = catalog.skills(in: group)
        let on = skills.filter { wizard.isSkillSelected($0.id, source: $0.source) }.count
        return HStack(alignment: .firstTextBaseline) {
            SmallCapsText(string: group.name.text(in: wizard.language), size: 12, tracking: 0.12)
                .foregroundStyle(Color.ink500)
            Spacer(minLength: 8)
            Text(verbatim: "\(on)/\(skills.count)")
                .font(Typo.text(12))
                .foregroundStyle(Color.ink500)
        }
        .padding(.top, 6)
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.parchment300).frame(height: 1) }
        // Opaco: las cards pasan por debajo al desplazarse.
        .background(Color.parchment50)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func grid(for group: SkillGroup) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: Self.columns),
            alignment: .leading, spacing: 8
        ) {
            ForEach(catalog.skills(in: group)) { skill in
                SkillCard(
                    skill: skill, isFocused: focused == skill.id,
                    toggle: { wizard.toggleSkill(skill.id, source: skill.source) },
                    preview: { wizard.previewedSkill = skill }
                )
                .id(skill.id)
                .focusable()
                .focused($focused, equals: skill.id)
                .onKeyPress(.space) {
                    wizard.toggleSkill(skill.id, source: skill.source)
                    return .handled
                }
                .onKeyPress(.return) {
                    wizard.previewedSkill = skill
                    return .handled
                }
            }
        }
    }

    /// Las flechas recorren la rejilla como se ve: ←/→ dentro de la fila; ↑/↓ a la fila de arriba o de abajo, también
    /// de un grupo a otro, en la misma columna (o en la última card si esa fila es más corta).
    private func move(_ direction: MoveCommandDirection) {
        let rows = SkillGrid.rows(groups.map { catalog.skills(in: $0).map(\.id) }, columns: Self.columns)
        guard let current = focused else {
            focused = rows.first?.first
            return
        }
        if let target = SkillGrid.neighbor(of: current, direction, in: rows) { focused = target }
    }
}

/// La rejilla de cards como filas, para mover el foco con las flechas. Es lógica pura (se prueba sin vistas).
enum SkillGrid {
    /// Los ids de cada grupo partidos en filas de `columns`; las filas de todos los grupos, una tras otra.
    static func rows(_ groups: [[String]], columns: Int) -> [[String]] {
        groups.flatMap { ids in
            stride(from: 0, to: ids.count, by: columns).map { Array(ids[$0..<min($0 + columns, ids.count)]) }
        }
    }

    /// La card a la que salta el foco desde `id`, o `nil` si en esa dirección no hay ninguna.
    static func neighbor(of id: String, _ direction: MoveCommandDirection, in rows: [[String]]) -> String? {
        guard let row = rows.firstIndex(where: { $0.contains(id) }), let column = rows[row].firstIndex(of: id) else {
            return nil
        }
        switch direction {
        case .left: return column > 0 ? rows[row][column - 1] : nil
        case .right: return column < rows[row].count - 1 ? rows[row][column + 1] : nil
        case .up: return row > 0 ? rows[row - 1][min(column, rows[row - 1].count - 1)] : nil
        case .down: return row < rows.count - 1 ? rows[row + 1][min(column, rows[row + 1].count - 1)] : nil
        @unknown default: return nil
        }
    }
}

/// Una card: icono, «Vista previa» (solo con el cursor o el foco encima), casilla, nombre, comando, qué hace.
/// Si todavía no le sirve al usuario (le falta una herramienta conectada) se ve apagada y dice qué falta, pero
/// se puede marcar igual. Alto fijo de 112 pt para que las filas alineen.
struct SkillCard: View {
    @EnvironmentObject private var wizard: WizardState
    let skill: CatalogSkill
    var isFocused = false
    let toggle: () -> Void
    let preview: () -> Void
    /// Para la hoja de estados y las pruebas de imagen: fuerza el estado «con el cursor encima».
    var forcedHover = false
    @State private var hovering = false
    @Environment(\.locale) private var locale

    private var isOn: Bool { wizard.isSkillSelected(skill.id, source: skill.source) }
    private var isMissing: Bool { !skill.isUseful(with: wizard.connectedTools) }
    private var isHot: Bool { hovering || forcedHover }
    private var showsPreview: Bool { isHot || isFocused }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                SkillIcon(id: skill.id, size: 20).opacity(isMissing ? 0.45 : 1)
                Spacer(minLength: 0)
                Button("skills.preview", action: preview)
                    .buttonStyle(InkLinkStyle(size: 12.5))
                    .opacity(showsPreview ? 1 : 0)
                    .allowsHitTesting(showsPreview)
                    .accessibilityHidden(true)  // la acción va en la card entera, abajo
                checkbox
            }
            .frame(height: 20)
            Text(verbatim: skill.name.text(in: wizard.language))
                .font(Typo.text(15, .medium))
                .foregroundStyle(isMissing ? Color.ink700 : Color.ink900)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.top, 5)
            Text(verbatim: skill.command)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(Color.ink500)
                .lineLimit(1)
                .frame(height: 14)
                .padding(.top, 1)
            Text(verbatim: skill.summary.text(in: wizard.language))
                .font(Typo.text(12.5))
                .foregroundStyle(isMissing ? Color.ink500 : Color.ink700)
                .lineLimit(isMissing ? 1 : 2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 3)
            if isMissing {
                Text(verbatim: SkillPresentation.missingLabel(for: skill, language: wizard.language, locale: locale))
                    .font(Typo.text(12))
                    .foregroundStyle(Color.ochre700)
                    .lineLimit(1)
                    .padding(.top, 1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 112)
        .background(isOn || isHot ? Color.parchment100 : Color.clear)
        .overlay(Rectangle().strokeBorder(isOn ? Color.ink900 : Color.parchment400, lineWidth: 1.5))
        // El anillo de foco: 1,5 pt de tinta, a 2 pt de la card.
        .overlay { if isFocused { Rectangle().strokeBorder(Color.ink900, lineWidth: 1.5).padding(-3.5) } }
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: Motion.micro), value: isOn)
        .animation(.easeOut(duration: Motion.micro), value: showsPreview)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityText))
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : [.isButton])
        .accessibilityAction { toggle() }
        .accessibilityAction(named: Text("skills.preview")) { preview() }
    }

    /// La casilla de 14 pt: filete de 1,5 en `ink-700`; marcada, rellena de tinta con su palomita.
    private var checkbox: some View {
        Rectangle()
            .strokeBorder(Color.ink700, lineWidth: 1.5)
            .background(Rectangle().fill(isOn ? Color.ink900 : Color.clear))
            .overlay {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(Color.onInk)
                }
            }
            .frame(width: 14, height: 14)
            .accessibilityHidden(true)
    }

    private var accessibilityText: String {
        var parts = [skill.name.text(in: wizard.language), skill.summary.text(in: wizard.language)]
        if isMissing {
            parts.append(SkillPresentation.missingLabel(for: skill, language: wizard.language, locale: locale))
        }
        return parts.joined(separator: ". ")
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

#Preview {
    let state = WizardState()
    state.setConnectionStatus(.slack, .connected)
    return SkillsStepView()
        .environmentObject(state)
        .frame(width: WindowMetrics.width, height: 520)
        .background(Color.parchment50)
}
