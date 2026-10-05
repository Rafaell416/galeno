import GalenoCore
import SwiftUI

/// Lo que el paso «Skills» dice de cada skill, calculado del catálogo: qué le falta, qué necesita y dónde
/// escribe. Es texto puro (se prueba sin vistas) y nunca afirma más que el catálogo.
enum SkillPresentation {
    /// Las herramientas de reuniones: una skill que acepta cualquiera de ellas pide «una herramienta de
    /// reuniones», no una marca. Google Drive cuenta porque ahí caen las transcripciones de Meet.
    static let meetingTools: Set<Tool> = [.fireflies, .granola, .fathom, .googleWorkspace, .googleMeet]

    /// ¿Lo que necesita es «una herramienta de reuniones» (cualquiera de varias)?
    static func needsAMeetingTool(_ skill: CatalogSkill) -> Bool {
        skill.needsAny.count > 1 && skill.needsAny.allSatisfy(meetingTools.contains)
    }

    /// Cómo se nombra una herramienta dentro de una frase: corto. «Google Drive, Docs y Sheets» lleva comas y
    /// rompería una lista.
    static func shortName(_ tool: Tool, in language: Language) -> String {
        tool == .googleWorkspace ? "Google Drive" : tool.displayName(in: language)
    }

    /// «A», «A o B», «A, B o C».
    static func oneOf(_ names: [String], locale: Locale) -> String {
        guard names.count > 1 else { return names.first ?? "" }
        let or = Localized.string("skills.list.or", locale: locale)
        return names.dropLast().joined(separator: ", ") + " \(or) " + names[names.count - 1]
    }

    /// La línea ochre de la card cuando todavía no le sirve: «Falta: herramienta de reuniones».
    static func missingLabel(for skill: CatalogSkill, language: Language, locale: Locale) -> String {
        let what =
            needsAMeetingTool(skill)
            ? Localized.string("skills.missing.meetings", locale: locale)
            : oneOf(skill.needsAny.map { shortName($0, in: language) }, locale: locale)
        return Localized.string("skills.missing %@", what, locale: locale)
    }

    /// «Qué necesita», en la vista previa: la conexión que pide (si pide alguna) y dónde escribe.
    static func needsText(for skill: CatalogSkill, language: Language, locale: Locale) -> String {
        var sentences: [String] = []
        if needsAMeetingTool(skill) {
            // Solo las marcas: Drive está en la lista por Meet, y decir «Google Drive» aquí confundiría.
            let brands = skill.needsAny.filter { $0 != .googleWorkspace && $0 != .googleMeet }
                .map { shortName($0, in: language) }
            sentences.append(
                Localized.string("skills.preview.needs.meetings %@", oneOf(brands, locale: locale), locale: locale))
        } else if !skill.needsAny.isEmpty {
            let names = oneOf(skill.needsAny.map { shortName($0, in: language) }, locale: locale)
            sentences.append(Localized.string("skills.preview.needs.tool %@", names, locale: locale))
        }
        let places = skill.writes.map { shortName($0, in: language) }
        // Solo Slack: no «escribe», publica en el canal del proyecto; y ya se dijo arriba que lo necesita.
        if skill.writes == [.slack] {
            return Localized.string("skills.preview.writes.slack", locale: locale)
        }
        switch places.count {
        case 0: sentences.append(Localized.string("skills.preview.writes.none", locale: locale))
        case 1: sentences.append(Localized.string("skills.preview.writes.one %@", places[0], locale: locale))
        default:
            sentences.append(
                Localized.string("skills.preview.writes.several %@", oneOf(places, locale: locale), locale: locale))
        }
        return sentences.joined(separator: " ")
    }
}

/// El icono de una skill: un dibujo de línea a 1,5 pt (`Assets.xcassets/SkillIcons`), en tinta. Una skill sin
/// dibujo (una que el catálogo traiga después) usa un símbolo genérico en vez de un hueco.
struct SkillIcon: View {
    let id: String
    var size: CGFloat = 20

    static func hasDrawing(_ id: String) -> Bool { NSImage(named: "skill-" + id) != nil }

    var body: some View {
        Group {
            if Self.hasDrawing(id) {
                Image("skill-" + id).renderingMode(.template).resizable().scaledToFit()
            } else {
                Image(systemName: "doc.text").resizable().scaledToFit().padding(size * 0.1)
            }
        }
        .frame(width: size, height: size)
        .foregroundStyle(Color.ink900)
        .accessibilityHidden(true)
    }
}

/// Un enlace de texto en tinta, subrayado: «Vista previa», «Todas», «Cerrar». En este paso los enlaces van en
/// tinta y no en lacre: el único lacre de la pantalla es el punto del título.
struct InkLinkStyle: ButtonStyle {
    var size: CGFloat = 14

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.text(size))
            .foregroundStyle(Color.ink900)
            .underline()
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}
