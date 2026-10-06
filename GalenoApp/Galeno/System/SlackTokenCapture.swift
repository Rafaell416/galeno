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
    /// El cliente de Slack (`app.slack.com/client/…`): ya inició sesión, pero no es la página de tokens.
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
        if host == "app.slack.com" {
            // Solo el cliente en sí. Las rutas `/t/<workspace>/login/…` son el paso intermedio que
            // completa el inicio de sesión: interrumpirlas deja la sesión a medias.
            return url?.path.hasPrefix("/client") == true ? .slackClient : .slack
        }
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
        /// `slack://…`: Slack intenta abrir su app de escritorio, lo que pasa al elegir un workspace
        /// en su página de inicio de sesión. No se abre nada, pero **es la señal de que el usuario
        /// ya entró**: la ventana vuelve a la página de tokens.
        case slackDeepLink
        case blocked
    }

    /// La ventana solo navega por `https` (y las páginas internas de WebKit): nada de `file:`,
    /// `http:` ni esquemas de otras apps. Y nunca al inicio de sesión de Google.
    static func navigationDecision(for url: URL?) -> NavigationDecision {
        guard let scheme = url?.scheme?.lowercased() else { return .blocked }
        if scheme == "about" { return .allow }
        if scheme == "slack" { return .slackDeepLink }
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
    ///
    /// La versión sale del Safari instalado; si no se puede leer, o lo que se lee no es creíble (un Safari anterior al 14 no
    /// existe en un Mac que corre esta app), se deduce de la versión de macOS, que es de donde viene su motor: macOS 14 → 17,
    /// 15 → 18, y de la 26 en adelante la misma cifra. Slack rechaza («tu navegador no es compatible») un identificador que
    /// no reconoce, y un número absurdo se lo parece (visto en un Mac con macOS 15.6.1, 5 oct 2026).
    static func safariApplicationName(
        safariVersion: String? = installedSafariVersion(),
        systemMajorVersion: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    ) -> String {
        let readable = safariVersion.flatMap { value -> String? in
            guard value.range(of: #"^\d+(\.\d+){0,2}$"#, options: .regularExpression) != nil,
                let major = Int(value.split(separator: ".")[0]), major >= 14
            else { return nil }
            return value
        }
        return "Version/\(readable ?? safariVersionImplied(by: systemMajorVersion)) Safari/605.1.15"
    }

    /// ¿Es esta la respuesta con la que Slack rechaza un navegador que considera viejo? Es un 403 de la propia Slack (comprobado
    /// el 5 oct 2026: respondía 403 a todo Safari anterior al 26, y también a un Chrome y un Firefox de hace un año).
    static func isUnsupportedBrowserResponse(status: Int, host: String?) -> Bool {
        guard status == 403, let host = host?.lowercased() else { return false }
        return host == "slack.com" || host.hasSuffix(".slack.com")
    }

    /// La versión de Safari que trae una versión de macOS.
    static func safariVersionImplied(by systemMajorVersion: Int) -> String {
        switch systemMajorVersion {
        case 26...: "\(systemMajorVersion).0"
        case 15: "18.0"
        default: "17.6"
        }
    }

    /// La versión del Safari de este Mac. Desde macOS 13 vive en el *cryptex* del sistema y `/Applications/Safari.app` solo
    /// lo enlaza: se mira primero donde está de verdad.
    static func installedSafariVersion() -> String? {
        for path in ["/System/Cryptexes/App/System/Applications/Safari.app", "/Applications/Safari.app"] {
            if let version = Bundle(path: path)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                return version
            }
        }
        return nil
    }

    /// El workspace en el que el usuario acaba de entrar, según las direcciones por las que pasó la
    /// ventana: así el diálogo de generar el token no le pregunta lo que ya eligió. Son
    /// identificadores públicos (`T0123ABCD`, `mi-equipo`); nunca se guarda nada de la ruta que
    /// lleve un código de inicio de sesión.
    struct WorkspaceHint: Equatable {
        var teamID: String?
        var slug: String?

        var isEmpty: Bool { teamID == nil && slug == nil }

        /// Lo nuevo manda sobre lo viejo, pero solo en lo que traiga.
        mutating func merge(_ other: WorkspaceHint) {
            if let id = other.teamID { teamID = id }
            if let newSlug = other.slug { slug = newSlug }
        }
    }

    /// Subdominios de slack.com que no son un workspace.
    private static let notWorkspaces: Set<String> = [
        "www", "api", "app", "edgeapi", "files", "status", "join", "help", "slack", "a", "b",
        "wss-primary", "wss-backup", "slackb", "docs", "get", "my",
    ]

    static func workspaceHint(from url: URL?) -> WorkspaceHint? {
        guard let url, let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased()
        else { return nil }
        let parts = url.pathComponents.dropFirst()
        var hint = WorkspaceHint()

        func isTeamID(_ value: String) -> Bool {
            value.range(of: #"^T[A-Z0-9]{5,}$"#, options: .regularExpression) != nil
        }
        func isSlug(_ value: String) -> Bool {
            value.range(of: #"^[a-z0-9][a-z0-9-]{0,62}$"#, options: .regularExpression) != nil
        }

        if scheme == "slack" {
            // `slack://T0123ABCD/magic-login/<código>`: solo interesa el host.
            if isTeamID(host.uppercased()) { hint.teamID = host.uppercased() }
        } else if scheme == "https" {
            if host == "app.slack.com" {
                let list = Array(parts)
                if list.count >= 2, list[0] == "t", isSlug(list[1].lowercased()) { hint.slug = list[1].lowercased() }
                if list.count >= 2, list[0] == "client", isTeamID(list[1]) { hint.teamID = list[1] }
            } else if host.hasSuffix(".slack.com") {
                let sub = String(host.dropLast(".slack.com".count))
                if !sub.contains("."), isSlug(sub), !notWorkspaces.contains(sub) { hint.slug = sub }
            }
        }
        return hint.isEmpty ? nil : hint
    }

    /// La configuración que lee el script. `freshOnly`: ignora los tokens que ya estaban en la
    /// página y genera uno nuevo (después de que Slack rechazara el anterior). `hint`: en qué
    /// workspace entró el usuario, para elegirlo en el diálogo en vez de preguntarle.
    static func configScript(freshOnly: Bool, hint: WorkspaceHint? = nil) -> String {
        var fields = ["freshOnly: \(freshOnly ? "true" : "false")"]
        // Ya validados por `workspaceHint` (solo letras, dígitos y guiones): seguros de incrustar.
        if let id = hint?.teamID { fields.append("teamID: '\(id)'") }
        if let slug = hint?.slug { fields.append("slug: '\(slug)'") }
        return "window.__galenoConfig = { \(fields.joined(separator: ", ")) };"
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
      var clickedGenerate = false, clickedConfirm = false, copyIndex = 0, generateAt = 0, generateClicks = 0;
      // Solo cuentan los gestos de verdad del usuario (`isTrusted`), no los clics que hace este script.
      var userTouched = false;
      ['mousedown', 'keydown'].forEach(function (type) {
        document.addEventListener(type, function (event) { if (event.isTrusted) userTouched = true; }, true);
      });

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

      // ¿Es este el workspace en el que el usuario acaba de entrar? Por su identificador, o por su
      // nombre: «Mi Equipo» ↔ `mi-equipo`.
      function norm(text) { return String(text || '').toLowerCase().replace(/[^a-z0-9]/g, ''); }
      function isHinted(value, label) {
        if (config.teamID && value === config.teamID) return true;
        if (config.slug) {
          var slug = norm(config.slug), name = norm(label);
          if (name === slug || name === slug + 'slackcom') return true;
        }
        return false;
      }
      // Qué opción elegir sin preguntar: la única, o la única que coincide con el workspace en el
      // que el usuario entró. Si hay duda, ninguna: elige el usuario.
      function pickFor(items, valueOf, labelOf) {
        if (items.length === 1) return items[0];
        var hinted = items.filter(function (item) { return isHinted(valueOf(item), labelOf(item)); });
        return hinted.length === 1 ? hinted[0] : null;
      }
      // Para diagnosticar (solo se muestra en Debug): cómo es la lista que no se pudo resolver.
      function shapeOf(items, valueOf, labelOf) {
        return items.slice(0, 20).map(function (item) {
          return valueOf(item) + '|' + labelOf(item);
        }).join(';;');
      }

      // --- El desplegable propio de Slack (no es un <select>): se abre, se mira qué opciones salen
      // y se elige la del workspace en el que el usuario entró. Todo por lo que dice la página
      // (roles y texto), sin depender de clases de CSS.
      var dropdownAttempts = 0, dropdownAt = 0;
      function press(element) {
        ['pointerdown', 'mousedown', 'pointerup', 'mouseup', 'click'].forEach(function (type) {
          var Ctor = type.indexOf('pointer') === 0 && window.PointerEvent ? PointerEvent : MouseEvent;
          element.dispatchEvent(new Ctor(type, { bubbles: true, cancelable: true, view: window, button: 0 }));
        });
      }
      // Todo lo que dicen los atributos de un elemento y de lo que lleva dentro (ids, data-*…).
      function attributeText(element) {
        var parts = [], nodes = [element].concat(Array.prototype.slice.call(element.querySelectorAll('*')));
        nodes.slice(0, 60).forEach(function (node) {
          Array.prototype.forEach.call(node.attributes, function (a) { parts.push(a.value); });
        });
        return parts.join(' ');
      }
      function dropdownTrigger(box) {
        var direct = box.querySelector('[role="combobox"], [aria-haspopup="listbox"], select ~ *, button[aria-expanded]');
        if (direct && visible(direct)) return direct;
        // Si no, el elemento más pequeño que dice «Select a workspace».
        var best = null;
        Array.prototype.forEach.call(box.querySelectorAll('*'), function (node) {
          if (!visible(node) || !/select a workspace/i.test(node.innerText || '')) return;
          if (!best || (node.innerText || '').length <= (best.innerText || '').length) best = node;
        });
        return best && (best.closest('button, [role="button"], [tabindex]') || best);
      }
      function openOptions() {
        var all = document.querySelectorAll(
          '[role="option"], [role="menuitem"], [role="menuitemradio"], [role="listbox"] li');
        return Array.prototype.filter.call(all, visible);
      }
      function optionIsHinted(option) {
        var blob = attributeText(option);
        if (config.teamID && blob.indexOf(config.teamID) >= 0) return true;
        return isHinted('', textOf(option));
      }
      // Devuelve true si ya hizo algo (o está esperando); false si no es este tipo de diálogo.
      function handleCustomDropdown(box) {
        var placeholder = /select a workspace/i.test(box.innerText || '');
        if (!placeholder) return false;  // ya hay un workspace elegido
        var options = openOptions();
        if (options.length) {
          var hinted = options.length === 1 ? options : options.filter(optionIsHinted);
          if (hinted.length === 1) { press(hinted[0]); report('pickedWorkspace'); return true; }
          report('chooseWorkspace', { count: options.length, kind: 'custom',
            shape: options.slice(0, 12).map(function (o) {
              return o.tagName + '|' + (o.getAttribute('role') || '') + '|' + attributeText(o).slice(0, 160) + '|' + textOf(o).slice(0, 60);
            }).join(';;') });
          return true;
        }
        var trigger = dropdownTrigger(box);
        if (trigger && dropdownAttempts < 4 && Date.now() - dropdownAt > 1200) {
          dropdownAttempts++; dropdownAt = Date.now();
          press(trigger);
          report('openingDropdown', { n: dropdownAttempts });
          return true;
        }
        if (trigger && dropdownAttempts < 4) return true;  // esperando a que se abra
        report('chooseWorkspace', { count: 0, kind: 'custom', shape: 'sin opciones', html: box.outerHTML.slice(0, 2500) });
        return true;
      }

      function handleDialog(box) {
        var select = box.querySelector('select');
        if (select && !select.value) {
          var options = Array.prototype.filter.call(select.options, function (o) {
            return o.value !== '' && !o.disabled;
          });
          var choice = pickFor(options, function (o) { return o.value; }, function (o) { return o.text; });
          if (!choice) {
            report('chooseWorkspace', { count: options.length, kind: 'select',
              shape: shapeOf(options, function (o) { return o.value; }, function (o) { return o.text; }) });
            return;
          }
          select.value = choice.value;
          select.dispatchEvent(new Event('input', { bubbles: true }));
          select.dispatchEvent(new Event('change', { bubbles: true }));
        }
        var radios = box.querySelectorAll('input[type="radio"]');
        if (!select && radios.length) {
          var checked = Array.prototype.some.call(radios, function (r) { return r.checked; });
          if (!checked) {
            var radioList = Array.prototype.slice.call(radios);
            var radioLabel = function (r) {
              var label = r.closest('label') || (r.id && document.querySelector('label[for="' + r.id + '"]'));
              return (label && label.innerText) || (r.parentElement && r.parentElement.innerText) || '';
            };
            var radio = pickFor(radioList, function (r) { return r.value; }, radioLabel);
            if (!radio) {
              report('chooseWorkspace', { count: radios.length, kind: 'radio',
                shape: shapeOf(radioList, function (r) { return r.value; }, radioLabel) });
              return;
            }
            radio.click();
          }
        }
        if (!select && !radios.length && handleCustomDropdown(box)) return;
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
        // El primer clic puede llegar antes de que la página le haya puesto su acción al botón, y se pierde:
        // si el diálogo no aparece, se repite (pocas veces). Nunca después de confirmar: ahí ya hay un token
        // en camino y otro clic pediría uno más. El botón se trae a la vista: suele quedar bajo el pliegue,
        // y si al final le toca pulsarlo al usuario tiene que poder verlo.
        var retryGenerate = clickedGenerate && !clickedConfirm && generateClicks < 3 &&
          Date.now() - generateAt > 2500 &&
          !buttons().some(function (b) { return /^copy\b/i.test(textOf(b)); });
        if (generate && (!clickedGenerate || retryGenerate)) {
          clickedGenerate = true;
          generateClicks++;
          generateAt = Date.now();
          try { generate.scrollIntoView({ block: 'center' }); } catch (e) {}
          generate.click();
          report('clickedGenerate', { n: generateClicks });
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
        // Sin controles: Galeno puede volver a cargar la página, salvo que el usuario ya esté haciendo algo en ella.
        if (generate || copies.length) report('waiting');
        else report('noControls', userTouched ? { touched: 1 } : undefined);
      }

      setInterval(tick, 400);
      if (document.readyState !== 'loading') tick();
      else document.addEventListener('DOMContentLoaded', tick);
    })();
    """#
}
