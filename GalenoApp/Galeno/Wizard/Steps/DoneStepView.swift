import AppKit
import GalenoCore
import SwiftUI

/// «Listo» (rediseño «Abrir es terminar», 6 oct 2026; guiado por «Galeno B1 Agente»): un solo gesto. El agente está
/// creado, y lo que sigue es probarlo: **un botón, «Abrir en Claude Code»**, que abre el agente con su primera pregunta
/// ya escrita, cierra el asistente y vuelve al home con el agente en la lista. Quien no quiera abrir ahora tiene la salida
/// «Ir a mis agentes sin abrir». Ya no hay «Atrás» ni «Terminar»: el paso lleva su propio pie.
struct DoneStepView: View {
    @EnvironmentObject private var wizard: WizardState
    @Environment(\.galenoFinishWizard) private var finishWizard

    var body: some View {
        VStack(spacing: 0) {
            // En un `ScrollView` por la misma razón que `StepScaffold`: la ventana es fija.
            ScrollView {
                Group {
                    if let agent = wizard.generatedAgent {
                        DoneContent(agent: agent, finish: finish)
                    } else {
                        // No debería pasar: a «Listo» solo se llega tras generar.
                        Text("done.noAgent")
                            .font(.galenoBody)
                            .foregroundStyle(Color.ink700)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Space.s48)
                .padding(.top, 18)
                .padding(.bottom, Space.s16)
            }
            .scrollBounceBehavior(.basedOnSize)
            Rectangle().fill(Color.parchment300).frame(height: 1)
            HStack {
                // La salida, discreta. ↩ la pulsa: es lo que hacía «Terminar», y no cierra ni abre nada.
                Button("done.skip", action: finish)
                    .buttonStyle(InkLinkStyle(size: 15))
                    .keyboardShortcut(.defaultAction)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.s48)
            .padding(.vertical, 18)
        }
    }

    private func finish() {
        if let finishWizard { finishWizard() } else { NSApplication.shared.terminate(nil) }
    }
}

/// El contenido de «Listo»: el sello, el título y, en el único recuadro de filete grueso, la primera pregunta y el botón que
/// abre el agente con ella ya escrita.
struct DoneContent: View {
    @EnvironmentObject private var wizard: WizardState
    let agent: AgentRecord
    /// Volver al home: el asistente se cierra.
    let finish: () -> Void

    /// Lo que salió mal al abrir: no se pudo, o Claude no se cerró. `nil` = nada. En ese caso **no** se sale: se queda aquí,
    /// con la pregunta a mano para copiarla.
    @State private var openProblem: AgentOpenOutcome?
    /// Abriendo en la app de Claude o en Terminal: el botón conserva su ancho y muestra la rueda hasta que otra app toma el foco.
    @State private var opening: OpenTarget?
    @State private var copied = false
    /// El recuadro se ilumina un momento al copiar (150 ms ida, 400 ms vuelta).
    @State private var lit = false
    private enum OpenTarget { case app, terminal }

    private var prompt: String {
        FirstCommand.suggestion(for: wizard.connectedTools, language: wizard.language)
    }

    /// Sin la app de Claude en el Mac, Claude Code se abre en Terminal.
    private var appAvailable: Bool { wizard.opener.isClaudeAppAvailable }
    private var name: String { agent.config.agentName }

    var body: some View {
        VStack(spacing: 16) {
            PortraitMark(size: 60).stamp()
            StepTitle(text: Text("done.headline \(name)"))

            warnings

            firstBox
                .staggered(0, base: 0.3)

            pact

            // Con Claude Design conectado, se dice cómo usarlo: pasarle el enlace de un diseño.
            if wizard.connectedTools.contains(.claudeDesign) {
                Text("tools.designNote")
                    .font(Typo.text(13))
                    .foregroundStyle(Color.ink500)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .staggered(1, base: 0.3)
            }

            // La frase de dopamina entra al final, 400 ms después del contenido.
            Text("dopamine.done")
                .font(Typo.display(16, italic: true))
                .foregroundStyle(Color.ink500)
                .multilineTextAlignment(.center)
                .appearing(after: 0.3 + Motion.stagger + 0.4)
        }
        .frame(maxWidth: 540)
        .onAppear { Sounds.play(.seal) }
    }

    // MARK: El recuadro

