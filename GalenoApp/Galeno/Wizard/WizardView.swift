import AppKit
import GalenoCore
import SwiftUI

/// El contenedor del wizard (B1): la cabecera con el filete que avanza, el paso actual en el centro
/// y la navegación abajo. Encima de todo, el grano del papel.
struct WizardView: View {
    @EnvironmentObject private var wizard: WizardState
    @Environment(\.galenoReduceMotion) private var reduceMotion
    @Environment(\.galenoCancelWizard) private var cancelWizard

    /// La portada de la primera vez: el retrato y el nombre, un momento. Después, nunca más.
    @AppStorage(Prefs.splashShown) private var splashShown = false
    @State private var splashVisible = true

    var body: some View {
        Group {
            if let draft = wizard.pendingDraft {
                ResumeView(draft: draft)
            } else {
                content
            }
        }
        .background(Color.parchment50)
        .overlay {
            if !splashShown && splashVisible { SplashView() }
        }
        .task {
            guard !splashShown else { return }
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 800 : 1500))
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { splashVisible = false }
            splashShown = true
        }
        .overlay { GrainOverlay() }
        .animation(reduceMotion ? nil : .pageTurn, value: wizard.step)
        // Esc vuelve un paso, salvo donde el paso lleva su propia salida.
        .onExitCommand {
            switch wizard.step {
            case .welcome, .connect, .generating: break
            default:
                if wizard.isFirstStep { cancelWizard?() } else { wizard.back() }
            }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            ProgressHeader()
            stepScreen
                .id(wizard.step)
                .transition(reduceMotion ? .opacity : .pageTurn)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if !wizard.hidesNavigation {
                Rectangle().fill(Color.parchment300).frame(height: 1)
                NavigationBar()
            }
        }
        // Cambio de idioma: todo el texto se funde a cero y vuelve (120 + 120 ms).
        .opacity(wizard.languageFading ? 0 : 1)
        .animation(.easeInOut(duration: 0.12), value: wizard.languageFading)
    }

    @ViewBuilder
    private var stepScreen: some View {
        switch wizard.step {
        case .welcome: WelcomeStepView()
        case .detection: DetectionStepView()
        case .agent: AgentStepView()
        case .tools: ToolsStepView()
        case .connect: ConnectStepView()
        case .skills: SkillsStepView()
        case .rules: RulesStepView()
        case .review: ReviewStepView()
        case .generating: GeneratingStepView()
        case .done: DoneStepView()
        }
    }
}

/// La cabecera de B1: «Paso 3 de 10 · ~12 min» en versalitas a la izquierda, el nombre del paso en
/// cursiva a la derecha, y debajo el filete de 1 pt con el trazo de 3 pt que avanza.
private struct ProgressHeader: View {
    @EnvironmentObject private var wizard: WizardState
    @Environment(\.locale) private var locale

    private var label: String {
        Localized.string("wizard.progress.step %lld %lld", wizard.stepNumber, wizard.stepCount, locale: locale)
            + " · "
            + Localized.string("wizard.progress.timeLeft %lld", wizard.estimatedMinutesLeft, locale: locale)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SmallCapsText(string: label, size: 13)
                    .foregroundStyle(Color.ink700)
                    .lineLimit(1)
                Spacer()
                Text(wizard.step.title)
                    .font(Typo.display(15, italic: true))
                    .foregroundStyle(Color.ink500)
                if wizard.step.rawValue >= WizardStep.agent.rawValue, wizard.step != .generating, wizard.step != .done,
                    !wizard.agentName.trimmingCharacters(in: .whitespaces).isEmpty
                {
                    PreviewButton()
                }
                if wizard.step != .generating { HelpButton(step: wizard.step) }
            }
            RuleProgress(value: wizard.progress)
                .accessibilityValue(Text(verbatim: label))
        }
        .padding(.horizontal, Space.s48)
        .padding(.top, 18)
    }
}

/// Atrás a la izquierda; a la derecha, la frase de dopamina y el botón que dice qué hace.
private struct NavigationBar: View {
    @EnvironmentObject private var wizard: WizardState
    @Environment(\.galenoFinishWizard) private var finishWizard
    @Environment(\.galenoCancelWizard) private var cancelWizard

