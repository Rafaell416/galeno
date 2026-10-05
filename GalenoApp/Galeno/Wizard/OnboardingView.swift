import GalenoCore
import SwiftUI

/// Antes del asistente, una sola vez: tres pantallas de una frase cada una (rediseño «Activación»). Qué es
/// Galeno, qué va a pasar y qué hay que tener a mano. Se saltan. No preguntan nada: lo primero que se decide
/// es el rol, ya dentro del asistente.
struct OnboardingView: View {
    @EnvironmentObject private var wizard: WizardState
    @Environment(\.galenoReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
    let onFinish: () -> Void
    @State private var page: Int

    init(startingAt page: Int = 0, onFinish: @escaping () -> Void) {
        _page = State(initialValue: page)
        self.onFinish = onFinish
    }

    private static let pageCount = 3

    var body: some View {
        VStack(spacing: 0) {
            // La marca, arriba: el asistente todavía no empezó.
            SmallCapsText(string: "Galeno", size: 13, tracking: 0.2)
                .foregroundStyle(Color.ink500)
                .padding(.top, 26)
                .accessibilityHidden(true)
            Group {
                switch page {
                case 0: WhatItIs()
                case 1: WhatWillHappen()
                default: WhatYouNeed()
                }
            }
            .id(page)
            .transition(reduceMotion ? .opacity : .pageTurn)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, Space.s48)

            Rectangle().fill(Color.parchment300).frame(height: 1)
            HStack(spacing: Space.s16) {
                Button("onboarding.skip", action: onFinish)
                    .buttonStyle(InkLinkStyle(size: 15))
                HStack(spacing: 6) {
                    ForEach(0..<Self.pageCount, id: \.self) { index in
                        Rectangle()
                            .strokeBorder(Color.ink900, lineWidth: 1)
                            .background(Rectangle().fill(index == page ? Color.ink900 : Color.clear))
                            .frame(width: 7, height: 7)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    Text(verbatim: Localized.string("onboarding.page %lld %lld", page + 1, Self.pageCount, locale: locale)))
                Spacer(minLength: 0)
                languageSwitch
                Button(page == Self.pageCount - 1 ? "onboarding.start" : "onboarding.next") { advance() }
                    .buttonStyle(InkButtonStyle(.primary, padding: 26))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, Space.s48)
            .padding(.vertical, 14)
        }
        .background(Color.parchment50)
        .animation(reduceMotion ? nil : .pageTurn, value: page)
        .opacity(wizard.languageFading ? 0 : 1)
        .animation(.easeInOut(duration: 0.12), value: wizard.languageFading)
        .onExitCommand { if page > 0 { page -= 1 } }
    }

    private func advance() {
        if page == Self.pageCount - 1 { onFinish() } else { page += 1 }
    }

    /// El idioma arranca en el del Mac; aquí se puede cambiar, sin ocupar una pantalla.
    private var languageSwitch: some View {
        HStack(spacing: 6) {
            ForEach(Language.allCases, id: \.self) { language in
                Button(language == .spanish ? "Español" : "English") {
                    wizard.changeLanguage(language, animated: !reduceMotion)
                }
                .buttonStyle(.plain)
                .font(Typo.text(14))
                .foregroundStyle(wizard.language == language ? Color.ink900 : Color.ink500)
                .underline(wizard.language == language)
                if language != Language.allCases.last {
                    Text(verbatim: "·").font(Typo.text(14)).foregroundStyle(Color.ink500)
                }
            }
        }
        .padding(.trailing, 6)
    }
}

/// El encabezado de una pantalla del onboarding: el título con su punto en lacre y, si acaso, una línea.
private struct OnboardingHeading: View {
    let title: LocalizedStringKey
    var summary: LocalizedStringKey?

