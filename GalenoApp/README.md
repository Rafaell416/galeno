# GalenoApp

La app de Mac, en Swift y SwiftUI. Es lo único que ve el usuario: el wizard de 10 pasos.

**Fase 4, en curso.** Ya está el proyecto Xcode y el esqueleto del wizard: los 10 pasos de
`docs/03` §3 como pantallas vacías con su título, navegación adelante/atrás, barra de progreso
siempre visible y ventana fija de 720×560 centrada. Cada pantalla se llena en un paso aparte.

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
| `Galeno/Wizard/Steps/` | Una vista por pantalla (hoy placeholders) |
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
- Textos en español e inglés, siempre por `Localizable.xcstrings`.
- Diseño: nativo primero. Ver `docs/04-design-system.md`.

Flujo del wizard: `docs/03-especificacion-v0.0.1.md` §3.
