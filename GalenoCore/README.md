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
| `AgentConfig` | La raíz: nombre del agente, idioma, rol, conexiones, skills y reglas | — |
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
hook de aprobación, los subagentes, las skills). Probado con snapshots de árbol completo en `Tests/Snapshots/`
(`GALENO_RECORD_SNAPSHOTS=1` para regrabarlos).

Los subagentes (`scribe`, `tracker`, `reporter`) salen de `SubagentsRenderer`. Lo que
pueden tocar lo fija su campo `tools`, una lista blanca: lecturas locales y el servidor MCP
de cada herramienta conectada que no puede enviar. Slack y Gmail nunca entran, porque un
servidor se concede entero. Detalle y motivo: `../docs/03-especificacion-v0.0.1.md` §6.

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
