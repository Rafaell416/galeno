import AppKit
import GalenoCore
import SwiftUI

/// Una conexión por pantalla (`docs/03` §3): el logo grande, una línea de lo que el
/// agente va a poder hacer con la herramienta y el botón Conectar. Debajo, lo que
/// toque según la fase: esperando, éxito con un dato real, o fallo con salida.
struct ConnectionScreen: View {
    @ObservedObject var flow: ConnectFlow
    @EnvironmentObject private var wizard: WizardState
    let tool: Tool

    private var name: String { tool.displayName(in: wizard.language) }

    var body: some View {
        VStack(spacing: Space.s16) {
            Spacer(minLength: 0)
            content
                .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
            footer
        }
        .padding(.horizontal, Space.s48)
        .padding(.vertical, Space.s24)
        .animation(.easeOut(duration: 0.2), value: flow.phase)
    }

    // MARK: Contenido por fase

    @ViewBuilder
    private var content: some View {
        switch flow.phase {
        case .qr(let image):
            QRPanel(image: image)
        case .syncing(let chats):
            VStack(spacing: Space.s16) {
                header(lit: true)
                SyncingPanel(chats: chats)
            }
        case .succeeded(let already):
            VStack(spacing: Space.s12) {
                SuccessMark(size: 64)
                Text(already ? "connect.success.already \(name)" : "connect.success.title \(name)")
                    .font(.galenoTitle)
                    .foregroundStyle(Color.ink900)
                    .multilineTextAlignment(.center)
                findingLine
            }
        case .failed(let failure):
            VStack(spacing: Space.s16) {
                header(lit: false)
                FailurePanel(failure: failure, detail: flow.failureDetail)
            }
        case .needsOwnApp:
            VStack(spacing: Space.s16) {
                header(lit: false)
                NoticePanel(kind: .seal) {
                    Text("connect.ownApp.title \(name)")
                        .font(.galenoBody.weight(.semibold))
                        .foregroundStyle(Color.ink900)
                    Text("connect.ownApp.body")
                        .font(.galenoBody)
                        .foregroundStyle(Color.ink700)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .working(let step):
            VStack(spacing: Space.s16) {
                header(lit: false)
                WorkingPanel(step: step)
            }
        case .ready:
            VStack(spacing: Space.s16) {
                header(lit: false)
                if tool == .whatsapp { WhatsAppWarning() }
            }
        }
    }

    /// El logo, el nombre y la línea de qué va a poder hacer el agente.
    private func header(lit: Bool) -> some View {
        VStack(spacing: Space.s8) {
            ToolIcon(tool: tool, size: 56, color: lit ? Color.ink900 : Color.ink700)
            Text(verbatim: name)
                .font(.galenoTitle)
                .foregroundStyle(Color.ink900)
            Text(LocalizedStringKey("connect.value." + tool.rawValue))
                .font(.galenoBody)
                .foregroundStyle(Color.ink700)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 480)
        }
    }

    /// "Encontré 12 canales", o el aviso de que todavía se está contando.
    @ViewBuilder
    private var findingLine: some View {
        if let finding = flow.findings[tool] {
            finding.text
                .font(.galenoBody)
                .foregroundStyle(Color.ink700)
                .transition(.opacity)
        } else if flow.pendingData.contains(tool) {
            HStack(spacing: Space.s8) {
                ProgressView().controlSize(.small)
                Text("connect.counting")
                    .font(.galenoCaption)
                    .foregroundStyle(Color.ink500)
            }
            .transition(.opacity)
        }
    }

    // MARK: Botones

    private var footer: some View {
        HStack(alignment: .center) {
            if flow.canReturnToToolSelection {
                Button("connect.backToTools") { wizard.back() }
                    .buttonStyle(.link)
                    .font(.galenoCaption)
                    .foregroundStyle(Color.ink700)
            }
            Spacer()
            HStack(spacing: Space.s12) {
                secondaryButtons
                primaryButton
            }
        }
        .controlSize(.large)
        .frame(minHeight: 32)
    }

    @ViewBuilder
    private var secondaryButtons: some View {
        switch flow.phase {
        case .ready, .working, .qr:
            // Discreto: no compite con Conectar.
            Button("connect.later") { flow.skip() }
                .buttonStyle(.plain)
                .font(.galenoCaption)
                .foregroundStyle(Color.ink500)
        case .failed:
            Button("connect.skip") { flow.skip() }
                .buttonStyle(.bordered)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch flow.phase {
        case .ready:
            PrimaryButton(tool == .whatsapp ? "connect.whatsapp.continue" : "connect.connect") {
                flow.connect()
            }
        case .failed:
            PrimaryButton("connect.retry") { flow.retry() }
        case .needsOwnApp:
            PrimaryButton("connect.later") { flow.skip() }
        case .syncing:
            PrimaryButton("connect.whatsapp.continueInBackground") { flow.continueWhileSyncing() }
        default:
            EmptyView()
        }
    }
}

// MARK: - Piezas

/// El botón primario nativo con tinte `ink-900` y la etiqueta en `parchment-50`
/// (`docs/04` §9), con Enter como acción por defecto.
struct PrimaryButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title).foregroundStyle(Color.parchment50)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.ink900)
        .keyboardShortcut(.defaultAction)
    }
}

private struct WorkingPanel: View {
    let step: ConnectFlow.Step

