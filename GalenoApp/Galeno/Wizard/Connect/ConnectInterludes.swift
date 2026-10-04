import AppKit
import GalenoCore
import SwiftUI

/// Las pantallas de dopamina (`docs/03` §3): pantalla completa, sin botones de OAuth,
/// que rompen la sensación de proceso largo. Los textos los escribe Rafa; mientras
/// tanto muestran la clave `TODO(dopamina)`.
struct DopamineScreen: View {
    @ObservedObject var flow: ConnectFlow
    @EnvironmentObject private var wizard: WizardState
    let kind: ConnectFlow.Dopamine

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 18) {
                // La lámina de la pausa: un grabado de línea (en Debug, su marcador mientras no hay arte).
                // La lámina se graba con un barrido de izquierda a derecha (900 ms); la frase entra 300 ms después.
                plate
                    .revealed(duration: 0.9)
                Text(message)
                    .font(Typo.display(26, italic: true))
                    .foregroundStyle(Color.ink900)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .frame(maxWidth: 480)
                    .fixedSize(horizontal: false, vertical: true)
                    .appearing(after: 0.3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Spacer()
                PrimaryButton("connect.continue") { flow.continueFromDopamine() }
            }
            .padding(.top, 10)
        }
        .padding(.horizontal, Space.s48)
        .padding(.top, 22)
        .padding(.bottom, Space.s16)
    }

    /// Una lámina distinta por pausa: la columnata al empezar, el códice a la mitad y, al final, la pluma
    /// (orígenes y licencias en `THIRD_PARTY.md`).
    @ViewBuilder
    private var plate: some View {
        switch kind {
        case .first:
            Plate(asset: "plate-columnata", caption: "columnata, grabado de línea", size: CGSize(width: 300, height: 164))
        case .half:
            Plate(asset: "plate-codice", caption: "códice abierto, grabado de línea", size: CGSize(width: 300, height: 141), printOnPaper: true)
        case .last:
            Plate(asset: "plate-pluma", caption: "pluma sobre un folio, grabado de línea", size: CGSize(width: 300, height: 190), printOnPaper: true)
        }
    }

    private var agentName: String { wizard.agentName.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var message: LocalizedStringKey {
        switch kind {
        case .first: "dopamine.connect.first \(agentName)"
        case .half: "dopamine.connect.half"
        case .last: "dopamine.connect.last \(agentName)"
        }
    }
}

/// Al terminar: lo que el agente ya ve, con los totales (`docs/03` §3).
struct CelebrationScreen: View {
    @ObservedObject var flow: ConnectFlow
    @EnvironmentObject private var wizard: WizardState

    private var skippedNames: String {
        flow.tools
            .filter { flow.statuses[$0] == .skipped }
            .map { $0.displayName(in: wizard.language) }
            .joined(separator: ", ")
    }

    private var connectedNames: String {
        flow.tools
            .filter { flow.statuses[$0] == .connected }
            .map { $0.displayName(in: wizard.language) }
            .joined(separator: ", ")
    }

    /// «Esto es lo que tu agente ya ve» solo si hay algo que mostrar debajo (totales, o aún
    /// contando). Si no se pudo contar nada, no se promete lo que no se enseña.
    private var hasFindings: Bool { !flow.totals.isEmpty || !flow.pendingData.isEmpty }

    private var celebrationTitle: LocalizedStringKey {
        if flow.connectedCount == 0 { return "connect.celebration.nothing" }
        return hasFindings
            ? "connect.celebration.title \(wizard.agentName.trimmingCharacters(in: .whitespacesAndNewlines))"
            : "connect.celebration.connected"
    }

