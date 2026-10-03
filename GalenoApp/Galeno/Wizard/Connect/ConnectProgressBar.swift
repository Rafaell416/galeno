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

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s8) {
            Text("connect.progress \(flow.connectedCount) \(flow.total)")
                .font(.galenoCaption.smallCaps())
                .kerning(1.2)
                .foregroundStyle(Color.ink700)

            HStack(spacing: Space.s8) {
                ForEach(flow.tools) { tool in
                    chip(for: tool)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("connect.progress \(flow.connectedCount) \(flow.total)"))
    }

    private func chip(for tool: Tool) -> some View {
        let status = flow.statuses[tool] ?? .selected
        let isCurrent = tool == currentTool
        return ToolIcon(
            tool: tool, size: 18,
            color: status == .connected ? Color.ink900 : Color.ink500
        )
        .frame(width: 34, height: 34)
        .background(
            status == .connected ? Color.parchment100 : Color.clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isCurrent ? Color.ink900 : Color.parchment300,
                    lineWidth: isCurrent ? 1.5 : 1)
        )
        .overlay(alignment: .bottomTrailing) {
            if status == .connected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.moss700)
                    .background(Circle().fill(Color.parchment50))
                    .offset(x: 4, y: 4)
                    .transition(.opacity)
            }
        }
        .opacity(status == .skipped ? 0.4 : 1)
        .animation(.easeOut(duration: 0.4), value: status)
    }
}
