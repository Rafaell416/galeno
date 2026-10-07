import GalenoCore
import SwiftUI

/// Un dibujo de línea del rediseño «Activación» (`Assets.xcassets/ActIcons`), en tinta: los tres roles, la
/// cuenta, el navegador, la pregunta, la llave y el candado.
struct ActIcon: View {
    let name: String
    var size: CGFloat = 24
    var color: Color = .ink900

    var body: some View {
        Image("act-" + name)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}

extension AgentRole {
    /// Su dibujo en `ActIcons`.
    var drawing: String {
        switch self {
        case .productManager: "producto"
        case .marketing: "marketing"
        case .sales: "comercial"
        }
    }

    /// La clave de la frase que dice qué hará el agente por alguien de ese oficio.
    var summaryKey: LocalizedStringKey {
        switch self {
        case .productManager: "role.product.summary"
        case .marketing: "role.marketing.summary"
        case .sales: "role.sales.summary"
        }
    }
}

/// Paso 1: el rol. Tres tarjetas grandes, cada una con su dibujo y una sola frase. Elegir una decide qué skills
/// trae el agente y en qué orden se le ofrecen las herramientas; no hay nada más que leer.
struct RoleStepView: View {
    @EnvironmentObject private var wizard: WizardState
    @FocusState private var focused: AgentRole?

    var body: some View {
        StepScaffold(step: .role, summarySize: 16, titleGap: 8, contentGap: 22) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(Array(AgentRole.allCases.enumerated()), id: \.element) { index, role in
                    RoleCard(role: role, isSelected: wizard.role == role, isFocused: focused == role) {
                        wizard.role = role
                    }
                    .focusable()
                    // El foco lo marca el filete propio de la tarjeta, no el anillo del sistema (que sale en lacre).
                    .focusEffectDisabled()
                    .focused($focused, equals: role)
                    .onKeyPress(.space) {
                        wizard.role = role
                        return .handled
                    }
                    .staggered(index)
                }
            }
            .onMoveCommand { direction in
                let roles = AgentRole.allCases
                guard let index = roles.firstIndex(of: focused ?? wizard.role) else { return }
                switch direction {
                case .left where index > 0: focused = roles[index - 1]
                case .right where index < roles.count - 1: focused = roles[index + 1]
                default: break
                }
            }
        }
    }
}

/// Una tarjeta de rol: el retrato de su personaje (o el dibujo de 48 pt), nombre y una frase. La elegida lleva el filete de tinta, el fondo del
/// papel marcado y la palomita que se traza, como una herramienta marcada.
private struct RoleCard: View {
    @EnvironmentObject private var wizard: WizardState
    let role: AgentRole
    let isSelected: Bool
    var isFocused = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                // Cada rol trae su personaje, como quien elige el suyo: su retrato y su nombre. Sin retrato en el
                // catálogo, el dibujo del rol de siempre.
                if role.persona.hasPortrait {
                    PortraitMark(asset: role.persona.portrait, size: 72, doubleRing: isSelected)
                        .frame(width: 80, height: 80)
                        .opacity(isSelected ? 1 : 0.82)
                } else {
                    ActIcon(name: role.drawing, size: 48, color: isSelected ? .ink900 : .ink700)
                }
                VStack(spacing: 2) {
                    Text(verbatim: role.title(in: wizard.language))
                        .font(Typo.display(24))
                        .foregroundStyle(Color.ink900)
                    if role.persona.hasPortrait {
                        SmallCapsText(string: role.persona.name, size: 12)
                            .foregroundStyle(Color.ink500)
                    }
                }
                Text(role.summaryKey)
                    .font(Typo.text(14.5))
                    .lineSpacing(1.5)
                    .foregroundStyle(Color.ink700)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, minHeight: 208, alignment: .top)
            .background(isSelected || hovering ? Color.parchment100 : Color.clear)
            .overlay(Rectangle().strokeBorder(isSelected ? Color.ink900 : Color.parchment400, lineWidth: 1.5))
            .overlay(alignment: .topTrailing) {
                // Un radio, no una casilla: el rol es uno solo (feedback de Aquiles, 5 oct 2026: la casilla
                // le hizo pensar que podía marcar varios).
                Circle()
                    .strokeBorder(isSelected ? Color.ink900 : Color.parchment400, lineWidth: 1.5)
                    .overlay {
                        if isSelected {
                            // 4 pt de aire, no 3,5: en una pantalla sin Retina medio punto descentra el relleno.
                            Circle().fill(Color.ink900).padding(4)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .frame(width: 16, height: 16)
                    .padding(8)
                    .accessibilityHidden(true)
            }
            .overlay {
                if isFocused { Rectangle().strokeBorder(Color.ink500, lineWidth: 1).padding(-3) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .pointingHandOnHover()
        .accessibilityLabel(Text(verbatim: role.title(in: wizard.language)))
        .accessibilityHint(Text(role.summaryKey))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(.easeOut(duration: 0.2), value: isSelected)
        .animation(.easeOut(duration: Motion.micro), value: hovering)
    }
}

#Preview {
    RoleStepView()
        .environmentObject(WizardState())
        .frame(width: WindowMetrics.width, height: 440)
        .background(Color.parchment50)
}
