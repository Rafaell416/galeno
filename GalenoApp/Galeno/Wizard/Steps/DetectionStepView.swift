import AppKit
import SwiftUI

/// Paso 2: detectar Claude Code (`docs/03` §3). Galeno solo mira y guía: no
/// instala nada. Si falta, muestra el comando oficial para que el usuario lo
/// corra en su terminal.
struct DetectionStepView: View {
    @EnvironmentObject private var wizard: WizardState
    /// El último resultado que no fue «buscando»: al comprobar de nuevo, la tarjeta se queda (a media
    /// opacidad) en vez de ceder el sitio a la rueda.
    @State private var previous: ClaudeCodeStatus?

    static let installCommand = "curl -fsSL https://claude.ai/install.sh | bash"
    static let guideURL = URL(string: "https://code.claude.com/docs/en/setup")!

    private var isChecking: Bool { wizard.claudeStatus == .checking }

    /// Lo que se dibuja: el resultado anterior mientras se vuelve a buscar, si lo había.
    private var shown: ClaudeCodeStatus {
        if isChecking, let previous, previous != .checking, !previous.isFound || isLoggedOut(previous) {
            return previous
        }
        return wizard.claudeStatus
    }

    private func isLoggedOut(_ status: ClaudeCodeStatus) -> Bool {
        if case .found(_, _, let loggedIn) = status { return loggedIn == false }
        return false
    }

    var body: some View {
        StepScaffold(step: .detection, summarySize: 16, titleGap: 8, contentGap: 20) {
            switch shown {
            case .checking:
                HStack(spacing: Space.s12) {
                    InkSpinner(size: 16)
                    Text("detection.checking")
                        .font(Typo.body)
                        .foregroundStyle(Color.ink700)
                }
            case .found(let version, let path, let loggedIn):
                // `nil` es "no se pudo saber": en ese caso no se avisa de nada.
                if loggedIn == false {
                    LoggedOutPanel(version: version, path: path, isChecking: isChecking)
                } else {
                    FoundPanel(version: version, path: path, loggedIn: loggedIn == true)
                }
            case .notFound:
                NotFoundPanel(isChecking: isChecking)
            }
        }
        .onChange(of: wizard.claudeStatus) { _, status in if status != .checking { previous = status } }
        .onAppear { if wizard.claudeStatus != .checking { previous = wizard.claudeStatus } }
        .task {
            // Si ya se encontró, volver atrás y adelante no lo vuelve a buscar.
            if !wizard.claudeStatus.isFound { await wizard.detectClaudeCode() }
        }
    }
}

/// Encontrado: una caja con filete, la palomita que se traza, la versión y la ruta, que aparecen en
/// escalón (título, +80 ms la versión, +160 ms la ruta).
private struct FoundPanel: View {
    let version: String
    let path: String
    let loggedIn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                // El anillo se cierra (300 ms) y la palomita se traza (500 ms).
                SuccessMark(size: 26, circleDuration: 0.3, checkDelay: 0.3)
                VStack(alignment: .leading, spacing: 6) {
                    Text("detection.found.title")
                        .font(Typo.display(20))
                        .foregroundStyle(Color.ink900)
                        .appearing(after: 0.3)
                    (Text("detection.found.version \(version)")
                        + (loggedIn
                            ? Text(verbatim: " · ") + Text("detection.found.session").foregroundColor(Color.moss700)
                            : Text(verbatim: "")))
                        .font(Typo.list)
                        .foregroundStyle(Color.ink700)
                        .appearing(after: 0.38)
                    Text(verbatim: path)
                        .font(Typo.mono)
                        .foregroundStyle(Color.ink500)
                        .textSelection(.enabled)
                        .appearing(after: 0.46)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .background(Color.parchment100)
            .overlay(Rectangle().strokeBorder(Color.parchment300, lineWidth: 1))

            Text("detection.why")
                .font(Typo.text(14))
                .foregroundStyle(Color.ink500)
                .fixedSize(horizontal: false, vertical: true)
                .appearing(after: 0.6)
        }
    }
}

/// Instalado pero sin sesión: no bloquea, solo avisa. Entra como «encontrado», pero con un anillo
/// ocre completo y un «!» en lugar de la palomita.
private struct LoggedOutPanel: View {
    @EnvironmentObject private var wizard: WizardState
    let version: String
    let path: String
    var isChecking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                TracedShape(shape: Circle().inset(by: 0.75), lineWidth: 1.5, color: .ochre700, duration: 0.3)
                    .frame(width: 26, height: 26)
                    .overlay {
                        Text(verbatim: "!").font(Typo.text(15, .semibold)).foregroundStyle(Color.ochre700)
                            .appearing(after: 0.15, duration: 0.15)
                    }
                    .padding(.top, 2)
                NoticePanel(kind: .ochre) {
                    Text("detection.loggedOut.title")
                        .font(Typo.display(20))
                        .foregroundStyle(Color.ink900)
                    Text("detection.loggedOut.body")
                        .font(Typo.list)
                        .foregroundStyle(Color.ink700)
                        .fixedSize(horizontal: false, vertical: true)
                    (Text("detection.found.version \(version)") + Text(verbatim: " · \(path)"))
                        .font(Typo.mono)
                        .foregroundStyle(Color.ink500)
                        .textSelection(.enabled)
                        .padding(.top, 4)
                }
            }
            .opacity(isChecking ? 0.5 : 1)
            .animation(.easeOut(duration: Motion.micro), value: isChecking)
            Button("detection.recheck") { Task { await wizard.detectClaudeCode() } }
                .buttonStyle(InkButtonStyle(.secondary, padding: 20, isLoading: isChecking))
                .disabled(isChecking)
        }
    }
}

