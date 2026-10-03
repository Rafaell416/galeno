import AppKit
import SwiftUI

/// Paso 2: detectar Claude Code (`docs/03` §3). Galeno solo mira y guía: no
/// instala nada. Si falta, muestra el comando oficial para que el usuario lo
/// corra en su terminal.
struct DetectionStepView: View {
    @EnvironmentObject private var wizard: WizardState

    static let installCommand = "curl -fsSL https://claude.ai/install.sh | bash"
    static let guideURL = URL(string: "https://code.claude.com/docs/en/setup")!

    var body: some View {
        StepScaffold(step: .detection) {
            VStack(alignment: .leading, spacing: Space.s16) {
                switch wizard.claudeStatus {
                case .checking:
                    HStack(spacing: Space.s12) {
                        ProgressView().controlSize(.small)
                        Text("detection.checking")
                            .font(.galenoBody)
                            .foregroundStyle(Color.ink700)
                    }
                case .found(let version, let path, let loggedIn):
                    found(version: version, path: path, loggedIn: loggedIn)
                case .notFound:
                    NotFoundPanel()
                }
            }
        }
        .task {
            // Si ya se encontró, volver atrás y adelante no lo vuelve a buscar.
            if !wizard.claudeStatus.isFound { await wizard.detectClaudeCode() }
        }
    }

    @ViewBuilder
    private func found(version: String, path: String, loggedIn: Bool?) -> some View {
        NoticePanel(kind: .moss) {
            Label {
                Text("detection.found.title")
                    .font(.galenoBody.weight(.semibold))
                    .foregroundStyle(Color.ink900)
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.moss700)
            }
            Text("detection.found.version \(version)")
                .font(.galenoBody)
                .foregroundStyle(Color.ink700)
            Text(verbatim: path)
                .font(.galenoCaption)
                .foregroundStyle(Color.ink500)
                .textSelection(.enabled)
        }

        // `nil` es "no se pudo saber": en ese caso no se avisa de nada.
        if loggedIn == false {
            NoticePanel(kind: .seal) {
                Text("detection.loggedOut.title")
                    .font(.galenoBody.weight(.semibold))
                    .foregroundStyle(Color.ink900)
                Text("detection.loggedOut.body")
                    .font(.galenoBody)
                    .foregroundStyle(Color.ink700)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        DopamineLine(key: "dopamine.detection")
    }
}

/// Qué hacer si `claude` no está: el comando, el enlace y volver a comprobar.
private struct NotFoundPanel: View {
    @EnvironmentObject private var wizard: WizardState
    @State private var copied = false

    var body: some View {
        NoticePanel(kind: .seal) {
            Text("detection.notFound.title")
                .font(.galenoBody.weight(.semibold))
                .foregroundStyle(Color.ink900)
            Text("detection.notFound.body")
                .font(.galenoBody)
                .foregroundStyle(Color.ink700)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Space.s12) {
                Text(verbatim: DetectionStepView.installCommand)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(Color.ink900)
                    .textSelection(.enabled)
                    .padding(.horizontal, Space.s12)
                    .padding(.vertical, Space.s8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.parchment50, in: RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.parchment300, lineWidth: 1))
                Button(copied ? "detection.copied" : "detection.copy") { copyCommand() }
                    .buttonStyle(.bordered)
            }

            Text("detection.notFound.afterInstall")
                .font(.galenoCaption)
                .foregroundStyle(Color.ink700)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Space.s16) {
                Button("detection.recheck") { Task { await wizard.detectClaudeCode() } }
                    .buttonStyle(.bordered)
                // `docs/04` §6: enlace en seal-700 con subrayado fino, no el azul del sistema.
                Link("detection.guide", destination: DetectionStepView.guideURL)
                    .font(.galenoBody)
                    .foregroundStyle(Color.seal700)
                    .underline()
            }
            .padding(.top, Space.s4)
        }
    }

    private func copyCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(DetectionStepView.installCommand, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
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
