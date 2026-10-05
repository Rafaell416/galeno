import SwiftUI

/// Los pasos del asistente (rediseño «Activación», `docs/03` §3). El usuario ve **seis**: rol, cuenta de
/// Claude, nombre, herramientas, reglas y creación (`phase`); varios de aquí son momentos de un mismo paso
/// («Tus herramientas» y «Conectar»; «Revisión», «Creando» y «Listo»). «Skills» ya no está en el camino de
/// crear un agente (las fija el rol): solo en «Gestionar».
enum WizardStep: Int, CaseIterable, Identifiable {
    case role
    case detection
    case agent
    case tools
    case connect
    case skills
    case rules
    case review
    case generating
    case done

    /// El paso que el usuario ve: los momentos de un mismo paso comparten número.
    var phase: Int {
        switch self {
        case .role: 0
        case .detection: 1
        case .agent: 2
        case .tools, .connect: 3
        case .skills: 4
        case .rules: 5
        case .review, .generating, .done: 6
        }
    }

    var id: Int { rawValue }

    /// Las claves de `Localizable.xcstrings`.
    var titleKey: String { "step.\(slug).title" }
    /// Desde el paso 6 el resumen habla del agente por su nombre: la clave lleva un argumento.
    var summaryKey: String {
        switch self {
        case .skills, .rules: "step.\(slug).summary %@"
        default: "step.\(slug).summary"
        }
    }

    /// El título de la página, cuando no es el rótulo corto de la cabecera («Tu rol» arriba, «¿En qué trabajas?»
    /// en la página).
    var headingKey: String {
        switch self {
        case .role, .agent, .tools: "step.\(slug).heading"
        default: titleKey
        }
    }
    /// El signo que cierra el título, en lacre: un punto, salvo en la pregunta del rol.
    var headingMark: String { self == .role ? "?" : "." }

    var title: LocalizedStringKey { LocalizedStringKey(titleKey) }
    var heading: LocalizedStringKey { LocalizedStringKey(headingKey) }
    var summary: LocalizedStringKey { LocalizedStringKey(summaryKey) }

    /// Mientras se escribe la config no se vuelve atrás: no hay nada que
    /// corregir a medias. (En el primer paso tampoco hay a dónde: lo decide `WizardState.canGoBack`.)
    var allowsGoingBack: Bool {
        self != .generating
    }

    var slug: String {
        switch self {
        case .role: "role"
        case .detection: "detection"
        case .agent: "agent"
        case .tools: "tools"
        case .connect: "connect"
        case .skills: "skills"
        case .rules: "rules"
        case .review: "review"
        case .generating: "generating"
        case .done: "done"
        }
    }
}
