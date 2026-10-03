import SwiftUI

/// Los 10 pasos del wizard, en el orden de `docs/03-especificacion-v0.0.1.md` §3.
enum WizardStep: Int, CaseIterable, Identifiable {
    case welcome
    case detection
    case agent
    case tools
    case connect
    case sources
    case skills
    case rules
    case generating
    case done

    var id: Int { rawValue }

    /// 1 a 10.
    var number: Int { rawValue + 1 }

    /// Las claves de `Localizable.xcstrings`.
    var titleKey: String { "step.\(slug).title" }
    var summaryKey: String { "step.\(slug).summary" }

    var title: LocalizedStringKey { LocalizedStringKey(titleKey) }
    var summary: LocalizedStringKey { LocalizedStringKey(summaryKey) }

    /// Mientras se escribe la config no se vuelve atrás: no hay nada que
    /// corregir a medias. En el primer paso tampoco hay a dónde.
    var allowsGoingBack: Bool {
        self != .welcome && self != .generating
    }

    private var slug: String {
        switch self {
        case .welcome: "welcome"
        case .detection: "detection"
        case .agent: "agent"
        case .tools: "tools"
        case .connect: "connect"
        case .sources: "sources"
        case .skills: "skills"
        case .rules: "rules"
        case .generating: "generating"
        case .done: "done"
        }
    }
}
