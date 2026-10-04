import GalenoCore
import SwiftUI

/// Paso 9: el motor escribe la carpeta del agente y la registra. Los pasos se ven mientras
/// ocurre (`docs/03` §3); si algo falla, se dice qué y se puede reintentar o volver a las reglas.
struct GeneratingStepView: View {
    @EnvironmentObject private var wizard: WizardState

    var body: some View {
        StepScaffold(step: .generating) {
            if let generation = wizard.generation {
                Progress(generation: generation)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .onAppear { wizard.beginGeneration() }
    }
}

private struct Progress: View {
    @EnvironmentObject private var wizard: WizardState
    @ObservedObject var generation: GenerationFlow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s16) {
            Text("generating.headline \(wizard.makeConfig().agentName)")
                .font(.galenoTitle)
                .foregroundStyle(Color.ink900)

            VStack(alignment: .leading, spacing: Space.s12) {
                ForEach(GenerationFlow.Step.allCases, id: \.self) { step in
                    StepRow(step: step, generation: generation)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: generation.completed)

            if case .failed(let detail) = generation.phase {
                NoticePanel(kind: .seal) {
                    Text("generating.failed")
                        .font(.galenoBody.weight(.semibold))
                        .foregroundStyle(Color.ink900)
                    Text("generating.detail \(detail)")
                        .font(.galenoCaption)
                        .foregroundStyle(Color.ink500)
                        .textSelection(.enabled)
                    HStack(spacing: Space.s12) {
                        Button("generating.back") { wizard.leaveFailedGeneration() }
                            .buttonStyle(.bordered)
                        Button("generating.retry") { generation.retry() }
                            .buttonStyle(.bordered)
                    }
                }
            }

            DopamineLine(key: "dopamine.generating")
        }
        // Terminó bien: un instante para ver el último check y se pasa a «Listo».
        .task(id: generation.phase) {
            guard generation.phase == .succeeded else { return }
            try? await Task.sleep(for: .milliseconds(900))
            wizard.finishGeneration()
        }
    }
}

private struct StepRow: View {
    let step: GenerationFlow.Step
    @ObservedObject var generation: GenerationFlow

    var body: some View {
        HStack(spacing: Space.s12) {
            mark
                .frame(width: 20, height: 20)
            Text(LocalizedStringKey(titleKey))
                .font(.galenoBody)
                .foregroundStyle(isDone || isCurrent ? Color.ink900 : Color.ink500)
        }
        .accessibilityElement(children: .combine)
    }

    private var isDone: Bool { generation.completed.contains(step) }
    private var isCurrent: Bool { generation.current == step && !isDone }
    private var hasFailed: Bool {
        if case .failed = generation.phase { return isCurrent }
        return false
    }

    @ViewBuilder
    private var mark: some View {
        if isDone {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.moss700)
        } else if hasFailed {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.seal700)
        } else if isCurrent {
            ProgressView().controlSize(.small)
        } else {
            Image(systemName: "circle").foregroundStyle(Color.parchment300)
        }
    }

    private var titleKey: String {
        switch step {
        case .rules: "generating.step.rules"
        case .tools: "generating.step.tools"
        case .skills: "generating.step.skills"
        case .saving: "generating.step.saving"
        }
    }
}

#Preview {
    GeneratingStepView()
        .environmentObject(WizardState())
        .frame(width: WindowMetrics.width, height: 400)
        .background(Color.parchment50)
}
