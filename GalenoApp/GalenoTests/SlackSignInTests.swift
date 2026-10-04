import AppKit
import WebKit
import XCTest

@testable import Galeno

/// Un token falso evidente, con la forma de uno de verdad (más de 40 caracteres tras el prefijo).
private func fakeToken(_ tag: String = "A") -> String {
    "xoxe.xoxp-1-TOKEN_FALSO_DE_PRUEBA_\(tag)_" + String(repeating: "x", count: 48)
}

// MARK: - Sin navegador: el patrón, las páginas y de quién se aceptan mensajes

final class SlackTokenPatternTests: XCTestCase {
    func testFindsAConfigurationTokenInsideOtherText() {
        let token = fakeToken()

        XCTAssertEqual(SlackTokenPattern.bestToken(in: "{\"token\":\"\(token)\",\"ok\":true}"), token)
        XCTAssertEqual(SlackTokenPattern.bestToken(in: "<input value=\"\(token)\">"), token)
    }

    /// Lo que Slack muestra recortado en pantalla no es un token.
    func testATruncatedTokenIsNotAToken() {
        XCTAssertNil(SlackTokenPattern.bestToken(in: "xoxe.xoxp-1-Mi0y…"))
        XCTAssertNil(SlackTokenPattern.bestToken(in: "xoxe.xoxp-1-corto"))
    }

    func testOtherSlackTokensAreNotConfigurationAccessTokens() {
        let tail = String(repeating: "x", count: 60)

        XCTAssertNil(SlackTokenPattern.bestToken(in: "xoxe-1-\(tail)"), "el refresh token")
        XCTAssertNil(SlackTokenPattern.bestToken(in: "xoxb-\(tail)"))
        XCTAssertNil(SlackTokenPattern.bestToken(in: "xoxp-\(tail)"))
        XCTAssertNil(SlackTokenPattern.bestToken(in: ""))
    }

    func testPicksTheLongestWhenThereAreSeveral() {
        let short = fakeToken("A")
        let long = fakeToken("B") + "_mas_largo"

        XCTAssertEqual(SlackTokenPattern.bestToken(in: "\(short) y \(long)"), long)
    }

    func testClassifiesWhereTheWindowIs() {
        func at(_ string: String) -> SlackSignInLocation { .classify(URL(string: string)) }

        XCTAssertEqual(at("https://api.slack.com/apps"), .tokensPage)
        XCTAssertEqual(at("https://api.slack.com/apps?new_app=1"), .tokensPage)
        XCTAssertEqual(at("https://api.slack.com/docs"), .slack)
        XCTAssertEqual(at("https://slack.com/signin"), .slack)
        XCTAssertEqual(at("https://eternals.slack.com/"), .slack)
        XCTAssertEqual(at("https://app.slack.com/client/T123"), .slackClient)
        // El paso intermedio que completa el inicio de sesión no es «ya entró»: no se interrumpe.
        XCTAssertEqual(at("https://app.slack.com/t/equipo/login/z-app-1-2-abc"), .slack)
        XCTAssertEqual(at("https://accounts.google.com/o/oauth2/auth"), .google)
        XCTAssertEqual(at("https://empresa.okta.com/login"), .other)
        XCTAssertEqual(SlackSignInLocation.classify(nil), .other)
    }

    /// Un dominio que solo *parece* de Slack no es Slack.
    func testLookalikeDomainsAreNotSlack() {
        func at(_ string: String) -> SlackSignInLocation { .classify(URL(string: string)) }

        XCTAssertEqual(at("https://api.slack.com.evil.example/apps"), .other)
        XCTAssertEqual(at("https://notslack.com/apps"), .other)
        XCTAssertEqual(at("https://api-slack.com/apps"), .other)
    }

    func testOnlyTheMainFrameOfTheTokensSiteIsTrusted() {
        XCTAssertTrue(SlackCapture.isTrustedSource(host: "api.slack.com", isMainFrame: true))
        XCTAssertTrue(SlackCapture.isTrustedSource(host: "API.slack.com", isMainFrame: true))
        XCTAssertFalse(SlackCapture.isTrustedSource(host: "api.slack.com", isMainFrame: false), "un marco incrustado")
        XCTAssertFalse(SlackCapture.isTrustedSource(host: "slack.com", isMainFrame: true))
        XCTAssertFalse(SlackCapture.isTrustedSource(host: "api.slack.com.evil.example", isMainFrame: true))
        XCTAssertFalse(SlackCapture.isTrustedSource(host: "", isMainFrame: true))
    }

