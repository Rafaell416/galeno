import GalenoCore
import SwiftUI

/// "2 de 5 conectadas" y los logos de las herramientas, que se van encendiendo
/// conforme se conectan (`docs/03` §3).
struct ConnectProgressBar: View {
    @ObservedObject var flow: ConnectFlow
    @EnvironmentObject private var wizard: WizardState

    private var currentTool: Tool? {
        if case .connection(let tool) = flow.screen { return tool }
        return nil
    }

    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: Space.s8) {
            SmallCapsText(
                string: Localized.string("connect.progress %lld %lld", flow.connectedCount, flow.total, locale: locale),
                size: 13, tracking: 0.12
            )
            .foregroundStyle(Color.ink700)
            .lineLimit(1)
            // «2 de 5 conectadas» cuenta con el rodillo de dígitos.
            .contentTransition(.numericText())
            .animation(.easeOut(duration: Motion.micro), value: flow.connectedCount)
            .padding(.trailing, Space.s8)

            ForEach(flow.tools) { tool in
                chip(for: tool)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("connect.progress \(flow.connectedCount) \(flow.total)"))
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
        .opacity(status == .skipped ? 0.35 : status == .connected || isCurrent ? 1 : 0.55)
        // «Encender»: el logo conectado pasa a tinta plena en 200 ms.
        .animation(.easeOut(duration: 0.2), value: status)
        .animation(.easeOut(duration: Motion.micro), value: isCurrent)
    }
}
