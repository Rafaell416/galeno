/// Una skill que el usuario dejó marcada en el paso 7 del wizard.
public struct SelectedSkill: Codable, Hashable, Sendable, Identifiable {
    /// El id de la skill: `prd`, `informe-slack`. Para las curadas, el id con
    /// el que aparece en nuestro catálogo.
    public var id: String

    /// De dónde sale. El motor lo necesita para saber de dónde copiarla y, en
    /// las curadas, a quién acreditar.
    public var source: SkillSource

    public init(id: String, source: SkillSource) {
        self.id = id
        self.source = source
    }
}

/// El origen de una skill.
///
/// En v0.0.1 solo hay dos niveles, los dos revisados por nosotros antes de
/// entrar al catálogo: no existe ninguna puerta por la que entre código sin
/// revisar. "Trae la tuya" —pegar un link de GitHub— llega en v0.2 con su
/// propio guardrail.
public enum SkillSource: String, Codable, CaseIterable, Sendable {
    /// Las nuestras, en `skills/`. Escritas en inglés, con la instrucción de
    /// responder en el idioma del usuario.
    case galeno
    /// De terceros, seleccionadas y revisadas por nosotros, con crédito y link
    /// a su autor.
    case curated
}