    func testTheWindowOnlyNavigatesOverHTTPS() {
        XCTAssertTrue(SlackCapture.allowsNavigation(to: URL(string: "https://slack.com/signin")))
        XCTAssertTrue(SlackCapture.allowsNavigation(to: URL(string: "about:blank")))
        for blocked in ["http://slack.com", "file:///etc/passwd", "slack://open", "javascript:alert(1)", "data:text/html,x"] {
            XCTAssertFalse(SlackCapture.allowsNavigation(to: URL(string: blocked)), blocked)
        }
        XCTAssertFalse(SlackCapture.allowsNavigation(to: nil))
    }

    /// Google no permite iniciar sesión en ventanas embebidas. Galeno no lo esquiva: no lo abre.
    func testGoogleSignInIsNeverOpenedInsideTheWindow() {
        for url in ["https://accounts.google.com/o/oauth2/v2/auth?client_id=x", "https://accounts.google.com/signin"] {
            XCTAssertEqual(SlackCapture.navigationDecision(for: URL(string: url)), .blockedGoogleSignIn, url)
        }
        // El resto del inicio de sesión sí: Slack, y el proveedor de la empresa.
        for url in ["https://slack.com/signin", "https://empresa.okta.com/login", "https://appleid.apple.com/auth"] {
            XCTAssertEqual(SlackCapture.navigationDecision(for: URL(string: url)), .allow, url)
        }
        XCTAssertEqual(SlackCapture.navigationDecision(for: URL(string: "http://slack.com")), .blocked)
    }

    /// Al elegir un workspace, Slack intenta abrir su app de escritorio (`slack://`). Nunca se abre
    /// (sigue sin poder navegar la ventana), pero se reconoce: es la señal de que ya entró.
    func testSlackDesktopAppLinksAreNeverFollowedButAreRecognized() {
        for url in ["slack://open?team=T123", "slack://channel?team=T1&id=C1", "SLACK://open"] {
            XCTAssertEqual(SlackCapture.navigationDecision(for: URL(string: url)), .slackDeepLink, url)
            XCTAssertFalse(SlackCapture.allowsNavigation(to: URL(string: url)), url)
        }
        XCTAssertEqual(SlackCapture.navigationDecision(for: URL(string: "file:///etc/passwd")), .blocked)
    }

    /// Slack rechaza un WebKit que no dice ser Safari («your browser is not supported»): la
    /// ventana declara la versión del Safari del sistema, como hace Safari.
    func testTheWindowIdentifiesItselfAsTheSystemSafari() {
        XCTAssertEqual(SlackCapture.safariApplicationName(safariVersion: "18.5"), "Version/18.5 Safari/605.1.15")
        XCTAssertEqual(SlackCapture.safariApplicationName(safariVersion: "26.0.1"), "Version/26.0.1 Safari/605.1.15")
        XCTAssertEqual(SlackCapture.safariApplicationName(safariVersion: nil), "Version/17.6 Safari/605.1.15")
        // Un valor raro no se cuela en el identificador.
        XCTAssertEqual(SlackCapture.safariApplicationName(safariVersion: "18.5 (evil)\r\nX: y"), "Version/17.6 Safari/605.1.15")
    }

    /// El script no hace nada fuera de `api.slack.com`: es la primera comprobación que hace.
    func testTheScriptBailsOutOnAnyOtherSite() {
        let script = SlackCapture.script
        let guardLine = "if (location.hostname !== 'api.slack.com') return;"
        let guardAt = script.range(of: guardLine)
        XCTAssertNotNil(guardAt)
        for hook in ["navigator.clipboard", "window.fetch", "XMLHttpRequest", "addEventListener", "querySelectorAll"] {
            let hookAt = script.range(of: hook)
            XCTAssertNotNil(hookAt, hook)
            XCTAssertTrue(guardAt!.lowerBound < hookAt!.lowerBound, "\(hook) va después de la comprobación del sitio")
        }
        XCTAssertTrue(script.contains("input:not([type=password])"), "nunca se leen campos de contraseña")
    }
}

// MARK: - Con un navegador de verdad y réplicas de la página

/// Cómo "entrega" el token la página de mentira.
private enum Reveal {
    case field          // en el valor de un campo de solo lectura
    case attribute      // en un atributo data-clipboard-text
    case copyButton     // solo al pulsar «Copy» (API moderna del portapapeles)
    case legacyCopy     // solo al pulsar «Copy» (execCommand sobre un textarea temporal)
    case xhr            // solo en la respuesta de la petición que lo genera
    case truncated      // nunca entero: solo recortado en pantalla
}

