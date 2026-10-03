import AppKit
import SwiftUI

/// El contenedor del wizard: barra de progreso arriba (siempre visible), el paso
/// actual en el centro y la navegación abajo.
struct WizardView: View {
    @EnvironmentObject private var wizard: WizardState

    var body: some View {
        VStack(spacing: 0) {
            ProgressHeader()
            Divider()
            stepScreen
                .id(wizard.step)
                .transition(.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            NavigationBar()
        }
        .background(Color.parchment50)
        .animation(.easeOut(duration: 0.2), value: wizard.step)
    }

    @ViewBuilder
    private var stepScreen: some View {
        switch wizard.step {
        case .welcome: WelcomeStepView()
        case .detection: DetectionStepView()
        case .agent: AgentStepView()
        case .tools: ToolsStepView()
        case .connect: ConnectStepView()
        case .sources: SourcesStepView()
        case .skills: SkillsStepView()
        case .rules: RulesStepView()
        case .generating: GeneratingStepView()
        case .done: DoneStepView()
        }
    }
}

/// "PASO 3 DE 10" y la barra. Nativa, con el relleno en `ink-900` y no en un
/// color (`docs/04` §6).
private struct ProgressHeader: View {
    @EnvironmentObject private var wizard: WizardState

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s8) {
            Text("wizard.progress.step \(wizard.step.number) \(wizard.stepCount)")
                .font(.galenoCaption.smallCaps())
                .kerning(1.2)
                .foregroundStyle(Color.ink700)
            ProgressView(value: wizard.progress)
                .progressViewStyle(.linear)
                .tint(Color.ink900)
                .accessibilityLabel(Text("wizard.progress.label"))
                .accessibilityValue(Text("wizard.progress.step \(wizard.step.number) \(wizard.stepCount)"))
        }
        .padding(.horizontal, Space.s48)
        .padding(.vertical, Space.s16)
    }
}

/// Atrás y Siguiente. El primario es el botón nativo, con tinte `ink-900`.
private struct NavigationBar: View {
    @EnvironmentObject private var wizard: WizardState

    var body: some View {
        HStack {
            Button("wizard.back") { wizard.back() }
                .buttonStyle(.bordered)
                .opacity(wizard.canGoBack ? 1 : 0)
                .disabled(!wizard.canGoBack)

            Spacer()

            Button {
                if wizard.isLastStep {
                    NSApplication.shared.terminate(nil)
                } else {
                    wizard.next()
                }
            } label: {
                Text(wizard.isLastStep ? "wizard.finish" : "wizard.next")
                    .foregroundStyle(Color.parchment50)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.ink900)
            .keyboardShortcut(.defaultAction)
        }
        .controlSize(.large)
        .padding(.horizontal, Space.s48)
        .padding(.vertical, Space.s16)
    }
}
