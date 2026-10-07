import GalenoCore
import SwiftUI

/// Paso 4: las herramientas (rediseño «Activación»). Una sola grilla, en el orden del rol; las tres primeras
/// vienen marcadas. Las marcadas llevan su número: es el orden en que se conectan después, una por una.
struct ToolsStepView: View {
    @EnvironmentObject private var wizard: WizardState
    /// La tarjeta con el foco del teclado: flechas para moverse, espacio para marcar.
    @FocusState private var focused: Tool?
    @Environment(\.galenoReduceMotion) private var reduceMotion
    /// Las que se marcaron solas por depender de otra (`Tool.requires`): se encienden 100 ms después.
    @State private var autoTicked: Set<Tool> = []

    private static let columns = 3

    /// Las que se pueden marcar, en el orden del rol; las que todavía no se ofrecen, al final. Google Meet no va
    /// en la grilla: no tiene servidor, sus transcripciones se leen por Drive.
    private var tools: [Tool] {
        let offered = wizard.toolsInRoleOrder.filter { $0 != .googleMeet }
        return offered.filter { !$0.isComingSoon } + offered.filter(\.isComingSoon)
    }

    var body: some View {
        StepScaffold(step: .tools, summarySize: 16, titleGap: 8, contentGap: 16) {
            VStack(alignment: .leading, spacing: Space.s8) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: Self.columns),
                    alignment: .leading, spacing: 8
                ) {
                    ForEach(tools) { tool in
                        ToolCard(
                            tool: tool, order: wizard.selectedTools.firstIndex(of: tool).map { $0 + 1 },
                            isFocused: focused == tool,
                            lightDelay: autoTicked.contains(tool) && !reduceMotion ? 0.1 : 0
                        ) { toggle(tool) }
                            .focusable(!tool.isComingSoon)
                            .focused($focused, equals: tool)
                            .onKeyPress(.space) {
                                toggle(tool)
                                return .handled
                            }
                    }
                    // La búsqueda web no se conecta ni se elige: viene con el agente (decisión de Rafa,
                    // 5 oct 2026). Se enseña aquí para que se sepa que la tiene.
                    IncludedToolCard()
                }

                if wizard.isSelected(.claudeDesign) {
                    // Qué hace: basta con pasarle un enlace de diseño o el nombre de un proyecto.
                    Text("tools.designNote")
                        .font(Typo.text(13))
                        .foregroundStyle(Color.ink500)
                        .transition(.opacity)
                }
            }
            .onMoveCommand(perform: move)
            .animation(.easeOut(duration: Motion.enter), value: wizard.isSelected(.claudeDesign))
        }
    }

    private func toggle(_ tool: Tool) {
        guard !tool.isComingSoon else { return }
        let wasSelected = wizard.isSelected(tool)
        let needed = tool.requires.filter { !wizard.isSelected($0) }
        wizard.toggle(tool)
        autoTicked = wasSelected ? [] : Set(needed)
    }

    /// Las flechas recorren la grilla como se ve: de tres en tres hacia arriba y abajo.
    private func move(_ direction: MoveCommandDirection) {
        let all = tools.filter { !$0.isComingSoon }
        guard let current = focused ?? all.first, let index = all.firstIndex(of: current) else { return }
        let target: Int
        switch direction {
        case .left: target = index - 1
        case .right: target = index + 1
        case .up: target = index - Self.columns
        case .down: target = index + Self.columns
        @unknown default: return
        }
        if all.indices.contains(target) { focused = all[target] }
    }
}

/// Una tarjeta de herramienta: número (si está marcada), logo, nombre y una casilla de 14 pt. La marcada lleva
/// el filete de 1,5 pt en `ink-900`.
private struct ToolCard: View {
    @EnvironmentObject private var wizard: WizardState
    let tool: Tool
    /// Su lugar entre las marcadas: el orden en que se va a conectar.
    var order: Int?
    var isFocused = false
    /// Cuando la marcó otra herramienta, su logo y su casilla se encienden con este retraso.
    var lightDelay: Double = 0
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let selected = wizard.isSelected(tool)
        let name = tool.displayName(in: wizard.language)
        let soon = tool.isComingSoon
        // En el wizard corto, las que la instalación ya tiene conectadas llevan su marca: no habrá que conectarlas.
        let alreadyConnected = wizard.mode != .full && wizard.connection(for: tool)?.status == .connected

