/// El idioma que el usuario elige en el paso 1 del wizard.
///
/// Define el idioma de la app y el que el motor inyecta en la config generada,
/// con la instrucción explícita de responder y generar los documentos en ese
/// idioma. Eso evita que el agente devuelva un PRD en inglés solo porque el
/// ticket de Jira estaba en inglés.
///
/// Las skills nuestras se escriben siempre en inglés, sin importar este valor:
/// la instrucción de idioma va arriba de cada una.
public enum Language: String, Codable, CaseIterable, Sendable {
    case spanish = "es"
    case english = "en"

    /// El nombre del idioma en su propio idioma, para el selector del paso 1.
    public var nativeName: String {
        switch self {
        case .spanish: "Español"
        case .english: "English"
        }
    }
}
