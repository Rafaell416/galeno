import AppKit
import Combine
import GalenoCore
import SwiftUI
import WebKit

/// La ventana donde el usuario inicia sesión en Slack y Galeno consigue el token de
/// configuración por él (`docs/03` §4e).
///
/// - La sesión **no se guarda**: el almacén de datos es efímero y muere con la ventana.
/// - Galeno **no lee la contraseña**: el script de captura solo actúa en `api.slack.com`.
/// - **No se esquiva a Google**: Google no permite iniciar sesión en ventanas embebidas en
///   apps, así que aquí su inicio de sesión no se abre; se le dice al usuario que use el código
///   por correo de Slack. La ventana se identifica como lo que es (el WebKit de Safari).
/// - El token va de la página a un `OAuthSecret`, sin pasar por el portapapeles ni el disco.
@MainActor
final class SlackSignInModel: NSObject, ObservableObject {
    enum Stage: Equatable {
        case loading
        /// En una página de inicio de sesión (Slack o el proveedor de la empresa).
        case signIn
        /// En Google, que no deja iniciar sesión en ventanas embebidas.
        case googleSignIn
        /// En la página de tokens: Galeno está generando el token.
        case working
        /// Hay varios workspaces: elige el usuario en la propia página.
        case chooseWorkspace
        /// Pasó un rato sin token: que el usuario pulse «Generate Token» él mismo.
        case needsClick
        case captured
        case loadFailed(String)
    }

    @Published private(set) var stage: Stage = .loading
    @Published private(set) var host = ""

    let webView: WKWebView
    /// Cuánto se espera en la página de tokens antes de pedirle al usuario que pulse él.
    var hintDelay: Duration = .seconds(15)

    private let onToken: (OAuthSecret) -> Void
    private var captured = false
    private var hintTask: Task<Void, Never>?
    private var urlObserver: AnyCancellable?
    private var redirectsToTokensPage = 0
    private var openedSignIn = false
    private var returnedAfterSignIn = false

    /// Cómo se navega. Las pruebas lo reemplazan para no salir a la red.
    var navigate: (URL) -> Void = { _ in }