    private var firstBox: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SmallCapsLabel("done.first.title", size: 12)
                    .foregroundStyle(Color.ink500)
                Spacer(minLength: 8)
                Button { copy() } label: { CopyLabel(copied: copied, idle: "done.first.copy") }
                    .buttonStyle(InkButtonStyle(.tertiary, size: .bar, quiet: true))
            }
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(verbatim: "«\(prompt)»")
                    .font(Typo.display(24, italic: true))
                    .foregroundStyle(Color.ink900)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                InvitingCursor()
            }

            HStack(alignment: .center, spacing: 16) {
                Button("done.open.claudeCode") { open(inApp: appAvailable) }
                    .buttonStyle(InkButtonStyle(.primary, padding: 22, isLoading: opening != nil))
                    .disabled(opening != nil)
                VStack(alignment: .leading, spacing: 2) {
                    Text("done.open.hint")
                    Text("done.open.listed \(name)")
                }
                .font(Typo.text(13.5))
                .foregroundStyle(Color.ink500)
                .fixedSize(horizontal: false, vertical: true)
            }

            // Qué va a pasar al abrirlo (y, antes de pulsar, si Claude se va a reiniciar); si no se pudo abrir, el texto
            // cambia con un fundido.
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                status
                    .id(noteID)
                    .transition(.opacity)
                    .font(Typo.text(13))
                    .fixedSize(horizontal: false, vertical: true)
                    .animation(.easeOut(duration: Motion.micro), value: noteID)
                Spacer(minLength: 0)
                // Con la app de Claude, Terminal es la otra manera; sin ella, ya es la principal.
                if appAvailable {
                    Button("done.open.terminal") { open(inApp: false) }
                        .buttonStyle(InkLinkStyle(size: 13))
                        .disabled(opening != nil)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(lit ? Color.parchment200 : Color.parchment100, in: RoundedRectangle(cornerRadius: Radius.b1))
        .overlay(RoundedRectangle(cornerRadius: Radius.b1).strokeBorder(Color.ink900, lineWidth: 1.5))
    }

    @ViewBuilder
    private var status: some View {
        if let openProblem {
            Text(openProblem == .claudeDidNotQuit ? "done.open.claudeStillOpen" : "done.open.failed")
                .foregroundStyle(Color.seal700)
        } else if opening == .app {
            // Puede tardar: si hay que reiniciar la app de Claude, se espera a que termine de cargar.
            Text("done.open.opening \(name)").foregroundStyle(Color.ink700)
        } else if !appAvailable {
            Text("done.open.inTerminal").foregroundStyle(Color.ink500)
        } else {
            Text(needsClaudeRestart ? "done.open.restart" : "done.open.confirm").foregroundStyle(Color.ink500)
        }
    }

    /// La app de Claude carga los conectores de la cuenta al arrancar (`docs/03` §4e): si lleva abierta
    /// desde antes de que el agente existiera, hay que reiniciarla para que vea los suyos.
    private var needsClaudeRestart: Bool {
        AgentOpenPolicy.needsClaudeRestart(tools: wizard.connectedTools, folder: agent.folder, opener: wizard.opener)
    }

    /// Qué nota se ve bajo el botón, para fundir de una a otra.
    private var noteID: String {
        if let openProblem { return "problema-\(openProblem)" }
        if opening == .app { return "abriendo" }
        return "antes"
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
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("pact.change") { wizard.jump(to: .rules) }
                .buttonStyle(LinkTextStyle())
        }
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

    // MARK: Acciones

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        copied = true
        withAnimation(.easeOut(duration: Motion.micro)) { lit = true }
        // El recuadro se ilumina y vuelve (400 ms); el botón vuelve a «Copiar» a los 1,5 s.
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.easeOut(duration: 0.4)) { lit = false }
            try? await Task.sleep(for: .milliseconds(1350))
            copied = false
        }
    }

    /// Abre el agente con su primera pregunta y, **si se abrió**, cierra el asistente. Si no se pudo (o Claude no se cerró) se
    /// queda aquí y lo dice: no se da por hecho lo que no pasó.
    private func open(inApp: Bool) {
        let opener = wizard.opener
        let claudePath = wizard.claudePath
        openProblem = nil
        opening = inApp ? .app : .terminal
        // Un solo camino con el home (`AgentOpenPolicy`): si Claude lleva abierto desde antes de conectar, se cierra y se
        // vuelve a abrir en el agente (decisión de Rafa, 4 oct 2026; la nota bajo el botón ya lo avisó), y si hay que
        // arrancarlo, se espera a que cargue antes de mandarle el enlace.
        Task {
            let outcome = await AgentOpenPolicy.open(
                folder: agent.folder, tools: wizard.connectedTools, inApp: inApp, prompt: prompt, resume: false,
                opener: opener, claudePath: claudePath)
            openProblem = outcome == .opened ? nil : outcome
            guard outcome == .opened else {
                opening = nil
                return
            }
            // Cargando hasta que la otra app toma el foco (o, como mucho, 2 s); entonces el asistente se cierra y el home
            // queda con el agente en la lista.
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(100))
                if !NSApp.isActive { break }
            }
            opening = nil
            finish()
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
