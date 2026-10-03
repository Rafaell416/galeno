# GalenoCore

El motor: un Swift Package que, a partir de las respuestas del wizard, genera la
configuración de Claude Code del usuario (`AGENTS.md`, `.claude/settings.json`,
`.mcp.json`, subagentes, hooks y skills).

**Fase 2, en curso.** Ya está el modelo de datos (`Sources/GalenoCore/Model/`): `AgentConfig`
representa todo lo que el wizard captura y es la única entrada del generador. El generador
todavía no existe.

```bash
swift build
swift test
```

## El modelo

`AgentConfig` es `Codable` y se puede guardar en disco: **no lleva credenciales**. Los tokens
del usuario nunca pasan por aquí; en `.mcp.json` quedan como referencias a variables de entorno.

| Tipo | Qué representa | Paso del wizard |
|---|---|---|
| `AgentConfig` | La raíz: nombre del agente, idioma, rol, descripción del proyecto, conexiones, skills y reglas | — |
| `Language` · `AgentRole` | Español o inglés; en v0.0.1 solo Product Manager | 1 y 3 |
| `Tool` | Las 10 herramientas, con sus capacidades (`allowsWriting`, `connectionMethod`, `requires`) | 4 |
| `ToolConnection` · `ConnectionStatus` | Estado de cada conexión: marcada, conectada o saltada | 5 |
| `SourceSelection` · `Source` · `SourceKind` | Qué canales, grupos, carpetas o proyectos lee | 6 |
| `SelectedSkill` · `SkillSource` | Las skills marcadas, nuestras o curadas | 7 |
| `SendingRules` | Qué escrituras internas van sin preguntar | 8 |

Dos líneas rojas viven en el sistema de tipos, no en la disciplina:

- `SendingRules` **no puede expresar** un envío externo sin aprobación. No hay propiedad ni
  constructor que ponga Slack o email en `allow`.
- `ExternalSend` no tiene caso de WhatsApp, y `Tool.whatsapp.allowsWriting` es `false`.

## El generador

`Sources/GalenoCore/Generator/` convierte un `AgentConfig` en la configuración de Claude Code
de una carpeta destino (`AGENTS.md`, `CLAUDE.md`, `.claude/settings.json`, `.mcp.json`, el
hook de aprobación, los subagentes, las skills, la memoria). Probado con snapshots de árbol
completo en `Tests/Snapshots/` (`GALENO_RECORD_SNAPSHOTS=1` para regrabarlos).

Los subagentes (`scribe`, `tracker`, `reporter`) salen de `SubagentsRenderer`. Lo que
pueden tocar lo fija su campo `tools`, una lista blanca: lecturas locales y el servidor MCP
de cada herramienta conectada que no puede enviar. Slack y Gmail nunca entran, porque un
servidor se concede entero. Detalle y motivo: `../docs/03-especificacion-v0.0.1.md` §6.

La memoria del proyecto (`memoria/proyecto.md`) la crea el motor una sola vez y **nunca la
sobrescribe**: regenerar la config no la toca, ni a nada más dentro de `memoria/`. Es lo único
que el agente puede escribir sin que nadie lo apruebe. `SettingsRenderer` lo impone con
reglas de permiso por ruta: niega por nombre lo que el motor genera (`protectedPaths`) y
permite `Edit(/memoria/**)`. No se puede negar "todo menos `memoria/`" con una excepción `!`:
Claude Code no reabre un directorio bloqueado entero. Cualquier otra ruta no tiene regla, así
que pide permiso. Si el generador escribe un archivo nuevo fuera de `memoria/`, hay que
añadirlo a `protectedPaths`; un test falla si se olvida.

**Regenerar.** Aplicar el generador sobre una carpeta que ya tiene config la deja igual que una
nueva con la misma config: calcula todo antes de escribir (un error no la deja a medias) y
después quita las skills desmarcadas y el hook que ya no aplica. `GenerationResult.removedFiles`
lista lo quitado.

## La instalación y los agentes

`Sources/GalenoCore/Installation/` es lo que Galeno recuerda entre sesiones, en
`~/Library/Application Support/Galeno/installation.json` (`InstallationStore`; `load()` devuelve
`nil` la primera vez, y un archivo ilegible o de una versión más nueva lanza un error y no se
pisa). Sin secretos.

| Tipo | Qué es |
|---|---|
| `SharedConnection` | Herramienta, estado y `client_id`: se conecta una vez y la comparten todos los agentes |
| `AgentRecord` | Un agente: `id` estable, su `AgentConfig` y la ruta de su carpeta |
| `GalenoInstallation` | El idioma del paso 1, las conexiones compartidas y los agentes |
| `AgentFolder` | `~/Galeno/<agente>/`: nombre saneado, sin choques (`Aurora 2`) |

`startingPoint(agentName:projectDescription:)` arma el `AgentConfig` de un agente nuevo con las
herramientas ya conectadas (base del wizard corto). `resolvedConfig(for:)` devuelve el config del
agente con el estado y el `client_id` tomados de las conexiones compartidas: es lo que se le
pasa al generador, para que haya una sola fuente de verdad.

Las skills no van embebidas en el motor: el generador las copia desde el `skillsDirectory`
que recibe. Eso es lo que permite que en producción vengan de una fuente remota versionada,
con un fallback local (`../docs/03-especificacion-v0.0.1.md` §4f, capa 3). Quién descarga y
llena ese directorio todavía no está diseñado (`../HANDOFF.md` §12).

Para probarlo a mano sin escribir Swift, `swift run galeno-gen` toma un `AgentConfig` en JSON
y una carpeta y genera ahí. Es una herramienta de desarrollo, **no se distribuye**: ver
`../docs/DEV.md`.

**Slack, Gmail y Google Workspace exigen que el cliente traiga su propia app OAuth** —nunca
Galeno—. Para Slack, `Sources/GalenoCore/SlackSetup/` la crea **por API, sin pantallas**:
`SlackManifestRenderer` arma el manifiesto y `SlackAppProvisioner` llama a
`apps.manifest.create`, que devuelve el `client_id`/`client_secret` directamente en la
respuesta. Lo único que Slack no deja evitar por API —generar el primer token de
configuración en `api.slack.com/apps`, su documentación confirma que no hay forma
programática de arrancarlo— **también lo hace la automatización de navegador de Galeno**
(GalenoApp, Fase 4), no el usuario a mano: un solo clic en una sola pantalla, una vez por
workspace. De ahí en adelante `SlackAppProvisioner.rotate(refreshToken:)` lo renueva solo,
sin volver a tocar el navegador.

El `client_id` (no es secreto) se guarda en `ToolConnection.oauthClientID`. El
`client_secret` **nunca entra a `AgentConfig` ni a ningún archivo generado**; pasa por
`GalenoApp` en memoria, una sola vez, directo a `claude mcp add --client-secret`. Detalle de
la decisión: `docs/03-especificacion-v0.0.1.md` §4e.

- Es interno: el usuario nunca lo ve ni lo usa directamente.
- No depende de la UI ni importa SwiftUI; se prueba solo.
- Nunca escribe tokens en texto plano: solo referencias a variables de entorno.

Qué genera: `docs/03-especificacion-v0.0.1.md` §6.
