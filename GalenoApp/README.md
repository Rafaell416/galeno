# GalenoApp

La app de Mac, en Swift y SwiftUI. Es lo único que ve el usuario: el wizard de 10 pasos.

**Fase 4, en curso.** Ya están el proyecto Xcode, el esqueleto de los 10 pasos de `docs/03` §3
(navegación, barra de progreso siempre visible, ventana fija de 720×560 centrada) y las pantallas
**1 a 4**: idioma y bienvenida (el idioma cambia toda la app en caliente), detección de Claude
Code, tu agente y la grilla de herramientas. Los pasos 5 a 10 siguen como marcadores y se
llenan uno a uno. Las decisiones de las pantallas 1–4 están en `docs/03` §3.

```bash
xcodebuild -project GalenoApp/Galeno.xcodeproj -scheme Galeno -destination 'platform=macOS' build
xcodebuild -project GalenoApp/Galeno.xcodeproj -scheme Galeno -destination 'platform=macOS' -only-testing:GalenoTests test
```

O abrir `Galeno.xcodeproj` en Xcode y ⌘R con destino **My Mac**.

## Estructura

| Ruta | Qué es |
|---|---|
| `Galeno/GalenoApp.swift` | La app: una sola `Window` de 720×560, centrada y sin redimensionar |
| `Galeno/Theme.swift` | Tokens de `docs/04` §10: colores dinámicos claro/oscuro, New York, espaciado |
| `Galeno/Wizard/WizardStep.swift` | Los 10 pasos, en orden, con su título y si permiten volver |
| `Galeno/Wizard/WizardState.swift` | `ObservableObject` con las respuestas; `makeConfig()` produce el `AgentConfig` |
| `Galeno/Wizard/WizardView.swift` | Contenedor: barra de progreso, paso actual, Atrás / Siguiente |
| `Galeno/Wizard/Steps/` | Una vista por pantalla (1–4 construidas; 5–10 marcadores) |
| `Galeno/Wizard/ToolEstimate.swift`, `ToolIcon.swift` | Minutos por herramienta y su logo |
| `Galeno/System/ClaudeCodeDetector.swift` | Busca `claude`, su versión y si hay sesión; lanza procesos con tiempo máximo |
| `THIRD_PARTY.md` | Origen y licencia de los logos |
| `Galeno/Localizable.xcstrings` | Textos en español e inglés |
| `GalenoTests/` | Pruebas unitarias (XCTest). `GalenoUITests/` existe pero no corre en CI |

## Decisiones del proyecto

- **macOS 14.0 mínimo**, Swift 6, **sin App Sandbox** (la app lanza procesos y escribe en
  `~/Galeno` y `~/Library/LaunchAgents`), hardened runtime activado.
- **Firma ad hoc, sin equipo de desarrollo**, para que compile igual en cualquier Mac y en CI.
  La firma y la notarización reales llegan en la Fase 8.
- **Bundle id provisional** `com.galeno.Galeno`, a juego con la etiqueta del LaunchAgent del
  bridge (`com.galeno.whatsapp-bridge`). Se alinean cuando haya uno definitivo.
- `GalenoCore` entra como paquete local (`../GalenoCore`). La app no duplica su lógica: el
  wizard solo arma un `AgentConfig` y se lo pasa al generador.

## Reglas

- Consume `GalenoCore` para generar la config; no duplica su lógica.
- Lanza y supervisa el binario de `whatsapp-bridge` y registra los MCP hospedados con `claude mcp add`.
- Textos en español e inglés, siempre por `Localizable.xcstrings`. Los textos de dopamina los
  escribe Rafa: están marcados `TODO(dopamina)` (`grep -rn "TODO(dopamina)" GalenoApp`).
- El idioma cambia en caliente con `\.locale`: no usar `String(localized:)`.
- En Debug, `-galeno-claude-missing` como argumento de arranque finge que `claude` no está
  instalado, para ver esa pantalla en un Mac que sí lo tiene.
- Diseño: nativo primero. Ver `docs/04-design-system.md`.

Flujo del wizard: `docs/03-especificacion-v0.0.1.md` §3.