private func replica(
    workspaces: [String] = ["Acme Test"], reveal: Reveal = .field, token: String = fakeToken(),
    existing: String? = nil, hasGenerateButton: Bool = true
) -> String {
    // «valor|nombre» da a la opción un valor distinto del nombre, como el identificador del equipo.
    let options = workspaces.map { entry -> String in
        let pair = entry.split(separator: "|", maxSplits: 1).map(String.init)
        return pair.count == 2 ? "<option value=\"\(pair[0])\">\(pair[1])</option>" : "<option>\(entry)</option>"
    }.joined()
    // El token no va escrito tal cual en la página (se capturaría del propio código, antes de
    // "generarlo"): la página lo arma al vuelo, como una de verdad que lo recibe del servidor.
    let pieces = token.split(separator: ".", maxSplits: 1).map(String.init)
    let existingRow = existing.map { "<p>Token anterior: <input readonly value=\"\($0)\"></p>" } ?? ""
    let button = hasGenerateButton ? "<button id=\"gen\">Generate Token</button>" : ""
    return """
        <!doctype html><html><head><meta charset="utf-8"><title>Slack API: Applications</title></head><body>
        <h1>Your Apps</h1>
        <h2>Your App Configuration Tokens</h2>
        \(existingRow)
        \(button)
        <div id="row" hidden>
          <span>Access Token</span> <code>xoxe.xoxp-1-Mi0y…</code> <span id="slot"></span>
          <button id="copyAccess">Copy</button>
          <span>Refresh Token</span> <code>xoxe-1-My0x…</code> <button id="copyRefresh">Copy</button>
        </div>
        <dialog id="dlg"><p>Which workspace?</p>
          <select id="ws"><option value="">Select a workspace</option>\(options)</select>
          <button id="cancel">Cancel</button> <button id="go">Generate</button>
        </dialog>
        <script>
          var TOKEN = ["\(pieces[0])", "\(pieces[1])"].join("."), MODE = "\(reveal)";
          var gen = document.getElementById('gen'), dlg = document.getElementById('dlg'), ws = document.getElementById('ws');
          window.systemClipboardWrites = [];
          if (gen) gen.onclick = function () { dlg.showModal(); };
          document.getElementById('go').onclick = function () {
            if (!ws.value) return;
            dlg.close();
            document.getElementById('row').hidden = false;
            var slot = document.getElementById('slot');
            if (MODE === 'field') slot.innerHTML = '<input readonly value="' + TOKEN + '">';
            if (MODE === 'attribute') document.getElementById('copyAccess').setAttribute('data-clipboard-text', TOKEN);
            if (MODE === 'xhr') {
              var request = new XMLHttpRequest();
              request.open('GET', 'data:application/json,' + encodeURIComponent(JSON.stringify({ ok: true, token: TOKEN })));
              request.send();
            }
          };
          document.getElementById('copyAccess').onclick = function () {
            if (MODE === 'copyButton') navigator.clipboard.writeText(TOKEN);
            if (MODE === 'legacyCopy') {
              var area = document.createElement('textarea');
              area.value = TOKEN; document.body.appendChild(area); area.select();
              document.execCommand('copy'); document.body.removeChild(area);
            }
          };
          document.getElementById('copyRefresh').onclick = function () {
            navigator.clipboard.writeText('xoxe-1-REFRESH_FALSO_' + 'y'.repeat(50));
          };
        </script></body></html>
        """
}

/// El diálogo de verdad de Slack: no es un `<select>` sino un desplegable propio (un `div` con rol
/// `combobox` que, al pulsarlo, muestra una lista de opciones), como el de la pantalla real.
private func dropdownReplica(workspaces: [(id: String, name: String)], token: String = fakeToken()) -> String {
    let pieces = token.split(separator: ".", maxSplits: 1).map(String.init)
    let items = workspaces.map {
        "<li role=\"option\" data-team-id=\"\($0.id)\" tabindex=\"-1\">\($0.name)</li>"
    }.joined()
    return """
        <!doctype html><html><head><meta charset="utf-8"><title>Slack API: Applications</title></head><body>
        <h1>Your Apps</h1><h2>Your App Configuration Tokens</h2>
        <button id="gen">Generate Token</button>
        <div id="row" hidden><span id="slot"></span> <button id="copyAccess">Copy</button></div>
        <dialog id="dlg"><h3>Generate Your App Configuration Token</h3><p>Workspace</p>
          <div id="combo" role="combobox" aria-expanded="false" tabindex="0">Select a workspace</div>
          <ul id="list" role="listbox" hidden>\(items)</ul>
          <button id="close">Close</button> <button id="go" disabled>Generate</button>
        </dialog>
        <script>
          var TOKEN = ["\(pieces[0])", "\(pieces[1])"].join(".");
          var dlg = document.getElementById('dlg'), combo = document.getElementById('combo'),
              list = document.getElementById('list'), go = document.getElementById('go');
          document.getElementById('gen').onclick = function () { dlg.showModal(); };
          // Solo reacciona a la secuencia completa de un clic de verdad (mousedown y luego click).
          var downSeen = false;
          combo.onmousedown = function () { downSeen = true; };
          combo.onclick = function () { if (!downSeen) return; list.hidden = !list.hidden; };
          Array.prototype.forEach.call(list.children, function (li) {
            li.onclick = function () {
              combo.textContent = li.textContent; list.hidden = true; go.disabled = false;
              window.chosenTeam = li.getAttribute('data-team-id');
            };
          });
          go.onclick = function () {
            dlg.close();
            document.getElementById('row').hidden = false;
            document.getElementById('slot').innerHTML = '<input readonly value="' + TOKEN + '">';
          };
        </script></body></html>
        """
}

