import GalenoCore
import SwiftUI

/// Slack necesita una app OAuth del propio cliente (`docs/03` §4e). Para crearla hace falta un
/// "token de configuración" que Slack solo entrega desde su página.
///
/// El usuario pulsa **Iniciar sesión en Slack**, se autentica en una ventana de Galeno y Galeno
/// consigue el token por él (`SlackSignInWindow`). El token se usa una vez para crear la app y se
/// descarta; no se guarda en ninguna parte. No hay camino de «pegar el token a mano»: si la
/// ventana no avanza sola, ella misma le pide al usuario el clic que falte.
struct SlackTokenPanel: View {
    @ObservedObject var flow: ConnectFlow
    @EnvironmentObject private var wizard: WizardState
    let name: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s12) {
                HStack(spacing: Space.s12) {
                    ToolIcon(tool: .slack, size: 32, color: Color.ink900)
                    Text(verbatim: name)
                        .font(.galenoTitle)
                        .foregroundStyle(Color.ink900)
                }

                Text("connect.slack.signin.body")
                    .font(.galenoBody)
                    .foregroundStyle(Color.ink900)
                    .fixedSize(horizontal: false, vertical: true)

                PrimaryButton("connect.slack.signin.button", action: openSignIn)
                    .controlSize(.large)

                Text("connect.slack.signin.privacy")
                    .font(.galenoCaption)
                    .foregroundStyle(Color.ink700)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Space.s4)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func openSignIn() {
        // La misma sesión efímera servirá luego para autorizar la app: el usuario entra una vez.
        SlackSignInWindow.present(
            freshOnly: flow.slackNeedsFreshToken, language: wizard.language,
            dataStore: flow.webSession.dataStore
        ) { secret in
            flow.submitSlackSecret(secret)
        }
    }
}
