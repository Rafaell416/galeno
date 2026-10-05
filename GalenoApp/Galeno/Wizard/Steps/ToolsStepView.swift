import GalenoCore
import SwiftUI

/// Paso 4: las herramientas, en cuatro grupos (B1). El usuario marca solo las que usa; eso define
/// cuántas conexiones tendrá el paso 5.
struct ToolsStepView: View {
    @EnvironmentObject private var wizard: WizardState
    /// La tarjeta con el foco del teclado: flechas para moverse, espacio para marcar.
    @FocusState private var focused: Tool?
    @Environment(\.galenoReduceMotion) private var reduceMotion
    /// Las que se marcaron solas por depender de otra (`Tool.requires`): se encienden 100 ms después.
    @State private var autoTicked: Set<Tool> = []

    /// Los grupos y su orden, como en el diseño.
    private static let groups: [(label: String, tools: [Tool])] = [
        ("tools.group.messaging", [.whatsapp, .slack]),
        ("tools.group.docs", [.notion, .googleWorkspace, .gmail]),
        ("tools.group.work", [.jira, .googleCalendar, .claudeDesign]),
        // Google Meet no va en la grilla: no tiene servidor, sus transcripciones se leen por Drive.
        ("tools.group.meetings", [.fireflies, .granola, .fathom]),
    ]

    /// El grupo donde se enseña la búsqueda web, que no es una conexión.
    private static let webSearchGroup = "tools.group.work"

