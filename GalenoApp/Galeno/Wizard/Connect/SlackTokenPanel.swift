import AppKit
import GalenoCore
import SwiftUI

/// Slack: el usuario genera un "token de configuración" en `api.slack.com/apps` y lo pega
/// aquí (`docs/03` §4e). Slack dice que ese primer token solo se genera por interfaz.
///
/// Se pega en un campo seguro: el valor sale del campo en cuanto se envía, se envuelve en un
/// `OAuthSecret`, se usa una vez para crear la app y se descarta. No se guarda en ninguna parte.
struct SlackTokenPanel: View {
    @ObservedObject var flow: ConnectFlow
    let name: String

    @State private var token = ""

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

                VStack(alignment: .leading, spacing: Space.s8) {
                    StepRow(number: 1, text: "connect.slack.step1") {
                        Button("connect.slack.open") { NSWorkspace.shared.open(Self.appsURL) }
                            .buttonStyle(.bordered)
                    }
                    StepRow(number: 2, text: "connect.slack.step2") { EmptyView() }
                    StepRow(number: 3, text: "connect.slack.step3") { EmptyView() }
                }

                // Un campo seguro: el token no se ve ni se queda en pantalla.
                SecureField("connect.slack.tokenField", text: $token, prompt: Text("connect.slack.tokenPlaceholder"))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .frame(maxWidth: 440)
                    .onSubmit(submit)
                    .accessibilityLabel(Text("connect.slack.tokenField"))

                if pastedTheRefreshToken {
                    Label("connect.slack.refreshTokenHint", systemImage: "exclamationmark.circle")
                        .font(.galenoCaption)
                        .foregroundStyle(Color.seal700)
                }

                Text("connect.slack.privacy")
                    .font(.galenoCaption)
                    .foregroundStyle(Color.ink700)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Spacer()
                    PrimaryButton("connect.slack.create", action: submit)
                        .controlSize(.large)
                        .disabled(!isReady)
                }
            }
            .padding(.horizontal, Space.s4)
        }
        .scrollBounceBehavior(.basedOnSize)
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