        Button(action: action) {
            HStack(spacing: 10) {
                Text(verbatim: order.map(String.init) ?? "")
                    .font(Typo.display(18))
                    .foregroundStyle(Color.ink500)
                    .contentTransition(.numericText())
                    .frame(width: 14, alignment: .center)
                // El logo se enciende: de `ink-500` a `ink-900` (200 ms).
                ToolIcon(tool: tool, size: 26, color: selected ? .ink900 : .ink500)
                    .opacity(soon ? 0.55 : 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: name)
                        .font(Typo.text(14.5, .medium))
                        .foregroundStyle(soon ? Color.ink500 : Color.ink900)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(-2)
                        .lineLimit(soon || alreadyConnected ? 1 : 2)
                        .minimumScaleFactor(0.85)
                    if soon {
                        // Todavía no se ha probado de punta a punta: se ve, pero no se puede marcar.
                        SmallCapsLabel("tools.comingSoon", size: 10)
                            .foregroundStyle(Color.ink500)
                    } else if alreadyConnected {
                        SmallCapsLabel("tools.connected", size: 10)
                            .foregroundStyle(Color.ink500)
                    }
                }
                Spacer(minLength: 0)
                if !soon {
                    Rectangle()
                        .strokeBorder(selected ? Color.ink900 : Color.parchment400, lineWidth: 1.5)
                        .background(Rectangle().fill(selected ? Color.ink900 : Color.clear))
                        .overlay {
                            // La casilla se rellena (150 ms) y la palomita se traza (180 ms).
                            if selected {
                                TracedShape(shape: CheckMark(), lineWidth: 1.5, color: .onInk, duration: 0.18)
                                    .padding(1)
                            }
                        }
                        .frame(width: 14, height: 14)
                        .accessibilityHidden(true)
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(selected || (hovering && !soon) ? Color.parchment100 : Color.clear)
            .overlay(
                Rectangle()
                    .strokeBorder(
                        selected ? Color.ink900 : Color.parchment400,
                        style: StrokeStyle(lineWidth: soon ? 1 : 1.5, dash: soon ? [3, 3] : []))
            )
            .overlay {
                // El foco del teclado: un filete de tinta, no el lacre (que se reserva para un acento por pantalla).
                if isFocused { Rectangle().strokeBorder(Color.ink500, lineWidth: 1).padding(-3) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(soon)
        .onHover { hovering = $0 && !soon }
        .pointingHandOnHover(!soon)
        .accessibilityLabel(soon ? Text(verbatim: name + ", ") + Text("tools.comingSoon") : Text(verbatim: name))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(.easeOut(duration: 0.2).delay(lightDelay), value: selected)
        .animation(.easeOut(duration: 0.2), value: order)
        .animation(.easeOut(duration: Motion.micro), value: hovering)
    }
}

/// Lo que el agente trae sin conectar nada: hoy, la búsqueda web. Tiene la forma de una tarjeta marcada, pero no
/// es un botón: no hay nada que elegir ni que autorizar. El agente busca y abre páginas sin pedir permiso
/// (`SettingsRenderer.allowedWebTools`).
private struct IncludedToolCard: View {
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 10) {
            Color.clear.frame(width: 14)
            Image(systemName: "globe")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Color.ink900)
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text("tools.web.name")
                    .font(Typo.text(14.5, .medium))
                    .foregroundStyle(Color.ink900)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                SmallCapsLabel("tools.included", size: 10)
                    .foregroundStyle(Color.ink500)
            }
            Spacer(minLength: 0)
            Rectangle()
                .fill(Color.ink900)
                .overlay { CheckMark().stroke(Color.onInk, lineWidth: 1.5).padding(1) }
                .frame(width: 14, height: 14)
                .accessibilityHidden(true)
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .background(Color.parchment100)
        .overlay(Rectangle().strokeBorder(Color.ink900, lineWidth: 1.5))
        .help(Text("tools.web.help"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text(verbatim: Localized.string("tools.web.name", locale: locale) + ", ") + Text("tools.included"))
        .accessibilityHint(Text("tools.web.help"))
    }
}

extension Tool {
    /// Las que todavía no se han probado de punta a punta con una cuenta real: se muestran en el paso 4
    /// como «Próximamente» y no se pueden marcar. El motor las sigue sabiendo generar; para abrir una,
    /// basta quitarla de aquí después de probarla. Google Meet ya no se ofrece (se lee por Drive).
    var isComingSoon: Bool {
        switch self {
        case .fireflies, .granola, .googleMeet: true
        case .whatsapp, .slack, .notion, .gmail, .googleWorkspace, .googleCalendar, .claudeDesign, .jira, .fathom: false
        }
    }
}

#Preview {
    let state = WizardState()
    state.toggle(.notion)
    state.toggle(.slack)
    return ToolsStepView()
        .environmentObject(state)
        .frame(width: WindowMetrics.width, height: 440)
        .background(Color.parchment50)
}
