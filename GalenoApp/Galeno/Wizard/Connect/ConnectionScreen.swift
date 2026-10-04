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

    /// WhatsApp tiene un paso propio antes de vincular: primero se ve qué va a pasar, como en las
    /// demás, y al pulsar «Conectar» aparece el aviso, que hay que aceptar para seguir.
    @State private var showsWhatsAppWarning = false
    /// Slack: «Iniciar sesión» abre la ventana en cuanto el flujo está listo para recibir el token.
    @State private var opensSlackSignIn = false
    @Environment(\.galenoReduceMotion) private var reduceMotion

    /// Qué clase de pantalla es la de ahora. Cambiar de clase pasa página; los pasos internos de «trabajando»
    /// no (el anillo no debe reentrar).
    private var phaseKey: String {
        switch flow.phase {
        case .ready: showsWhatsAppWarning ? "warning" : "ready"
        case .working: "working"
        case .succeeded: "succeeded"
        case .failed: "failed"
        case .qr: "qr"
        case .syncing: "syncing"
        case .slackToken: "slackToken"
        case .nameConflict: "conflict"
        case .confirmingRemoval: "removal"
        case .needsOwnApp: "ownApp"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            content
                .id(phaseKey)
                .transition(reduceMotion ? .opacity : .pageTurn)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
                .padding(.top, 10)
        }
        .padding(.horizontal, Space.s48)
        .padding(.bottom, Space.s16)
        .animation(.easeOut(duration: 0.2), value: flow.phase)
        .onChange(of: flow.phase) { _, phase in
            if case .slackToken = phase, opensSlackSignIn {
                opensSlackSignIn = false
                SlackTokenPanel.openSignIn(flow: flow, language: wizard.language)
            }
            if case .ready = phase {} else { showsWhatsAppWarning = false }
        }
    }

    // MARK: Contenido por fase

    @ViewBuilder
    private var content: some View {
        switch flow.phase {
        case .qr(let image):
            QRPanel(image: image)
        case .syncing(let chats):
            SyncingPanel(chats: chats)
                .frame(maxWidth: 460)
        case .succeeded(let already):
            // Secuencia fija: círculo (700 ms) → palomita (500 ms, desde los 500) → título (900 ms) → la cifra real
            // cuenta desde 0 (1200 ms). Si ya estaba conectado no hay nada que celebrar: todo aparece completo.
            VStack(spacing: Space.s12) {
                SuccessMark(size: 72, traced: !already)
                Text(already ? "connect.success.already \(name)" : "connect.success.title \(name)")
                    .font(Typo.display(30))
                    .foregroundStyle(Color.ink900)
                    .multilineTextAlignment(.center)
                    .appearing(after: already ? 0 : 0.9)
                findingLine(delay: already ? 0.3 : 1.2)
            }
            // Suena solo cuando la conexión se acaba de lograr, no si ya estaba hecha.
            .onAppear { if !already { Sounds.play(.connected) } }
        case .failed(let failure):
            FailurePanel(
                failure: failure, detail: flow.failureDetail, toolName: name, agentName: wizard.agentName,
                language: wizard.language, onRecreateSlackApp: { flow.recreateSlackApp() }
            )
            .frame(maxWidth: 540)
            .onAppear { Sounds.play(.failed) }
        case .slackToken:
            ReadyLayout(tool: tool, name: name)
        case .nameConflict(let server):
            NameConflictPanel(flow: flow, server: server)
                .frame(maxWidth: 560)
        case .confirmingRemoval(let server):
            RemovalConfirmPanel(flow: flow, server: server)
                .frame(maxWidth: 560)
        case .needsOwnApp:
            NoticePanel(kind: .seal) {
                Text("connect.ownApp.title \(name)")
                    .font(Typo.display(24))
                    .foregroundStyle(Color.ink900)
                Text("connect.ownApp.body")
                    .font(Typo.list)
                    .foregroundStyle(Color.ink700)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 540)
        case .working(let step):
            WorkingPanel(step: step)
        case .ready:
            if tool == .whatsapp, showsWhatsAppWarning {
                WhatsAppWarningLayout(name: name)
            } else {
                ReadyLayout(tool: tool, name: name)
            }
        }
    }

    /// "Encontré 12 canales", o el aviso de que todavía se está contando.
    @ViewBuilder
    private func findingLine(delay: Double) -> some View {
        if let finding = flow.findings[tool] {
            CountingFinding(finding: finding, delay: delay)
                .font(Typo.text(17))
                .foregroundStyle(Color.ink700)
                .transition(.opacity)
        } else if flow.pendingData.contains(tool) {
            HStack(spacing: Space.s8) {
                InkSpinner(size: 12)
                Text("connect.counting")
                    .font(Typo.list)
                    .foregroundStyle(Color.ink500)
            }
            .transition(.opacity)
        }
    }

    // MARK: Botones

    private var footer: some View {
        HStack(alignment: .center, spacing: Space.s12) {
            if flow.canReturnToToolSelection, case .ready = flow.phase, !showsWhatsAppWarning {
                Button("connect.backToTools") { wizard.back() }
                    .buttonStyle(.inkTertiary)
            }
            Spacer(minLength: 0)
            secondaryButtons
            primaryButton
        }
        .frame(minHeight: Control.primary)
    }

    @ViewBuilder
    private var secondaryButtons: some View {
        switch flow.phase {
        case .ready, .working, .qr, .slackToken:
            // Discreto: no compite con Conectar.
            Button("connect.later") { flow.skip() }
                .buttonStyle(InkButtonStyle(.tertiary, quiet: true))
        case .failed:
            Button("connect.skip") { flow.skip() }
                .buttonStyle(InkButtonStyle(.secondary, padding: 18))
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch flow.phase {
        case .ready:
            if tool == .whatsapp, showsWhatsAppWarning {
                PrimaryButton("connect.whatsapp.continue") { flow.connect() }
            } else if tool == .whatsapp {
                PrimaryButton("connect.connect \(name)") { showsWhatsAppWarning = true }
            } else if tool == .slack {
                PrimaryButton("connect.slack.signin.button") {
                    opensSlackSignIn = true
                    flow.connect()
                }
            } else {
                PrimaryButton("connect.connect \(name)") { flow.connect() }
            }
        case .slackToken:
            PrimaryButton("connect.slack.signin.button") {
                SlackTokenPanel.openSignIn(flow: flow, language: wizard.language)
            }
        case .succeeded:
            // Mientras se cuenta lo encontrado no hay botón: aparece con el dato.
            if !flow.pendingData.contains(tool) {
                PrimaryButton("connect.continue") { flow.continueFromSuccess() }
                    .appearing(after: 0.9)
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

/// El botón primario de tinta (`InkButtonStyle`), con Enter como acción por defecto.
struct PrimaryButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
        }
        .buttonStyle(InkButtonStyle(.primary, padding: 24))
        .keyboardShortcut(.defaultAction)
    }
}

/// La ayuda mientras se espera el navegador: alterna cada 8 s entre tres frases, con fundido. El botón
/// «Conectar después» no desaparece nunca durante la espera.
private struct BrowserHint: View {
    private static let keys: [LocalizedStringKey] = [
        "connect.step.waitingForBrowser.hint", "connect.step.waitingForBrowser.hint2",
        "connect.step.waitingForBrowser.hint3",
    ]
    @State private var start = Date()

    var body: some View {
        TimelineView(.periodic(from: start, by: 8)) { context in
            let index = Int(context.date.timeIntervalSince(start) / 8) % Self.keys.count
            Text(Self.keys[index])
                .id(index)
                .transition(.opacity)
                .font(Typo.list)
                .foregroundStyle(Color.ink700)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .animation(.easeOut(duration: Motion.enter), value: index)
        }
    }
}

private struct WorkingPanel: View {
    let step: ConnectFlow.Step
    /// "Revisando…" dura 1–4 s y casi siempre menos: se muestra solo si tarda, para que una
    /// comprobación rápida no parpadee como si fuera una espera.
    @State private var visible = false

    var body: some View {
        VStack(spacing: 6) {
            InkSpinner(size: 28)
                .padding(.bottom, 10)
                .opacity(visible ? 1 : 0)
            // El texto del paso cambia con un fundido (150 ms) cuando cambia la fase.
            Text(label)
                .id(step)
                .transition(.opacity)
                .font(Typo.display(24))
                .foregroundStyle(Color.ink900)
                .multilineTextAlignment(.center)
                .opacity(visible ? 1 : 0)
            if step == .waitingForBrowser {
                BrowserHint()
            }
        }
        .animation(.easeOut(duration: Motion.micro), value: step)
        .task {
            // Solo el paso de comprobación espera; los demás pasos se ven desde el primer momento.
            if step == .checking { try? await Task.sleep(for: .seconds(1)) }
            visible = true
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
        case .validatingToken: "connect.step.validatingToken"
        case .creatingSlackApp: "connect.step.creatingSlackApp"
        case .removingServer: "connect.step.removingServer"
        }
    }
}

private struct FailurePanel: View {
    let failure: ConnectFlow.Failure
    let detail: String
    let toolName: String
    let agentName: String
    let language: Language
    var onRecreateSlackApp: () -> Void = {}

    var body: some View {
        NoticePanel(kind: .seal) {
            // Tres partes: qué falló, qué hacer y el detalle técnico.
            Text("connect.failure.title \(toolName)")
                .font(Typo.display(24))
                .foregroundStyle(Color.ink900)
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(Typo.list)
                .foregroundStyle(Color.ink900)
                .fixedSize(horizontal: false, vertical: true)
                .staggered(0)
            if let what {
                Text(what)
                    .font(Typo.list)
                    .foregroundStyle(Color.ink700)
                    .fixedSize(horizontal: false, vertical: true)
                    .staggered(1)
            }
            if failure == .slackAppMissing {
                Button("connect.slack.recreate", action: onRecreateSlackApp)
                    .buttonStyle(.inkInline)
            } else if failure == .slackMCPNotEnabled, let url = URL(string: detail) {
                Button("connect.slack.openAppPage") { NSWorkspace.shared.open(url) }
                    .buttonStyle(.inkInline)
            } else if failure == .nameInUse, !detail.isEmpty {
                // Para este fallo el detalle es el nombre que está ocupado.
                Text(verbatim: detail)
                    .font(Typo.mono)
                    .foregroundStyle(Color.ink900)
                    .textSelection(.enabled)
            } else if !detail.isEmpty {
                Text("connect.failure.detail \(detail)")
                    .font(Typo.mono)
                    .foregroundStyle(Color.ink500)
                    .opacity(0.7)
                    .staggered(2)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            if failure == .slackNotAllowed {
                Button("connect.slack.copyAdminMessage") { copyAdminMessage() }
                    .buttonStyle(.inkInline)
            }
        }
    }

    /// Un mensaje listo para pegar al administrador del workspace.
    private func copyAdminMessage() {
        let appName = agentName.isEmpty ? "Galeno" : "\(agentName) (Galeno)"
        // El idioma que eligió el usuario en el paso 1, no el del sistema: `String(localized:)`
        // no sigue el cambio en caliente.
        let bundle = Bundle.main.path(forResource: language.rawValue, ofType: "lproj")
            .flatMap(Bundle.init(path:)) ?? .main
        let format = bundle.localizedString(forKey: "connect.slack.adminMessage %@", value: nil, table: nil)
        let text = String(format: format, appName)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// «Qué hacer». Los fallos que ya traen su propia salida (un botón, o la instrucción dentro del
    /// mensaje) no repiten una genérica.
    private var what: LocalizedStringKey? {
        switch failure {
        case .couldNotRegister, .notAuthorizedInTime, .loginFailed, .stillNotConnected:
            "connect.failure.what.browser"
        case .bridgeFailed, .bridgeMissing, .qrExpired, .tokenRejected, .slackManifest, .slackUnreachable:
            "connect.failure.what.generic"
        case .slackNotAllowed, .nameInUse, .couldNotRemove, .slackMCPNotEnabled, .slackAppMissing:
            nil
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
        case .tokenRejected: "connect.failure.tokenRejected"
        case .slackNotAllowed: "connect.failure.slackNotAllowed"
        case .slackManifest: "connect.failure.slackManifest"
        case .slackUnreachable: "connect.failure.slackUnreachable"
        case .nameInUse: "connect.failure.nameInUse"
        case .couldNotRemove: "connect.failure.couldNotRemove"
        case .slackMCPNotEnabled: "connect.failure.slackMCPNotEnabled"
        case .slackAppMissing: "connect.failure.slackAppMissing"
        }
    }
}

// MARK: - Listo para conectar

/// La pantalla de cada conexión, antes de conectar (B1): a la izquierda el logo, el nombre y qué
/// leerá el agente; a la derecha, tras un filete, qué va a pasar y una maqueta de lo que se verá.
private struct ReadyLayout: View {
    let tool: Tool
    let name: String

    private var what: LocalizedStringKey {
        switch tool {
        case .slack: "connect.what.slack"
        case .whatsapp: "connect.what.whatsapp"
        default: "connect.what.oauth"
        }
    }

    private var see: LocalizedStringKey {
        switch tool {
        case .slack: "connect.see.slack"
        case .whatsapp: "connect.see.whatsapp"
        default: "connect.see.oauth"
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 32) {
            VStack(spacing: 0) {
                ToolIcon(tool: tool, size: 64, color: Color.ink700)
                    .padding(.bottom, 14)
                Text(verbatim: name)
                    .font(Typo.display(32))
                    .foregroundStyle(Color.ink900)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 6)
                Text(LocalizedStringKey("connect.value." + tool.rawValue))
                    .font(Typo.list)
                    .foregroundStyle(Color.ink700)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 0) {
                SmallCapsLabel("connect.what.title", size: 13)
                    .foregroundStyle(Color.seal700)
                    .padding(.bottom, 6)
                Text(what)
                    .font(Typo.body)
                    .lineSpacing(2)
                    .foregroundStyle(Color.ink900)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 12)
                if tool == .slack {
                    Text("connect.slack.signin.privacy")
                        .font(Typo.text(13))
                        .foregroundStyle(Color.ink500)
                        .fixedSize(horizontal: false, vertical: true)
                }
                SeeSchemes(tool: tool)
                    .padding(.top, 12)
                Text(see)
                    .font(Typo.text(12))
                    .foregroundStyle(Color.ink500)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            .padding(.leading, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) { Rectangle().fill(Color.parchment300).frame(width: 1) }
            // Entrada en dos tiempos: primero el logo y qué hará; 150 ms después, «Qué va a pasar».
            .appearing(after: 0.15)
        }
    }
}

/// Lo que el usuario va a ver al conectar, dibujado como un esquema de línea (B1 · «Lo que verás»):
/// uno por tipo de flujo, con el botón que tendrá que pulsar señalado con un filete lacre.
/// Slack lleva dos, porque son dos ventanas: entrar y permitir.
private struct SeeSchemes: View {
    let tool: Tool

    var body: some View {
        switch tool {
        case .slack:
            HStack(alignment: .center, spacing: 6) {
                SeeMock(kind: .slackSignIn, width: 126)
                Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(Color.ink500)
                SeeMock(kind: .slackAllow, width: 126)
            }
        case .whatsapp:
            SeeMock(kind: .phone, width: 200)
        default:
            SeeMock(kind: .browser, width: 200)
        }
    }
}

enum SeeKind { case browser, slackSignIn, slackAllow, phone }

/// El esquema en sí: formas sencillas en `parchment-400`, sin texto de Slack ni de ningún tercero,
/// salvo el nombre del botón. Es decorativo: lo que dice ya está en el texto de al lado.
struct SeeMock: View {
    let kind: SeeKind
    let width: CGFloat
    /// Con el puntero encima, el botón señalado se ilumina en tinta (150 ms): es el que se va a pulsar.
    @State private var hovering = false

    private var line: Color { .parchment400 }

    var body: some View {
        Group {
            switch kind {
            case .phone: phone
            default: window
            }
        }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: Motion.micro), value: hovering)
        .accessibilityHidden(true)
    }

    // MARK: Ventana

    private var window: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 3) {
                Circle().fill(line).frame(width: 5, height: 5)
                Circle().fill(line).frame(width: 5, height: 5)
                RoundedRectangle(cornerRadius: 2).fill(line).frame(width: width * 0.35, height: 4)
                    .padding(.leading, 6)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(height: 14)
            Rectangle().fill(line).frame(height: 1)
            VStack(alignment: .leading, spacing: 5) {
                switch kind {
                case .slackSignIn:
                    Rectangle().fill(line).frame(width: width * 0.4, height: 4)
                    Rectangle().strokeBorder(line, lineWidth: 1).frame(height: 14)
                    Rectangle().strokeBorder(line, lineWidth: 1).frame(height: 14)
                    HStack { Spacer(); pointed("connect.see.signin") }.padding(.top, 2)
                case .slackAllow:
                    HStack(spacing: 5) {
                        Rectangle().strokeBorder(line, lineWidth: 1).frame(width: 14, height: 14)
                        VStack(alignment: .leading, spacing: 3) {
                            Rectangle().fill(line).frame(width: width * 0.4, height: 4)
                            Rectangle().fill(line).frame(width: width * 0.25, height: 3)
                        }
                    }
                    Rectangle().fill(line).frame(width: width * 0.7, height: 3)
                    Rectangle().fill(line).frame(width: width * 0.5, height: 3)
                    HStack { Spacer(); pointed("connect.see.allow") }.padding(.top, 2)
                default:
                    Rectangle().fill(line).frame(width: width * 0.5, height: 4)
                    Rectangle().fill(line).frame(width: width * 0.7, height: 4)
                    Rectangle().fill(line).frame(width: width * 0.4, height: 4)
                    HStack { Spacer(); pointed("connect.see.allow") }.padding(.top, 4)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
        }
        .frame(width: width)
        .background(Color.parchment100)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.parchment400, lineWidth: 1))
    }

    // MARK: Teléfono

    /// «Ajustes → Dispositivos vinculados → Vincular un dispositivo», en el teléfono.
    private var phone: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(spacing: 0) {
                Capsule().fill(line).frame(width: 18, height: 3).padding(.top, 5)
                VStack(alignment: .leading, spacing: 6) {
                    Rectangle().fill(line).frame(width: 36, height: 3)
                    Rectangle().fill(line).frame(width: 28, height: 3)
                    pointed("connect.see.link")
                    Rectangle().fill(line).frame(width: 32, height: 3)
                }
                .padding(.top, 10)
                Spacer(minLength: 0)
            }
            .frame(width: 56, height: 96)
            .background(Color.parchment100)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.parchment400, lineWidth: 1.5))

            // El código que la cámara tiene que apuntar.
            Image(systemName: "qrcode")
                .font(.system(size: 34, weight: .ultraLight))
                .foregroundStyle(line)
        }
        .frame(width: width, alignment: .leading)
    }

    /// El botón que hay que pulsar, señalado en lacre.
    private func pointed(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(Typo.text(10))
            .foregroundStyle(hovering ? Color.ink900 : Color.seal700)
            .padding(.horizontal, 8)
            .frame(height: 18)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(hovering ? Color.ink900 : Color.seal700, lineWidth: 1.5))
    }
}

