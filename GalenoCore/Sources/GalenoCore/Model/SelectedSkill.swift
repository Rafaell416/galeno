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
/// Dos niveles del catálogo, los dos revisados por nosotros antes de entrar: no
/// existe ninguna puerta por la que entre código de terceros sin revisar. "Trae la
/// tuya" —pegar un link de GitHub— sigue fuera. Lo que sí entra, con alcance
/// acotado (decisión de Rafa, 6 oct 2026, `docs/03` §6.3), son las **propias** del
/// usuario: archivos de su propio Mac, para su propio agente.
public enum SkillSource: String, Codable, CaseIterable, Sendable {
    /// Las nuestras, en `skills/`. Escritas en inglés, con la instrucción de
    /// responder en el idioma del usuario.
    case galeno
    /// De terceros, seleccionadas y revisadas por nosotros, con crédito y link
    /// a su autor.
    case curated
    /// Del propio usuario: una carpeta con `SKILL.md` (o un `.md` suelto) que
    /// trajo de su Mac. Vive en `skills-propias/<id>/` dentro de la carpeta del
    /// agente (``OwnSkills``) —el motor nunca la toca al regenerar, como
    /// `memoria/`— y se instala desde ahí a `.claude/skills/<id>/`. Nada
    /// remoto, ni de terceros, ni catálogo. Una skill propia no cambia ningún
    /// permiso: las reglas `deny`, el `ask` y los hooks aplican aunque la skill
    /// diga lo contrario, y enviar sigue preguntando.
    case own
}
