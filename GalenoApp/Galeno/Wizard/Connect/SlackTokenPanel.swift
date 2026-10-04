import AppKit
import GalenoCore
import SwiftUI

/// Slack necesita una app OAuth del propio cliente (`docs/03` §4e). Para crearla hace falta un
/// "token de configuración" que Slack solo entrega desde su página.
///
/// El camino principal: el usuario pulsa **Iniciar sesión en Slack**, se autentica en una
/// ventana de Galeno y Galeno consigue el token por él (`SlackSignInWindow`). El de respaldo:
/// generarlo a mano y pegarlo en un campo seguro. En los dos casos el token se usa una vez
/// para crear la app y se descarta; no se guarda en ninguna parte.
struct SlackTokenPanel: View {
    @ObservedObject var flow: ConnectFlow
    @EnvironmentObject private var wizard: WizardState
    let name: String

    @State private var token = ""
    @State private var showsManual = false

    private static let appsURL = URL(string: "https://api.slack.com/apps")!

    private var isReady: Bool { ConnectFlow.looksLikeSlackAccessToken(token) }
    private var pastedTheRefreshToken: Bool { ConnectFlow.looksLikeSlackRefreshToken(token) }

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

                DisclosureGroup("connect.slack.manual", isExpanded: $showsManual) {
                    manual.padding(.top, Space.s8)
                }
                .font(.galenoCaption)
                .foregroundStyle(Color.ink700)
            }
            .padding(.horizontal, Space.s4)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    /// El respaldo: generar el token a mano y pegarlo.
    private var manual: some View {
        VStack(alignment: .leading, spacing: Space.s8) {
            StepRow(number: 1, text: "connect.slack.step1") {
                Button("connect.slack.open") { NSWorkspace.shared.open(Self.appsURL) }
                    .buttonStyle(.bordered)
            }
            StepRow(number: 2, text: "connect.slack.step2") { EmptyView() }
            StepRow(number: 3, text: "connect.slack.step3") { EmptyView() }

            HStack(spacing: Space.s12) {
                // Un campo seguro: el token no se ve ni se queda en pantalla.
                SecureField("connect.slack.tokenField", text: $token, prompt: Text("connect.slack.tokenPlaceholder"))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .frame(maxWidth: 380)
                    .onSubmit(submit)
                    .accessibilityLabel(Text("connect.slack.tokenField"))
                Button("connect.slack.create", action: submit)
                    .buttonStyle(.bordered)
                    .disabled(!isReady)
            }

            if pastedTheRefreshToken {
                Label("connect.slack.refreshTokenHint", systemImage: "exclamationmark.circle")
                    .font(.galenoCaption)
                    .foregroundStyle(Color.seal700)
            }
            Text("connect.slack.privacy")
                .font(.galenoCaption)
                .foregroundStyle(Color.ink700)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func openSignIn() {
        SlackSignInWindow.present(freshOnly: flow.slackNeedsFreshToken, language: wizard.language) { secret in
            flow.submitSlackSecret(secret)
        }
    }

    private func submit() {
        guard isReady else { return }
        flow.submitSlackToken(token)
        token = ""  // el campo se vacía en cuanto se envía
    }
}

private struct StepRow<Accessory: View>: View {
    let number: Int
    let text: LocalizedStringKey
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s12) {
            Text(verbatim: "\(number)")
                .font(.galenoCaption.weight(.semibold))
                .foregroundStyle(Color.ink900)
                .frame(width: 20, height: 20)
                .overlay(Circle().stroke(Color.ink500, lineWidth: 1))
            Text(text)
                .font(.galenoBody)
                .foregroundStyle(Color.ink900)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Space.s8)
            accessory
        }
    }
}