/// El aviso de WhatsApp, a pantalla completa (B1): el logo a la izquierda y el aviso en su marco.
private struct WhatsAppWarningLayout: View {
    let name: String

    var body: some View {
        HStack(alignment: .center, spacing: 28) {
            VStack(spacing: 0) {
                ToolIcon(tool: .whatsapp, size: 56, color: Color.ink700)
                    .padding(.bottom, 10)
                Text(verbatim: name)
                    .font(Typo.display(26))
                    .foregroundStyle(Color.ink900)
                Text("connect.value.whatsapp")
                    .font(Typo.text(13))
                    .foregroundStyle(Color.ink500)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            .frame(width: 150)
            WhatsAppWarning()
        }
    }
}

// MARK: - Un servidor con el mismo nombre

/// Ya hay otro servidor con el nombre normal en Claude Code. Lo predeterminado es **no tocarlo**:
/// Galeno registra el suyo con otro nombre. Borrarlo es una opción aparte y pide confirmación.
private struct NameConflictPanel: View {
    @ObservedObject var flow: ConnectFlow
    let server: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s8) {
            Text("connect.nameConflict.title \(server)")
                .font(Typo.display(24))
                .foregroundStyle(Color.ink900)
                .fixedSize(horizontal: false, vertical: true)
            Text("connect.nameConflict.body \(server)")
                .font(Typo.list)
                .lineSpacing(2)
                .foregroundStyle(Color.ink700)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 10)
            // Lo predeterminado es no tocar el servidor del usuario: el botón principal registra el
            // de Galeno con otro nombre. Borrar es la opción aparte.
            Button {
                flow.useAlternateName()
            } label: {
                HStack {
                    (Text("connect.nameConflict.useOther") + Text(verbatim: " · galeno-\(server)"))
                    Spacer()
                    SmallCapsLabel("connect.nameConflict.recommended", size: 12, tracking: 0.1)
                        .opacity(0.8)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(InkButtonStyle(.primary, padding: 18, height: 48))
            .keyboardShortcut(.defaultAction)
            .padding(.bottom, 2)
            // La opción recomendada se posa 250 ms después del texto; la otra, 80 ms más tarde, solo con opacidad.
            .settling(after: 0.25)
            Button {
                flow.askToRemoveConflictingServer()
            } label: {
                Text("connect.nameConflict.remove").frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(InkButtonStyle(.secondary, padding: 18, quiet: true))
            .appearing(after: 0.33)
        }
    }
}

/// La confirmación de borrar: dice qué se borra y qué no, y el botón destructivo no es el
/// predeterminado (Enter no borra).
private struct RemovalConfirmPanel: View {
    @ObservedObject var flow: ConnectFlow
    let server: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s8) {
            Text("connect.removal.title \(server)")
                .font(Typo.display(24))
                .foregroundStyle(Color.ink900)
                .fixedSize(horizontal: false, vertical: true)
            Text("connect.removal.body")
                .font(Typo.list)
                .lineSpacing(2)
                .foregroundStyle(Color.ink700)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 10)
            HStack(spacing: Space.s12) {
                Button("connect.removal.cancel") { flow.cancelRemoval() }
                    .buttonStyle(.inkPrimary)
                    .keyboardShortcut(.defaultAction)
                Button("connect.removal.confirm \(server)", role: .destructive) {
                    flow.removeConflictingServer()
                }
                .buttonStyle(.inkSecondary)
            }
        }
    }
}

