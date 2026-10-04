import Foundation

/// Cómo se reconoce un token de configuración de Slack.
nonisolated enum SlackTokenPattern {
    /// `xoxe.xoxp-…` con al menos 40 caracteres después: así un token recortado en pantalla
    /// ("xoxe.xoxp-1-Mi0y…") no se toma por uno entero. Los de verdad pasan de 100.
    static let pattern = #"xoxe\.xoxp-[A-Za-z0-9_-]{40,}"#

    /// El token más largo que aparezca en `text`, o `nil`.
    static func bestToken(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let string = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: string.length))
            .map { string.substring(with: $0.range) }
            .max { $0.count < $1.count }
    }
}

/// En qué página está la ventana de inicio de sesión.
nonisolated enum SlackSignInLocation: Equatable {
    /// `api.slack.com/apps`: aquí se genera el token.
    case tokensPage
    /// El cliente de Slack (`app.slack.com`): ya inició sesión, pero no es la página de tokens.
    case slackClient
    /// Otra página de Slack: lo normal mientras inicia sesión.
    case slack
    /// Google no deja iniciar sesión en ventanas embebidas en apps.
    case google
    /// Un proveedor de identidad de la empresa, o cualquier otra cosa.
    case other

    static func classify(_ url: URL?) -> SlackSignInLocation {
        guard let host = url?.host?.lowercased() else { return .other }
        if host == "api.slack.com" {
            return url?.path.hasPrefix("/apps") == true ? .tokensPage : .slack
        }
        if host == "app.slack.com" { return .slackClient }
        if host == "slack.com" || host.hasSuffix(".slack.com") { return .slack }
        if host == "accounts.google.com" { return .google }
        return .other
    }
}

