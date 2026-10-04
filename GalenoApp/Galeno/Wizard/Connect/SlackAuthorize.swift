import AppKit
import Combine
import GalenoCore
import OSLog
import SwiftUI
import WebKit

#if DEBUG
private let authorizeLog = Logger(subsystem: "com.galeno.Galeno", category: "slackSignIn")
private func trace(_ message: String) { authorizeLog.notice("\(message, privacy: .public)") }
#else
private func trace(_ message: @autoclosure () -> String) {}
#endif

// MARK: - Qué se puede abrir

/// Las reglas de la ventana de autorización de Slack (`docs/03` §4e).
///
/// Después de crear la app, `claude mcp login` abre una página de Slack («Permitir») y espera a
/// que el navegador vuelva a `http://localhost:51820/callback`, donde `claude` recibe el código.
/// Galeno muestra esa página en su propia ventana, con la sesión que ya tiene, y la cierra sola
/// cuando `claude` confirma. Solo se abre una dirección de Slack, y la única dirección que no es
/// `https` que se acepta es la vuelta exacta a ese puerto.
nonisolated enum SlackAuthorization {
    /// ¿Es una página de autorización de Slack? Solo `https` y solo `slack.com` (o un subdominio).
    static func isSlackAuthorizationURL(_ url: URL?) -> Bool {
        guard let url, url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return host == "slack.com" || host.hasSuffix(".slack.com")
    }

    /// La vuelta de `claude`: exactamente `http://localhost:<puerto de Galeno>/callback`.
    static func isCallback(_ url: URL?) -> Bool {
        guard let url, url.scheme?.lowercased() == "http", url.host?.lowercased() == "localhost",
            url.port == SlackOAuth.callbackPort, url.path == "/callback"
        else { return false }
        return true
    }

    static func navigationDecision(for url: URL?) -> SlackCapture.NavigationDecision {
        if isCallback(url) { return .allow }
        return SlackCapture.navigationDecision(for: url)
    }
}

// MARK: - La sesión

/// La sesión de Slack de esta conexión: un almacén **efímero** (nada llega al disco) que primero
/// usa la ventana de inicio de sesión y luego la de autorización, para que el usuario entre una
/// sola vez. Se descarta al terminar la conexión.
@MainActor
final class SlackWebSession {
    private var store: WKWebsiteDataStore?

    var dataStore: WKWebsiteDataStore {
        if let store { return store }
        let created = WKWebsiteDataStore.nonPersistent()
        store = created
        return created
    }

    func reset() { store = nil }
}

// MARK: - Modelo

@MainActor
final class SlackAuthorizeModel: NSObject, ObservableObject {
    enum Stage: Equatable {
        case loading
        /// La página de Slack espera que el usuario pulse «Permitir» (o inicie sesión).
        case userTurn
        case googleSignIn
        /// `claude` recibió el código.
        case done
        /// Slack dice «Invalid client_id parameter»: la app ya no existe (alguien la borró).
        case appNotFound
        case loadFailed(String)

        var isGalenoWorking: Bool { self == .loading }
    }

    @Published private(set) var stage: Stage = .loading
    @Published private(set) var host = ""

    let webView: WKWebView
    private let url: URL
    private let onFinished: () -> Void
    private let onAppNotFound: () -> Void
    private var finished = false
    /// Cuánto se deja ver el final antes de cerrar la ventana.
    var closeDelay: Duration = .milliseconds(900)

    init(
        url: URL, dataStore: WKWebsiteDataStore, onAppNotFound: @escaping () -> Void = {},
        onFinished: @escaping () -> Void
    ) {
        self.url = url
        self.onAppNotFound = onAppNotFound
        self.onFinished = onFinished
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        configuration.applicationNameForUserAgent = SlackCapture.safariApplicationName()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    func start() {
        host = url.host ?? ""
        webView.load(URLRequest(url: url))
    }

    func tearDown() {
        webView.stopLoading()
    }

    /// La página terminó de cargar: si es la vuelta a `localhost`, `claude` ya tiene el código.
    func pageFinished(_ url: URL?) {
        host = url?.host ?? ""
        trace("autorización: cargó \(url?.scheme ?? "?")://\(url?.host ?? "")\(url?.path == "/callback" ? "/callback" : "")")
        if SlackAuthorization.isCallback(url) {
            guard !finished else { return }
            finished = true
            stage = .done
            let delay = closeDelay
            Task { [weak self] in
                try? await Task.sleep(for: delay)
                self?.onFinished()
            }
        } else if !finished, stage != .googleSignIn, stage != .appNotFound {
            stage = .userTurn
            checkForMissingApp()
        }
    }

    /// Slack avisa «Invalid client_id parameter» cuando la app a la que apunta el registro ya no
    /// existe. Solo se pregunta si la página dice eso (un sí/no): no se lee ni se guarda su texto.
    private func checkForMissingApp() {
        guard SlackAuthorization.isSlackAuthorizationURL(webView.url) else { return }
        webView.evaluateJavaScript("/invalid client_id/i.test(document.body ? document.body.innerText : '')") {
            [weak self] result, _ in
            guard let self, (result as? Bool) == true, !self.finished, self.stage != .appNotFound else { return }
            self.stage = .appNotFound
            self.onAppNotFound()
        }
    }
}

extension SlackAuthorizeModel: WKNavigationDelegate, WKUIDelegate {
    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        let decision = SlackAuthorization.navigationDecision(for: navigationAction.request.url)
        trace("autorización: navegación \(navigationAction.request.url?.host ?? "?") → \(decision)")
        switch decision {
        case .allow:
            return .allow
        case .blockedGoogleSignIn:
            if navigationAction.targetFrame?.isMainFrame ?? true { stage = .googleSignIn }
            return .cancel
        case .slackDeepLink, .blocked:
            return .cancel
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageFinished(webView.url)
    }

