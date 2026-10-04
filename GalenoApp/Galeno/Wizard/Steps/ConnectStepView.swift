import GalenoCore
import SwiftUI

/// Paso 5: conecta una por una (`docs/03` §3). Es un sub-wizard: el contenedor del
/// wizard oculta su barra de navegación mientras dura (`WizardState.hidesNavigation`)
/// y el propio sub-wizard lleva sus botones.
struct ConnectStepView: View {
    @EnvironmentObject private var wizard: WizardState

    var body: some View {
        Group {
            if let flow = wizard.connectFlow {
                ConnectFlowView(flow: flow)
            } else {
                InkSpinner(size: 20)
            }
        }
        .onAppear { wizard.beginConnecting() }
    }
}

private struct ConnectFlowView: View {
    @ObservedObject var flow: ConnectFlow

    var body: some View {
        VStack(spacing: 0) {
            if showsProgress {
                ConnectProgressBar(flow: flow)
                    .padding(.horizontal, Space.s48)
                    .padding(.top, 22)
                    .padding(.bottom, 6)
            }
            screen
                .id(flow.position)
                .transition(.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.easeOut(duration: 0.2), value: flow.position)
    }

    /// La barra "N de M" va en las conexiones, no en las pantallas completas.
    private var showsProgress: Bool {
        if case .connection = flow.screen { return true }
        return false
    }

    @ViewBuilder
    private var screen: some View {
        switch flow.screen {
        case .connection(let tool): ConnectionScreen(flow: flow, tool: tool)
        case .dopamine(let kind): DopamineScreen(flow: flow, kind: kind)
        case .celebration: CelebrationScreen(flow: flow)
        }
    }
}
