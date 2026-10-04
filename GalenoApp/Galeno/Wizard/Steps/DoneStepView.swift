import AppKit
import GalenoCore
import SwiftUI

/// Paso 10: dónde quedó el agente, qué pedirle primero y dónde abrirlo (`docs/03` §3): en la app
/// de Claude o en Terminal, a elección del usuario. Desde aquí se llega al home (§3b).
struct DoneStepView: View {
    @EnvironmentObject private var wizard: WizardState

    var body: some View {
        StepScaffold(step: .done) {
            if let agent = wizard.generatedAgent {
                DoneContent(agent: agent)
            } else {
                // No debería pasar: a «Listo» solo se llega tras generar.
                Text("done.noAgent")
                    .font(.galenoBody)
                    .foregroundStyle(Color.ink700)
            }
        }
    }
}

private struct DoneContent: View {
    @EnvironmentObject private var wizard: WizardState
    let agent: AgentRecord

    @State private var copied: Copied?
    @State private var openFailed = false

    private enum Copied { case path, prompt }

    private var prompt: String {
        FirstCommand.suggestion(for: wizard.connectedTools, language: wizard.language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s16) {
            HStack(spacing: Space.s12) {
                SuccessMark(size: 40)
                Text("done.headline \(agent.config.agentName)")
                    .font(.galenoTitle)
                    .foregroundStyle(Color.ink900)
            }

            warnings

            card("done.where.title") {
                Text(verbatim: displayPath)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(Color.ink900)
                    .textSelection(.enabled)
                    .lineLimit(2)
                HStack(spacing: Space.s12) {
                    Button("done.where.reveal") { wizard.opener.reveal(agent.folder) }
                    Button(copied == .path ? "done.copied" : "done.copyPath") { copy(agent.folderPath, .path) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            card("done.first.title") {
                Text(verbatim: "“\(prompt)”")
                    .font(.galenoBody)
                    .foregroundStyle(Color.ink900)
                    .textSelection(.enabled)
                Button(copied == .prompt ? "done.copied" : "done.first.copy") { copy(prompt, .prompt) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            card("done.open.title") {
                HStack(spacing: Space.s12) {
                    Button("done.open.app") { open(inApp: true) }
                        .disabled(!wizard.opener.isClaudeAppAvailable)
                    Button("done.open.terminal") { open(inApp: false) }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                if !wizard.opener.isClaudeAppAvailable {
                    Text("done.open.appMissing")
                        .font(.galenoCaption)
                        .foregroundStyle(Color.ink500)
                } else {
                    Text("done.open.confirm")
                        .font(.galenoCaption)
                        .foregroundStyle(Color.ink500)
                }
                if openFailed {
                    Text("done.open.failed")
                        .font(.galenoCaption)
                        .foregroundStyle(Color.seal700)
                }
            }

            DopamineLine(key: "dopamine.done")
        }
    }

    /// `~` en lugar de la ruta completa del usuario.
    private var displayPath: String {
        let home = NSHomeDirectory()
        return agent.folderPath.hasPrefix(home) ? "~" + agent.folderPath.dropFirst(home.count) : agent.folderPath
    }

    /// Lo que el motor avisó y alguien debería mirar. Solo lo que le sirve al usuario.
    @ViewBuilder
    private var warnings: some View {
        if wizard.lastGeneration?.warnings.contains(where: {
            if case .existingClaudeFileLeftAlone = $0 { return true } else { return false }
        }) == true {
            NoticePanel(kind: .seal) {
                Text("done.warning.claudeFile")
                    .font(.galenoCaption)
                    .foregroundStyle(Color.ink900)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func card<Content: View>(
        _ title: LocalizedStringKey, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.s8) {
            Text(title)
                .font(.galenoCaption.smallCaps())
                .kerning(1)
                .foregroundStyle(Color.ink500)
            content()
        }
        .padding(Space.s12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.parchment100, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.parchment300, lineWidth: 1))
    }

    private func copy(_ text: String, _ what: Copied) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = what
    }

    private func open(inApp: Bool) {
        let opener = wizard.opener
        openFailed = !(inApp
            ? opener.openInClaudeApp(folder: agent.folder, prompt: prompt)
            : opener.openInTerminal(folder: agent.folder, prompt: prompt, claudePath: wizard.claudePath))
    }
}

#Preview {
    DoneStepView()
        .environmentObject(WizardState())
        .frame(width: WindowMetrics.width, height: 520)
        .background(Color.parchment50)
}