/// Qué hacer si `claude` no está: tres pasos numerados, el comando para copiar y volver a comprobar.
/// El aviso entra (300 ms); el comando se «teclea» y luego aparecen los pasos 2 y 3 en escalón.
private struct NotFoundPanel: View {
    @EnvironmentObject private var wizard: WizardState
    @Environment(\.galenoReduceMotion) private var reduceMotion
    var isChecking = false
    @State private var copied = false
    /// El bloque del comando se ilumina un momento al copiarlo («lo tomé»).
    @State private var lit = false

    private static let typingDuration = 0.6

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Group {
                NoticePanel(kind: .seal) {
                    Text("detection.notFound.title")
                        .font(Typo.display(20))
                        .foregroundStyle(Color.ink900)
                    Text("detection.notFound.body")
                        .font(Typo.list)
                        .foregroundStyle(Color.ink700)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 10) {
                    NumberedLine(number: 1) {
                        HStack(alignment: .bottom, spacing: Space.s12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("detection.step1").font(Typo.list).foregroundStyle(Color.ink900)
                                TypedCommand(text: DetectionStepView.installCommand, duration: Self.typingDuration)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(lit ? Color.parchment300 : Color.parchment200)
                                    .overlay(Rectangle().strokeBorder(Color.parchment400, lineWidth: 1))
                            }
                            Button { copyCommand() } label: {
                                CopyLabel(copied: copied, idle: "detection.copy", done: "detection.copied")
                            }
                            .buttonStyle(InkButtonStyle(.secondary, size: .bar, padding: 16))
                        }
                    }
                    NumberedLine(number: 2) {
                        Text("detection.step2").font(Typo.list).foregroundStyle(Color.ink900)
                    }
                    .appearing(after: Self.typingDuration + 0.1)
                    NumberedLine(number: 3) {
                        Text("detection.step3").font(Typo.list).foregroundStyle(Color.ink900)
                    }
                    .appearing(after: Self.typingDuration + 0.18)
                }
            }
            // Mientras se busca de nuevo, la tarjeta baja a media opacidad; si sigue sin estar, vuelve a 1.
            .opacity(isChecking ? 0.5 : 1)
            .animation(.easeOut(duration: Motion.micro), value: isChecking)

            HStack(spacing: Space.s16) {
                Button("detection.recheck") { Task { await wizard.detectClaudeCode() } }
                    .buttonStyle(InkButtonStyle(.primary, padding: 20, isLoading: isChecking))
                    .disabled(isChecking)
                // Enlace en lacre con subrayado fino, no el azul del sistema.
                Link("detection.guide", destination: DetectionStepView.guideURL)
                    .font(Typo.list)
                    .foregroundStyle(Color.seal700)
                    .underline()
            }
        }
        .appearing(after: 0, duration: Motion.enter)
    }

    private func copyCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(DetectionStepView.installCommand, forType: .string)
        copied = true
        withAnimation(.easeOut(duration: Motion.micro)) { lit = true }
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.easeOut(duration: 0.4)) { lit = false }
            try? await Task.sleep(for: .seconds(1.35))
            copied = false
        }
    }
}

/// El comando que se escribe solo, carácter a carácter (600 ms en total), con un cursor fino al final
/// que desaparece al terminar. Con «Reducir movimiento» aparece completo. Ocupa siempre el espacio del
/// comando entero, así que nada se mueve mientras se «teclea».
private struct TypedCommand: View {
    let text: String
    let duration: Double
    @Environment(\.galenoReduceMotion) private var reduceMotion
    @State private var count = 0

    private var finished: Bool { reduceMotion || count >= text.count }

    var body: some View {
        ZStack(alignment: .leading) {
            Text(verbatim: text).hidden()
            if finished {
                Text(verbatim: text).textSelection(.enabled)
            } else {
                Text(verbatim: String(text.prefix(count))) + Text(verbatim: "▏").foregroundColor(Color.ink500)
            }
        }
        .font(Typo.mono)
        .foregroundStyle(Color.ink900)
        .task {
            guard !reduceMotion else { return }
            let step = Duration.milliseconds(max(1, Int(duration * 1000) / max(text.count, 1)))
            while count < text.count {
                try? await Task.sleep(for: step)
                if Task.isCancelled { return }
                count += 1
            }
        }
        .accessibilityLabel(Text(verbatim: text))
    }
}

#Preview("Encontrado") {
    DetectionStepView()
        .environmentObject(
            WizardState(claudeStatus: .found(version: "2.1.277", path: "/opt/homebrew/bin/claude", loggedIn: false)))
        .frame(width: WindowMetrics.width, height: 440)
        .background(Color.parchment50)
}

#Preview("No instalado") {
    DetectionStepView()
        .environmentObject(WizardState(claudeStatus: .notFound))
        .frame(width: WindowMetrics.width, height: 440)
        .background(Color.parchment50)
}
