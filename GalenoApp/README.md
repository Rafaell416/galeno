# GalenoApp

La app de Mac, en Swift y SwiftUI. Es lo único que ve el usuario: el wizard de 10 pasos.

**Fase 4.** El proyecto Xcode se crea en esa fase; por ahora la carpeta está vacía.

- Consume `GalenoCore` para generar la config; no duplica su lógica.
- Lanza y supervisa el binario de `whatsapp-bridge` y registra los MCP hospedados con `claude mcp add`.
- Textos en español e inglés (`Localizable.strings`).
- Diseño: nativo primero. Ver `docs/04-design-system.md`.

Flujo del wizard: `docs/03-especificacion-v0.0.1.md` §3.