@MainActor
final class SlackSignInWebViewTests: XCTestCase {
    private var captured: [OAuthSecret] = []
    private var models: [SlackSignInModel] = []
    /// A dónde quiso navegar la ventana. Las pruebas no salen a la red.
    private var navigations: [URL] = []

    override func tearDown() async throws {
        for model in models { model.tearDown() }
        models = []
        captured = []
        navigations = []
    }

    private func makeModel(freshOnly: Bool = false) -> SlackSignInModel {
        let model = SlackSignInModel(freshOnly: freshOnly) { [unowned self] secret in captured.append(secret) }
        model.webView.frame = NSRect(x: 0, y: 0, width: 960, height: 720)
        model.navigate = { [unowned self] url in navigations.append(url) }
        models.append(model)
        return model
    }

    private func load(_ html: String, into model: SlackSignInModel, at url: String = "https://api.slack.com/apps") {
        model.webView.loadHTMLString(html, baseURL: URL(string: url)!)
    }

    private var capturedValue: String? { captured.first?.withValue { $0 } }

    private func waitForCapture(timeout: TimeInterval = 15) async -> Bool {
        await waitUntil(timeout: timeout) { !self.captured.isEmpty }
    }

    // MARK: Las vías de captura

    func testClicksGenerateChoosesTheOnlyWorkspaceAndCapturesTheToken() async {
        let model = makeModel()
        load(replica(reveal: .field), into: model)

        let done = await waitForCapture()

        XCTAssertTrue(done, "etapa: \(model.stage)")
        XCTAssertEqual(capturedValue, fakeToken())
        XCTAssertEqual(model.stage, .captured)
        XCTAssertEqual(model.host, "api.slack.com")
    }

    func testCapturesATokenThatOnlyLivesInAnAttribute() async {
        let model = makeModel()
        load(replica(reveal: .attribute), into: model)

        let done = await waitForCapture()

        XCTAssertTrue(done, "etapa: \(model.stage)")
        XCTAssertEqual(capturedValue, fakeToken())
    }

    /// Si la página solo entrega el token al pulsar «Copy», se pulsa y se intercepta: el token
    /// llega a Galeno y **no** al portapapeles del sistema.
    func testCapturesViaTheCopyButtonWithoutTouchingTheSystemClipboard() async {
        let model = makeModel()
        let clipboardBefore = NSPasteboard.general.changeCount
        load(replica(reveal: .copyButton), into: model)

        let done = await waitForCapture()

        XCTAssertTrue(done, "etapa: \(model.stage)")
        XCTAssertEqual(capturedValue, fakeToken())
        XCTAssertEqual(NSPasteboard.general.changeCount, clipboardBefore, "el portapapeles del sistema no cambió")
    }

    func testCapturesViaTheOldStyleCopyToo() async {
        let model = makeModel()
        let clipboardBefore = NSPasteboard.general.changeCount
        load(replica(reveal: .legacyCopy), into: model)

        let done = await waitForCapture()

        XCTAssertTrue(done, "etapa: \(model.stage)")
        XCTAssertEqual(capturedValue, fakeToken())
        XCTAssertEqual(NSPasteboard.general.changeCount, clipboardBefore)
    }

    func testCapturesTheTokenFromTheResponseThatGeneratesIt() async {
        let model = makeModel()
        load(replica(reveal: .xhr), into: model)

        let done = await waitForCapture()

        XCTAssertTrue(done, "etapa: \(model.stage)")
        XCTAssertEqual(capturedValue, fakeToken())
    }

    /// El refresh token también se intercepta al copiarlo, pero no se entrega como token.
    func testTheRefreshTokenIsNeverDeliveredNorCopied() async throws {
        let model = makeModel()
        let clipboardBefore = NSPasteboard.general.changeCount
        load(replica(reveal: .truncated), into: model)
        _ = await waitUntil(timeout: 10) { model.stage == .working || model.stage == .needsClick }
        // Se da tiempo a que el script pulse los dos botones «Copy».
        try await Task.sleep(for: .seconds(3))

        XCTAssertTrue(captured.isEmpty)
        XCTAssertEqual(NSPasteboard.general.changeCount, clipboardBefore, "el refresh token no llegó al portapapeles")
    }

