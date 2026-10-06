import GalenoCore
import SwiftUI

/// Paso 5: conecta una por una (`docs/03` §3). Es un sub-wizard: el contenedor del
/// wizard oculta su barra de navegación mientras dura (`WizardState.hidesNavigation`)
/// y el propio sub-wizard lleva sus botones.
struct ConnectStepView: View {
    @EnvironmentObject private var wizard: WizardState

    var body: some View {
        Group {
            if !wizard.claudeStatus.isReady || wizard.claudeSetup != .idle {
                // El wizard corto y «Gestionar» no pasan por el paso 2: si Claude Code falta, está viejo o
                // sin sesión, se arregla aquí antes de conectar nada, en vez de fallar en cada herramienta.
                ClaudeSetupGate()
            } else if let flow = wizard.connectFlow {
                ConnectFlowView(flow: flow)
            } else {
                InkSpinner(size: 20)
            }
        }
        .onAppear { beginIfReady() }
        .onChange(of: wizard.claudeStatus) { _, _ in beginIfReady() }
        .onChange(of: wizard.claudeSetup) { _, _ in beginIfReady() }
    }

    private func beginIfReady() {
        if wizard.claudeStatus.isReady, wizard.claudeSetup == .idle { wizard.beginConnecting() }
    }
}

/// «Antes de conectar»: lo mismo que el paso 2, a pantalla completa y con una salida hacia atrás (aquí no
/// hay barra de navegación).
private struct ClaudeSetupGate: View {
    @EnvironmentObject private var wizard: WizardState
    @Environment(\.galenoEmbeddedConnection) private var embedded

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepTitle(text: Text("connect.claude.title"))
            ClaudeSetupContent()
            Spacer(minLength: 0)
            if !wizard.claudeSetup.isWorking, !embedded {
                Button("connect.backToTools") { wizard.back() }
                    .buttonStyle(.inkTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, Space.s48)
        .padding(.top, 28)
        .padding(.bottom, Space.s16)
    }
}

private struct ConnectFlowView: View {
    @ObservedObject var flow: ConnectFlow
    @Environment(\.galenoEmbeddedConnection) private var embedded

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
        // Dentro del detalle hay una sola herramienta: una tira con un solo logo no cuenta nada.
        if embedded { return false }
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