    private var agentName: String { wizard.agentName.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// La frase junto al botón: solo cuando el paso ya está completo. «Listo» la lleva en la página.
    private var dopamine: LocalizedStringKey? {
        switch wizard.step {
        case .welcome: return "dopamine.welcome"
        case .detection: return wizard.claudeStatus.isFound ? "dopamine.detection" : nil
        case .agent: return wizard.agentNameIssue == nil ? "dopamine.agent" : nil
        case .tools: return wizard.connections.isEmpty ? nil : "dopamine.tools \(agentName)"
        default: return nil
        }
    }

    /// El primario dice qué hace: «Empezar», «Conectar 5 herramientas», «Escribir a Hera», «Terminar».
    private var primaryLabel: Text {
        switch wizard.step {
        case .welcome: Text("wizard.start")
        // «Conectar 5 herramientas»: solo las que faltan por conectar. Si ya están todas, «Siguiente».
        case .tools where wizard.hasToConnect: Text("tools.primary \(wizard.toConnect.count)")
        case .review: Text("review.primary \(agentName)")
        case .done: Text("wizard.finish")
        default: Text("wizard.next")
        }
    }

    var body: some View {
        HStack(spacing: Space.s16) {
            if wizard.canGoBack {
                Button("wizard.back") { wizard.back() }
                    .buttonStyle(InkButtonStyle(.secondary, padding: 20))
            } else if wizard.mode == .short, wizard.isFirstStep, let cancelWizard {
                // El wizard corto no tiene «Atrás» en su primer paso: se cancela y se vuelve al home.
                Button("wizard.cancel") { cancelWizard() }
                    .buttonStyle(InkButtonStyle(.secondary, padding: 20))
            }

            Spacer(minLength: 0)

            if let dopamine {
                Text(dopamine)
                    .font(Typo.display(15, italic: true))
                    .foregroundStyle(Color.ink500)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 360, alignment: .trailing)
                    .fixedSize(horizontal: false, vertical: true)
                    // La frase de dopamina entra la última: 400 ms después del contenido.
                    .id(wizard.step)
                    .appearing(after: 0.4)
            }

            Button {
                if wizard.isLastStep {
                    if let finishWizard { finishWizard() } else { NSApplication.shared.terminate(nil) }
                } else {
                    wizard.next()
                }
            } label: {
                primaryLabel
            }
            .buttonStyle(InkButtonStyle(.primary, padding: 26))
            .keyboardShortcut(.defaultAction)
            .disabled(!wizard.canGoForward && !wizard.isLastStep)
        }
        .padding(.horizontal, Space.s48)
        .padding(.vertical, 14)
    }
}

/// «Ibas por el paso 5»: se ofrece seguir donde se quedó o empezar de nuevo. Ocupa toda la ventana,
/// sin cabecera ni navegación, hasta que el usuario decide.
private struct ResumeView: View {
    @EnvironmentObject private var wizard: WizardState
    let draft: WizardDraft

    private var stepNumber: Int { draft.step + 1 }
    private var connected: Int { draft.connections.filter { $0.status == .connected }.count }
    private var name: String { draft.agentName.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                SmallCapsLabel("resume.kicker", size: 13, tracking: 0.14)
                    .foregroundStyle(Color.seal700)
                    .padding(.bottom, 10)
                StepTitle(text: Text("resume.title \(stepNumber)"), size: 36)
                    .padding(.bottom, 10)
                VStack(alignment: .leading, spacing: 4) {
                    if !name.isEmpty { Text("resume.agent \(name)") }
                    if !draft.connections.isEmpty {
                        Text("resume.tools \(connected) \(draft.connections.count)")
                    }
                    Text("resume.ask")
                }
                .font(Typo.body)
                .foregroundStyle(Color.ink700)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 520, alignment: .leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Rectangle().fill(Color.parchment300).frame(height: 1)
            HStack(spacing: Space.s16) {
                Button("resume.restart") { wizard.discardDraft() }
                    .buttonStyle(InkButtonStyle(.secondary, padding: 20))
                Spacer()
                Button("resume.continue") { wizard.resumeDraft() }
                    .buttonStyle(InkButtonStyle(.primary, padding: 26))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, Space.s48)
            .padding(.vertical, 14)
        }
    }
}