    /// - Parameters:
    ///   - freshOnly: ignora los tokens que ya estén en la página y genera uno nuevo.
    ///   - dataStore: efímero por defecto: nada de la sesión queda en el disco.
    init(
        freshOnly: Bool = false,
        dataStore: WKWebsiteDataStore = .nonPersistent(),
        onToken: @escaping (OAuthSecret) -> Void
    ) {
        self.onToken = onToken

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        configuration.applicationNameForUserAgent = SlackCapture.safariApplicationName()
        let content = configuration.userContentController
        content.addUserScript(
            WKUserScript(
                source: SlackCapture.configScript(freshOnly: freshOnly),
                injectionTime: .atDocumentStart, forMainFrameOnly: true))
        content.addUserScript(
            WKUserScript(
                source: SlackCapture.script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        webView = WKWebView(frame: .zero, configuration: configuration)

        super.init()

        // El controlador retiene a quien recibe los mensajes: va un intermediario débil.
        content.add(MessageProxy(self), name: SlackCapture.messageHandlerName)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        navigate = { [weak self] url in self?.webView.load(URLRequest(url: url)) }
        dataStore.httpCookieStore.add(self)
        urlObserver = webView.publisher(for: \.url).sink { [weak self] url in
            self?.locationChanged(url)
        }
    }

    func start() {
        navigate(SlackCapture.tokensURL)
    }

    func goToTokensPage() {
        navigate(SlackCapture.tokensURL)
    }

    /// Al cerrar la ventana: se corta todo y la sesión efímera se pierde con el `WKWebView`.
    func tearDown() {
        hintTask?.cancel()
        urlObserver = nil
        webView.stopLoading()
        webView.configuration.websiteDataStore.httpCookieStore.remove(self)
        webView.configuration.userContentController.removeAllUserScripts()
        webView.configuration.userContentController
            .removeScriptMessageHandler(forName: SlackCapture.messageHandlerName)
    }

    // MARK: - Lo que dice la página

    /// Un mensaje del script. `host` e `isMainFrame` los da WebKit, no la página.
    func receive(body: Any, host: String, isMainFrame: Bool) {
        guard SlackCapture.isTrustedSource(host: host, isMainFrame: isMainFrame),
            let message = body as? [String: Any], let kind = message["kind"] as? String
        else { return }

        switch kind {
        case "token":
            // Se vuelve a comprobar aquí: no se confía en que el script haya filtrado bien.
            guard !captured, let raw = message["value"] as? String,
                let token = SlackTokenPattern.bestToken(in: raw)
            else { return }
            captured = true
            hintTask?.cancel()
            stage = .captured
            onToken(OAuthSecret(token))
        case "page":
            guard !captured, let state = message["state"] as? String else { return }
            switch state {
            case "signedOut":
                // Sin sesión: se abre el inicio de sesión de Slack, una sola vez.
                hintTask?.cancel()
                hintTask = nil
                stage = .signIn
                if !openedSignIn {
                    openedSignIn = true
                    navigate(SlackCapture.signInURL)
                }
            case "chooseWorkspace":
                stage = .chooseWorkspace
            default:
                // Con sesión y en la página de tokens: Galeno trabaja; si tarda, se avisa.
                if stage != .needsClick && stage != .chooseWorkspace { stage = .working }
                if hintTask == nil { startHintTimer() }
            }
        default:
            break
        }
    }

    private func locationChanged(_ url: URL?) {
        guard !captured else { return }
        host = url?.host ?? ""
        switch SlackSignInLocation.classify(url) {
        case .tokensPage:
            // Todavía no se sabe si hay sesión: lo dice el script en cuanto mira la página.
            if stage != .working && stage != .chooseWorkspace && stage != .needsClick {
                stage = .loading
            }
        case .slackClient:
            // Ya inició sesión pero cayó en el cliente de Slack: se le lleva a la de tokens.
            hintTask?.cancel()
            hintTask = nil
            if redirectsToTokensPage < 3 {
                redirectsToTokensPage += 1
                goToTokensPage()
            } else {
                stage = .signIn
            }
        case .google:
            hintTask?.cancel()
            hintTask = nil
            stage = .googleSignIn
        case .slack, .other:
            hintTask?.cancel()
            hintTask = nil
            if url != nil { stage = .signIn }
        }
    }

    /// Apareció la sesión de Slack: tras iniciar sesión, Slack deja al usuario en su página de
    /// workspaces, no en la de tokens. Se le lleva de vuelta, una sola vez.
    func sessionCookieAppeared() {
        guard !captured, !returnedAfterSignIn,
            SlackSignInLocation.classify(webView.url) != .tokensPage
        else { return }
        returnedAfterSignIn = true
        goToTokensPage()
    }

    private func startHintTimer() {
        hintTask?.cancel()
        let delay = hintDelay
        hintTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, !self.captured else { return }
            if self.stage == .working { self.stage = .needsClick }
        }
    }

    private final class MessageProxy: NSObject, WKScriptMessageHandler {
        weak var model: SlackSignInModel?
        init(_ model: SlackSignInModel) { self.model = model }

        func userContentController(
            _ userContentController: WKUserContentController, didReceive message: WKScriptMessage
        ) {
            model?.receive(
                body: message.body, host: message.frameInfo.securityOrigin.host,
                isMainFrame: message.frameInfo.isMainFrame)
        }
    }
}

extension SlackSignInModel: WKHTTPCookieStoreObserver {
    nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        Task { @MainActor [weak self] in
            let cookies = await cookieStore.allCookies()
            if SlackCapture.hasSessionCookie(cookies) { self?.sessionCookieAppeared() }
        }
    }
}

