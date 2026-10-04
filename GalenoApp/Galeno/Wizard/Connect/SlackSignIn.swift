import AppKit
import Combine
import GalenoCore
import OSLog
import SwiftUI
import WebKit

#if DEBUG
/// Solo en Debug: por dónde navega la ventana (esquema, host y primer segmento de la ruta; **nunca**
/// el resto, la consulta ni el fragmento, que pueden llevar códigos de inicio de sesión). `log stream --predicate
/// 'category == "slackSignIn"'`.
private let signInLog = Logger(subsystem: "com.galeno.Galeno", category: "slackSignIn")
private func trace(_ message: String) { signInLog.notice("\(message, privacy: .public)") }
private func describe(_ url: URL?) -> String {
    guard let url else { return "nil" }
    // Solo el primer segmento: rutas como `/t/<equipo>/login/<código>` llevan un código de un solo uso.
    let first = url.pathComponents.dropFirst().first.map { "/" + $0 } ?? ""
    let more = url.pathComponents.count > 2 ? "/…" : ""
    return "\(url.scheme ?? "?")://\(url.host ?? "")\(first)\(more)"
}
#else
private func trace(_ message: @autoclosure () -> String) {}
private func describe(_ url: URL?) -> String { "" }
#endif

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
        /// Galeno pulsó «Generate Token» y espera el diálogo.
        case openingDialog
        /// Galeno está eligiendo, en el desplegable, el workspace en el que el usuario entró.
        case pickingWorkspace
        /// Galeno confirmó y Slack está generando el token.
        case generating
        case captured
        case loadFailed(String)

        /// En cuál de los 4 pasos de la barra está: iniciar sesión, elegir workspace, generar el
        /// token, listo.
        var step: Int {
            switch self {
            case .loading, .signIn, .googleSignIn, .loadFailed: 1
            case .chooseWorkspace, .pickingWorkspace: 2
            case .working, .openingDialog, .generating, .needsClick: 3
            case .captured: 4
            }
        }

        /// ¿Es el turno del usuario? Entonces la barra no avanza sola: espera.
        var isUserTurn: Bool {
            switch self {
            case .signIn, .googleSignIn, .chooseWorkspace, .needsClick: true
            default: false
            }
        }

        /// ¿Está Galeno haciendo algo ahora mismo? (Y no ha terminado ni falló.)
        var isGalenoWorking: Bool {
            switch self {
            case .loading, .working, .openingDialog, .pickingWorkspace, .generating: true
            default: false
            }
        }
    }

    @Published private(set) var stage: Stage = .loading {
        didSet { if stage.step > progress { progress = stage.step } }
    }
    /// El paso más lejano al que se llegó: la barra de progreso nunca retrocede, aunque la
    /// ventana vuelva a cargar una página.
    @Published private(set) var progress = 1
    static let totalSteps = 4
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
    private var returnsFromAppLink = 0
    private let freshOnly: Bool
    /// En qué workspace entró el usuario (por las direcciones por las que pasó la ventana).
    private(set) var workspaceHint = SlackCapture.WorkspaceHint()

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
        self.freshOnly = freshOnly

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

    /// Apunta en qué workspace entró el usuario, si la dirección lo dice, y se lo pasa al script
    /// para las páginas que se carguen a partir de ahora (el diálogo de generar el token).
    func learnWorkspace(from url: URL?) {
        guard let found = SlackCapture.workspaceHint(from: url) else { return }
        var updated = workspaceHint
        updated.merge(found)
        guard updated != workspaceHint else { return }
        workspaceHint = updated
        trace("workspace: id=\(updated.teamID ?? "-") slug=\(updated.slug ?? "-")")
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        controller.addUserScript(
            WKUserScript(
                source: SlackCapture.configScript(freshOnly: freshOnly, hint: updated),
                injectionTime: .atDocumentStart, forMainFrameOnly: true))
        controller.addUserScript(
            WKUserScript(
                source: SlackCapture.script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
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
            trace("página dice: \(state) en \(describe(webView.url)) \(message["kind"] ?? "") \(message["shape"] ?? "") \(message["html"] ?? "")")
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
            case "clickedGenerate":
                stage = .openingDialog
                if hintTask == nil { startHintTimer() }
            case "openingDropdown", "pickedWorkspace":
                stage = .pickingWorkspace
                if hintTask == nil { startHintTimer() }
            case "generating", "copying":
                stage = .generating
                if hintTask == nil { startHintTimer() }
            default:
                // Con sesión y en la página de tokens: Galeno trabaja; si tarda, se avisa.
                let inProgress: [Stage] = [.needsClick, .chooseWorkspace, .openingDialog, .pickingWorkspace, .generating]
                if !inProgress.contains(stage) { stage = .working }
                if hintTask == nil { startHintTimer() }
            }
        default:
            break
        }
    }

    /// Slack intentó abrir su app de escritorio (`slack://`): el usuario ya eligió su workspace.
    /// No se abre nada; se vuelve a la página de tokens (unas pocas veces, por si no hay sesión
    /// de verdad y Slack insiste).
    private func appLinkBlocked() {
        guard !captured, returnsFromAppLink < 3 else { return }
        returnsFromAppLink += 1
        hintTask?.cancel()
        hintTask = nil
        stage = .loading
        goToTokensPage()
    }

    private func locationChanged(_ url: URL?) {
        guard !captured else { return }
        host = url?.host ?? ""
        trace("ubicación \(describe(url)) → \(SlackSignInLocation.classify(url))")
        switch SlackSignInLocation.classify(url) {
        case .tokensPage:
            // Todavía no se sabe si hay sesión: lo dice el script en cuanto mira la página.
            let keep: [Stage] = [.working, .openingDialog, .pickingWorkspace, .generating, .chooseWorkspace, .needsClick]
            if !keep.contains(stage) { stage = .loading }
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
        trace("cookie de sesión apareció; en \(describe(webView.url))")
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
            if self.stage.isGalenoWorking, self.stage != .loading { self.stage = .needsClick }
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
        let decision = SlackCapture.navigationDecision(for: navigationAction.request.url)
        // Slack lanza el enlace `slack://` desde un marco oculto: ese sí se mira aunque no sea el
        // principal. Las demás direcciones, solo las de la página principal.
        if decision == .slackDeepLink || (navigationAction.targetFrame?.isMainFrame ?? true) {
            learnWorkspace(from: navigationAction.request.url)
        }
        trace("navegación \(describe(navigationAction.request.url)) → \(decision)")
        switch decision {
        case .allow:
            return .allow
        case .blockedGoogleSignIn:
            // Solo cuenta la página principal: un recurso de Google incrustado no es un login.
            if navigationAction.targetFrame?.isMainFrame ?? true { stage = .googleSignIn }
            return .cancel
        case .slackDeepLink:
            appLinkBlocked()
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
        let decision = SlackCapture.navigationDecision(for: navigationAction.request.url)
        learnWorkspace(from: navigationAction.request.url)
        trace("ventana nueva \(describe(navigationAction.request.url)) → \(decision)")
        switch decision {
        case .allow: webView.load(navigationAction.request)
        case .blockedGoogleSignIn: stage = .googleSignIn
        case .slackDeepLink: appLinkBlocked()
        case .blocked: break
        }
        return nil
    }

    func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error
    ) {
        // -999 es una navegación cancelada (por otra más nueva o por la política de arriba).
        trace("falló la carga: \((error as NSError).domain) \((error as NSError).code)")
        guard (error as NSError).code != NSURLErrorCancelled, !captured else { return }
        stage = .loadFailed(error.localizedDescription)
    }
}

