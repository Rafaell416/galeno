import AppKit
import GalenoCore
import SwiftUI

/// Paso 10: dónde quedó el agente, qué pedirle primero y dónde abrirlo (`docs/03` §3): en la app
/// de Claude o en Terminal, a elección del usuario. Desde aquí se llega al home (§3b).
struct DoneStepView: View {
    @EnvironmentObject private var wizard: WizardState

    var body: some View {
        // En un `ScrollView` por la misma razón que `StepScaffold`: la ventana es fija.
        ScrollView {
            Group {
                if let agent = wizard.generatedAgent {
                    DoneContent(agent: agent)
                } else {
                    // No debería pasar: a «Listo» solo se llega tras generar.
                    Text("done.noAgent")
                        .font(.galenoBody)
                        .foregroundStyle(Color.ink700)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, Space.s48)
            .padding(.top, 22)
            .padding(.bottom, Space.s16)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// La pantalla «Listo» (B1): el retrato y el título, cuatro tarjetas con filete y, destacado, lo
/// primero que hay que pedirle al agente.
struct DoneContent: View {
    @EnvironmentObject private var wizard: WizardState
    let agent: AgentRecord

    @State private var copied: Copied?
    /// Lo que salió mal al abrir: no se pudo, o Claude no se cerró. `nil` = nada.
    @State private var openProblem: AgentOpenOutcome?
    /// La tarjeta que se ilumina un momento al copiar (150 ms ida, 400 ms vuelta).
    @State private var lit: Copied?
    /// Abriendo en la app o en Terminal: el botón conserva su ancho y muestra la rueda hasta que otra app toma el foco.
    @State private var opening: OpenTarget?
    /// Ya se abrió una vez en la app de Claude: la nota pasa a decir cómo repetirlo si no cayó en su carpeta.
    @State private var openedInApp = false
    private enum OpenTarget { case app, terminal }

    private enum Copied { case path, prompt }

    /// La tarjeta «Dónde quedó» (ruta, Finder, copiar ruta). Apagada: ver el cuerpo.
    private static let showsFolderCard = false

    private var prompt: String {
        FirstCommand.suggestion(for: wizard.connectedTools, language: wizard.language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 18) {
                PortraitMark(size: 56).stamp()
                VStack(alignment: .leading, spacing: 2) {
                    StepTitle(text: Text("done.headline \(agent.config.agentName)"))
                    Text("step.done.summary")
                        .font(Typo.list)
                        .foregroundStyle(Color.ink700)
                }
            }

            pact

            warnings

            // Lo que importa ahora: probar el agente. Un solo bloque —el único con filete grueso y el rótulo
            // en lacre— con la primera pregunta y dónde abrirlo; se abre con la pregunta ya escrita.
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    SmallCapsLabel("done.first.title", size: 12)
                        .foregroundStyle(Color.seal700)
                    HStack(alignment: .lastTextBaseline, spacing: 3) {
                        Text(verbatim: "«\(prompt)»")
                            .font(Typo.display(24, italic: true))
                            .foregroundStyle(Color.ink900)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        InvitingCursor()
                    }
                }

                HStack(spacing: 10) {
                    // Sin la app de Claude en el Mac, Terminal es la acción principal.
                    if wizard.opener.isClaudeAppAvailable {
                        appButton(.primary)
                        terminalButton(.secondary)
                    } else {
                        terminalButton(.primary)
                    }
                    Spacer(minLength: 0)
                    Button { copy(prompt, .prompt) } label: {
                        CopyLabel(copied: copied == .prompt, idle: "done.first.copy")
                    }
                    .buttonStyle(InkButtonStyle(.secondary, padding: 14, quiet: true))
                }

                // Qué va a pasar al abrirlo; si no se pudo abrir, el texto cambia con un fundido.
                Group {
                    if let openProblem {
                        Text(openProblem == .claudeDidNotQuit ? "done.open.claudeStillOpen" : "done.open.failed")
                            .foregroundStyle(Color.seal700)
                    } else if opening == .app {
                        // Puede tardar: si hay que reiniciar la app de Claude, se espera a que termine de cargar.
                        Text("done.open.opening \(agent.config.agentName)")
                            .foregroundStyle(Color.ink700)
                    } else if openedInApp {
                        // La app de Claude a veces pierde la carpeta del enlace mientras carga. Con ella ya
                        // abierta, repetirlo sí cae en su sitio.
                        Text("done.open.again \(agent.config.agentName)")
                            .foregroundStyle(Color.ink700)
                    } else {
                        (Text("done.open.hint") + Text(verbatim: " ") + Text(openNote))
                            .foregroundStyle(Color.ink500)
                    }
                }
                .id(noteID)
                .transition(.opacity)
                .font(Typo.text(13))
                .fixedSize(horizontal: false, vertical: true)
                .animation(.easeOut(duration: Motion.micro), value: noteID)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(lit == .prompt ? Color.parchment200 : Color.parchment100, in: RoundedRectangle(cornerRadius: Radius.b1))
            .overlay(RoundedRectangle(cornerRadius: Radius.b1).strokeBorder(Color.ink900, lineWidth: 1.5))
            .staggered(0, base: 0.3)

            // Dónde quedó la carpeta: oculto por ahora (decisión de Rafa: a quien acaba de crear su agente
            // le importa probarlo, no la ruta). Se enciende con `showsFolderCard`.
            if Self.showsFolderCard {
                card("done.where.title", lit: lit == .path) {
                    Text(verbatim: displayPath)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(Color.ink900)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .padding(.vertical, 2)
                    HStack(spacing: 8) {
                        Button("done.where.reveal") { wizard.opener.reveal(agent.folder) }
                            .buttonStyle(InkButtonStyle(.secondary, size: .bar, padding: 12))
                        Button { copy(agent.folderPath, .path) } label: {
                            CopyLabel(copied: copied == .path, idle: "done.copyPath")
                        }
                        .buttonStyle(InkButtonStyle(.secondary, size: .bar, padding: 12, quiet: true))
                    }
                }
                .staggered(1, base: 0.3)
            }

            // Con Claude Design conectado, se dice cómo usarlo: pasarle el enlace de un diseño.
            if wizard.connectedTools.contains(.claudeDesign) {
                Text("tools.designNote")
                    .font(Typo.text(13))
                    .foregroundStyle(Color.ink500)
                    .fixedSize(horizontal: false, vertical: true)
                    .staggered(1, base: 0.3)
            }

            // La frase de dopamina entra al final, 400 ms después del contenido.
            Text("dopamine.done")
                .font(Typo.display(16, italic: true))
                .foregroundStyle(Color.ink500)
                .appearing(after: 0.3 + Motion.stagger + 0.4)
        }
        .onAppear { Sounds.play(.seal) }
    }

    /// La app de Claude carga los conectores de la cuenta al arrancar (`docs/03` §4e): si lleva abierta
    /// desde antes de que el agente existiera, hay que reiniciarla para que vea los suyos.
    private var needsClaudeRestart: Bool {
        AgentOpenPolicy.needsClaudeRestart(tools: wizard.connectedTools, folder: agent.folder, opener: wizard.opener)
    }

    /// Qué nota se ve bajo los botones, para fundir de una a otra.
    private var noteID: String {
        if let openProblem { return "problema-\(openProblem)" }
        if opening == .app { return "abriendo" }
        return openedInApp ? "abierto" : "antes"
    }

    /// La nota bajo los botones. Si Claude se va a reiniciar, se dice antes de pulsar.
    private var openNote: LocalizedStringKey {
        guard wizard.opener.isClaudeAppAvailable else { return "done.open.appMissing" }
        return needsClaudeRestart ? "done.open.restart" : "done.open.confirm"
    }

    private func appButton(_ kind: InkButtonStyle.Kind) -> some View {
        Button("done.open.app") { open(inApp: true) }
            .buttonStyle(InkButtonStyle(kind, padding: 18, isLoading: opening == .app))
            .disabled(opening != nil)
    }

    private func terminalButton(_ kind: InkButtonStyle.Kind) -> some View {
        Button("done.open.terminal") { open(inApp: false) }
            .buttonStyle(InkButtonStyle(kind, padding: 18, isLoading: opening == .terminal))
            .disabled(opening != nil)
    }

    /// El pacto de reglas, en una línea y siempre a la vista: lo que nunca hace, lo que siempre
    /// pregunta y lo que escribe sin preguntar. Sale de la misma config que se escribió.
    private var pact: some View {
        let writes = wizard.configurableWrites
        let allowed = writes.filter { wizard.policy(for: $0) == .allow }.map(\.toolDisplayName)
        let asked = writes.filter { wizard.policy(for: $0) == .ask }.map(\.toolDisplayName)
        var parts: [Text] = []
        if wizard.connectedTools.contains(.whatsapp) { parts.append(Text("pact.never")) }
        parts.append(Text("pact.always"))
        if !allowed.isEmpty { parts.append(Text("pact.allow \(allowed.joined(separator: ", "))")) }
        if !asked.isEmpty { parts.append(Text("pact.ask \(asked.joined(separator: ", "))")) }
        let line = parts.dropFirst().reduce(parts[0]) { $0 + Text(verbatim: " · ") + $1 }
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            line
                .font(Typo.text(14))
                .foregroundStyle(Color.ink700)
                .fixedSize(horizontal: false, vertical: true)
            Button("pact.change") { wizard.jump(to: .rules) }
                .buttonStyle(LinkTextStyle())
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
        _ title: String, lit: Bool = false, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.s8) {
            SmallCapsLabel(title, size: 12)
                .foregroundStyle(Color.ink500)
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(lit ? Color.parchment100 : Color.clear, in: RoundedRectangle(cornerRadius: Radius.b1))
        .overlay(RoundedRectangle(cornerRadius: Radius.b1).strokeBorder(Color.parchment300, lineWidth: 1))
    }

    private func copy(_ text: String, _ what: Copied) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = what
        withAnimation(.easeOut(duration: Motion.micro)) { lit = what }
        // La tarjeta se ilumina y vuelve (400 ms); el botón vuelve a «Copiar» a los 1,5 s.
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.easeOut(duration: 0.4)) { if lit == what { lit = nil } }
            try? await Task.sleep(for: .milliseconds(1350))
            if copied == what { copied = nil }
        }
    }

    private func open(inApp: Bool) {
        let opener = wizard.opener
        let claudePath = wizard.claudePath
        openProblem = nil
        opening = inApp ? .app : .terminal
        // Un solo camino con el home (`AgentOpenPolicy`): si Claude lleva abierto desde antes de conectar, se cierra y se
        // vuelve a abrir en el agente (decisión de Rafa, 4 oct 2026; la nota bajo los botones ya lo avisó), y si hay que
        // arrancarlo, se espera a que cargue antes de mandarle el enlace.
        Task {
            let outcome = await AgentOpenPolicy.open(
                folder: agent.folder, tools: wizard.connectedTools, inApp: inApp, prompt: prompt, resume: false,
                opener: opener, claudePath: claudePath)
            openProblem = outcome == .opened ? nil : outcome
            if outcome == .opened, inApp { openedInApp = true }
            // Cargando hasta que la otra app toma el foco (o, como mucho, 2 s).
            if outcome == .opened {
                for _ in 0..<20 {
                    try? await Task.sleep(for: .milliseconds(100))
                    if !NSApp.isActive { break }
                }
            }
            opening = nil
        }
    }
}

/// El cursor fino que invita a copiar el primer comando: a los 1,2 s parpadea una vez (dos ciclos de
/// 500 ms) y desaparece. Con «Reducir movimiento» no se muestra.
private struct InvitingCursor: View {
    @Environment(\.galenoReduceMotion) private var reduceMotion
    @State private var visible = false

    var body: some View {
        Rectangle()
            .fill(Color.ink900)
            .frame(width: 1, height: 20)
            .opacity(visible ? 1 : 0)
            .task {
                guard !reduceMotion else { return }
                try? await Task.sleep(for: .milliseconds(1200))
                for _ in 0..<2 {
                    withAnimation(.easeOut(duration: 0.05)) { visible = true }
                    try? await Task.sleep(for: .milliseconds(250))
                    withAnimation(.easeOut(duration: 0.05)) { visible = false }
                    try? await Task.sleep(for: .milliseconds(250))
                    if Task.isCancelled { return }
                }
            }
            .accessibilityHidden(true)
    }
}

#Preview {
    DoneStepView()
        .environmentObject(WizardState())
        .frame(width: WindowMetrics.width, height: 520)
        .background(Color.parchment50)
}