    func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error
    ) {
        guard (error as NSError).code != NSURLErrorCancelled, !finished else { return }
        stage = .loadFailed(error.localizedDescription)
    }

    /// Los enlaces que piden ventana nueva se abren aquí mismo.
    func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if SlackAuthorization.navigationDecision(for: navigationAction.request.url) == .allow {
            webView.load(navigationAction.request)
        }
        return nil
    }
}

// MARK: - Vista

struct SlackAuthorizeView: View {
    @ObservedObject var model: SlackAuthorizeModel
    let onCancel: () -> Void
    @Environment(\.galenoReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
            SlackWebViewContainer(webView: model.webView)
                .opacity(model.stage.isGalenoWorking ? 0.6 : 1)
                .allowsHitTesting(!model.stage.isGalenoWorking)
                .animation(.easeOut(duration: 0.2), value: model.stage.isGalenoWorking)
        }
        .background(Color.parchment50)
        .onExitCommand(perform: onCancel)
    }

    private var header: some View {
        SlackWindowBar(
            host: model.host, step: model.stage == .done ? 2 : 1, total: 2, turn: turn, text: statusText,
            textKey: "\(model.stage)"
        ) {
            if model.stage != .done {
                Button("connect.slack.window.cancel", action: onCancel)
                    .buttonStyle(InkButtonStyle(.secondary, size: .bar, padding: 16))
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.stage)
    }

    private var turn: SlackTurn {
        switch model.stage {
        case .loading: .galeno
        case .userTurn: .user
        case .done: .done
        case .googleSignIn: .notice
        case .loadFailed, .appNotFound: .warning
        }
    }

    private var statusText: Text {
        switch model.stage {
        case .loading: Text("connect.slack.authorize.loading")
        case .userTurn: Text("connect.slack.authorize.userTurn")
        case .googleSignIn: Text("connect.slack.window.google")
        case .done: Text("connect.slack.authorize.done")
        case .appNotFound: Text("connect.slack.authorize.appNotFound")
        case .loadFailed(let detail): Text("connect.slack.window.loadFailed \(detail)")
        }
    }
}

// MARK: - La ventana

/// Quien muestra la autorización de Slack. Las pruebas lo reemplazan.
@MainActor
protocol SlackAuthorizationPresenting: AnyObject {
    func presentAuthorization(
        url: URL, dataStore: WKWebsiteDataStore, language: Language,
        onCancel: @escaping @MainActor () -> Void, onAppNotFound: @escaping @MainActor () -> Void)
    func dismissAuthorization()
}

@MainActor
final class SlackAuthorizeWindowPresenter: SlackAuthorizationPresenting {
    func presentAuthorization(
        url: URL, dataStore: WKWebsiteDataStore, language: Language,
        onCancel: @escaping @MainActor () -> Void, onAppNotFound: @escaping @MainActor () -> Void
    ) {
        SlackAuthorizeWindow.present(
            url: url, dataStore: dataStore, language: language, onCancel: onCancel, onAppNotFound: onAppNotFound)
    }

    func dismissAuthorization() { SlackAuthorizeWindow.dismiss() }
}

/// Abre la ventana, la cierra sola cuando `claude` recibe el código y limpia todo al cerrarse,
/// la cierre quien la cierre.
@MainActor
final class SlackAuthorizeWindow: NSObject, NSWindowDelegate {
    private static var current: SlackAuthorizeWindow?

    private let window: NSWindow
    private let model: SlackAuthorizeModel
    private var finishedNormally = false
    private let onCancel: @MainActor () -> Void

    static func present(
        url: URL, dataStore: WKWebsiteDataStore, language: Language,
        onCancel: @escaping @MainActor () -> Void, onAppNotFound: @escaping @MainActor () -> Void
    ) {
        current?.finishedNormally = true  // la reemplaza Galeno: no es una cancelación del usuario
        current?.window.close()
        current = SlackAuthorizeWindow(
            url: url, dataStore: dataStore, language: language, onCancel: onCancel, onAppNotFound: onAppNotFound)
    }

    static func dismiss() {
        current?.finishedNormally = true  // lo cerró Galeno, no el usuario
        current?.window.close()
    }

    private init(
        url: URL, dataStore: WKWebsiteDataStore, language: Language,
        onCancel: @escaping @MainActor () -> Void, onAppNotFound: @escaping @MainActor () -> Void
    ) {
        self.onCancel = onCancel
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 720),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        var finish: (() -> Void)?
        var missing: (() -> Void)?
        model = SlackAuthorizeModel(
            url: url, dataStore: dataStore, onAppNotFound: { missing?() }, onFinished: { finish?() })
        super.init()

        missing = { [weak self] in
            // Se cierra la ventana (no es una cancelación del usuario) y Galeno explica qué pasó.
            self?.finishedNormally = true
            self?.window.close()
            onAppNotFound()
        }
        finish = { [weak self] in
            self?.finishedNormally = true
            self?.window.close()
        }
        window.title = "Slack"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(
            rootView: SlackAuthorizeView(model: model, onCancel: { [weak self] in self?.window.close() })
                .motionPreference()
                .environment(\.locale, Locale(identifier: language.rawValue)))
        window.center()
        window.makeKeyAndOrderFront(nil)
        model.start()
    }

    func windowWillClose(_ notification: Notification) {
        model.tearDown()
        let wasCancelled = !finishedNormally
        if Self.current === self { Self.current = nil }
        if wasCancelled { onCancel() }
    }
}
