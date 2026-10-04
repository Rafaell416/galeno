/// La memoria del proyecto: el único lugar donde el agente escribe.
///
/// Vive en `memoria/proyecto.md` dentro de la carpeta del agente y `CLAUDE.md`
/// la importa, así que carga en cada sesión. El motor solo la crea, y solo si
/// no existe: de ahí en adelante es del agente (y del usuario), y regenerar la
/// config nunca la toca.
///
/// La carpeta se llama igual en español y en inglés. Las reglas de permisos
/// que la dejan escribir ven una sola ruta, y la ruta no depende del idioma.
///
/// La descripción del proyecto **no** se copia aquí: vive en `AGENTS.md`, que
/// sí se regenera, para que cambiarla en Galeno surta efecto sin pisar nada.
enum MemoryRenderer {
    static let directory = "memoria"
    static let mainFile = "memoria/proyecto.md"
    /// Donde Galeno deja el material que el usuario trajo al crear el agente.
    static let contextDirectory = "memoria/contexto"

    /// Lo que dice la sección de resumen mientras nadie la confirmó. El
    /// `AGENTS.md` cita este mismo texto: así el agente sabe que es su primera
    /// sesión.
    static func unconfirmedMarker(_ language: Language) -> String {
        switch language {
        case .spanish: "Sin confirmar."
        case .english: "Not confirmed yet."
        }
    }

    static func summaryHeading(_ language: Language) -> String {
        switch language {
        case .spanish: "Resumen"
        case .english: "Summary"
        }
    }

    static func renderInitialFile(language: Language) -> String {
        switch language {
        case .spanish:
            """
            # Memoria del proyecto

            Notas que mantiene el agente. Se cargan en cada sesión y Galeno nunca las sobrescribe.

            ## \(summaryHeading(.spanish))

            \(unconfirmedMarker(.spanish))

            ## Quién es quién

            ## Decisiones

            ## Pendientes

            """
        case .english:
            """
            # Project memory

            Notes the agent keeps. They load in every session and Galeno never overwrites them.

            ## \(summaryHeading(.english))

            \(unconfirmedMarker(.english))

            ## Who is who

            ## Decisions

            ## Open items

            """
        }
    }
}
