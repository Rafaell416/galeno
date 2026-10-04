import Foundation

/// Lo que el sub-wizard necesita del mundo: cómo hablar con `claude`, con el bridge de
/// WhatsApp y con el reloj. En producción es lo real; las pruebas y el modo de
/// depuración `-galeno-fake-connect` ponen conectores falsos.
@MainActor
struct ConnectServices {
    /// Recibe la ruta a `claude` que encontró el paso 2.
    var makeMCP: @MainActor (_ claudePath: String) -> any MCPConnecting
    var whatsapp: any WhatsAppLinking
    var slack: any SlackAppSetting = SlackAppSetupService()
    /// Muestra la autorización de Slack en una ventana de Galeno. `nil` (pruebas y conectores
    /// falsos) = se usa el navegador del sistema.
    var authorizer: (any SlackAuthorizationPresenting)?
    var fetchRealData: Bool = true
    var timing = ConnectFlow.Timing()
    var sleep: ConnectFlow.Sleeper = { _ = try? await Task.sleep(for: $0) }

    static func live() -> ConnectServices {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-galeno-fake-connect") {
            return .scripted()
        }
        #endif
        return ConnectServices(
            makeMCP: { ClaudeMCPClient(claudePath: $0) },
            whatsapp: WhatsAppBridge.live(),
            authorizer: SlackAuthorizeWindowPresenter())
    }
}
