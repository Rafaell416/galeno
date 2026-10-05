import AppKit
import AuthenticationServices

/// Quien muestra la autorización de una herramienta (Notion, Jira, las de reuniones) en la hoja de autenticación del
/// sistema. Las pruebas lo reemplazan.
@MainActor
protocol SystemAuthorizationPresenting: AnyObject {
    /// Muestra la página de autorización. `false` si no se pudo: quien llama abre el navegador de siempre.
    /// `onCancel`: el usuario cerró la hoja sin terminar.
    func present(url: URL, onCancel: @escaping @MainActor () -> Void) -> Bool
    /// La cierra (la autorización terminó, falló o se canceló). Sin hoja abierta no hace nada.
    func dismiss()
}

/// La hoja de autenticación de macOS (`ASWebAuthenticationSession`), decidida por Rafa el 4 de octubre de 2026 para las
/// herramientas que se autorizan con OAuth en el navegador. **No es una vista web de Galeno**: es una ventana del
/// navegador del usuario, con su sesión, sus contraseñas y el inicio con Google permitido, y Galeno no ve nada de lo
/// que pasa dentro. Lo que se gana frente a abrir una pestaña es que se cierra sola al terminar y el usuario no pierde
/// de vista a Galeno.
///
/// La vuelta de OAuth no pasa por aquí: va a `http://localhost:<puerto>/callback`, donde escucha `claude mcp login`.
/// Por eso el esquema de vuelta de la sesión es uno que nunca llega; Galeno sabe que terminó porque el proceso
/// `claude` sale, y entonces cierra la hoja (`dismiss`).
@MainActor
final class SystemAuthorizationSheet: NSObject, SystemAuthorizationPresenting, ASWebAuthenticationPresentationContextProviding {
    /// La sesión exige un esquema de vuelta; este no lo usa nadie.
    static let unusedCallbackScheme = "galeno-authorization"

    private var session: ASWebAuthenticationSession?
    /// Cuál es la hoja de ahora: su aviso de cierre solo cuenta si no la cerró Galeno.
    private var current: UUID?

    func present(url: URL, onCancel: @escaping @MainActor () -> Void) -> Bool {
        guard url.scheme?.lowercased() == "https" else { return false }
        dismiss()
        let id = UUID()
        let session = ASWebAuthenticationSession(
            url: url, callbackURLScheme: Self.unusedCallbackScheme,
            completionHandler: Self.completion { [weak self] in
                guard let self, self.current == id else { return }
                self.session = nil
                self.current = nil
                onCancel()
            })
        session.presentationContextProvider = self
        // Con la sesión del navegador del usuario: para eso se usa la hoja y no una ventana propia.
        session.prefersEphemeralWebBrowserSession = false
        guard session.start() else { return false }
        self.session = session
        current = id
        return true
    }

    /// El aviso de cierre de la sesión. **`nonisolated` a propósito:** AuthenticationServices lo llama desde su propia
    /// cola, no desde la principal, y un cierre escrito dentro de esta clase `@MainActor` hereda ese aislamiento y Swift le
    /// pone una comprobación al entrar que aborta el proceso (`dispatch_assert_queue`) — pasó el 4 de octubre de 2026 al
    /// cerrar la hoja con `dismiss()`, que dispara este aviso. Aquí no se toca nada de la clase: solo se pasa el trabajo
    /// al hilo principal.
    nonisolated static func completion(
        _ closed: @escaping @MainActor @Sendable () -> Void
    ) -> ASWebAuthenticationSession.CompletionHandler {
        { _, _ in Task { @MainActor in closed() } }
    }

    func dismiss() {
        guard let session else { return }
        self.session = nil
        current = nil
        session.cancel()
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        AppDelegate.wizardWindow ?? NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
    }
}