    var body: some View {
        VStack(spacing: 10) {
            // Un solo texto, para que el punto de lacre siga a la última palabra aunque el título ocupe dos renglones.
            (Text(title).foregroundColor(Color.ink900) + Text(verbatim: ".").foregroundColor(Color.seal700))
                .font(Typo.display(36))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 600)
                .fixedSize(horizontal: false, vertical: true)
            if let summary {
                Text(summary)
                    .font(Typo.text(17))
                    .foregroundStyle(Color.ink700)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// 1 · Qué es: las herramientas → el agente → lo que produce. La imagen se compone con los iconos reales y el
/// retrato, que se estampa.
private struct WhatItIs: View {
    @EnvironmentObject private var wizard: WizardState

    private static let shown: [Tool] = [.notion, .googleWorkspace, .gmail]
    private var others: Int { Tool.allCases.filter { !$0.isComingSoon && $0 != .googleMeet }.count - Self.shown.count }

    var body: some View {
        VStack(spacing: 34) {
            OnboardingHeading(title: "onboarding.what.title", summary: "onboarding.what.summary")
            HStack(spacing: 0) {
                LazyVGrid(columns: [GridItem(.fixed(52), spacing: 8), GridItem(.fixed(52))], spacing: 8) {
                    ForEach(Array(Self.shown.enumerated()), id: \.element) { index, tool in
                        tile { ToolIcon(tool: tool, size: 26, color: .ink900) }.staggered(index, base: 0.15)
                    }
                    tile {
                        Text(verbatim: "+\(others)").font(Typo.text(13, .semibold)).foregroundStyle(Color.ink500)
                    }
                    .staggered(3, base: 0.15)
                }
                .frame(width: 112)
                arrow(after: 0.5)
                PortraitMark(size: 96, doubleRing: true).stamp()
                arrow(after: 0.9)
                VStack(alignment: .leading, spacing: 8) {
                    output("prd", "onboarding.what.documents", 0)
                    output("resumen-proyecto", "onboarding.what.summaries", 1)
                    output("seguimiento", "onboarding.what.followups", 2)
                }
            }
        }
    }

    private func tile(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .frame(width: 52, height: 52)
            .overlay(Rectangle().strokeBorder(Color.parchment400, lineWidth: 1))
    }

    /// Una flecha fina que se traza de izquierda a derecha.
    private func arrow(after delay: Double) -> some View {
        WriteUnderline(color: .ink500, duration: 0.35)
            .frame(width: 44, height: 1)
            .overlay(alignment: .trailing) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .regular))
                    .foregroundStyle(Color.ink500)
                    .offset(x: 3)
            }
            .padding(.horizontal, 10)
            .appearing(after: delay, duration: 0.2)
            .accessibilityHidden(true)
    }

    private func output(_ skill: String, _ key: LocalizedStringKey, _ index: Int) -> some View {
        HStack(spacing: 10) {
            SkillIcon(id: skill, size: 22)
            Text(key).font(Typo.text(15)).foregroundStyle(Color.ink900)
        }
        .staggered(index, base: 1.1)
    }
}

/// 2 · Qué va a pasar: tres columnas, tres dibujos, tres frases de dos palabras.
private struct WhatWillHappen: View {
    var body: some View {
        VStack(spacing: 28) {
            Plate(asset: "plate-columnata", caption: "columnata, grabado de línea", size: CGSize(width: 220, height: 120))
                .appearing(after: 0.05, duration: 0.4)
            OnboardingHeading(title: "onboarding.steps.title")
            HStack(alignment: .top, spacing: 24) {
                column(1, "account", "onboarding.steps.role")
                column(2, "browser", "onboarding.steps.connect")
                column(3, "ask", "onboarding.steps.ask")
            }
        }
    }

    private func column(_ number: Int, _ drawing: String, _ key: LocalizedStringKey) -> some View {
        VStack(spacing: 10) {
            Text(verbatim: String(number)).font(Typo.display(22)).foregroundStyle(Color.ink500)
            ActIcon(name: drawing, size: 40)
            Text(key).font(Typo.text(16)).foregroundStyle(Color.ink900).multilineTextAlignment(.center)
        }
        .frame(width: 160)
        .staggered(number - 1, base: 0.15)
    }
}

/// 3 · Qué hay que tener a mano: dos tarjetas, no una lista.
private struct WhatYouNeed: View {
    var body: some View {
        VStack(spacing: 28) {
            Plate(
                asset: "plate-codice", caption: "códice abierto, grabado de línea", size: CGSize(width: 220, height: 103),
                printOnPaper: true
            )
            .appearing(after: 0.05, duration: 0.4)
            OnboardingHeading(title: "onboarding.need.title")
            HStack(alignment: .top, spacing: 24) {
                card(title: "onboarding.need.claude", note: "onboarding.need.claude.note") {
                    ActIcon(name: "key", size: 36)
                }
                .staggered(0, base: 0.15)
                card(title: "onboarding.need.tool", note: "onboarding.need.tool.note") {
                    HStack(spacing: 6) {
                        ForEach([Tool.notion, .googleWorkspace, .whatsapp], id: \.self) { tool in
                            ToolIcon(tool: tool, size: 22, color: .ink900)
                        }
                    }
                    .frame(height: 36)
                }
                .staggered(1, base: 0.15)
            }
        }
    }

    private func card(
        title: LocalizedStringKey, note: LocalizedStringKey, @ViewBuilder drawing: () -> some View
    ) -> some View {
        VStack(spacing: 10) {
            drawing()
            Text(title).font(Typo.text(17, .medium)).foregroundStyle(Color.ink900)
            Text(note).font(Typo.text(14)).foregroundStyle(Color.ink500)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 14)
        .frame(width: 256, height: 136)
        .overlay(Rectangle().strokeBorder(Color.parchment400, lineWidth: 1))
    }
}

#Preview {
    OnboardingView(onFinish: {})
        .environmentObject(WizardState())
        .frame(width: WindowMetrics.width, height: WindowMetrics.height)
}