    var body: some View {
        StepScaffold(step: .tools, summarySize: 15, titleGap: 6, contentGap: 10) {
            summary
        } content: {
            VStack(alignment: .leading, spacing: Space.s8) {
                ForEach(Array(Self.groups.enumerated()), id: \.offset) { _, group in
                    HStack(alignment: .top, spacing: Space.s12) {
                        SmallCapsLabel(group.label, size: 12)
                            .foregroundStyle(Color.ink500)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(width: 92, alignment: .leading)
                            .padding(.top, Space.s8)
                            .overlay(alignment: .top) {
                                Rectangle().fill(Color.parchment300).frame(height: 1)
                            }
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4),
                            alignment: .leading, spacing: 6
                        ) {
                            ForEach(group.tools) { tool in
                                ToolCard(
                                    tool: tool, isFocused: focused == tool,
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
                            if group.label == Self.webSearchGroup { IncludedToolCard() }
                        }
                        .frame(maxWidth: .infinity)
                    }
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

    /// Las flechas recorren la grilla como se ve: izquierda y derecha por la fila, arriba y abajo
    /// por los grupos, en la misma columna (o la última si el grupo es más corto).
    private func move(_ direction: MoveCommandDirection) {
        let rows = Self.groups.map(\.tools)
        guard let current = focused ?? rows.first?.first,
            let row = rows.firstIndex(where: { $0.contains(current) }),
            let column = rows[row].firstIndex(of: current)
        else { return }
        switch direction {
        case .left where column > 0: focused = rows[row][column - 1]
        case .right where column < rows[row].count - 1: focused = rows[row][column + 1]
        case .up where row > 0: focused = rows[row - 1][min(column, rows[row - 1].count - 1)]
        case .down where row < rows.count - 1: focused = rows[row + 1][min(column, rows[row + 1].count - 1)]
        default: break
        }
    }

    /// «Vas a conectar 5 herramientas · ~8 min», a la derecha del título.
    @ViewBuilder
    private var summary: some View {
        // Solo cuenta lo que falta por conectar: en el wizard corto, lo ya conectado no se vuelve a hacer.
        let count = wizard.toConnect.count
        let minutes = wizard.estimatedSetupMinutes
        let chosen = wizard.selectedTools.count
        Group {
            switch count {
            case 0 where chosen > 0: Text("tools.summary.ready")
            case 0: Text("tools.summary.none")
            case 1: Text("tools.summary.one \(minutes)")
            default: Text("tools.summary.other \(count) \(minutes)")
            }
        }
        .font(Typo.list)
        .foregroundStyle(chosen == 0 ? Color.ink500 : Color.ink700)
        .multilineTextAlignment(.trailing)
        // Las cifras giran como un rodillo; el texto no se reconstruye entero.
        .contentTransition(.numericText())
        .animation(.easeOut(duration: 0.2), value: count)
        .animation(.easeOut(duration: 0.2), value: minutes)
    }
}

/// Una tarjeta de herramienta (B1): icono, nombre y una casilla de 14 pt en la esquina. La marcada
/// lleva el filete de 1,5 pt en `ink-900`.
private struct ToolCard: View {
    @EnvironmentObject private var wizard: WizardState
    let tool: Tool
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
            VStack(spacing: soon || alreadyConnected ? 2 : 5) {
                // El logo se enciende: de `ink-500` a `ink-900` (200 ms).
                ToolIcon(tool: tool, size: soon ? 20 : 24, color: selected ? .ink900 : .ink500)
                    .opacity(soon ? 0.55 : 1)
                Text(verbatim: name)
                    .font(Typo.text(13.5, .medium))
                    .foregroundStyle(soon ? Color.ink500 : Color.ink900)
                    .multilineTextAlignment(.center)
                    .lineSpacing(-2)
                    .lineLimit(soon ? 1 : 2)
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
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .frame(height: 76)
            .background(
                selected || (hovering && !soon) ? Color.parchment100 : Color.clear, in: RoundedRectangle(cornerRadius: Radius.b1))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.b1)
                    .strokeBorder(
                        selected ? Color.ink900 : Color.parchment400,
                        style: StrokeStyle(lineWidth: soon ? 1 : 1.5, dash: soon ? [3, 3] : []))
            )
            .overlay(alignment: .topTrailing) {
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
                    .padding(4)
                    .accessibilityHidden(true)
                }
            }
            .overlay {
                // El foco del teclado: un filete de tinta, no el lacre (que se reserva para un acento por pantalla).
                if isFocused { Rectangle().strokeBorder(Color.ink500, lineWidth: 1).padding(-3) }
            }
            .contentShape(RoundedRectangle(cornerRadius: Radius.b1))
        }
        .buttonStyle(.plain)
        .disabled(soon)
        .onHover { inside in
            guard !soon else { return }
            hovering = inside
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .onDisappear { if hovering { NSCursor.pop(); hovering = false } }
        .accessibilityLabel(soon ? Text(verbatim: name + ", ") + Text("tools.comingSoon") : Text(verbatim: name))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(.easeOut(duration: 0.2).delay(lightDelay), value: selected)
        .animation(.easeOut(duration: Motion.micro), value: hovering)
    }
}

/// Lo que el agente trae sin conectar nada: hoy, la búsqueda web. Tiene la forma de una tarjeta marcada, pero no
/// es un botón: no hay nada que elegir ni que autorizar. El agente busca sin pedir permiso; abrir una página
/// concreta sí lo pide (`SettingsRenderer.allowedWebTools`).
private struct IncludedToolCard: View {
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "globe")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(Color.ink900)
                .frame(height: 24)
            Text("tools.web.name")
                .font(Typo.text(13.5, .medium))
                .foregroundStyle(Color.ink900)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            SmallCapsLabel("tools.included", size: 10)
                .foregroundStyle(Color.ink500)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .frame(height: 76)
        .background(Color.parchment100, in: RoundedRectangle(cornerRadius: Radius.b1))
        .overlay(RoundedRectangle(cornerRadius: Radius.b1).strokeBorder(Color.ink900, lineWidth: 1.5))
        .overlay(alignment: .topTrailing) {
            Rectangle()
                .fill(Color.ink900)
                .overlay { CheckMark().stroke(Color.onInk, lineWidth: 1.5).padding(1) }
                .frame(width: 14, height: 14)
                .padding(4)
                .accessibilityHidden(true)
        }
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