    /// Las herramientas conectadas, en el orden en que se eligieron.
    private var connectedTools: [Tool] { flow.tools.filter { flow.statuses[$0] == .connected } }

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            Text(celebrationTitle)
                .font(Typo.display(30))
                .foregroundStyle(Color.ink900)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // Una línea por herramienta: su logo, su nombre y lo que se encontró.
            // Hasta tres por fila, cada una con todo el ancho que le toque (como `auto-fit` del diseño).
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(minimum: 180), spacing: 20, alignment: .leading),
                    count: max(1, min(connectedTools.count, 3))),
                alignment: .leading, spacing: Space.s8
            ) {
                ForEach(Array(connectedTools.enumerated()), id: \.element) { index, tool in
                    HStack(spacing: 10) {
                        ToolIcon(tool: tool, size: 18, color: Color.ink700)
                        line(for: tool, delay: 0.3 + Double(min(index, 6)) * Motion.stagger)
                            .font(Typo.list)
                            .foregroundStyle(Color.ink900)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 6)
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.parchment300).frame(height: 1) }
                    // Cada herramienta entra con su cifra, escalonada 80 ms, y la cifra cuenta (600 ms).
                    .staggered(index, base: 0.3)
                }
            }
            .frame(maxWidth: 600)
            .animation(.easeOut(duration: 0.2), value: flow.totals.count)

            if !flow.pendingData.isEmpty {
                HStack(spacing: Space.s8) {
                    InkSpinner(size: 12)
                    Text("connect.counting")
                        .font(.galenoCaption)
                        .foregroundStyle(Color.ink500)
                }
            }

            if !skippedNames.isEmpty {
                // «Para después»: entra la última, en gris, sin animación propia.
                Text("connect.celebration.skipped \(skippedNames)")
                    .font(Typo.text(14))
                    .foregroundStyle(Color.ink500)
                    .multilineTextAlignment(.center)
                    .appearing(after: 0.3 + Double(min(connectedTools.count, 6)) * Motion.stagger, duration: 0.15)
            }

            if flow.statuses[.slack] == .connected {
                // «Ponle cara a tu app»: entra 400 ms después de la lista y no compite con la celebración.
                SlackAppDetailsCard(
                    appID: flow.slackAppID, agentName: wizard.agentName.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                .appearing(after: 0.4 + 0.3 + Double(min(connectedTools.count, 6)) * Motion.stagger)
            }
            Spacer(minLength: 0)
            // El paso 5 termina con su propio botón, como las pausas: no vuelve la barra del wizard.
            HStack {
                Spacer()
                PrimaryButton("connect.continue") { wizard.next() }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Space.s48)
        .padding(.top, 22)
        .padding(.bottom, Space.s16)
    }

    /// «Notion · Encontré 48 páginas y bases de datos», o solo el nombre si no hubo dato.
    @ViewBuilder
    private func line(for tool: Tool, delay: Double) -> some View {
        let name = Text(verbatim: tool.displayName(in: wizard.language)).font(Typo.text(15, .semibold))
        if let finding = flow.findings[tool] {
            HStack(spacing: 0) {
                name + Text(verbatim: " · ")
                CountingFinding(finding: finding, delay: delay)
            }
        } else {
            name
        }
    }
}

/// La app de Slack ya funciona, pero el icono no se puede poner por API ni por manifiesto: queda
/// para el usuario. Se le dice dónde, con las medidas que exige Slack (verificadas en
/// docs.slack.dev: icono entre 512×512 y 2000×2000 px; descripción corta de hasta 140 caracteres
/// y larga de 174 a 4000).
struct SlackAppDetailsCard: View {
    let appID: String?
    var agentName = ""
    @Environment(\.locale) private var locale

    /// La página de la app en Slack si se conoce su identificador; si no, la lista de apps.
    static func pageURL(appID: String?) -> URL {
        if let appID, appID.range(of: #"^A[A-Z0-9]{5,}$"#, options: .regularExpression) != nil {
            return URL(string: "https://api.slack.com/apps/\(appID)/general")!
        }
        return URL(string: "https://api.slack.com/apps")!
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            (Text("connect.slackDetails.title").font(Typo.text(13.5, .semibold)).foregroundColor(Color.ink900)
                + Text(verbatim: "\n") + Text("connect.slackDetails.body"))
                .font(Typo.text(13.5))
                .foregroundStyle(Color.ink700)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 4) {
                Button("connect.slackDetails.saveIcon") {
                    SealIcon.saveWithPanel(for: agentName, locale: locale)
                }
                Button("connect.slackDetails.open") { NSWorkspace.shared.open(Self.pageURL(appID: appID)) }
            }
            .buttonStyle(.plain)
            .font(Typo.text(13.5))
            .foregroundStyle(Color.seal700)
            .underline()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 600)
        .overlay(Rectangle().strokeBorder(Color.parchment300, lineWidth: 1))
    }
}
