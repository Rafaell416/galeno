import AppKit
import SwiftUI

/// Paso 2: dejar Claude Code listo (`docs/03` §3). Galeno mira qué falta y lo hace cuando el usuario lo
/// pide con un botón: instalarlo, actualizarlo o iniciar su sesión. No se sigue hasta que esté listo.
struct DetectionStepView: View {
    static let guideURL = URL(string: "https://code.claude.com/docs/en/setup")!

    var body: some View {
        StepScaffold(step: .detection, summarySize: 16, titleGap: 8, contentGap: 20) {
            ClaudeSetupContent()
        }
    }
}

/// Cómo está Claude Code y, si falta algo, el botón que lo arregla. Lo usan el paso 2 y la entrada a
/// «Conectar» del wizard corto y de «Gestionar», que no pasan por el paso 2.
struct ClaudeSetupContent: View {
    @EnvironmentObject private var wizard: WizardState
    @Environment(\.locale) private var locale
    /// El último resultado que no fue «buscando»: al comprobar de nuevo, la tarjeta se queda (a media
    /// opacidad) en vez de ceder el sitio a la rueda.
    @State private var previous: ClaudeCodeStatus?

    private var isChecking: Bool { wizard.claudeStatus == .checking }

    /// Lo que se dibuja: el resultado anterior mientras se vuelve a buscar, si pedía algo.
    private var shown: ClaudeCodeStatus {
        if isChecking, let previous, previous != .checking, !previous.isReady { return previous }
        return wizard.claudeStatus
    }

    var body: some View {
        Group {
            switch wizard.claudeSetup {
            case .installing, .signingIn:
                SetupWorkingPanel(phase: wizard.claudeSetup)
            case .failed(let failure):
                SetupFailurePanel(failure: failure)
            case .idle:
                status
            }
        }
        .onChange(of: wizard.claudeStatus) { _, status in if status != .checking { previous = status } }
        .onAppear { if wizard.claudeStatus != .checking { previous = wizard.claudeStatus } }
        .task { await wizard.detectClaudeCodeIfNeeded() }
    }

