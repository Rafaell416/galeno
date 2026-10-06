import GalenoCore
import SwiftUI

/// «Abrir | ▾»: el botón partido que abre el agente donde se abrió la última vez, con una flecha que despliega
/// «Abrir en» (app de Claude o Terminal). Lo usan la tarjeta del home y la cabecera del detalle del agente.
struct AgentOpenButton: View {
    /// Hacia dónde se despliega «Abrir en»: la tarjeta del home lo abre hacia arriba (está abajo); la cabecera del
    /// detalle, hacia abajo.
    enum MenuEdge { case above, below }

    @ObservedObject var model: HomeModel
    let agent: HomeAgent
    var menuEdge: MenuEdge = .above

    private var isOpening: Bool { model.opening == agent.id }

    var body: some View {
        splitButton
            .overlay(alignment: menuEdge == .above ? .bottomTrailing : .topTrailing) {
                if model.menuOpen == agent.id {
                    menu
                        // Justo encima (o debajo) del botón: 36 pt de alto y 6 de aire.
                        .offset(y: menuEdge == .above ? -42 : 42)
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
}

/// Un renglón de «Abrir en»: la elección actual lleva una palomita; al pasar el cursor se ilumina.
struct MenuOption: View {
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
