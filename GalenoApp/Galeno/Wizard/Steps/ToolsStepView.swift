import GalenoCore
import SwiftUI

/// Paso 4: la grilla de herramientas (`docs/03` §3). El usuario marca solo las
/// que usa; eso define cuántas conexiones tendrá el paso 5.
struct ToolsStepView: View {
    @EnvironmentObject private var wizard: WizardState

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Space.s12), count: 5)

    var body: some View {
        StepScaffold(step: .tools) {
            VStack(alignment: .leading, spacing: Space.s12) {
                LazyVGrid(columns: columns, spacing: Space.s12) {
                    ForEach(Tool.allCases) { tool in
                        ToolCard(tool: tool)
                    }
                }

                if wizard.isSelected(.googleMeet) {
                    Label("tools.meetNote", systemImage: "info.circle")
                        .font(.galenoCaption)
                        .foregroundStyle(Color.ink700)
                }

                summary

                if !wizard.connections.isEmpty {
                    DopamineLine(key: "dopamine.tools")
                }
            }
        }
    }

    /// "Vas a conectar 5 herramientas · ~8 min".
    @ViewBuilder
    private var summary: some View {
        let count = wizard.selectedTools.count
        let minutes = wizard.estimatedSetupMinutes
        Group {
            switch count {
            case 0: Text("tools.summary.none")
            case 1: Text("tools.summary.one \(minutes)")
            default: Text("tools.summary.other \(count) \(minutes)")
            }
        }
        .font(.galenoBody)
        .foregroundStyle(Color.ink900)
        .animation(nil, value: count)
    }
}

/// Una tarjeta de la grilla (`docs/04` §5): papel, borde fino y sin sombra. La
/// marcada lleva borde de 1,5 px en `ink-900` y una palomita en `moss-700`.
private struct ToolCard: View {
    @EnvironmentObject private var wizard: WizardState
    let tool: Tool

    var body: some View {
        let selected = wizard.isSelected(tool)
        let name = tool.displayName(in: wizard.language)

        Button {
            wizard.toggle(tool)
        } label: {
            VStack(spacing: Space.s8) {
                ToolIcon(tool: tool)
                Text(verbatim: name)
                    .font(.galenoCaption)
                    .foregroundStyle(Color.ink900)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.vertical, Space.s12)
            .padding(.horizontal, Space.s8)
            .background(Color.parchment100, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selected ? Color.ink900 : Color.parchment300, lineWidth: selected ? 1.5 : 1)
            )
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.moss700)
                        .padding(Space.s4)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(.easeOut(duration: 0.15), value: selected)
    }
}

#Preview {
    let state = WizardState()
    state.toggle(.googleMeet)
    state.toggle(.slack)
    return ToolsStepView()
        .environmentObject(state)
        .frame(width: WindowMetrics.width, height: 440)
        .background(Color.parchment50)
}
