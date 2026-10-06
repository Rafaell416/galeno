import GalenoCore
import SwiftUI

/// El detalle de un agente (`docs/03` §3b; guiado por «Galeno B1 Agente»): cabecera con «Abrir», cinco secciones a la
/// izquierda y el contenido a la derecha, todo en el idioma visual de Galeno (filetes, versalitas, controles de tinta).
/// Sin pasos ni «Siguiente»: se edita en su sitio.
struct AgentDetailView: View {
    @ObservedObject var model: AgentDetailModel
    /// «← Tus agentes».
    let onBack: () -> Void
    /// Se eliminó el agente desde aquí: ya no hay detalle que mostrar.
    let onRemoved: () -> Void
    @Environment(\.locale) private var locale
    @Environment(\.galenoReduceMotion) private var reduceMotion

    static let margin: CGFloat = 40

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                    .zIndex(3)
                Rectangle().fill(Color.parchment300).frame(height: 1)
                if model.config == nil {
                    missing
                } else {
                    HStack(alignment: .top, spacing: 28) {
                        nav
                            .frame(width: 168)
                        if model.section == .skills {
                            // Las cards llevan su propio desplazamiento y el pie de «Guardar»: no van dentro de otro.
                            VStack(alignment: .leading, spacing: 0) {
                                heading
                                SkillsEditor(model: model)
                            }
                            .padding(.trailing, 6)
                            .padding(.bottom, 14)
                        } else {
                            ScrollView {
                                content
                                    .padding(.trailing, 6)
                                    .padding(.bottom, 20)
                            }
                            .scrollBounceBehavior(.basedOnSize)
                        }
                    }
                    .padding(.horizontal, Self.margin)
                    .padding(.top, 16)
                }
            }
        }
        .background(Color.parchment50)
        .overlay { GrainOverlay() }
        // Hojas y diálogos: sobre el fondo atenuado, como los del home.
        .overlay {
            if let dialog = model.home.dialog {
                HomeDialogView(model: model.home, dialog: dialog, onRemoved: onRemoved)
                    .id(dialog.agent.id)
                    .transition(.opacity)
            } else if case .removeTool(let tool)? = model.sheet {
                RemoveToolSheet(model: model, tool: tool)
                    .transition(.opacity)
            } else if model.health.relink != .idle {
                RelinkPanelView(model: model.health)
                    .transition(.opacity)
            }
        }
        // La vista previa de una skill cae sobre toda la ventana, como en el asistente.
        .overlay {
            if model.section == .skills, let picker = model.picker, let skill = picker.previewedSkill {
                SkillPreviewSheet(skill: skill)
                    .environmentObject(picker)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 4)))
            }
        }
        // Conectar una herramienta nueva: su conexión, encima del detalle.
        .overlay {
            if let wizard = model.connecting {
                ConnectOverlay(model: model, wizard: wizard)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: Motion.micro), value: model.sheet)
        .animation(reduceMotion ? nil : .easeOut(duration: Motion.micro), value: model.home.dialog)
        .animation(reduceMotion ? nil : .easeOut(duration: Motion.micro), value: model.connecting == nil)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.picker?.previewedSkill)
        .onExitCommand(perform: escape)
        .onAppear { model.refreshHealth() }
        .onDisappear { model.stop() }
        .simultaneousGesture(TapGesture().onEnded { if model.home.menuOpen != nil { model.home.closeMenu() } })
    }

    /// Esc cierra lo de encima, en este orden; y con nada abierto, vuelve a los agentes.
    private func escape() {
        if model.connecting != nil { return }  // la conexión lleva su propio «Cancelar» (y su Esc)
        if let picker = model.picker, picker.previewedSkill != nil { picker.previewedSkill = nil; return }
        if model.health.relink != .idle { model.health.cancelRelink(); return }
        if model.home.dialog != nil { model.home.cancelDialog(); return }
        if model.sheet != nil { model.closeSheet(); return }
        if model.home.menuOpen != nil { model.home.closeMenu(); return }
        back()
    }

    private func back() {
        guard model.health.relink != .closing, model.health.relink != .finishing, !model.isWorking else { return }
        onBack()
    }

    // MARK: Cabecera

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: back) {
                Text("← ") + Text("agent.back")
            }
            .buttonStyle(InkLinkStyle(size: 14))
            .foregroundStyle(Color.ink700)

            HStack(alignment: .center, spacing: 16) {
                Text(verbatim: String(model.name.first.map(String.init) ?? "·"))
                    .font(Typo.display(26))
                    .foregroundStyle(Color.ink900)
                    .frame(width: 48, height: 48)
                    .overlay(Circle().strokeBorder(Color.ink900, lineWidth: 1))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(verbatim: model.name)
                            .font(Typo.display(32))
                            .foregroundStyle(Color.ink900)
                            .lineLimit(1)
                        SmallCapsText(string: model.role.title(in: model.language), size: 13, tracking: 0.12)
                            .foregroundStyle(Color.ink700)
                            .lineLimit(1)
                    }
                    Text(verbatim: meta)
                        .font(Typo.text(14))
                        .foregroundStyle(Color.ink500)
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
                if model.isWorking { InkSpinner(size: 16) }
                if let agent = model.agent {
                    AgentOpenButton(model: model.home, agent: agent, menuEdge: .below)
                }
            }
        }
        .padding(.horizontal, Self.margin)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }

    /// «Lee 4 herramientas · 16 skills».
    private var meta: String {
        let tools = model.toolRows.count
        let skills = model.skillCount
        let toolsText = Localized.string(tools == 1 ? "home.reads.one" : "home.reads.other %lld", tools, locale: locale)
        let skillsText = Localized.string(skills == 1 ? "agent.meta.skills.one" : "agent.meta.skills.other %lld", skills, locale: locale)
        return toolsText + " · " + skillsText
    }

    // MARK: Navegación

    private var nav: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(AgentDetailModel.Section.allCases) { section in
                NavItem(
                    title: LocalizedStringKey(section.titleKey), hint: hint(for: section),
                    isActive: model.section == section
                ) {
                    model.section = section
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func hint(for section: AgentDetailModel.Section) -> NavItem.Hint? {
        switch section {
        case .tools: model.reviewCount > 0 ? NavItem.Hint(text: "\(model.reviewCount) !", warn: true) : nil
        // Con lo marcado sin guardar, un punto en ocre en vez del número.
        case .skills: model.skillsDirty ? NavItem.Hint(text: "•", warn: true) : NavItem.Hint(text: "\(model.skillCount)", warn: false)
        default: nil
        }
    }

    // MARK: Contenido

    /// El título de la sección, su línea de apoyo y, si algo falló, el error.
    private var heading: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepTitle(text: Text(LocalizedStringKey(model.section.titleKey)), size: 28)
                .id(model.section)
            if let subtitle {
                Text(verbatim: subtitle)
                    .font(Typo.text(15))
                    .lineSpacing(2)
                    .foregroundStyle(Color.ink700)
                    .frame(maxWidth: 520, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
            if let error = model.error {
                Text(verbatim: error)
                    .font(Typo.text(14))
                    .foregroundStyle(Color.seal700)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading
            Group {
                switch model.section {
                case .general: GeneralSection(model: model)
                case .tools: ToolsSection(model: model)
                case .skills: EmptyView()  // va aparte: ver `body`
                case .rules: RulesSection(model: model)
                case .context: ContextSection(model: model)
                }
            }
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var subtitle: String? {
        switch model.section {
        case .general: nil
        case .tools: Localized.string("agent.tools.sub %@", model.name, locale: locale)
        case .skills: Localized.string("agent.skills.sub", locale: locale)
        case .rules: Localized.string("agent.rules.sub %@", model.name, locale: locale)
        case .context: Localized.string("agent.context.sub", locale: locale)
        }
    }

    /// El agente ya no está en la instalación (alguien lo quitó por fuera) o no se pudo leer.
    private var missing: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("agent.missing.title").font(Typo.display(26)).foregroundStyle(Color.ink900)
            Text("agent.missing.body").font(Typo.text(15)).foregroundStyle(Color.ink700)
                .fixedSize(horizontal: false, vertical: true)
            Button("agent.missing.back", action: onBack).buttonStyle(.inkInline)
        }
        .frame(maxWidth: 520, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, Self.margin)
        .padding(.top, 28)
    }
}

/// Un renglón de la navegación: 36 pt, el activo con el fondo del papel y un filete de tinta a la izquierda; a la
/// derecha, una pista corta («2 !» en ocre si algo pide mirarse, «16» en gris).
private struct NavItem: View {
    struct Hint: Equatable {
        var text: String
        var warn: Bool
    }

    let title: LocalizedStringKey
    let hint: Hint?
    let isActive: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(Typo.text(15, isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? Color.ink900 : Color.ink700)
                Spacer(minLength: 4)
                if let hint {
                    Text(verbatim: hint.text)
                        .font(Typo.text(12.5, hint.warn ? .semibold : .regular))
                        .foregroundStyle(hint.warn ? Color.ochre700 : Color.ink500)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isActive || hovering ? Color.parchment100 : Color.clear)
            .overlay(alignment: .leading) {
                if isActive { Rectangle().fill(Color.ink900).frame(width: 1.5) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

// MARK: - Hoja: quitar una herramienta

/// «Quitar»: dos intenciones distintas. **Quitar de este agente** (deja de leerla; la cuenta sigue conectada, y otro agente
/// puede estar usándola) o, solo si la cuenta es de Galeno, **desconectarla** (deja de leerla quien la use). Una cuenta
/// que no es de Galeno —un conector de la cuenta de Claude, o un servidor del usuario con el nombre genérico— solo se quita
/// de este agente: Galeno no cierra sesiones ajenas.
private struct RemoveToolSheet: View {
    @ObservedObject var model: AgentDetailModel
    let tool: Tool
    @Environment(\.locale) private var locale

    private var toolName: String { tool.displayName(in: model.language) }
    private var others: [String] { model.sharedWith[tool] ?? [] }
    private var othersText: String { others.joined(separator: ", ") }
    private var canDisconnect: Bool { model.canDisconnectAccount(tool) }

    var body: some View {
        ZStack {
            Color.ink900.opacity(0.30)
                .contentShape(Rectangle())
                .onTapGesture { model.closeSheet() }
            VStack(alignment: .leading, spacing: 12) {
                Text(verbatim: Localized.string("agent.remove.title %@", toolName, locale: locale))
                    .font(Typo.display(26)).foregroundStyle(Color.ink900)
                Text(verbatim: subtitle)
                    .font(Typo.text(14.5)).foregroundStyle(Color.ink700)
                    .fixedSize(horizontal: false, vertical: true)

                choice(
                    title: Localized.string("agent.remove.fromAgent %@", model.name, locale: locale),
                    detail: others.isEmpty
                        ? Localized.string("agent.remove.fromAgent.alone", locale: locale)
                        : Localized.string("agent.remove.fromAgent.shared %@", othersText, locale: locale),
                    filled: true
                ) { model.removeFromAgent(tool) }

                if canDisconnect {
                    choice(
                        title: Localized.string("agent.remove.account %@", toolName, locale: locale),
                        detail: others.isEmpty
                            ? Localized.string("agent.remove.account.alone %@", model.name, locale: locale)
                            : Localized.string("agent.remove.account.shared %@ %@", model.name, othersText, locale: locale),
                        filled: false
                    ) { Task { await model.disconnectAccount(tool) } }
                } else if tool != .whatsapp {
                    Text("agent.remove.notOurs")
                        .font(Typo.text(13.5)).foregroundStyle(Color.ink500)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error = model.error {
                    Text(verbatim: error).font(Typo.text(13.5)).foregroundStyle(Color.seal700)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button("wizard.cancel") { model.closeSheet() }
                        .buttonStyle(InkLinkStyle(size: 15))
                        .disabled(model.isWorking)
                    Spacer(minLength: 0)
                    if model.isWorking { InkSpinner(size: 16) }
                }
                .padding(.top, 4)
            }
            .padding(24)
            .frame(width: 520, alignment: .leading)
            .background(Color.parchment50)
            .overlay(RoundedRectangle(cornerRadius: Radius.b1).strokeBorder(Color.ink900, lineWidth: 1.5))
        }
        .onExitCommand { model.closeSheet() }
    }

    private var subtitle: String {
        others.isEmpty
            ? Localized.string("agent.remove.sub", locale: locale)
            : Localized.string("agent.remove.sub.shared %@ %@", toolName, othersText, locale: locale)
    }

    /// Una intención: un bloque con lo que hace y lo que pasa con lo demás. El relleno de tinta es la que se
    /// recomienda (la reversible).
    private func choice(title: String, detail: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).font(Typo.text(16.5, .medium))
                Text(verbatim: detail).font(Typo.text(13.5)).opacity(filled ? 0.85 : 1)
                    .foregroundStyle(filled ? Color.onInk : Color.ink700)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(filled ? Color.onInk : Color.ink900)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(filled ? Color.ink900 : Color.clear)
            .overlay(RoundedRectangle(cornerRadius: Radius.b1).strokeBorder(Color.ink900, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.isWorking)
    }
}

// MARK: - Conectar una herramienta nueva, encima del detalle

/// La conexión de la herramienta que se acaba de elegir, a pantalla completa: la misma de siempre (`ConnectStepView`), con su
/// ficha, el navegador y la autorización. Al quedar conectada se cierra sola y la herramienta entra a la lista; «Cancelar» la
/// cierra sin guardar nada (no hay «Cancelar» mientras WhatsApp sincroniza: se espera a que termine, como en el asistente).
private struct ConnectOverlay: View {
    @ObservedObject var model: AgentDetailModel
    @ObservedObject var wizard: WizardState

    private var isSyncing: Bool {
        if case .syncing? = wizard.connectFlow?.phase { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { model.cancelConnecting() } label: { Text("← ") + Text("agent.connect.cancel") }
                    .buttonStyle(InkLinkStyle(size: 14))
                    .foregroundStyle(Color.ink700)
                    .disabled(isSyncing)
                    .opacity(isSyncing ? 0 : 1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AgentDetailView.margin)
            .padding(.top, 16)
            ConnectStepView()
                .environmentObject(wizard)
                .environment(\.galenoEmbeddedConnection, true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.parchment50)
        .overlay { GrainOverlay() }
        .onExitCommand { if !isSyncing { model.cancelConnecting() } }
    }
}