    // MARK: Cuando el usuario tiene que intervenir

    func testWithSeveralWorkspacesItAsksTheUserAndCapturesAfterTheyChoose() async throws {
        let model = makeModel()
        load(replica(workspaces: ["Acme Test", "Otro Workspace"], reveal: .field), into: model)

        let asked = await waitUntil(timeout: 15) { model.stage == .chooseWorkspace }
        XCTAssertTrue(asked, "etapa: \(model.stage)")
        XCTAssertTrue(captured.isEmpty, "no se elige un workspace por el usuario")

        // El usuario elige en la propia página; Galeno confirma y recoge el resultado.
        _ = try await model.webView.evaluateJavaScript(
            "var s = document.getElementById('ws'); s.value = 'Otro Workspace'; s.dispatchEvent(new Event('change')); true")

        let done = await waitForCapture()
        XCTAssertTrue(done, "etapa: \(model.stage)")
        XCTAssertEqual(capturedValue, fakeToken())
    }

    // MARK: El workspace en el que el usuario ya entró no se vuelve a preguntar

    func testTheWorkspaceTheUserSignedIntoIsChosenByItsTeamID() async {
        let model = makeModel()
        model.learnWorkspace(from: URL(string: "slack://T0FAKETEAM1/magic-login/codigo-de-un-solo-uso"))
        load(replica(workspaces: ["T111AAAA|Acme Test", "T0FAKETEAM1|Acme Workspace", "T222BBBB|Otro"], reveal: .field), into: model)

        let done = await waitForCapture()

        XCTAssertTrue(done, "etapa: \(model.stage)")
        XCTAssertNotEqual(model.stage, .chooseWorkspace)
    }

    func testTheWorkspaceTheUserSignedIntoIsChosenByItsName() async {
        let model = makeModel()
        model.learnWorkspace(from: URL(string: "https://app.slack.com/t/acme-workspace/login/z-app-1-2-abc"))
        load(replica(workspaces: ["Acme Test", "Acme Workspace", "Otro"], reveal: .field), into: model)

        let done = await waitForCapture()

        XCTAssertTrue(done, "etapa: \(model.stage)")
    }

    /// Si lo que sabemos no coincide con ninguna opción, elige el usuario: no se adivina un workspace.
    func testWithNoMatchItStillAsksTheUser() async {
        let model = makeModel()
        model.learnWorkspace(from: URL(string: "slack://T999ZZZZ9/magic-login/x"))
        load(replica(workspaces: ["T111AAAA|Acme Test", "T222BBBB|Otro"], reveal: .field), into: model)

        let asked = await waitUntil(timeout: 15) { model.stage == .chooseWorkspace }

        XCTAssertTrue(asked, "etapa: \(model.stage)")
        XCTAssertTrue(captured.isEmpty)
    }

    /// El desplegable propio de Slack: Galeno lo abre, elige el workspace en el que el usuario entró
    /// (por el identificador que lleva la opción) y sigue solo.
    func testItOpensSlacksCustomDropdownAndPicksTheWorkspaceTheUserSignedInto() async throws {
        let model = makeModel()
        model.learnWorkspace(from: URL(string: "slack://T0FAKETEAM1/magic-login/x"))
        load(
            dropdownReplica(workspaces: [("T111AAAA", "Acme Test"), ("T0FAKETEAM1", "Acme Co"), ("T222BBBB", "Otro")]),
            into: model)

        let done = await waitForCapture()

        XCTAssertTrue(done, "etapa: \(model.stage)")
        let chosen = try await model.webView.evaluateJavaScript("window.chosenTeam") as? String
        XCTAssertEqual(chosen, "T0FAKETEAM1", "eligió el workspace correcto, no el primero")
    }

    func testTheCustomDropdownStillAsksTheUserWhenNothingMatches() async throws {
        let model = makeModel()
        model.learnWorkspace(from: URL(string: "slack://T999ZZZZ9/magic-login/x"))
        load(dropdownReplica(workspaces: [("T111AAAA", "Acme Test"), ("T222BBBB", "Otro")]), into: model)

        let asked = await waitUntil(timeout: 15) { model.stage == .chooseWorkspace }

        XCTAssertTrue(asked, "etapa: \(model.stage)")
        XCTAssertTrue(captured.isEmpty, "no se adivina un workspace")
        let chosen = try await model.webView.evaluateJavaScript("window.chosenTeam") as? String
        XCTAssertNil(chosen)
    }