    @ViewBuilder
    private var status: some View {
        switch shown {
        case .checking:
            // Buscar tarda unos segundos (hay que preguntarle a `claude` su versión y su sesión): se dice qué
            // se mira, en vez de dejar una rueda sola.
            VStack(alignment: .leading, spacing: 10) {
                Text("detection.checking")
                    .font(Typo.display(20))
                    .foregroundStyle(Color.ink900)
                WaitingTicker(lines: WaitingLines.checking(locale), interval: 3.5)
            }
            .frame(maxWidth: 520, alignment: .leading)
        case .found(let version, let path, let loggedIn):
            // `nil` es "no se pudo saber": en ese caso no se detiene a nadie.
            if loggedIn == false {
                SetupPanel(need: .signIn, isChecking: isChecking)
            } else {
                FoundPanel(version: version, path: path, loggedIn: loggedIn == true)
            }
        case .outdated(let version, _):
            SetupPanel(need: .update(version: version), isChecking: isChecking)
        case .notFound:
            SetupPanel(need: .install, isChecking: isChecking)
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

/// Algo falta y Galeno lo arregla (decisión de Rafa, 5 oct 2026): un aviso corto y **un** botón. El usuario
/// no ve comandos ni abre la Terminal.
private struct SetupPanel: View {
    enum Need: Equatable {
        case install
        case update(version: String)
        case signIn
    }

    @EnvironmentObject private var wizard: WizardState
    let need: Need
    var isChecking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // La instalación salió bien y ahora toca la sesión: primero se dice lo logrado (feedback de
            // Aquiles, 5 oct 2026: pasó a «inicia sesión» sin confirmar que ya quedó instalado).
            if need == .signIn, let version = wizard.claudeJustInstalledVersion, !version.isEmpty {
                HStack(spacing: 10) {
                    TracedShape(shape: CheckMark(), lineWidth: 1.5, color: .moss700, duration: 0.25)
                        .frame(width: 14, height: 14)
                        .accessibilityHidden(true)
                    Text("detection.justInstalled \(version)")
                        .font(Typo.list)
                        .foregroundStyle(Color.ink700)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .appearing(after: 0, duration: Motion.enter)
            }
            HStack(alignment: .top, spacing: 14) {
                TracedShape(shape: Circle().inset(by: 0.75), lineWidth: 1.5, color: .ochre700, duration: 0.3)
                    .frame(width: 26, height: 26)
                    .overlay {
                        Text(verbatim: "!").font(Typo.text(15, .semibold)).foregroundStyle(Color.ochre700)
                            .appearing(after: 0.15, duration: 0.15)
                    }
                    .padding(.top, 2)
                NoticePanel(kind: .ochre) {
                    Text(title)
                        .font(Typo.display(20))
                        .foregroundStyle(Color.ink900)
                    body(for: need)
                        .font(Typo.list)
                        .foregroundStyle(Color.ink700)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .opacity(isChecking ? 0.5 : 1)
            .animation(.easeOut(duration: Motion.micro), value: isChecking)
            Button(action: act) { Text(button) }
                .buttonStyle(InkButtonStyle(.primary, padding: 24, isLoading: isChecking))
                .keyboardShortcut(.defaultAction)
                .disabled(isChecking)
        }
        .appearing(after: 0, duration: Motion.enter)
    }

    private func act() {
        switch need {
        case .install, .update: wizard.installClaudeCode()
        case .signIn: wizard.signInToClaude()
        }
    }

    private var title: LocalizedStringKey {
        switch need {
        case .install: "detection.notFound.title"
        case .update: "detection.outdated.title"
        case .signIn: "detection.loggedOut.title"
        }
    }

    private func body(for need: Need) -> Text {
        switch need {
        case .install: Text("detection.notFound.body")
        case .update(let version): Text("detection.outdated.body \(version)")
        case .signIn: Text("detection.loggedOut.body")
        }
    }

    private var button: LocalizedStringKey {
        switch need {
        case .install: "detection.install"
        case .update: "detection.update"
        case .signIn: "detection.signin"
        }
    }
}

/// Galeno está instalando, o espera a que el usuario entre en el navegador. Mientras se espera el
/// navegador hay dos salidas a la vista: «Ya inicié sesión, comprobar» y «Cancelar».
private struct SetupWorkingPanel: View {
    @EnvironmentObject private var wizard: WizardState
    let phase: ClaudeSetupPhase
    @State private var confirming = false
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // La espera más larga del asistente: en vez de una rueda, frases que se escriben solas, un trazo
            // que va y viene y el tiempo que lleva. A la derecha, la lámina de la pluma.
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(phase == .installing ? "detection.installing" : "detection.signingIn")
                        .font(Typo.display(24))
                        .foregroundStyle(Color.ink900)
                    if phase == .installing {
                        WaitingTicker(
                            lines: WaitingLines.installing(locale), loopFrom: 2,
                            slowLine: Localized.string("wait.slow", locale: locale))
                    } else {
                        WaitingTicker(lines: WaitingLines.signingIn(locale), interval: 6)
                    }
                }
                .frame(maxWidth: 440, alignment: .leading)
                Plate(
                    asset: "plate-pluma", caption: "pluma sobre un folio, grabado de línea",
                    size: CGSize(width: 190, height: 120), printOnPaper: true
                )
                .appearing(after: 0.2, duration: 0.5)
            }
            if phase == .signingIn {
                HStack(spacing: Space.s12) {
                    Button("detection.signingIn.confirm") {
                        confirming = true
                        Task {
                            await wizard.confirmClaudeSignIn()
                            confirming = false
                        }
                    }
                    .buttonStyle(InkButtonStyle(.secondary, padding: 20, isLoading: confirming))
                    .disabled(confirming)
                    Button("detection.cancel") { wizard.cancelClaudeSetup() }
                        .buttonStyle(.inkTertiary)
                }
            }
        }
        .appearing(after: 0, duration: Motion.enter)
    }
}

