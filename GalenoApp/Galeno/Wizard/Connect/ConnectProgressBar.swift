import GalenoCore
import SwiftUI

/// Los logos de las herramientas, unidos por una línea punteada, que se van encendiendo conforme se conectan
/// (`docs/03` §3). **Sin cuenta escrita** («2 de 5», «1 de 3»; 6 oct 2026, petición de Rafa): competía con el
/// «Paso 5 de 7» del asistente, que es el único progreso que se numera. La cuenta queda solo para VoiceOver.
struct ConnectProgressBar: View {
    @ObservedObject var flow: ConnectFlow
    @EnvironmentObject private var wizard: WizardState

    private var currentTool: Tool? {
        if case .connection(let tool) = flow.screen { return tool }
        return nil
    }

    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            ForEach(Array(flow.tools.enumerated()), id: \.element) { index, tool in
                if index > 0 {
                    // El hilo que une un icono con el siguiente: en tinta una vez que el de la izquierda está
                    // conectado; en gris mientras no.
                    DottedLine()
                        .stroke(
                            (flow.statuses[flow.tools[index - 1]] ?? .selected) == .connected
                                ? Color.ink700 : Color.parchment400,
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [0.1, 5]))
                        .frame(width: 30, height: 2)
                        .animation(.easeOut(duration: 0.2), value: flow.statuses[flow.tools[index - 1]])
                        .accessibilityHidden(true)
                }
                // Cada icono lleva a su conexión (demo de Aquiles, 5 oct 2026: quiso pasar de una a otra
                // pulsándolos). La que ya está conectada y la de ahora no hacen nada.
                Button { flow.jump(to: tool) } label: { chip(for: tool) }
                    .buttonStyle(.plain)
                    .disabled(!flow.canJump(to: tool))
                    .pointingHandOnHover(flow.canJump(to: tool))
                    .help(Text(verbatim: tool.displayName(in: wizard.language)))
                    .accessibilityLabel(Text(verbatim: tool.displayName(in: wizard.language)))
                    .accessibilityValue(statusLabel(for: tool))
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: Localized.string("connect.progress %lld %lld", flow.connectedCount, flow.total, locale: locale)))
    }

    private func statusLabel(for tool: Tool) -> Text {
        switch flow.statuses[tool] ?? .selected {
        case .connected: Text("tools.connected")
        case .skipped: Text("connect.chip.skipped")
        default: tool == currentTool ? Text("connect.chip.current") : Text("connect.chip.pending")
        }
    }

    private func chip(for tool: Tool) -> some View {
        let status = flow.statuses[tool] ?? .selected
        let isCurrent = tool == currentTool
        return ToolIcon(
            tool: tool, size: 16,
            color: status == .connected ? Color.ink900 : Color.ink700
        )
        .frame(width: 30, height: 30)
        .overlay(
            Rectangle().strokeBorder(isCurrent ? Color.ink900 : Color.parchment400, lineWidth: 1.5)
        )
        .overlay(alignment: .bottom) {
            // El logo activo: un filete de 1,5 pt bajo él se traza de izquierda a derecha (300 ms).
            if isCurrent {
                WriteUnderline(color: .ink900, duration: Motion.enter)
                    .frame(height: 1.5)
                    .padding(.horizontal, 4)
                    .offset(y: 7)
                    .id(tool)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            // Conectada: el check de 12 pt se traza. Saltada: un guion fino, sin celebrar.
            if status == .connected {
                Circle().fill(Color.moss700)
                    .frame(width: 12, height: 12)
                    .overlay {
                        TracedShape(shape: CheckMark(), lineWidth: 1.3, color: .white, duration: 0.3)
                            .padding(2.5)
                    }
                    .offset(x: 5, y: 5)
            } else if status == .skipped {
                Text(verbatim: "–")
                    .font(Typo.text(13, .medium))
                    .foregroundStyle(Color.ink700)
                    .offset(x: 5, y: 7)
            }
        }
        .contentShape(Rectangle())
        // Apagados hasta que se conectan: los que faltan se ven, pero tenues.
        .opacity(status == .skipped ? 0.3 : status == .connected || isCurrent ? 1 : 0.4)
        // «Encender»: el logo conectado pasa a tinta plena en 200 ms.
        .animation(.easeOut(duration: 0.2), value: status)
        .animation(.easeOut(duration: Motion.micro), value: isCurrent)
    }
}

/// Una raya horizontal, para dibujarla punteada.
private struct DottedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

/// El cursor de mano sobre algo que se puede pulsar y no parece un botón. Lo que pone, lo quita.
private struct PointingHand: ViewModifier {
    let enabled: Bool
    @State private var pushed = false

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                if inside, enabled, !pushed {
                    NSCursor.pointingHand.push()
                    pushed = true
                } else if !inside, pushed {
                    NSCursor.pop()
                    pushed = false
                }
            }
            .onDisappear {
                if pushed {
                    NSCursor.pop()
                    pushed = false
                }
            }
    }
}

extension View {
    func pointingHandOnHover(_ enabled: Bool = true) -> some View { modifier(PointingHand(enabled: enabled)) }
}
