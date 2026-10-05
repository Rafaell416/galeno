import GalenoCore
import SwiftUI

/// Paso 9: el motor escribe la carpeta del agente y la registra. Los pasos se ven mientras
/// ocurre (`docs/03` §3); si algo falla, se dice qué y se puede reintentar o volver a las reglas.
struct GeneratingStepView: View {
    @EnvironmentObject private var wizard: WizardState

    var body: some View {
        Group {
            if let generation = wizard.generation {
                Progress(generation: generation)
            } else {
                InkSpinner(size: 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { wizard.beginGeneration() }
    }
}

/// La pantalla «Escribiendo» (B1): centrada, con el nombre del agente, los cuatro renglones que se
/// van escribiendo y, si algo falla, qué pasó y cómo seguir.
private struct Progress: View {
    @EnvironmentObject private var wizard: WizardState
    @ObservedObject var generation: GenerationFlow
    @Environment(\.galenoReduceMotion) private var reduceMotion

    private var agentName: String { wizard.agentName.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// Gestionando un agente que ya existe: se actualiza, no se escribe de cero.
    private var updating: Bool { wizard.mode == .edit }

    /// Las líneas reales del `AGENTS.md` que el motor va a escribir (el mismo texto que el paso
    /// «Revisar», sin escribir nada). Lo que se ve es dato verdadero, no una animación inventada.
    private var fileLines: [String] {
        AgentPreview.agentsFile(for: wizard.makeConfig())
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Las tres últimas líneas escritas hasta ahora: avanzan con los renglones completados.
    /// Cada una lleva su número de línea: así una línea nueva entra abajo y empuja a las anteriores, como un log.
    private var visibleLines: [(index: Int, text: String)] {
        let all = fileLines
        let total = GenerationFlow.Step.allCases.count
        let done = generation.phase == .succeeded ? total : min(generation.completed.count, total)
        let written = max(min(all.count, 3), all.count * done / total)
        return Array(all.enumerated().map { (index: $0.offset, text: $0.element) }.prefix(written).suffix(3))
    }

    private var hasFailed: Bool {
        if case .failed = generation.phase { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            // La pluma, como en el diseño. Nunca junto a un error: si algo falla, la lámina se va.
            if !hasFailed {
                Plate(
                    asset: "plate-pluma", caption: "pluma sobre un folio, grabado de línea",
                    size: CGSize(width: 170, height: 108), printOnPaper: true
                )
                .padding(.bottom, 10)
                .transition(.opacity)
            }
            Text(updating ? "generating.headline.edit \(agentName)" : "generating.headline \(agentName)")
                .font(Typo.stepTitle)
                .foregroundStyle(Color.ink900)
                .padding(.bottom, 4)
            Text("step.generating.summary")
                .font(Typo.list)
                .foregroundStyle(Color.ink500)
                .padding(.bottom, 22)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(GenerationFlow.Step.allCases, id: \.self) { step in
                    StepRow(step: step, generation: generation)
                }
            }
            // Reintentar empieza de cero: los renglones se desvanecen (200 ms) y los trazos se dibujan otra vez.
            .id(generation.attempt)
            .transition(.opacity)
            .frame(width: 380, alignment: .leading)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: generation.completed)
            .animation(.easeOut(duration: 0.2), value: generation.attempt)

            // Lo que se va escribiendo: las tres últimas líneas, como quien mira por encima del hombro.
            VStack(alignment: .leading, spacing: 3) {
                ForEach(visibleLines, id: \.index) { line in
                    HStack(spacing: 2) {
                        Text(verbatim: line.text)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        // El cursor fino al final de lo último escrito, mientras se escribe.
                        if line.index == visibleLines.last?.index, generation.phase == .running {
                            WritingCursor()
                        }
                    }
                    .transition(.opacity)
                }
            }
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(Color.ink500)
            .frame(width: 380, alignment: .topLeading)
            .frame(minHeight: 58, alignment: .top)
            .padding(.top, 8)
            .overlay(alignment: .top) { Rectangle().fill(Color.parchment300).frame(height: 1) }
            .padding(.top, 16)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: generation.completed.count)
            .accessibilityHidden(true)

            if case .failed(let detail) = generation.phase {
                NoticePanel(kind: .seal) {
                    Text(updating ? "generating.failed.edit \(agentName)" : "generating.failed \(agentName)")
                        .font(Typo.list)
                        .foregroundStyle(Color.ink900)
                    Text("generating.detail \(detail)")
                        .font(Typo.mono)
                        .foregroundStyle(Color.ink500)
                        .textSelection(.enabled)
                }
                .frame(width: 420)
                .padding(.top, 20)
                .transition(.opacity)
                HStack(spacing: Space.s12) {
                    Button("generating.back") { wizard.leaveFailedGeneration() }
                        .buttonStyle(InkButtonStyle(.secondary, padding: 18))
                    Button("connect.retry") { generation.retry() }
                        .buttonStyle(.inkPrimary)
                }
                .padding(.top, 14)
                .transition(.opacity)
            } else {
                Text(updating ? "dopamine.generating.edit" : "dopamine.generating")
                    .font(Typo.display(18, italic: true))
                    .foregroundStyle(Color.ink500)
                    .padding(.top, 26)
                    // Aparece a los 0,6 s, cuando el usuario ya empezó a esperar.
                    .appearing(after: 0.6)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s48)
        // El panel de fallo entra en 300 ms y, al reintentar, se desvanece en 200 ms.
        .animation(.easeOut(duration: hasFailed ? Motion.enter : 0.2), value: hasFailed)
        .onChange(of: hasFailed) { _, failed in if failed { Sounds.play(.failed) } }
        // Terminó bien: un instante para ver el último renglón y se pasa a «Listo».
        .task(id: generation.phase) {
            guard generation.phase == .succeeded else { return }
            try? await Task.sleep(for: .milliseconds(600))
            wizard.finishGeneration()
        }
    }
}

private struct StepRow: View {
    @EnvironmentObject private var wizard: WizardState
    let step: GenerationFlow.Step
    @ObservedObject var generation: GenerationFlow

    var body: some View {
        HStack(spacing: Space.s12) {
            mark
                .frame(width: 22, height: 22)
            ZStack(alignment: .bottomLeading) {
                title
                    .font(Typo.body)
                    .foregroundStyle(hasFailed ? Color.seal700 : isDone || isCurrent ? Color.ink900 : Color.ink500)
                // «Escribir»: el renglón en curso se subraya de izquierda a derecha.
                // Si falla, el trazo se queda a medias y se pone en lacre: ahí se paró.
                // Si el paso termina antes que el trazo, el trazo salta al final: nada espera a la animación.
                if isCurrent || isDone {
                    WriteUnderline(color: hasFailed ? .seal700 : .ink900, stopped: hasFailed, finished: isDone)
                        .offset(y: 3).id(step)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var isDone: Bool { generation.completed.contains(step) }
    private var isCurrent: Bool { generation.current == step && !isDone }
    private var hasFailed: Bool {
        if case .failed = generation.phase { return isCurrent }
        return false
    }

    /// Un anillo de 18 pt: vacío, en curso, con palomita o con aviso.
    @ViewBuilder
    private var mark: some View {
        ZStack {
            Circle().strokeBorder(ringColor, lineWidth: 1.5).frame(width: 18, height: 18)
            if isDone {
                // La palomita se traza (300 ms) cuando el paso termina de verdad.
                TracedShape(shape: CheckMark(), lineWidth: 1.5, color: .moss700, duration: 0.3)
                    .frame(width: 18, height: 18)
            } else if hasFailed {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(Color.seal700)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: Motion.micro), value: hasFailed)
    }

    private var ringColor: Color {
        if isDone { return .moss700 }
        if hasFailed { return .seal700 }
        return .parchment400
    }

    private var title: Text {
        switch step {
        case .rules: Text(wizard.mode == .edit ? "generating.step.rules.edit" : "generating.step.rules")
        case .tools: Text("generating.step.tools")
        case .skills: Text(wizard.mode == .edit ? "generating.step.skills.edit" : "generating.step.skills")
        case .saving: Text("generating.step.saving \(wizard.agentName.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }
}

/// El cursor fino que parpadea al final de lo que se va escribiendo (500 ms). Con «Reducir movimiento» queda fijo.
private struct WritingCursor: View {
    @Environment(\.galenoReduceMotion) private var reduceMotion
    @State private var visible = true

    var body: some View {
        Rectangle()
            .fill(Color.ink500)
            .frame(width: 1, height: 12)
            .opacity(visible ? 1 : 0)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { visible = false }
            }
            .accessibilityHidden(true)
    }
}

#Preview {
    GeneratingStepView()
        .environmentObject(WizardState())
        .frame(width: WindowMetrics.width, height: 400)
        .background(Color.parchment50)
}