/// Lo que Galeno intentó y no salió: qué pasó, por qué y qué hacer, con «Reintentar» siempre a la vista.
private struct SetupFailurePanel: View {
    @EnvironmentObject private var wizard: WizardState
    let failure: ClaudeSetupFailure

    private var isInstall: Bool {
        switch failure {
        case .offline, .installTimedOut, .installFailed: true
        case .signInTimedOut, .signInFailed: false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            NoticePanel(kind: .seal) {
                Text(isInstall ? "detection.failure.install.title" : "detection.failure.signin.title")
                    .font(Typo.display(20))
                    .foregroundStyle(Color.ink900)
                Text(cause)
                    .font(Typo.list)
                    .foregroundStyle(Color.ink900)
                    .fixedSize(horizontal: false, vertical: true)
                Text(what)
                    .font(Typo.list)
                    .foregroundStyle(Color.ink700)
                    .fixedSize(horizontal: false, vertical: true)
                if !failure.detail.isEmpty {
                    Text("connect.failure.detail \(failure.detail)")
                        .font(Typo.mono)
                        .foregroundStyle(Color.ink500)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }
            HStack(spacing: Space.s16) {
                Button("detection.retry") {
                    if isInstall { wizard.installClaudeCode() } else { wizard.signInToClaude() }
                }
                .buttonStyle(InkButtonStyle(.primary, padding: 24))
                .keyboardShortcut(.defaultAction)
                if isInstall, failure != .offline {
                    // La salida de emergencia: la guía oficial, para hacerlo a mano.
                    Link("detection.guide", destination: DetectionStepView.guideURL)
                        .font(Typo.list)
                        .foregroundStyle(Color.ink900)
                        .underline()
                }
            }
        }
        .onAppear { Sounds.play(.failed) }
        .appearing(after: 0, duration: Motion.enter)
    }

    private var cause: LocalizedStringKey {
        switch failure {
        case .offline: "detection.failure.offline"
        case .installTimedOut: "detection.failure.installTimedOut"
        case .installFailed: "detection.failure.installFailed"
        case .signInTimedOut: "detection.failure.signInTimedOut"
        case .signInFailed: "detection.failure.signInFailed"
        }
    }

    private var what: LocalizedStringKey {
        switch failure {
        case .offline: "detection.failure.offline.what"
        case .installTimedOut, .installFailed: "detection.failure.install.what"
        case .signInTimedOut, .signInFailed: "detection.failure.signin.what"
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

#Preview("Desactualizado") {
    DetectionStepView()
        .environmentObject(
            WizardState(claudeStatus: .outdated(version: "2.1.150", path: "/usr/local/bin/claude")))
        .frame(width: WindowMetrics.width, height: 440)
        .background(Color.parchment50)
}

#Preview("No instalado") {
    DetectionStepView()
        .environmentObject(WizardState(claudeStatus: .notFound))
        .frame(width: WindowMetrics.width, height: 440)
        .background(Color.parchment50)
}

/// Las frases de cada espera del paso 2 (`WaitingTicker`), ya en el idioma de la app. Todas son ciertas pase
/// lo que pase: no dicen en qué punto va la descarga, que Galeno no lo sabe.
enum WaitingLines {
    private static func lines(_ prefix: String, _ count: Int, _ locale: Locale) -> [String] {
        (1...count).map { Localized.string(prefix + "." + String($0), locale: locale) }
    }

    static func checking(_ locale: Locale) -> [String] { lines("wait.check", 3, locale) }
    static func installing(_ locale: Locale) -> [String] { lines("wait.install", 7, locale) }
    static func signingIn(_ locale: Locale) -> [String] { lines("wait.signin", 3, locale) }
}
