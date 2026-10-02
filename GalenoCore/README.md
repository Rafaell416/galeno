# GalenoCore

El motor: un Swift Package que, a partir de las respuestas del wizard, genera la
configuración de Claude Code del usuario (`AGENTS.md`, `.claude/settings.json`,
`.mcp.json`, subagentes, hooks y skills).

**Fase 2.** El paquete ya compila y corre sus pruebas, pero todavía no tiene comportamiento:
`GalenoCore.swift` solo expone la versión. La lógica se escribe en esa fase.

```bash
swift build
swift test
```

- Es interno: el usuario nunca lo ve ni lo usa directamente.
- No depende de la UI ni importa SwiftUI; se prueba solo.
- Nunca escribe tokens en texto plano: solo referencias a variables de entorno.

Qué genera: `docs/03-especificacion-v0.0.1.md` §6.