// MARK: - La vista

struct SlackSignInView: View {
    @ObservedObject var model: SlackSignInModel
    let onCancel: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            SlackWebViewContainer(webView: model.webView)
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
                activityMark
                statusText
                    .font(.galenoBody)
                    .foregroundStyle(isWarning ? Color.seal700 : Color.ink900)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                Spacer(minLength: Space.s8)
                Text("connect.slack.window.step \(min(model.progress, SlackSignInModel.totalSteps)) \(SlackSignInModel.totalSteps)")
                    .font(.galenoCaption.smallCaps())
                    .kerning(1)
                    .foregroundStyle(Color.ink500)
                    .fixedSize()
            }
            .animation(.easeOut(duration: 0.2), value: model.stage)
            SignInProgressTrack(
                step: model.progress, total: SlackSignInModel.totalSteps,
                isGalenoWorking: model.stage.isGalenoWorking, isUserTurn: model.stage.isUserTurn)
        }
        .padding(.horizontal, Space.s16)
        .padding(.vertical, Space.s12)
    }

    /// A la izquierda del texto: un indicador de quién tiene el turno. Mientras Galeno trabaja, una
    /// rueda; cuando es el turno del usuario, una mano que late; al terminar, una marca.
    @ViewBuilder
    private var activityMark: some View {
        if model.stage.isGalenoWorking {
            ProgressView().controlSize(.small)
        } else if model.stage == .captured {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.moss700)
        } else if model.stage.isUserTurn {
            Image(systemName: "hand.point.up.left.fill")
                .foregroundStyle(isWarning ? Color.seal700 : Color.ink900)
                .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
        } else {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.seal700)
        }
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
        case .openingDialog: Text("connect.slack.window.openingDialog")
        case .pickingWorkspace: Text("connect.slack.window.pickingWorkspace")
        case .generating: Text("connect.slack.window.generating")
        case .chooseWorkspace: Text("connect.slack.window.chooseWorkspace")
        case .needsClick: Text("connect.slack.window.needsClick")
        case .captured: Text("connect.slack.window.captured")
        case .loadFailed(let detail): Text("connect.slack.window.loadFailed \(detail)")
        }
    }
}

