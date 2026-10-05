import GalenoCore
import SwiftUI

/// El home (`docs/03` §3b, B1): los agentes en una tabla a filetes, cada uno con su «Abrir», y abajo
/// «Nuevo agente». Sin tarjetas ni láminas: un libro de registro.
struct HomeView: View {
    @ObservedObject var model: HomeModel
    let onNewAgent: () -> Void
    /// «Gestionar» un agente: cambiar qué lee, sus skills y sus reglas.
    var onManage: (UUID) -> Void = { _ in }
    /// Se eliminó un agente (si era el último, la ventana abre el wizard corto).
    var onAgentRemoved: () -> Void = {}
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Rectangle().fill(Color.parchment300).frame(height: 1)
            HStack {
                Spacer(minLength: 0)
                Button("home.new", action: onNewAgent)
                    .buttonStyle(InkButtonStyle(.primary, padding: 26))
                    .keyboardShortcut(.defaultAction)
                    // Con la instalación sin poder leerse no se crea nada: no se trabaja sobre lo que no se vio.
                    .disabled(model.isUnreadable)
            }
            .padding(.horizontal, Space.s48)
            .padding(.vertical, 14)
        }
        .background(Color.parchment50)
        .overlay { GrainOverlay() }
        .onExitCommand {
            model.closeMenu()
            model.closeManageMenu()
            model.cancelDialog()
        }
        .overlay {
            if let dialog = model.dialog {
                HomeDialogView(model: model, dialog: dialog, onRemoved: onAgentRemoved)
                    .id(dialog.agent.id)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: Motion.micro), value: model.dialog)
        // Un clic en cualquier parte que no sea el menú lo cierra.
        .simultaneousGesture(
            TapGesture().onEnded {
                if model.menuOpen != nil { model.closeMenu() }
                if model.manageMenu != nil { model.closeManageMenu() }
            })
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .unreadable(let reason):
            VStack(alignment: .leading, spacing: 14) {
                header
                NoticePanel(kind: .seal) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("home.error.title").font(Typo.text(15, .semibold)).foregroundStyle(Color.ink900)
                        Text("home.error.body").font(Typo.text(14)).foregroundStyle(Color.ink700)
                        Text(verbatim: reason)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Color.ink500)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Button("home.error.retry") { model.reload() }
                    .buttonStyle(InkButtonStyle(.secondary, size: .bar, padding: 16))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.s48)
            .padding(.top, 28)
        default:
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, Space.s48)
                    .padding(.top, 28)
                    .padding(.bottom, model.notice == nil ? 16 : 10)
                if let notice = model.notice {
                    NoticePanel(kind: .ochre) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: notice).font(Typo.text(14)).foregroundStyle(Color.ink900)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 12)
                            Button("home.notice.close") { model.dismissNotice() }.buttonStyle(LinkTextStyle())
                        }
                    }
                    .padding(.horizontal, Space.s48)
                    .padding(.bottom, 12)
                }
                ScrollView {
                    // De dos en dos: en cada par, las dos tarjetas miden lo mismo (la más alta manda).
                    VStack(spacing: 12) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, pair in
                            HStack(alignment: .top, spacing: 12) {
                                ForEach(Array(pair.enumerated()), id: \.element.id) { column, agent in
                                    AgentCard(model: model, agent: agent, onManage: onManage)
                                        .frame(maxHeight: .infinity)
                                        .staggered(rowIndex * 2 + column)
                                        .zIndex(model.manageMenu == agent.id || model.menuOpen == agent.id ? 5 : 0)
                                }
                                if pair.count == 1 { Color.clear.frame(maxWidth: .infinity) }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, Space.s48)
                    .padding(.bottom, Space.s16)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    /// Los agentes en pares, para las dos columnas de tarjetas.
    private var rows: [[HomeAgent]] {
        stride(from: 0, to: model.agents.count, by: 2).map { Array(model.agents[$0..<min($0 + 2, model.agents.count)]) }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            PortraitMark(size: 48)
            VStack(alignment: .leading, spacing: 2) {
                StepTitle(text: Text("home.title"), size: 32)
                Text(summary)
                    .font(Typo.list)
                    .foregroundStyle(Color.ink700)
            }
            Spacer(minLength: 12)
        }
    }

    /// «2 agentes» / «1 agente». Se arma como `String`: la clave del catálogo no lleva el número.
    private var summary: String {
        let count = model.agents.count
        return Localized.string(count == 1 ? "home.summary.one" : "home.summary.other %lld", count, locale: locale)
    }
}

