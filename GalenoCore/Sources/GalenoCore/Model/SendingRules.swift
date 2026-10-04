/// Qué puede hacer el agente sin preguntar (paso 8 del wizard).
///
/// Los envíos externos —un mensaje a Slack, un correo— **siempre** requieren
/// aprobación humana, y este tipo no tiene forma de expresar lo contrario: no
/// hay propiedad ni constructor que los ponga en ``ApprovalPolicy/allow``. Es
/// una línea roja del producto, así que vive en el sistema de tipos y no en la
/// disciplina de quien escriba la UI.
///
/// Lo único configurable son las escrituras internas: un borrador en el Notion
/// del propio usuario, un ticket en su Jira. Un PRD mal redactado en su propio
/// espacio se corrige; un correo mal enviado a un cliente, no.
public struct SendingRules: Codable, Hashable, Sendable {
    /// Documenta la línea roja en el código. Siempre `true`.
    public static let externalAlwaysRequiresApproval = true

    /// La política de cada escritura interna. Lo que falte se lee como
    /// ``ApprovalPolicy/ask``, que es el default seguro.
    public var internalWrites: [InternalWrite: ApprovalPolicy]

    public init(internalWrites: [InternalWrite: ApprovalPolicy] = [:]) {
        self.internalWrites = internalWrites
    }

    /// La política de una escritura interna. ``ApprovalPolicy/ask`` si no se
    /// fijó, para que una config incompleta nunca abra permisos de más.
    public func policy(for write: InternalWrite) -> ApprovalPolicy {
        internalWrites[write] ?? .ask
    }

    public mutating func setPolicy(_ policy: ApprovalPolicy, for write: InternalWrite) {
        internalWrites[write] = policy
    }

    /// Siempre ``ApprovalPolicy/ask``. No existe el setter equivalente: ver la
    /// nota del tipo.
    public func policy(for send: ExternalSend) -> ApprovalPolicy {
        .ask
    }

    /// Lo que trae el wizard de fábrica: nada externo sin preguntar (fijo), y
    /// las escrituras internas permitidas.
    public static let `default`: SendingRules = {
        var rules = SendingRules()
        for write in InternalWrite.allCases {
            // Claude Design puede borrar archivos (`delete_files`): de fábrica pregunta.
            rules.setPolicy(write == .claudeDesign ? .ask : .allow, for: write)
        }
        return rules
    }()
}

/// Las escrituras que se quedan dentro del mundo del usuario, y que por eso son
/// de bajo riesgo.
public enum InternalWrite: String, Codable, CaseIterable, Sendable {
    case notion
    case jira
    case googleDocs = "google-docs"
    case googleSheets = "google-sheets"
    /// Crear, editar o borrar archivos en los proyectos de Claude Design del propio usuario.
    case claudeDesign = "claude-design"
}

/// Lo que sale hacia afuera, hacia otras personas.
///
/// No hay caso de WhatsApp a propósito: el bridge no tiene herramientas de
/// envío, así que no es una posibilidad que haya que gobernar.
public enum ExternalSend: String, Codable, CaseIterable, Sendable {
    case slackMessage = "slack-message"
    case email
    /// Crear, cambiar o borrar un evento, o responder a una invitación: les llega a los invitados.
    case calendarEvent = "calendar-event"
}

public enum ApprovalPolicy: String, Codable, CaseIterable, Sendable {
    /// Requiere aprobación humana antes de ejecutarse.
    case ask
    /// Se ejecuta sin preguntar.
    case allow
}

/// Para que `[InternalWrite: ApprovalPolicy]` codifique como un objeto JSON.
/// Sin esto, `Dictionary` lo escribiría como un array de claves y valores
/// alternados, porque la clave no es `String` ni `Int`.
extension InternalWrite: CodingKeyRepresentable {}