    func testWorkspaceHintsComeOnlyFromRecognisedAddresses() {
        let hint = { (url: String) in SlackCapture.workspaceHint(from: URL(string: url)) }
        XCTAssertEqual(hint("slack://T0FAKETEAM1/magic-login/x"), .init(teamID: "T0FAKETEAM1", slug: nil))
        XCTAssertEqual(hint("https://app.slack.com/t/acme-workspace/login/z-app-1"), .init(teamID: nil, slug: "acme-workspace"))
        XCTAssertEqual(hint("https://app.slack.com/client/T0FAKETEAM1/C1"), .init(teamID: "T0FAKETEAM1", slug: nil))
        XCTAssertEqual(hint("https://acme-workspace.slack.com/ssb/redirect"), .init(teamID: nil, slug: "acme-workspace"))
        // Páginas de Slack que no son un workspace, esquemas ajenos y valores raros: nada.
        XCTAssertNil(hint("https://api.slack.com/apps"))
        XCTAssertNil(hint("https://slack.com/signin"))
        XCTAssertNil(hint("https://edgeapi.slack.com/x"))
        XCTAssertNil(hint("https://evil.example.com/t/acme-workspace/login"))
        XCTAssertNil(hint("slack://open"))
        XCTAssertNil(hint("https://app.slack.com/t/Acme'Workspace/login"))
    }

    func testTheHintReachesTheScriptWithoutBeingAbleToBreakIt() {
        let script = SlackCapture.configScript(
            freshOnly: true, hint: .init(teamID: "T0FAKETEAM1", slug: "acme-workspace"))
        XCTAssertEqual(
            script, "window.__galenoConfig = { freshOnly: true, teamID: 'T0FAKETEAM1', slug: 'acme-workspace' };")
        XCTAssertEqual(
            SlackCapture.configScript(freshOnly: false), "window.__galenoConfig = { freshOnly: false };")
    }

    /// Si la página nunca muestra el token entero, no se captura nada y se le pide al usuario que
    /// intervenga; el token recortado de la pantalla no se toma por bueno.
    func testATokenThatIsOnlyShownTruncatedIsNeverCaptured() async {
        let model = makeModel()
        model.hintDelay = .milliseconds(1500)
        load(replica(reveal: .truncated), into: model)

        let hinted = await waitUntil(timeout: 15) { model.stage == .needsClick }

        XCTAssertTrue(hinted, "etapa: \(model.stage)")
        XCTAssertTrue(captured.isEmpty)
    }

    /// Los clics automáticos pueden fallar si Slack cambia la pantalla. La captura no depende de
    /// ellos: si el token aparece porque el usuario hizo los clics, se recoge igual.
    func testCapturesEvenWhenTheButtonsAreNotTheOnesItKnows() async throws {
        let model = makeModel()
        let html = """
            <!doctype html><html><body><h1>Your Apps</h1>
            <div id="nuevo-diseno"><span onclick="mostrar()">Crear credencial</span><div id="out"></div></div>
            <script>function mostrar(){ document.getElementById('out').textContent = ["xoxe", "\(fakeToken("Z").dropFirst(5))"].join("."); }</script>
            </body></html>
            """
        load(html, into: model)
        _ = await waitUntil(timeout: 10) { model.stage == .working }
        try await Task.sleep(for: .seconds(1))
        XCTAssertTrue(captured.isEmpty, "todavía no hay token")

        _ = try await model.webView.evaluateJavaScript("mostrar(); true")  // el usuario hace el clic

        let done = await waitForCapture()
        XCTAssertTrue(done)
        XCTAssertEqual(capturedValue, fakeToken("Z"))
    }

    // MARK: Como es la página de verdad (comprobado contra api.slack.com sin sesión)

    /// El aviso de cookies de Slack también es un "diálogo". No es el de elegir workspace.
    private let cookieBanner = """
        <div role="dialog" aria-label="Cookie banner">
          <p>This website uses cookies to enhance user experience.</p>
          <button>COOKIES SETTINGS</button> <button onclick="window.cookiesAccepted = true">ACCEPT ALL COOKIES</button>
        </div>
        """

    /// Sin sesión, `api.slack.com/apps` no redirige: muestra un enlace para iniciar sesión.
    func testOnTheSignedOutPageItOpensSlackSignInOnce() async throws {
        let model = makeModel()
        let html = """
            <!doctype html><html><body><h1>Your Apps</h1>
            <p>You'll need to <a href="https://slack.com/signin">sign in to your Slack account</a> to create an application.</p>
            <p>Don't see an app you're looking for? <a href="https://slack.com/signin" target="_blank">Sign in to another workspace</a>.</p>
            \(cookieBanner)
            </body></html>
            """
        load(html, into: model)

        let signedOut = await waitUntil(timeout: 10) { model.stage == .signIn }
        try await Task.sleep(for: .seconds(1.5))  // varias pasadas del script

        XCTAssertTrue(signedOut, "etapa: \(model.stage)")
        XCTAssertEqual(navigations, [SlackCapture.signInURL], "se abre el inicio de sesión, y una sola vez")
        XCTAssertTrue(captured.isEmpty)
    }