/// «Ver cómo va quedando»: el `AGENTS.md` que Galeno escribiría ahora mismo, en solo lectura, con
/// lo nuevo desde la última vez marcado. Sirve para ver el artefacto mientras se construye.
private struct PreviewButton: View {
    @EnvironmentObject private var wizard: WizardState
    @State private var shown = false
    @State private var fresh: Set<String> = []
    @Environment(\.locale) private var locale

    private var lines: [String] {
        AgentPreview.agentsFile(for: wizard.makeConfig()).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    var body: some View {
        Button {
            if !shown {
                let current = Set(lines)
                // La primera vez no hay con qué comparar: no se marca todo.
                fresh = wizard.previewSeen.isEmpty ? [] : current.subtracting(wizard.previewSeen)
            }
            shown.toggle()
        } label: {
            Image(systemName: "doc.text")
                .font(.system(size: 11))
                .foregroundStyle(Color.ink700)
                .frame(width: 20, height: 20)
                .overlay(Circle().strokeBorder(Color.parchment400, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(Text("preview.button"))
        .accessibilityLabel(Text("preview.button"))
        .popover(isPresented: $shown, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                SmallCapsLabel("preview.title", size: 12)
                    .foregroundStyle(Color.ink500)
                Text("preview.hint")
                    .font(Typo.text(13))
                    .foregroundStyle(Color.ink500)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Text(verbatim: line.isEmpty ? " " : line)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(Color.ink900)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(fresh.contains(line) ? Color.seal100 : Color.clear)
                        }
                    }
                    .textSelection(.enabled)
                    .padding(10)
                }
                .background(Color.parchment100)
                .overlay(Rectangle().strokeBorder(Color.parchment300, lineWidth: 1))
            }
            .padding(16)
            .frame(width: 480, height: 400)
            .background(Color.parchment50)
            .environment(\.locale, locale)
            .onDisappear { wizard.previewSeen = Set(lines) }
        }
    }
}

/// El «?» de la cabecera: un popover con tres preguntas del paso y su respuesta en dos líneas.
/// Sin tour ni globos: solo aparece si el usuario lo pide.
private struct HelpButton: View {
    let step: WizardStep
    @State private var shown = false
    @Environment(\.locale) private var locale

    /// La clave se arma como `String` (no como interpolación de `LocalizedStringKey`) para que Xcode no la
    /// «extraiga» al catálogo como una clave genérica `help.%@.%lld.q`, que no existe.
    private static func helpKey(_ step: WizardStep, _ index: Int, _ part: String) -> String {
        "help." + step.slug + "." + String(index) + "." + part
    }

    var body: some View {
        Button {
            shown.toggle()
        } label: {
            Text(verbatim: "?")
                .font(Typo.display(14))
                .foregroundStyle(Color.ink700)
                .frame(width: 20, height: 20)
                .overlay(Circle().strokeBorder(Color.parchment400, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("help.button"))
        .popover(isPresented: $shown, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 14) {
                SmallCapsLabel("help.title", size: 12)
                    .foregroundStyle(Color.ink500)
                ForEach(1...3, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LocalizedStringKey(Self.helpKey(step, index, "q")))
                            .font(Typo.text(15, .semibold))
                            .foregroundStyle(Color.ink900)
                        Text(LocalizedStringKey(Self.helpKey(step, index, "a")))
                            .font(Typo.text(14))
                            .lineSpacing(1.5)
                            .foregroundStyle(Color.ink700)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(18)
            .frame(width: 360, alignment: .leading)
            .background(Color.parchment50)
            // El popover es otra ventana: el idioma del wizard hay que pasárselo.
            .environment(\.locale, locale)
        }
    }
}

/// La portada de la primera vez (B1): el retrato en su círculo y el nombre. Sin cita: una frase de
/// Galeno solo entra cuando esté verificada en la fuente.
private struct SplashView: View {
    var body: some View {
        VStack(spacing: 18) {
            if PortraitMark.isAvailable { PortraitMark(size: 120, doubleRing: true).stamp() }
            (Text(verbatim: "Galeno") + Text(verbatim: ".").foregroundColor(Color.seal700))
                .font(Typo.display(40))
                .kerning(1.2)
                .foregroundStyle(Color.ink900)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.parchment50)
        .transition(.opacity)
        .accessibilityHidden(true)
    }
}
