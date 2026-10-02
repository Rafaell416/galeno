# Desarrollo — `galeno-gen`

Herramienta interna para probar el motor (`GalenoCore`) sin escribir Swift. **No se
distribuye**: GalenoApp (Fase 4) consume `GalenoCore` como librería directamente, nunca
este binario. Es solo para quien trabaja en este repo — no contradice la regla de que
el motor es interno y sin CLI de cara al usuario (ver `AGENTS.md`, líneas rojas).

Recibe un `AgentConfig` en JSON y una carpeta, y genera ahí la configuración de Claude
Code tal como lo haría la app.

## Uso

```bash
swift run --package-path GalenoCore galeno-gen <config.json> <carpeta-destino> [opciones]
```

| Opción | Qué hace | Por defecto |
|---|---|---|
| `--skills-dir <ruta>` | Carpeta con `<galeno\|curated>/<id>/SKILL.md` | Las skills de prueba del repo, `GalenoCore/Tests/Fixtures/skills` |
| `--whatsapp-bridge-path <ruta>` | Ruta del binario del bridge que va en `.mcp.json` | Un valor de ejemplo, el mismo que usan los snapshots |
| `-h`, `--help` | Muestra el uso | — |

El default de `--skills-dir` apunta a los *fixtures* de prueba porque son las únicas
skills que existen hoy (las reales son Fase 5); sirve para probar el generador de punta
a punta, no para ver contenido real.

## Ejemplo

```bash
cat > /tmp/config.json <<'EOF'
{
  "schemaVersion": 1,
  "agentName": "Hipócrates",
  "language": "es",
  "role": "product-manager",
  "connections": [
    { "tool": "notion", "status": "connected",
      "sources": { "readsEverything": true, "selected": [] } }
  ],
  "skills": [{ "id": "prd", "source": "galeno" }],
  "sendingRules": { "internalWrites": { "notion": "allow" } }
}
EOF

swift run --package-path GalenoCore galeno-gen /tmp/config.json /tmp/agente-de-prueba
```

Escribe `AGENTS.md`, `CLAUDE.md`, `.claude/settings.json`, `.mcp.json` y
`.claude/skills/` en `/tmp/agente-de-prueba`, y lista cada archivo que generó. Si algo
no está verificado (un endpoint de MCP) o necesita atención (un `CLAUDE.md` que ya
existía), lo dice al final bajo "Advertencias".

La forma exacta del JSON es la de `AgentConfig` (`GalenoCore/Sources/GalenoCore/Model/`):
la manera más fácil de armar uno de prueba es copiar y adaptar un snapshot existente,
o mirar `GalenoCore/Tests/GalenoCoreTests/GeneratorFixtures.swift`.

## Errores

Sale con código 1 y el motivo en `stderr` si: el archivo de config no existe, no es un
`AgentConfig` válido, falta una skill seleccionada, un id de skill intenta escribir
fuera de la carpeta destino, el nombre del agente está vacío, o falta el `client_id`
de una herramienta que lo exige (Slack, Gmail, Google Workspace — ver `docs/03` §4e).

## Pruebas del motor

`galeno-gen` es para explorar a mano. Lo que de verdad verifica el generador son los
tests, en particular los snapshots:

```bash
swift test --package-path GalenoCore
GALENO_RECORD_SNAPSHOTS=1 swift test --package-path GalenoCore --filter SnapshotTests
```