nonisolated enum SlackCapture {
    static let tokensURL = URL(string: "https://api.slack.com/apps")!
    /// Sin sesión, la página de tokens no redirige: enlaza aquí.
    static let signInURL = URL(string: "https://slack.com/signin")!

    /// ¿Ya hay sesión de Slack en la ventana? Slack la guarda en la cookie `d` de `.slack.com`.
    /// Solo se mira que **exista**: su valor no se lee, no se copia y no se guarda.
    static func hasSessionCookie(_ cookies: [HTTPCookie]) -> Bool {
        cookies.contains { cookie in
            let domain = cookie.domain.lowercased()
            return cookie.name == "d" && (domain == "slack.com" || domain.hasSuffix(".slack.com"))
        }
    }
    static let messageHandlerName = "galeno"

    /// Solo se aceptan mensajes del documento principal de `api.slack.com`: ninguna otra página
    /// (ni un marco incrustado) puede hacerse pasar por la de tokens.
    static func isTrustedSource(host: String, isMainFrame: Bool) -> Bool {
        isMainFrame && host.lowercased() == "api.slack.com"
    }

    enum NavigationDecision: Equatable {
        case allow
        /// Google no permite iniciar sesión en ventanas embebidas en apps. Galeno respeta esa
        /// política: no abre su inicio de sesión aquí, y le dice al usuario que use otro método.
        case blockedGoogleSignIn
        case blocked
    }

    /// La ventana solo navega por `https` (y las páginas internas de WebKit): nada de `file:`,
    /// `http:` ni esquemas de otras apps. Y nunca al inicio de sesión de Google.
    static func navigationDecision(for url: URL?) -> NavigationDecision {
        guard let scheme = url?.scheme?.lowercased() else { return .blocked }
        if scheme == "about" { return .allow }
        guard scheme == "https" else { return .blocked }
        if SlackSignInLocation.classify(url) == .google { return .blockedGoogleSignIn }
        return .allow
    }

    static func allowsNavigation(to url: URL?) -> Bool { navigationDecision(for: url) == .allow }

    /// Cómo se identifica la ventana ante las páginas.
    ///
    /// Un `WKWebView` es el motor de Safari, pero por defecto no lo dice, y Slack responde
    /// «your browser is not supported». Se añade lo mismo que añade Safari, con la versión del
    /// Safari de este Mac: es una declaración cierta sobre el motor, no un disfraz de otro
    /// navegador. No sirve para saltarse el bloqueo de Google, que se respeta aparte
    /// (`navigationDecision`).
    static func safariApplicationName(
        safariVersion: String? = Bundle(path: "/Applications/Safari.app")?
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    ) -> String {
        let version = safariVersion.flatMap { value -> String? in
            value.range(of: #"^\d+(\.\d+){0,2}$"#, options: .regularExpression) != nil ? value : nil
        }
        return "Version/\(version ?? "17.6") Safari/605.1.15"
    }

    /// La configuración que lee el script. `freshOnly`: ignora los tokens que ya estaban en la
    /// página y genera uno nuevo (después de que Slack rechazara el anterior).
    static func configScript(freshOnly: Bool) -> String {
        "window.__galenoConfig = { freshOnly: \(freshOnly ? "true" : "false") };"
    }

    /// El script que corre en la ventana de inicio de sesión.
    ///
    /// **Solo actúa en `api.slack.com`**: en las páginas donde el usuario escribe su contraseña
    /// (Slack, Google, el proveedor de la empresa) sale en la primera línea y no toca nada.
    ///
    /// Hace dos cosas, y la segunda no depende de la primera:
    /// 1. *Ayuda con los clics*: pulsa «Generate Token», elige el workspace si solo hay uno y
    ///    confirma. Se guía por el texto de los botones, no por clases de CSS.
    /// 2. *Captura el token* por cualquier vía por la que aparezca: el texto o los atributos de
    ///    la página, un campo, la respuesta de la petición que lo genera, o el botón «Copy».
    ///    Si los clics automáticos fallan porque Slack cambió la pantalla, el usuario pulsa él
    ///    mismo y la captura funciona igual.
    ///
    /// Un token que la página intente copiar **no llega al portapapeles del sistema**: se
    /// entrega a Galeno y se descarta.
    static let script = #"""
    (function () {
      if (window.__galenoCapture) return;
      window.__galenoCapture = true;
      if (location.hostname !== 'api.slack.com') return;

      var config = window.__galenoConfig || {};
      var RE = /xoxe\.xoxp-[A-Za-z0-9_-]{40,}/g;
      var captured = false, lastReport = '';
      // Con `freshOnly` (Slack rechazó el token anterior) solo vale lo que aparezca **después**
      // de pulsar «Generate»: todo lo visto antes se anota para ignorarlo.
      var armed = !config.freshOnly, seenBefore = [];
      var clickedGenerate = false, clickedConfirm = false, copyIndex = 0, generateAt = 0;

      function post(message) {
        try { window.webkit.messageHandlers.galeno.postMessage(message); } catch (e) {}
      }
      function report(state, extra) {
        var key = state + JSON.stringify(extra || {});
        if (key === lastReport) return;
        lastReport = key;
        var message = extra || {};
        message.kind = 'page';
        message.state = state;
        post(message);
      }
      function tokensIn(text) { return (typeof text === 'string' && text.match(RE)) || []; }
      function offer(text) {
        if (captured) return false;
        var all = tokensIn(text);
        if (!armed) {
          for (var i = 0; i < all.length; i++) if (seenBefore.indexOf(all[i]) < 0) seenBefore.push(all[i]);
          return false;
        }
        var found = all.filter(function (t) { return seenBefore.indexOf(t) < 0; });
        if (!found.length) return false;
        found.sort(function (a, b) { return b.length - a.length; });
        captured = true;
        post({ kind: 'token', value: found[0] });
        return true;
      }
      // Cualquier token de Slack (también el refresh token): nunca al portapapeles del sistema.
      function isSlackToken(text) { return typeof text === 'string' && /^\s*xoxe[.-]/.test(text); }

      // 1. El botón «Copy», por la API moderna...
      try {
        var clipboard = navigator.clipboard;
        if (clipboard && clipboard.writeText) {
          var originalWrite = clipboard.writeText.bind(clipboard);
          clipboard.writeText = function (text) {
            if (isSlackToken(text)) { offer(text); return Promise.resolve(); }
            return originalWrite(text);
          };
        } else {
          Object.defineProperty(navigator, 'clipboard', {
            configurable: true,
            value: { writeText: function (text) { offer(text); return Promise.resolve(); } }
          });
        }
      } catch (e) {}
      // ...y por la antigua (execCommand('copy') sobre una selección).
      document.addEventListener('copy', function (event) {
        var active = document.activeElement;
        var text = String(document.getSelection() || '');
        if (active && typeof active.value === 'string' && active.selectionStart != null) {
          text = active.value.substring(active.selectionStart, active.selectionEnd) || text;
        }
        if (isSlackToken(text)) { offer(text); event.preventDefault(); }
      }, true);

      // Un «Copy» antiguo crea un campo temporal con el token y lo quita enseguida: el observador
      // lo ve en el momento, aunque ya no esté cuando se revise la página.
      try {
        new MutationObserver(function (records) {
          for (var i = 0; i < records.length && !captured; i++) {
            var added = records[i].addedNodes;
            for (var j = 0; j < added.length; j++) {
              var node = added[j];
              if (node.nodeType !== 1) continue;
              if (typeof node.value === 'string' && node.type !== 'password') offer(node.value);
              offer(node.textContent || '');
            }
          }
        }).observe(document, { childList: true, subtree: true });
      } catch (e) {}

      // 2. La respuesta de la petición que genera el token.
      if (window.fetch) {
        var originalFetch = window.fetch;
        window.fetch = function () {
          return originalFetch.apply(this, arguments).then(function (response) {
            try { response.clone().text().then(offer).catch(function () {}); } catch (e) {}
            return response;
          });
        };
      }
      var originalSend = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.send = function () {
        this.addEventListener('load', function () {
          try {
            if (this.responseType === '' || this.responseType === 'text') offer(this.responseText);
          } catch (e) {}
        });
        return originalSend.apply(this, arguments);
      };

      // 3. Lo que hay en la página: texto, atributos y campos (nunca los de contraseña).
      function pageText() {
        var parts = [document.documentElement ? document.documentElement.innerHTML : ''];
        var fields = document.querySelectorAll('input:not([type=password]), textarea');
        for (var i = 0; i < fields.length; i++) parts.push(fields[i].value || '');
        return parts.join('\n');
      }

      function visible(element) {
        return !!(element && element.getClientRects().length &&
          getComputedStyle(element).visibility !== 'hidden');
      }
      function textOf(element) {
        return (element.innerText || element.value || element.getAttribute('aria-label') || '').trim();
      }
      function buttons(root) {
        var all = (root || document).querySelectorAll(
          'button, [role="button"], a.btn, input[type="submit"], input[type="button"]');
        return Array.prototype.filter.call(all, visible);
      }
      function findButton(pattern, root) {
        var list = buttons(root);
        for (var i = 0; i < list.length; i++) if (pattern.test(textOf(list[i]))) return list[i];
        return null;
      }
      // El diálogo de generar el token, y no cualquier otro: el aviso de cookies de Slack también
      // es un "diálogo". Se reconoce porque tiene un botón «Generate» o deja elegir workspace.
      function dialog() {
        var candidates = document.querySelectorAll(
          'dialog[open], [role="dialog"], [aria-modal="true"], .ReactModal__Content, .c-sk-modal, .modal');
        for (var i = 0; i < candidates.length; i++) {
          var box = candidates[i];
          if (!visible(box)) continue;
          var choosesWorkspace = /workspace/i.test(box.innerText || '') &&
            box.querySelector('select, input[type="radio"]');
          if (findButton(/^generate(\s+token)?$/i, box) || choosesWorkspace) return box;
        }
        return null;
      }
      // Sin sesión, la página dice «You'll need to sign in to your Slack account…».
      function signInLink() {
        var links = document.querySelectorAll('a[href]');
        for (var i = 0; i < links.length; i++) {
          if (/sign in to your slack account/i.test(links[i].innerText || '')) return links[i];
        }
        return null;
      }

      function handleDialog(box) {
        var select = box.querySelector('select');
        if (select && !select.value) {
          var options = Array.prototype.filter.call(select.options, function (o) {
            return o.value !== '' && !o.disabled;
          });
          // Con un solo workspace no hay nada que preguntar; con varios, elige el usuario.
          if (options.length !== 1) { report('chooseWorkspace', { count: options.length }); return; }
          select.value = options[0].value;
          select.dispatchEvent(new Event('input', { bubbles: true }));
          select.dispatchEvent(new Event('change', { bubbles: true }));
        }
        var radios = box.querySelectorAll('input[type="radio"]');
        if (!select && radios.length) {
          var checked = Array.prototype.some.call(radios, function (r) { return r.checked; });
          if (!checked) {
            if (radios.length !== 1) { report('chooseWorkspace', { count: radios.length }); return; }
            radios[0].click();
          }
        }
        var confirm = findButton(/^generate(\s+token)?$/i, box);
        if (!confirm) { report('chooseWorkspace', { count: 0 }); return; }
        if (confirm.disabled || confirm.getAttribute('aria-disabled') === 'true') {
          report('chooseWorkspace', { count: 0 });
          return;
        }
        if (!clickedConfirm) {
          clickedConfirm = true;
          generateAt = Date.now();
          confirm.click();
          report('generating');
        }
      }

      // Un clic en «Generate…», de Galeno o del usuario, es lo que separa lo viejo de lo nuevo.
      document.addEventListener('click', function (event) {
        if (armed) return;
        var target = event.target && event.target.closest &&
          event.target.closest('button, [role="button"], a, input');
        if (target && /generate/i.test(textOf(target))) {
          offer(pageText());  // lo que hay ahora mismo también es "de antes"
          armed = true;
        }
      }, true);

      function tick() {
        if (captured) return;
        if (offer(pageText())) return;
        // Antes de que la página termine de cargar no se sabe si hay sesión ni qué botones hay.
        if (document.readyState === 'loading') return;

        var box = dialog();
        if (box) { handleDialog(box); return; }

        var generate = findButton(/generate\s+token/i);
        if (generate && !clickedGenerate) {
          clickedGenerate = true;
          generateAt = Date.now();
          generate.click();
          report('clickedGenerate');
          return;
        }

        // Si el token existe pero la página no lo muestra entero, queda el botón «Copy».
        var copies = buttons().filter(function (b) { return /^copy\b/i.test(textOf(b)); });
        var settled = Date.now() - generateAt > 800;
        var mayCopy = copies.length && settled &&
          (clickedGenerate || clickedConfirm || (!generate && !config.freshOnly));
        if (mayCopy && copyIndex < copies.length) {
          copies[copyIndex++].click();
          report('copying', { n: copyIndex });
          return;
        }
        if (!generate && !copies.length && signInLink()) { report('signedOut'); return; }
        report(generate || copies.length ? 'waiting' : 'noControls');
      }

      setInterval(tick, 400);
      if (document.readyState !== 'loading') tick();
      else document.addEventListener('DOMContentLoaded', tick);
    })();
    """#
}
