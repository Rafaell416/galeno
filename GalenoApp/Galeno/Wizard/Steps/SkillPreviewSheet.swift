import GalenoCore
import SwiftUI

/// La vista previa de una skill: una hoja **centrada** en la ventana (decisión de Rafa, 5 oct 2026; el diseño «Galeno B1
/// Skills» la hacía caer desde la barra de título), sobre un velo que cierra al pulsar. Enseña cómo se ve usarla
/// (`SkillDemoView`: la pregunta se escribe, se envía, el agente piensa y sale el resultado con su formato) —**ilustrativo:
/// no se ejecuta nada**—, dice cómo pedirla y qué necesita, y deja marcarla o desmarcarla para este agente.
struct SkillPreviewSheet: View {
    @EnvironmentObject private var wizard: WizardState
    let skill: CatalogSkill
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme
    /// Cuántas veces se pidió «Ver de nuevo»: cambiarlo vuelve a empezar la demostración.
    @State private var replays = 0

    private var language: Language { wizard.language }
    private var isOn: Bool { wizard.isSkillSelected(skill.id, source: skill.source) }
    private var agentName: String { wizard.agentName.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// Quién responde en la demostración: el agente por su nombre, o «Tu agente» si aún no lo tiene.
    private var speaker: String {
        agentName.isEmpty ? Localized.string("skills.demo.agent", locale: locale) : agentName
    }

    private func close() { wizard.previewedSkill = nil }

    var body: some View {
        ZStack {
            // El velo: papel al 62 % (66 % en oscuro). Pulsarlo cierra.
            Color.parchment50.opacity(colorScheme == .dark ? 0.66 : 0.62)
                .contentShape(Rectangle())
                .onTapGesture(perform: close)
                .accessibilityHidden(true)
            // Centrada, y nunca más alta que la ventana.
            panel
                .frame(width: 580)
                .padding(.vertical, 16)
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                SkillIcon(id: skill.id, size: 28).padding(.top, 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: skill.name.text(in: language))
                        .font(Typo.display(26))
                        .foregroundStyle(Color.ink900)
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(verbatim: skill.command)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(Color.ink500)
                        origin
                    }
                }
                Spacer(minLength: 0)
            }

            demo
                .padding(.top, 14)

            Grid(alignment: .topLeading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    label("skills.preview.how")
                    howToAsk
                }
                GridRow {
                    label("skills.preview.needs")
                    needs
                }
            }
            .font(Typo.text(14.5))
            .foregroundStyle(Color.ink900)
            .padding(.top, 12)

            HStack {
                Button("skills.preview.close", action: close)
                    .buttonStyle(InkLinkStyle(size: 15))
                    .keyboardShortcut(.cancelAction)
                Spacer(minLength: 0)
                if isOn {
                    Button("skills.preview.unmark") { wizard.toggleSkill(skill.id, source: skill.source) }
                        .buttonStyle(InkButtonStyle(.secondary, padding: 18, height: 40))
                } else {
                    Button {
                        wizard.toggleSkill(skill.id, source: skill.source)
                    } label: {
                        Text(verbatim: markLabel)
                    }
                    .buttonStyle(InkButtonStyle(.primary, padding: 18, height: 40))
                }
            }
            .padding(.top, 12)
            .overlay(alignment: .top) { Rectangle().fill(Color.parchment300).frame(height: 1) }
            .padding(.top, 16)
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .background(Color.parchment50)
        .overlay(Rectangle().strokeBorder(Color.ink900, lineWidth: 1.5))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    /// De quién es: «De Galeno», o el autor de una skill de un tercero con su licencia y el enlace al original.
    /// El crédito va siempre a la vista (`AGENTS.md`, «Skills y licencias»).
    @ViewBuilder
    private var origin: some View {
        if let credit = skill.credit {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                SmallCapsText(
                    string: Localized.string("skills.from.author %@ %@", credit.author, credit.license, locale: locale),
                    size: 12, tracking: 0.1
                )
                .foregroundStyle(Color.ink500)
                Link("skills.credit.original", destination: credit.sourceURL)
                    .font(Typo.text(13))
                    .foregroundStyle(Color.ink700)
                    .underline()
            }
        } else if skill.source == .own {
            SmallCapsLabel("skills.from.own", size: 12, tracking: 0.1)
                .foregroundStyle(Color.ink500)
        } else {
            SmallCapsLabel("skills.from.galeno", size: 12, tracking: 0.1)
                .foregroundStyle(Color.ink500)
        }
    }

    private var markLabel: String {
        agentName.isEmpty
            ? Localized.string("skills.preview.mark.plain", locale: locale)
            : Localized.string("skills.preview.mark %@", agentName, locale: locale)
    }

    /// El rótulo de una fila: versalitas en `ink-500`, en una columna de 118 pt.
    private func label(_ key: String) -> some View {
        SmallCapsLabel(key, size: 12, tracking: 0.12)
            .foregroundStyle(Color.ink500)
            .padding(.top, 3)
            .frame(width: 118, alignment: .leading)
    }

    /// «/acta o «Hazme el acta de la reunión de ayer»».
    private var howToAsk: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(verbatim: skill.command)
                .font(.system(size: 13, design: .monospaced))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Color.parchment200)
                .overlay(Rectangle().strokeBorder(Color.parchment400, lineWidth: 1))
                .fixedSize()
            if let ask = skill.ask?.text(in: language), !ask.isEmpty {
                Text("skills.list.or").foregroundStyle(Color.ink500)
                Text(verbatim: "«\(ask)»")
                    .font(Typo.text(14.5, italic: true))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// La demostración y, debajo, el rótulo que dice que es ilustrativa y el enlace para verla otra vez.
    @ViewBuilder
    private var demo: some View {
        if let example = skill.example {
            VStack(alignment: .leading, spacing: 5) {
                SkillDemoView(skill: skill, example: example, language: language, agentName: speaker)
                    // Alto fijo: caben la pregunta y un resultado de hasta siete líneas sin desplazarse.
                    .frame(height: 276)
                    .id(replays)
                HStack(alignment: .firstTextBaseline) {
                    SmallCapsLabel("skills.preview.illustrative", size: 11, tracking: 0.1)
                        .foregroundStyle(Color.ink500)
                    Spacer(minLength: 8)
                    Button("skills.demo.replay") { replays += 1 }
                        .buttonStyle(InkLinkStyle(size: 12.5))
                }
            }
        } else {
            Text("skills.preview.noExample")
                .font(Typo.text(13.5, italic: true))
                .foregroundStyle(Color.ink500)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(Rectangle().strokeBorder(Color.parchment400, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
        }
    }

    /// Qué necesita y dónde escribe; debajo, en negrita, lo que garantiza (aprobación antes de enviar, o lo suyo).
    private var needs: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: SkillPresentation.needsText(for: skill, language: language, locale: locale))
                .fixedSize(horizontal: false, vertical: true)
            if skill.sendsToOthers {
                Text("skills.preview.approval").font(Typo.text(14.5, .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let guarantee = skill.guarantee?.text(in: language), !guarantee.isEmpty {
                Text(verbatim: guarantee).font(Typo.text(14.5, .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