    var body: some View {
        VStack(spacing: Space.s8) {
            HStack(spacing: Space.s12) {
                ProgressView().controlSize(.small)
                Text(label)
                    .font(.galenoBody)
                    .foregroundStyle(Color.ink900)
            }
            if step == .waitingForBrowser {
                Text("connect.step.waitingForBrowser.hint")
                    .font(.galenoCaption)
                    .foregroundStyle(Color.ink700)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var label: LocalizedStringKey {
        switch step {
        case .checking: "connect.step.checking"
        case .registering: "connect.step.registering"
        case .waitingForBrowser: "connect.step.waitingForBrowser"
        case .preparingBridge: "connect.step.preparingBridge"
        case .checkingLink: "connect.step.checkingLink"
        case .installingSync: "connect.step.installingSync"
        }
    }
}

private struct FailurePanel: View {
    let failure: ConnectFlow.Failure
    let detail: String

    var body: some View {
        NoticePanel(kind: .seal) {
            Text(message)
                .font(.galenoBody.weight(.semibold))
                .foregroundStyle(Color.ink900)
                .fixedSize(horizontal: false, vertical: true)
            if !detail.isEmpty {
                Text("connect.failure.detail \(detail)")
                    .font(.galenoCaption)
                    .foregroundStyle(Color.ink500)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
    }

    private var message: LocalizedStringKey {
        switch failure {
        case .couldNotRegister: "connect.failure.couldNotRegister"
        case .notAuthorizedInTime: "connect.failure.notAuthorizedInTime"
        case .loginFailed: "connect.failure.loginFailed"
        case .stillNotConnected: "connect.failure.stillNotConnected"
        case .bridgeMissing: "connect.failure.bridgeMissing"
        case .bridgeFailed: "connect.failure.bridgeFailed"
        case .qrExpired: "connect.failure.qrExpired"
        }
    }
}

// MARK: - WhatsApp

/// La advertencia explícita de `docs/03` §4, **antes** del QR y con un botón para
/// continuar: "Tú decides si continuar". El texto es el de la spec y no se toca
/// sin que Rafa lo apruebe (`AGENTS.md`).
private struct WhatsAppWarning: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s8) {
            Text("connect.whatsapp.warning.title")
                .font(.galenoCaption.smallCaps())
                .kerning(1.2)
                .foregroundStyle(Color.ink700)
            Text("connect.whatsapp.warning.body")
                .font(.galenoBody)
                .foregroundStyle(Color.ink900)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s16)
        .frame(maxWidth: 560, alignment: .leading)
        .background(Color.parchment100, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.ink900, lineWidth: 1))
    }
}

/// El QR, en un marco de 1 px `ink-900` sobre `parchment-100` (`docs/04` §9). Va
/// sobre blanco: un QR de tinta clara sobre fondo oscuro no se lee.
private struct QRPanel: View {
    let image: Data?

    var body: some View {
        HStack(spacing: Space.s32) {
            qr
            VStack(alignment: .leading, spacing: Space.s12) {
                Text("connect.whatsapp.qr.title")
                    .font(.galenoTitle)
                    .foregroundStyle(Color.ink900)
                    .fixedSize(horizontal: false, vertical: true)
                Text("connect.whatsapp.qr.steps")
                    .font(.galenoBody)
                    .foregroundStyle(Color.ink700)
                    .fixedSize(horizontal: false, vertical: true)
                Text("connect.whatsapp.qr.rotates")
                    .font(.galenoCaption)
                    .foregroundStyle(Color.ink500)
            }
            .frame(maxWidth: 300, alignment: .leading)
        }
    }

    @ViewBuilder
    private var qr: some View {
        Group {
            if let image, let nsImage = NSImage(data: image) {
                Image(nsImage: nsImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(Space.s8)
                    .background(Color.white)
                    .accessibilityLabel(Text("connect.whatsapp.qr.title"))
            } else {
                VStack(spacing: Space.s8) {
                    ProgressView().controlSize(.small)
                    Text("connect.whatsapp.qr.generating")
                        .font(.galenoCaption)
                        .foregroundStyle(Color.ink700)
                }
            }
        }
        .frame(width: 208, height: 208)
        .padding(Space.s12)
        .background(Color.parchment100)
        .overlay(Rectangle().stroke(Color.ink900, lineWidth: 1))
    }
}

/// "Sincronizando…": barra indeterminada y los chats que ya aparecieron. El bridge
/// no da progreso real, y la barra no finge darlo.
private struct SyncingPanel: View {
    let chats: Int

    var body: some View {
        VStack(spacing: Space.s8) {
            ProgressView()
                .progressViewStyle(.linear)
                .tint(Color.ink900)
                .frame(maxWidth: 360)
            Text("connect.whatsapp.syncing \(chats)")
                .font(.galenoBody)
                .foregroundStyle(Color.ink900)
                .monospacedDigit()
            Text("connect.whatsapp.syncing.hint")
                .font(.galenoCaption)
                .foregroundStyle(Color.ink700)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 440)
        }
    }
}

// MARK: - El dato real

extension ConnectFlow.Finding {
    /// "Encontré 12 canales" / "Encontré al menos 10 páginas".
    var text: Text {
        let n = count.value
        switch (noun, count.isPartial) {
        case (.channels, false): return Text("connect.found.channels \(n)")
        case (.channels, true): return Text("connect.foundAtLeast.channels \(n)")
        case (.projects, false): return Text("connect.found.projects \(n)")
        case (.projects, true): return Text("connect.foundAtLeast.projects \(n)")
        case (.labels, false): return Text("connect.found.labels \(n)")
        case (.labels, true): return Text("connect.foundAtLeast.labels \(n)")
        case (.meetings, false): return Text("connect.found.meetings \(n)")
        case (.meetings, true): return Text("connect.foundAtLeast.meetings \(n)")
        case (.groups, false): return Text("connect.found.groups \(n)")
        case (.groups, true): return Text("connect.foundAtLeast.groups \(n)")
        }
    }
}