    func testTheCookieBannerIsNotMistakenForTheWorkspaceDialog() async throws {
        let model = makeModel()
        let page = replica(reveal: .field).replacingOccurrences(of: "<h1>Your Apps</h1>", with: "<h1>Your Apps</h1>\(cookieBanner)")
        XCTAssertTrue(page.contains("Cookie banner"))
        load(page, into: model)

        let done = await waitForCapture()

        XCTAssertTrue(done, "etapa: \(model.stage)")
        XCTAssertEqual(capturedValue, fakeToken())
        let accepted = try await model.webView.evaluateJavaScript("window.cookiesAccepted === true") as? Bool
        XCTAssertEqual(accepted, false, "Galeno no acepta cookies por el usuario")
    }

    /// Tras iniciar sesión, Slack deja al usuario en su página de workspaces. Cuando aparece la
    /// cookie de sesión se le lleva de vuelta a la de tokens, una sola vez.
    func testWhenTheSessionAppearsItReturnsToTheTokensPageOnce() async throws {
        let model = makeModel()
        load("<html><body>Welcome back! Choose a workspace</body></html>", into: model, at: "https://slack.com/signin")
        _ = await waitUntil(timeout: 10) { model.stage == .signIn }
        XCTAssertTrue(navigations.isEmpty)

        let session = try XCTUnwrap(HTTPCookie(properties: [
            .domain: ".slack.com", .path: "/", .name: "d", .value: "valor-falso-de-prueba", .secure: "TRUE",
        ]))
        await model.webView.configuration.websiteDataStore.httpCookieStore.setCookie(session)

        let returned = await waitUntil(timeout: 10) { !self.navigations.isEmpty }
        XCTAssertTrue(returned)
        XCTAssertEqual(navigations, [SlackCapture.tokensURL])

        model.sessionCookieAppeared()
        model.sessionCookieAppeared()
        XCTAssertEqual(navigations.count, 1, "no se le saca de donde esté más de una vez")
    }

    func testOtherCookiesAreNotASession() {
        func cookie(_ name: String, _ domain: String) -> HTTPCookie {
            HTTPCookie(properties: [.domain: domain, .path: "/", .name: name, .value: "x"])!
        }

        XCTAssertTrue(SlackCapture.hasSessionCookie([cookie("d", ".slack.com")]))
        XCTAssertTrue(SlackCapture.hasSessionCookie([cookie("b", ".slack.com"), cookie("d", "slack.com")]))
        XCTAssertFalse(SlackCapture.hasSessionCookie([cookie("b", ".slack.com"), cookie("x", ".slack.com")]))
        XCTAssertFalse(SlackCapture.hasSessionCookie([cookie("d", ".evil.example")]))
        XCTAssertFalse(SlackCapture.hasSessionCookie([cookie("d", ".notslack.com")]))
        XCTAssertFalse(SlackCapture.hasSessionCookie([]))
    }

    func testStartOpensTheTokensPage() {
        let model = makeModel()

        model.start()

        XCTAssertEqual(navigations, [SlackCapture.tokensURL])
    }

    // MARK: Tokens que ya estaban

    func testATokenAlreadyOnThePageIsUsedWithoutGeneratingAnother() async throws {
        let model = makeModel()
        load(replica(reveal: .field, token: fakeToken("NUEVO"), existing: fakeToken("VIEJO")), into: model)

        let done = await waitForCapture()

        XCTAssertTrue(done)
        XCTAssertEqual(capturedValue, fakeToken("VIEJO"))
    }

    /// Después de que Slack rechazó un token: el que sigue a la vista se ignora y se genera otro.
    func testFreshOnlyIgnoresTheTokenThatWasAlreadyThere() async {
        let model = makeModel(freshOnly: true)
        load(replica(reveal: .field, token: fakeToken("NUEVO"), existing: fakeToken("VIEJO")), into: model)

        let done = await waitForCapture()

        XCTAssertTrue(done, "etapa: \(model.stage)")
        XCTAssertEqual(capturedValue, fakeToken("NUEVO"))
    }

    /// Una página que pinta el token viejo tarde (después de cargar) tampoco engaña a `freshOnly`:
    /// solo cuenta lo que aparece después de pulsar «Generate».
    func testFreshOnlyAlsoIgnoresAnOldTokenThatIsRenderedLate() async throws {
        let model = makeModel(freshOnly: true)
        let html = """
            <!doctype html><html><body><h1>Your Apps</h1><div id="list"></div>
            <button id="gen" hidden>Generate Token</button>
            <script>
              var OLD = ["xoxe", "\(fakeToken("VIEJO").dropFirst(5))"].join("."), NEW = ["xoxe", "\(fakeToken("NUEVO").dropFirst(5))"].join(".");
              setTimeout(function () {
                document.getElementById('list').textContent = OLD;       // la lista llega tarde
                var gen = document.getElementById('gen'); gen.hidden = false;
                gen.onclick = function () { document.getElementById('list').textContent = OLD + ' ' + NEW; };
              }, 900);
            </script></body></html>
            """
        load(html, into: model)

        let done = await waitForCapture()

        XCTAssertTrue(done, "etapa: \(model.stage)")
        XCTAssertEqual(capturedValue, fakeToken("NUEVO"))
    }

