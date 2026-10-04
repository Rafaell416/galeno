import SwiftUI

/// La barra de las dos ventanas de Slack (B1): arriba, la dirección a la vista —el usuario tiene que
/// poder comprobar dónde escribe—, el paso y «Cancelar»; debajo, de quién es el turno y qué hacer;
/// y al pie, un filete de 2 pt que avanza. El contenido de Slack va debajo, sin tocar.
/// De quién es el turno en una ventana de Slack.
enum SlackTurn { case user, galeno, done, warning, notice }

struct SlackWindowBar<Actions: View>: View {
    let host: String
    let step: Int
    let total: Int
    let turn: SlackTurn
    let text: Text
    /// Cambia cuando cambia lo que dice la barra: el texto se funde (300 ms) en vez de saltar.
    var textKey: String = ""
    @ViewBuilder var actions: Actions

    @Environment(\.locale) private var locale
    @Environment(\.galenoReduceMotion) private var reduceMotion

    private var turnLabel: LocalizedStringKey? {
        switch turn {
        case .user: "connect.slack.turn.user"
        case .galeno: "connect.slack.turn.galeno"
        case .done, .warning, .notice: nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.s12) {
                HStack(spacing: 6) {
                    Image(systemName: "lock")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.moss700)
                    Text(verbatim: host.isEmpty ? "…" : "https://" + host)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.ink900)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.parchment50)
                .overlay(Rectangle().strokeBorder(Color.parchment400, lineWidth: 1))

                SmallCapsText(
                    string: Localized.string("connect.slack.window.step %lld %lld", step, total, locale: locale),
                    size: 13, tracking: 0.12
                )
                .foregroundStyle(Color.ink700)
                .fixedSize()

                Spacer(minLength: Space.s8)
                actions
            }
            .padding(.bottom, 10)

            (turnPrefix + text.foregroundColor(textColor))
                .font(Typo.list)
                .fixedSize(horizontal: false, vertical: true)
                .id(textKey + String(describing: turn))
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 4)))
                .padding(.bottom, 12)
                .animation(.easeOut(duration: Motion.enter), value: textKey)
                .animation(.easeOut(duration: Motion.enter), value: turn)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .background(Color.parchment100)
        .overlay(alignment: .bottom) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.parchment300)
                    Rectangle().fill(Color.ink900)
                        .frame(width: proxy.size.width * CGFloat(min(max(step, 0), total)) / CGFloat(max(total, 1)))
                }
            }
            .frame(height: 2)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: step)
            .accessibilityHidden(true)
        }
    }

    private var textColor: Color {
        switch turn {
        case .warning: .seal700
        case .notice: .ochre700  // un aviso, no un fallo (Google no deja entrar desde otra app)
        default: .ink900
        }
    }

    /// «Te toca a ti —» o «Galeno está trabajando —», en Cormorant cursiva y lacre.
    private var turnPrefix: Text {
        guard let turnLabel else { return Text(verbatim: "") }
        return (Text(turnLabel) + Text(verbatim: " —  "))
            .font(Typo.display(16, italic: true))
            .foregroundColor(Color.seal700)
    }
}