/// Una tarjeta: nombre, descripción, qué lee, y «Abrir» abajo. Filete fino de tinta y esquinas de B1; la que
/// no tiene carpeta se ve punteada y apagada, como una herramienta «Próximamente».
private struct AgentCard: View {
    @ObservedObject var model: HomeModel
    let agent: HomeAgent
    let onManage: (UUID) -> Void
    @Environment(\.locale) private var locale
    @State private var hovering = false

    private var isOpening: Bool { model.opening == agent.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: agent.name)
                    .font(Typo.display(24))
                    .foregroundStyle(agent.folderExists ? Color.ink900 : Color.ink500)
                    .lineLimit(1)
                Spacer(minLength: 8)
                // Sin carpeta no se gestiona: regenerar la crearía de nuevo en silencio, sin su memoria.
                Button("home.manage") { model.toggleManageMenu(agent) }
                    .buttonStyle(LinkTextStyle())
                    .disabled(!agent.folderExists || model.opening != nil)
            }
            .overlay(alignment: .topTrailing) {
                if model.manageMenu == agent.id {
                    manageMenu
                        .offset(y: 30)
                        .transition(.opacity)
                }
            }
            .zIndex(2)
            .animation(.easeOut(duration: Motion.micro), value: model.manageMenu)
            // Dos líneas reservadas: así las tarjetas de un par empiezan a la misma altura.
            Text(verbatim: agent.projectDescription)
                .font(Typo.list)
                .foregroundStyle(Color.ink700)
                .lineLimit(2, reservesSpace: true)
            reads
            note
            Spacer(minLength: 6)
            footer
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(hovering && agent.folderExists ? Color.parchment100 : Color.clear, in: RoundedRectangle(cornerRadius: Radius.b1))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.b1)
                .strokeBorder(
                    Color.parchment400,
                    style: StrokeStyle(lineWidth: agent.folderExists ? 1.5 : 1, dash: agent.folderExists ? [] : [3, 3]))
        )
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: Motion.micro), value: hovering)
        .accessibilityElement(children: .contain)
    }

    /// «Gestionar»: qué hacer con el agente. Mismo papel y filete que el menú de «Abrir»; sin sombra.
    private var manageMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuOption(title: "home.manage.edit", detail: nil, isCurrent: false, showsCheck: false) {
                model.closeManageMenu()
                onManage(agent.id)
            }
            Rectangle().fill(Color.parchment300).frame(height: 1)
            MenuOption(title: "home.manage.rename", detail: nil, isCurrent: false, showsCheck: false) {
                model.askRename(agent)
            }
            Rectangle().fill(Color.parchment300).frame(height: 1)
            MenuOption(title: "home.manage.delete", detail: "home.manage.delete.hint", isCurrent: false, showsCheck: false) {
                model.askDelete(agent)
            }
        }
        .frame(width: 236)
        .background(Color.parchment50)
        .overlay(RoundedRectangle(cornerRadius: Radius.b1).strokeBorder(Color.ink900, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.b1))
    }

    /// Abajo: dónde va a abrir (en versalitas), y el botón partido «Abrir | ▾». Lo principal abre donde se abrió la
    /// última vez; la flecha despliega «Abrir en» con la elección marcada.
    private var footer: some View {
        HStack(spacing: 10) {
            SmallCapsLabel(model.effectiveTarget == .app ? "home.target.app" : "home.target.terminal", size: 11)
                .foregroundStyle(Color.ink500)
                .lineLimit(1)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            splitButton
        }
        .overlay(alignment: .bottomTrailing) {
            if model.menuOpen == agent.id {
                menu
                    .offset(y: -42)  // justo encima del botón (36 pt + 6 de aire)
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .animation(.easeOut(duration: Motion.micro), value: model.menuOpen)
    }

    /// «Abrir» y su flecha, pegados con un solo filete entre los dos, como el botón de crear PR de GitHub.
    private var splitButton: some View {
        HStack(spacing: 0) {
            Button("home.open") { model.open(agent) }
                .buttonStyle(InkButtonStyle(.secondary, size: .bar, padding: 18, isLoading: isOpening))
                .accessibilityHint(Text(model.effectiveTarget == .app ? "home.target.app" : "home.target.terminal"))
            if model.canChoose {
                Button { model.toggleMenu(agent) } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .rotationEffect(.degrees(model.menuOpen == agent.id ? 180 : 0))
                }
                .buttonStyle(InkButtonStyle(.secondary, size: .bar, padding: 9))
                .padding(.leading, -1.5)  // el filete del medio se comparte
                .accessibilityLabel(Text("home.openIn"))
            }
        }
        .disabled(!agent.folderExists || model.opening != nil)
    }

    /// «Abrir en»: dos renglones a filetes, sin sombra (los bordes separan). Elegir uno abre y lo deja como la
    /// elección de ahí en adelante. Si abrir en la app va a reiniciar Claude, el renglón lo dice.
    private var menu: some View {
        VStack(alignment: .leading, spacing: 0) {
            SmallCapsLabel("home.openIn", size: 11)
                .foregroundStyle(Color.ink500)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 6)
            option(.app, "home.target.app", detail: model.willRestartClaude(for: agent) ? "home.menu.restart" : nil)
            Rectangle().fill(Color.parchment300).frame(height: 1)
            option(.terminal, "home.target.terminal", detail: nil)
        }
        .frame(width: 214)
        .background(Color.parchment50)
        .overlay(RoundedRectangle(cornerRadius: Radius.b1).strokeBorder(Color.ink900, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.b1))
    }

    private func option(_ target: OpenTarget, _ title: LocalizedStringKey, detail: LocalizedStringKey?) -> some View {
        MenuOption(
            title: title, detail: detail, isCurrent: model.effectiveTarget == target
        ) { model.open(agent, in: target) }
    }

    /// Los logos de lo que lee, pequeños, y «Lee WhatsApp, Gmail y 3 más».
    @ViewBuilder
    private var reads: some View {
        if agent.tools.isEmpty {
            Text("home.reads.none").font(Typo.text(13)).foregroundStyle(Color.ink500)
        } else {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    ForEach(agent.tools.prefix(6)) { tool in
                        ToolIcon(tool: tool, size: 16, color: .ink500)
                    }
                }
                .accessibilityHidden(true)
                Text(verbatim: readsText)
                    .accessibilityLabel(Text(verbatim: readsText + ": " + toolNames))
                    .font(Typo.text(13))
                    .foregroundStyle(Color.ink500)
                    .lineLimit(1)
            }
        }
    }

    /// «Lee 6 herramientas»: corto, para que no se corte en una tarjeta. Los nombres van a VoiceOver con los logos.
    private var readsText: String {
        let count = agent.tools.count
        return Localized.string(count == 1 ? "home.reads.one" : "home.reads.other %lld", count, locale: locale)
    }

    private var toolNames: String {
        let language = Language(rawValue: locale.identifier) ?? .spanish
        return agent.tools.map { $0.displayName(in: language) }.joined(separator: ", ")
    }

    /// Lo que conviene saber antes de pulsar «Abrir»: la carpeta no está, se va a reiniciar Claude, o falló.
    @ViewBuilder
    private var note: some View {
        if !agent.folderExists {
            Text("home.folderMissing").font(Typo.text(13)).foregroundStyle(Color.ink500)
        } else if let problem = model.problems[agent.id] {
            Text(problem == .claudeDidNotQuit ? "done.open.claudeStillOpen" : "done.open.failed")
                .font(Typo.text(13)).foregroundStyle(Color.ink700)
                .fixedSize(horizontal: false, vertical: true)
        } else if model.effectiveTarget == .app, model.willRestartClaude(for: agent) {
            Text("done.open.restart").font(Typo.text(13)).foregroundStyle(Color.ink500)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Un renglón de «Abrir en»: la elección actual lleva una palomita; al pasar el cursor se ilumina.
private struct MenuOption: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey?
    let isCurrent: Bool
    /// Los menús de elegir llevan una palomita en la opción actual; los de acciones no.
    var showsCheck = true
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if showsCheck {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .opacity(isCurrent ? 1 : 0)
                        .frame(width: 12)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(Typo.text(15, isCurrent ? .semibold : .regular)).foregroundStyle(Color.ink900)
                    if let detail {
                        Text(detail).font(Typo.text(12)).foregroundStyle(Color.ink500)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovering ? Color.parchment100 : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

/// Un diálogo dentro de la ventana (la ventana es fija): papel con filete de tinta sobre el fondo atenuado. Sirve
/// para renombrar y para confirmar que se elimina un agente, diciendo antes qué se manda a la Papelera.
private struct HomeDialogView: View {
    @ObservedObject var model: HomeModel
    let dialog: HomeModel.Dialog
    let onRemoved: () -> Void
    @State private var name: String
    @Environment(\.locale) private var locale

    init(model: HomeModel, dialog: HomeModel.Dialog, onRemoved: @escaping () -> Void) {
        self.model = model
        self.dialog = dialog
        self.onRemoved = onRemoved
        _name = State(initialValue: dialog.agent.name)
    }

    var body: some View {
        ZStack {
            Color.ink900.opacity(0.30)
                .contentShape(Rectangle())
                .onTapGesture { model.cancelDialog() }
            panel
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch dialog {
            case .rename(let agent): renameContent(agent)
            case .delete(let agent, let plan): deleteContent(agent, plan)
            }
            if let error = model.dialogError {
                Text(verbatim: error).font(Typo.text(13.5)).foregroundStyle(Color.seal700)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button("wizard.cancel") { model.cancelDialog() }
                    .buttonStyle(InkButtonStyle(.secondary, padding: 20))
                    .disabled(model.isWorking)
                primary
            }
            .padding(.top, 6)
        }
        .padding(24)
        .frame(width: 460, alignment: .leading)
        .background(Color.parchment50)
        .overlay(RoundedRectangle(cornerRadius: Radius.b1).strokeBorder(Color.ink900, lineWidth: 1.5))
        .onExitCommand { model.cancelDialog() }
    }

    @ViewBuilder
    private var primary: some View {
        switch dialog {
        case .rename(let agent):
            Button("home.rename.save") { model.rename(agent, to: name) }
                .buttonStyle(InkButtonStyle(.primary, padding: 22, isLoading: model.isWorking))
                .keyboardShortcut(.defaultAction)
                .disabled(HomeModel.renameIssue(for: name) != nil || model.isWorking)
        case .delete:
            Button("home.delete.confirm") { if model.confirmDelete() { onRemoved() } }
                .buttonStyle(InkButtonStyle(.primary, padding: 22, isLoading: model.isWorking))
                .disabled(model.isWorking)
        }
    }

    // MARK: Renombrar

    private func renameContent(_ agent: HomeAgent) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: Localized.string("home.rename.title %@", agent.name, locale: locale))
                .font(Typo.display(26)).foregroundStyle(Color.ink900)
            Text(verbatim: Localized.string("home.rename.body %@", agent.name, locale: locale))
                .font(Typo.text(14.5)).foregroundStyle(Color.ink700)
                .fixedSize(horizontal: false, vertical: true)
            RuleTextField(
                "home.rename.field", text: $name, prompt: "agent.name.placeholder", font: Typo.display(24),
                autofocus: true, isError: HomeModel.renameIssue(for: name) != nil
            )
            .onChange(of: name) { _, value in
                if value.count > WizardState.maxAgentNameLength { name = String(value.prefix(WizardState.maxAgentNameLength)) }
            }
            if let issue = HomeModel.renameIssue(for: name) {
                Text(issue == .empty ? "home.rename.issue.empty" : "home.rename.issue.long")
                    .font(Typo.text(13)).foregroundStyle(Color.seal700)
            }
        }
    }

    // MARK: Eliminar

    private func deleteContent(_ agent: HomeAgent, _ plan: AgentRemovalPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: Localized.string("home.delete.title %@", agent.name, locale: locale))
                .font(Typo.display(26)).foregroundStyle(Color.ink900)
            if plan.isEmpty {
                Text("home.delete.nothing").font(Typo.text(14.5)).foregroundStyle(Color.ink700)
            } else {
                Text("home.delete.lead").font(Typo.text(14.5)).foregroundStyle(Color.ink900)
                VStack(alignment: .leading, spacing: 4) {
                    if let folder = plan.folder {
                        bullet(Localized.string("home.delete.folder %@", Self.displayPath(folder), locale: locale))
                    }
                    if plan.conversationCount > 0 {
                        bullet(count("home.delete.conversations", plan.conversationCount))
                    }
                    if !plan.desktopSessions.isEmpty {
                        bullet(count("home.delete.desktop", plan.desktopSessions.count))
                    }
                }
            }
            Text("home.delete.kept").font(Typo.text(13.5)).foregroundStyle(Color.ink500)
                .fixedSize(horizontal: false, vertical: true)
            if plan.claudeCodeData != nil || !plan.desktopSessions.isEmpty {
                Text("home.delete.close").font(Typo.text(13.5)).foregroundStyle(Color.ink500)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func count(_ base: String, _ n: Int) -> String {
        Localized.string(n == 1 ? "\(base).one" : "\(base).other %lld", n, locale: locale)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(verbatim: "·").foregroundStyle(Color.ink500).frame(width: 12, alignment: .leading)
            Text(verbatim: text).foregroundStyle(Color.ink900).fixedSize(horizontal: false, vertical: true)
        }
        .font(Typo.text(14.5))
    }

    /// `~` en lugar de la ruta completa del usuario.
    private static func displayPath(_ url: URL) -> String {
        let home = NSHomeDirectory()
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }
}