    // MARK: Lo que no debe capturarse

    func testAPageOnAnotherSiteCannotDeliverAToken() async throws {
        let model = makeModel()
        load(replica(reveal: .field), into: model, at: "https://api.slack.com.evil.example/apps")

        try await Task.sleep(for: .seconds(3))

        XCTAssertTrue(captured.isEmpty)
        XCTAssertNotEqual(model.stage, .captured)
    }

    /// En una página de inicio de sesión el script no actúa: ni pulsa nada ni lee campos, aunque
    /// lo que haya en un campo parezca un token.
    func testTheScriptDoesNothingOnASignInPage() async throws {
        let model = makeModel()
        let html = """
            <!doctype html><html><body><h1>Sign in to Slack</h1>
            <input type="text" id="email" value="\(fakeToken())">
            <input type="password" id="password" value="\(fakeToken())">
            <button id="gen" onclick="window.clicked = true">Generate Token</button>
            </body></html>
            """
        load(html, into: model, at: "https://slack.com/signin")

        let onSignIn = await waitUntil(timeout: 10) { model.stage == .signIn }
        try await Task.sleep(for: .seconds(2))
        let clicked = try await model.webView.evaluateJavaScript("window.clicked === true") as? Bool

        XCTAssertTrue(onSignIn, "etapa: \(model.stage)")
        XCTAssertTrue(captured.isEmpty)
        XCTAssertEqual(clicked, false, "en una página que no es la de tokens no se pulsa nada")
    }

    func testGoogleSignInIsRecognisedSoTheUserCanBeTold() async {
        let model = makeModel()
        load("<html><body>Sign in with Google</body></html>", into: model, at: "https://accounts.google.com/signin")

        let told = await waitUntil(timeout: 10) { model.stage == .googleSignIn }

        XCTAssertTrue(told, "etapa: \(model.stage)")
    }

    // MARK: Los mensajes

    func testMessagesFromUntrustedSourcesAreIgnored() {
        let model = makeModel()
        let message: [String: Any] = ["kind": "token", "value": fakeToken()]

        model.receive(body: message, host: "evil.example", isMainFrame: true)
        model.receive(body: message, host: "api.slack.com", isMainFrame: false)
        XCTAssertTrue(captured.isEmpty)

        model.receive(body: message, host: "api.slack.com", isMainFrame: true)
        XCTAssertEqual(capturedValue, fakeToken())
    }

    func testAMessageWithoutARealTokenIsIgnored() {
        let model = makeModel()

        for value in ["xoxe.xoxp-1-corto", "hola", "", "xoxe-1-" + String(repeating: "x", count: 60)] {
            model.receive(body: ["kind": "token", "value": value], host: "api.slack.com", isMainFrame: true)
        }
        model.receive(body: "no soy un diccionario", host: "api.slack.com", isMainFrame: true)
        model.receive(body: ["kind": "token"], host: "api.slack.com", isMainFrame: true)

        XCTAssertTrue(captured.isEmpty)
        XCTAssertNotEqual(model.stage, .captured)
    }

    func testTheTokenIsDeliveredOnlyOnce() {
        let model = makeModel()

        model.receive(body: ["kind": "token", "value": fakeToken("1")], host: "api.slack.com", isMainFrame: true)
        model.receive(body: ["kind": "token", "value": fakeToken("2")], host: "api.slack.com", isMainFrame: true)

        XCTAssertEqual(captured.count, 1)
        XCTAssertEqual(capturedValue, fakeToken("1"))
    }

    func testTheSessionIsEphemeral() {
        let model = makeModel()

        XCTAssertFalse(model.webView.configuration.websiteDataStore.isPersistent, "la sesión no se guarda en el disco")
        XCTAssertTrue((model.webView.customUserAgent ?? "").isEmpty, "no se sustituye el identificador entero")
        XCTAssertEqual(model.webView.configuration.applicationNameForUserAgent, SlackCapture.safariApplicationName())
    }

    func testAfterTearDownNothingIsCaptured() async throws {
        let model = makeModel()
        model.tearDown()
        load(replica(reveal: .field), into: model)

        try await Task.sleep(for: .seconds(3))

        XCTAssertTrue(captured.isEmpty)
    }
}
