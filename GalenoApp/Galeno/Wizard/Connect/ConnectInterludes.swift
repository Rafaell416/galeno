import GalenoCore
import SwiftUI

/// Las pantallas de dopamina (`docs/03` §3): pantalla completa, sin botones de OAuth,
/// que rompen la sensación de proceso largo. Los textos los escribe Rafa; mientras
/// tanto muestran la clave `TODO(dopamina)`.
struct DopamineScreen: View {
    @ObservedObject var flow: ConnectFlow
    let kind: ConnectFlow.Dopamine

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false

    var body: some View {
        VStack(spacing: Space.s24) {
            Spacer(minLength: 0)
            // Un trazo que se dibuja, como el del retrato en `docs/04` §9; sin confeti.
            Circle()
                .trim(from: 0, to: drawn ? 1 : 0)
                .stroke(Color.ink900, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 72, height: 72)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.9), value: drawn)
                .accessibilityHidden(true)
            Text(message)
                .font(.galenoTitle)
                .foregroundStyle(Color.ink900)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            Spacer(minLength: 0)
            PrimaryButton("connect.continue") { flow.continueFromDopamine() }
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Space.s48)
        .padding(.vertical, Space.s32)
        .onAppear { drawn = true }
    }

    private var message: LocalizedStringKey {
        switch kind {
        case .first: "dopamine.connect.first"
        case .half: "dopamine.connect.half"
        case .last: "dopamine.connect.last"
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

    var body: some View {
        VStack(spacing: Space.s16) {
            Spacer(minLength: 0)
            SuccessMark(size: 72)
            Text(flow.connectedCount == 0 ? "connect.celebration.nothing" : "connect.celebration.title")
                .font(.galenoTitle)
                .foregroundStyle(Color.ink900)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: Space.s4) {
                ForEach(flow.totals, id: \.noun) { total in
                    ConnectFlow.Finding(noun: total.noun, count: total.count).text
                        .font(.galenoBody)
                        .foregroundStyle(Color.ink700)
                }
                // Lo que todavía se está contando llega solo y se suma aquí.
                if !flow.pendingData.isEmpty {
                    HStack(spacing: Space.s8) {
                        ProgressView().controlSize(.small)
                        Text("connect.counting")
                            .font(.galenoCaption)
                            .foregroundStyle(Color.ink500)
                    }
                }
            }
            .animation(.easeOut(duration: 0.2), value: flow.totals.count)

            if !skippedNames.isEmpty {
                Text("connect.celebration.skipped \(skippedNames)")
                    .font(.galenoCaption)
                    .foregroundStyle(Color.ink500)
                    .multilineTextAlignment(.center)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Space.s48)
        .padding(.vertical, Space.s24)
    }
}