// MARK: - WhatsApp

/// La advertencia explícita de `docs/03` §4, **antes** del QR y con un botón para
/// continuar: "Tú decides si continuar". El texto es el de la spec y no se toca
/// sin que Rafa lo apruebe (`AGENTS.md`).
private struct WhatsAppWarning: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SmallCapsLabel("connect.whatsapp.warning.title", size: 13, tracking: 0.14)
                .foregroundStyle(Color.seal700)
            Text("connect.whatsapp.warning.body")
                .font(Typo.text(15.5))
                .lineSpacing(2)
                .foregroundStyle(Color.ink900)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, Space.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.parchment100, in: RoundedRectangle(cornerRadius: Radius.b1))
        .overlay(RoundedRectangle(cornerRadius: Radius.b1).strokeBorder(Color.ink900, lineWidth: 1.5))
    }
}

/// El QR, en un marco de 1 px `ink-900` sobre `parchment-100` (`docs/04` §9). Va
/// sobre blanco: un QR de tinta clara sobre fondo oscuro no se lee.
private struct QRPanel: View {
    let image: Data?
    @Environment(\.galenoReduceMotion) private var reduceMotion
    /// Desde cuándo está visible este código: lo reinicia cada código nuevo.
    @State private var shownSince = Date()
    private var renewal: Int { image?.hashValue ?? 0 }