extension SlackSignInModel: WKNavigationDelegate, WKUIDelegate {
    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        switch SlackCapture.navigationDecision(for: navigationAction.request.url) {
        case .allow:
            return .allow
        case .blockedGoogleSignIn:
            // Solo cuenta la página principal: un recurso de Google incrustado no es un login.
            if navigationAction.targetFrame?.isMainFrame ?? true { stage = .googleSignIn }
            return .cancel
        case .blocked:
            return .cancel
        }
    }

    /// Los enlaces que piden ventana nueva (el inicio de sesión con un proveedor) se abren aquí
    /// mismo: no hay más ventanas que esta.
    func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        switch SlackCapture.navigationDecision(for: navigationAction.request.url) {
        case .allow: webView.load(navigationAction.request)
        case .blockedGoogleSignIn: stage = .googleSignIn
        case .blocked: break
        }
        return nil
    }

    func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error
    ) {
        // -999 es una navegación cancelada (por otra más nueva o por la política de arriba).
        guard (error as NSError).code != NSURLErrorCancelled, !captured else { return }
        stage = .loadFailed(error.localizedDescription)
    }
}

// MARK: - La vista

struct SlackSignInView: View {
    @ObservedObject var model: SlackSignInModel
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            WebViewContainer(webView: model.webView)
        }
        .background(Color.parchment50)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s8) {
            HStack(spacing: Space.s12) {
                // La dirección a la vista: el usuario tiene que poder comprobar dónde escribe.
                Label {
                    Text(verbatim: model.host.isEmpty ? "…" : model.host)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(Color.ink900)
                        .textSelection(.enabled)
                } icon: {
                    Image(systemName: "lock.fill").foregroundStyle(Color.ink700)
                }
                Spacer()
                Button("connect.slack.window.tokensPage") { model.goToTokensPage() }
                    .buttonStyle(.bordered)
                Button("connect.slack.window.cancel", action: onCancel)
                    .buttonStyle(.bordered)
            }
            HStack(alignment: .firstTextBaseline, spacing: Space.s8) {
                if model.stage == .loading || model.stage == .working {
                    ProgressView().controlSize(.small)
                }
                statusText
                    .font(.galenoBody)
                    .foregroundStyle(isWarning ? Color.seal700 : Color.ink900)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Space.s16)
        .padding(.vertical, Space.s12)
    }

    private var isWarning: Bool {
        switch model.stage {
        case .googleSignIn, .loadFailed: true
        default: false
        }
    }

    private var statusText: Text {
        switch model.stage {
        case .loading: Text("connect.slack.window.loading")
        case .signIn: Text("connect.slack.window.signIn")
        case .googleSignIn: Text("connect.slack.window.google")
        case .working: Text("connect.slack.window.working")
        case .chooseWorkspace: Text("connect.slack.window.chooseWorkspace")
        case .needsClick: Text("connect.slack.window.needsClick")
        case .captured: Text("connect.slack.window.captured")
        case .loadFailed(let detail): Text("connect.slack.window.loadFailed \(detail)")
        }
    }
}

private struct WebViewContainer: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

// MARK: - La ventana

/// Abre la ventana de inicio de sesión, entrega el token cuando aparece y lo limpia todo al
/// cerrarse, la cierre quien la cierre.
@MainActor
final class SlackSignInWindow: NSObject, NSWindowDelegate {
    private static var current: SlackSignInWindow?

    private let window: NSWindow
    private let model: SlackSignInModel

    static func present(
        freshOnly: Bool, language: Language, onToken: @escaping @MainActor (OAuthSecret) -> Void
    ) {
        current?.close()
        current = SlackSignInWindow(freshOnly: freshOnly, language: language, onToken: onToken)
    }

    private init(freshOnly: Bool, language: Language, onToken: @escaping @MainActor (OAuthSecret) -> Void) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 720),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        var deliver: ((OAuthSecret) -> Void)?
        model = SlackSignInModel(freshOnly: freshOnly) { secret in deliver?(secret) }
        super.init()

        deliver = { [weak self] secret in
            // Se entrega el token y se cierra: la sesión efímera muere con la ventana.
            self?.close()
            onToken(secret)
        }
        window.title = "Slack"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(
            rootView: SlackSignInView(model: model, onCancel: { [weak self] in self?.close() })
                .environment(\.locale, Locale(identifier: language.rawValue)))
        window.center()
        window.makeKeyAndOrderFront(nil)
        model.start()
    }

    private func close() {
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        model.tearDown()
        if Self.current === self { Self.current = nil }
    }
}