/// Los 4 pasos de la ventana como una barra: los hechos en tinta, el actual con movimiento si lo
/// hace Galeno (un destello que corre) o latiendo si espera al usuario, y los que faltan en gris.
/// Con «reducir movimiento» no se anima nada: el actual queda fijo.
struct SignInProgressTrack: View {
    let step: Int
    let total: Int
    let isGalenoWorking: Bool
    let isUserTurn: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Space.s4) {
            ForEach(1...total, id: \.self) { index in
                segment(index)
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }

    private func segment(_ index: Int) -> some View {
        let isCurrent = index == step
        return Capsule()
            .fill(index < step ? Color.ink900 : (isCurrent ? Color.ink700.opacity(0.35) : Color.parchment300))
            .overlay {
                if isCurrent && !reduceMotion {
                    if isGalenoWorking { shimmer } else if isUserTurn { pulse }
                } else if isCurrent {
                    Capsule().fill(Color.ink700)
                }
            }
            .clipShape(Capsule())
    }

    /// Un destello de tinta que cruza el tramo de izquierda a derecha.
    private var shimmer: some View {
        TimelineView(.animation) { context in
            GeometryReader { proxy in
                let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.3) / 1.3
                Capsule()
                    .fill(LinearGradient(colors: [.clear, Color.ink900, .clear], startPoint: .leading, endPoint: .trailing))
                    .frame(width: proxy.size.width * 0.6)
                    .offset(x: proxy.size.width * 1.6 * phase - proxy.size.width * 0.6)
            }
        }
    }

    /// Late despacio: es el turno del usuario y la barra espera.
    private var pulse: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Capsule().fill(Color.ink700).opacity(0.35 + 0.65 * (0.5 + 0.5 * sin(t * 3)))
        }
    }
}

struct SlackWebViewContainer: NSViewRepresentable {
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
        freshOnly: Bool, language: Language, dataStore: WKWebsiteDataStore = .nonPersistent(),
        onToken: @escaping @MainActor (OAuthSecret) -> Void
    ) {
        current?.close()
        current = SlackSignInWindow(
            freshOnly: freshOnly, language: language, dataStore: dataStore, onToken: onToken)
    }

    private init(
        freshOnly: Bool, language: Language, dataStore: WKWebsiteDataStore,
        onToken: @escaping @MainActor (OAuthSecret) -> Void
    ) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 720),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        var deliver: ((OAuthSecret) -> Void)?
        model = SlackSignInModel(freshOnly: freshOnly, dataStore: dataStore) { secret in deliver?(secret) }
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