    var body: some View {
        HStack(alignment: .center, spacing: 36) {
            qr
            VStack(alignment: .leading, spacing: 0) {
                Text("connect.whatsapp.qr.title")
                    .font(Typo.display(28))
                    .foregroundStyle(Color.ink900)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 12)
                // Los tres pasos se iluminan uno a uno cada 2 s, en bucle: guía pasiva, no hay nada que pulsar.
                TimelineView(.periodic(from: shownSince, by: 2)) { context in
                    let active = Int(context.date.timeIntervalSince(shownSince) / 2) % 3
                    VStack(alignment: .leading, spacing: Space.s8) {
                        ForEach(1...3, id: \.self) { number in
                            NumberedLine(number: number, numberWidth: 22) {
                                Text(LocalizedStringKey("connect.whatsapp.qr.step\(number)"))
                                    .font(Typo.text(15.5))
                                    .foregroundStyle(reduceMotion || active == number - 1 ? Color.ink900 : Color.ink700)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .animation(.easeOut(duration: Motion.enter), value: active)
                }
                // «El código cambia cada minuto»: el anillo da una vuelta por minuto, un indicador honesto.
                HStack(spacing: Space.s8) {
                    MinuteRing(since: shownSince)
                    Text("connect.whatsapp.qr.rotates")
                        .font(Typo.text(13))
                        .foregroundStyle(Color.ink500)
                }
                .padding(.top, 14)
            }
            .frame(maxWidth: 300, alignment: .leading)
        }
        // Cada código nuevo reinicia el anillo del minuto y la guía de los tres pasos.
        .onChange(of: renewal) { _, _ in shownSince = Date() }
    }

    /// El código va siempre sobre blanco, con un filete de tinta y, separado, otro más suave.
    @ViewBuilder
    private var qr: some View {
        Group {
            if let image, let nsImage = NSImage(data: image) {
                // Un código nuevo sustituye al viejo con un fundido cruzado (300 ms), sin cambiar de tamaño.
                Image(nsImage: nsImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .id(image.hashValue)
                    .transition(.opacity)
                    .accessibilityLabel(Text("connect.whatsapp.qr.title"))
            } else {
                VStack(spacing: Space.s8) {
                    InkSpinner(size: 16)
                    Text("connect.whatsapp.qr.generating")
                        .font(Typo.text(13))
                        .foregroundStyle(Color(red: 0.39, green: 0.40, blue: 0.37))
                }
            }
        }
        .frame(width: 189, height: 189)
        .animation(.easeOut(duration: Motion.enter), value: image)
        .padding(12)
        .background(Color.white)
        .overlay(Rectangle().strokeBorder(Color(red: 0.18, green: 0.176, blue: 0.165), lineWidth: 1))
        .padding(6)
        .overlay(Rectangle().strokeBorder(Color.parchment400, lineWidth: 1))
    }
}

/// "Sincronizando…": barra indeterminada y los chats que ya aparecieron. El bridge
/// no da progreso real, y la barra no finge darlo.
private struct SyncingPanel: View {
    let chats: Int

    var body: some View {
        VStack(spacing: 0) {
            Text("connect.whatsapp.syncing.title")
                .font(Typo.display(28))
                .foregroundStyle(Color.ink900)
            InkRunBar()
                .padding(.top, 18)
                .padding(.bottom, 12)
            ChasingNumber(target: chats) { Text("connect.whatsapp.syncing \($0)") }
                .font(Typo.text(18))
                .foregroundStyle(Color.ink900)
            Text("connect.whatsapp.syncing.hint")
                .font(Typo.text(14))
                .lineSpacing(2)
                .foregroundStyle(Color.ink700)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
    }
}

// MARK: - El dato real

extension ConnectFlow.Finding {
    /// "Encontré 12 canales" / "Encontré al menos 10 páginas".
    var text: Text { text(count.value) }

    /// El mismo texto con otra cifra: lo usa la cuenta que sube de 0 al dato real.
    func text(_ n: Int) -> Text {
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

/// «Encontré 48 páginas y bases de datos» con la cifra contando de 0 al dato real (600 ms), a partir de
/// `delay`. El valor es siempre el que devolvió el servidor: nunca se anima una cifra inventada.
struct CountingFinding: View {
    let finding: ConnectFlow.Finding
    var delay: Double = 0
    var duration: Double = 0.6

    @Environment(\.galenoReduceMotion) private var reduceMotion
    @State private var shown = 0

    var body: some View {
        finding.text(shown)
            .contentTransition(.numericText())
            .appearing(after: delay)
            .task(id: finding.count.value) {
                if reduceMotion { shown = finding.count.value; return }
                let target = finding.count.value
                let steps = min(max(target, 1), 24)
                try? await Task.sleep(for: .seconds(delay))
                for step in 1...steps {
                    try? await Task.sleep(for: .seconds(duration / Double(steps)))
                    if Task.isCancelled { return }
                    withAnimation(.easeOut(duration: 0.08)) { shown = target * step / steps }
                }
                shown = target
            }
    }
}

/// Un anillo de 10 pt que se llena en un minuto —lo que dura el código— y se reinicia con el siguiente.
private struct MinuteRing: View {
    let since: Date
    @Environment(\.galenoReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: since, by: 1)) { context in
            let fraction = reduceMotion ? 0.0 : min(1, context.date.timeIntervalSince(since) / 60)
            Circle()
                .strokeBorder(Color.ink300, lineWidth: 1.5)
                .overlay(
                    Circle().trim(from: 0, to: fraction)
                        .stroke(Color.ink700, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .rotationEffect(.degrees(-90)))
                .frame(width: 10, height: 10)
        }
        .accessibilityHidden(true)
    }
}
