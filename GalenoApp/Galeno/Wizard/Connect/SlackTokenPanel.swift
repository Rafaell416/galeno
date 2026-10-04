import GalenoCore
import SwiftUI

/// Slack necesita una app OAuth del propio cliente (`docs/03` §4e). Para crearla hace falta un
/// "token de configuración" que Slack solo entrega desde su página.
///
/// El usuario pulsa **Iniciar sesión en Slack**, se autentica en una ventana de Galeno y Galeno
/// consigue el token por él (`SlackSignInWindow`). El token se usa una vez para crear la app y se
/// descarta; no se guarda en ninguna parte. No hay camino de «pegar el token a mano»: si la
/// ventana no avanza sola, ella misma le pide al usuario el clic que falte.
///
/// La pantalla es la misma de las demás conexiones (`ConnectionScreen`); aquí solo vive abrir la ventana.
enum SlackTokenPanel {
    @MainActor
    static func openSignIn(flow: ConnectFlow, language: Language) {
        // La misma sesión efímera servirá luego para autorizar la app: el usuario entra una vez.
        SlackSignInWindow.present(
            freshOnly: flow.slackNeedsFreshToken, language: language,
            dataStore: flow.webSession.dataStore
        ) { secret in
            flow.submitSlackSecret(secret)
        }
    }
}
