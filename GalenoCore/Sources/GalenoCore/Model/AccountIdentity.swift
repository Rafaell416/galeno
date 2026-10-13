import Foundation

/// Cómo se identifica una conexión: la herramienta y, si el usuario tiene más de una cuenta de ella, cuál.
///
/// `account == nil` es **la cuenta de siempre** de esa herramienta: la que se conectó antes de que existieran las
/// cuentas, o la única. Así lo ya guardado se lee igual y no hay nada que migrar.
public struct ConnectionID: Hashable, Sendable, Codable {
    public var tool: Tool
    /// El identificador de la cuenta (`AccountID.slug(from:)`), o `nil` si es la cuenta por defecto.
    public var account: String?

    public init(tool: Tool, account: String? = nil) {
        self.tool = tool
        self.account = account
    }
}

/// El identificador de una cuenta extra de una herramienta.
///
/// Acaba dentro del nombre del servidor MCP (`galeno-notion-trabajo`), y ese nombre se interpola en las reglas de
/// permiso y en el patrón del hook de aprobación. Por eso solo admite minúsculas, dígitos y guiones: nada que un
/// patrón pueda interpretar de otra manera.
public enum AccountID {
    /// Lo más largo que puede ser un identificador: el nombre del servidor lo lleva dentro y se escribe a mano en
    /// `claude mcp list`.
    public static let maxLength = 24

    /// Lo que el usuario escribió («Trabajo», «Mi cuenta personal») convertido en un identificador estable
    /// (`trabajo`, `mi-cuenta-personal`). `nil` si no queda nada utilizable.
    public static func slug(from name: String) -> String? {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "en_US"))
            .lowercased()
        var slug = ""
        var lastWasDash = true
        for scalar in folded.unicodeScalars {
            if (scalar >= "a" && scalar <= "z") || (scalar >= "0" && scalar <= "9") {
                slug.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if !lastWasDash {
                slug.append("-")
                lastWasDash = true
            }
        }
        while slug.hasSuffix("-") { slug.removeLast() }
        if slug.count > maxLength {
            slug = String(slug.prefix(maxLength))
            while slug.hasSuffix("-") { slug.removeLast() }
        }
        return slug.isEmpty ? nil : slug
    }

    /// ¿Es un identificador que se puede escribir tal cual en un nombre de servidor?
    public static func isValid(_ id: String) -> Bool {
        guard !id.isEmpty, id.count <= maxLength, !id.hasPrefix("-"), !id.hasSuffix("-") else { return false }
        return id.unicodeScalars.allSatisfy { ($0 >= "a" && $0 <= "z") || ($0 >= "0" && $0 <= "9") || $0 == "-" }
    }
}

extension Tool {
    /// ¿Se puede tener más de una cuenta de esta herramienta en el mismo agente?
    ///
    /// Solo las que **Galeno registra** en Claude Code con su propio nombre (`galeno-notion`): ahí una cuenta
    /// extra es otro servidor con su nombre. No entra WhatsApp (un solo dispositivo vinculado), ni los
    /// conectores de la cuenta de Claude (Gmail, Calendar, Drive, Docs y Sheets: el nombre lo pone Claude y
    /// hoy es una sola cuenta de Google por cuenta de Claude), ni Claude Design (su endpoint no está documentado).
    public var supportsMultipleAccounts: Bool {
        switch self {
        case .slack, .notion, .jira, .fireflies, .granola, .fathom: true
        case .whatsapp, .googleWorkspace, .gmail, .googleMeet, .claudeDesign, .googleCalendar: false
        }
    }
}
