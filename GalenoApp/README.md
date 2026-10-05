# GalenoApp

La app de Mac, en Swift y SwiftUI. Es lo único que ve el usuario: el wizard de 10 pasos.

**Fase 4, en curso.** Ya están el proyecto Xcode, el esqueleto de los 10 pasos de `docs/03` §3
(navegación, barra de progreso siempre visible, ventana fija de 800×620 centrada) y las pantallas
**1 a 5**: idioma y bienvenida (el idioma cambia toda la app en caliente), detección de Claude
Code, tu agente, la grilla de herramientas y el sub-wizard de conexión (MCP hospedados con
`claude mcp`, y WhatsApp con QR). Slack crea **su propia app OAuth** (guía + token pegado en un campo seguro; Gmail y Google siguen para después). Los pasos 6 a 10 siguen como marcadores y se llenan uno a
uno. Las decisiones de las pantallas están en `docs/03` §3.

```bash
make -C whatsapp-bridge universal   # antes de compilar: la app empaqueta el bridge
```

```bash
xcodebuild -project GalenoApp/Galeno.xcodeproj -scheme Galeno -destination 'platform=macOS' build
xcodebuild -project GalenoApp/Galeno.xcodeproj -scheme Galeno -destination 'platform=macOS' -only-testing:GalenoTests test
```

O abrir `Galeno.xcodeproj` en Xcode y ⌘R con destino **My Mac**.

## Estructura

| Ruta | Qué es |
|---|---|
| `Galeno/GalenoApp.swift` | La app: una sola `Window` de 800×620, centrada y sin redimensionar |
| `Galeno/Theme.swift` | Tokens de `docs/04` §10: colores dinámicos claro/oscuro, New York, espaciado |
| `Galeno/Wizard/WizardStep.swift` | Los 10 pasos, en orden, con su título y si permiten volver |
| `Galeno/Wizard/WizardState.swift` | `ObservableObject` con las respuestas; `makeConfig()` produce el `AgentConfig` |
| `Galeno/Wizard/WizardView.swift` | Contenedor: barra de progreso, paso actual, Atrás / Siguiente |
| `Galeno/Wizard/Steps/` | Una vista por pantalla (1–4 construidas; 5–10 marcadores) |
| `Galeno/Wizard/ToolEstimate.swift`, `ToolIcon.swift` | Minutos por herramienta y su logo |
| `Galeno/System/ClaudeCodeDetector.swift` | Busca `claude`, su versión y si hay sesión; `ProcessRunner` corre comandos cortos con tiempo máximo |
| `Galeno/System/LongRunningProcess.swift` | `ManagedProcess` (hijo cancelable, con terminal opcional) y `ProcessRegistry` (mata todo al cerrar la app) |
| `Galeno/System/ClaudeMCP.swift` | `claude mcp get/add/login` y el dato real con `claude -p` |
| `Galeno/System/OAuthSecret.swift`, `SlackAppSetup.swift` | El `client_secret` en memoria (no se imprime ni se guarda) y la creación de la app de Slack |
| `Galeno/System/SlackTokenCapture.swift`, `Wizard/Connect/SlackSignIn.swift` | La ventana de inicio de sesión de Slack: el script de captura, sus reglas (solo `api.slack.com`, solo `https`, Google bloqueado) y el modelo |
| `Galeno/System/WhatsAppBridge.swift` | El contrato con el bridge, `BridgeInstaller` (copia a ruta estable) y vincular/sincronizar |
| `Galeno/Wizard/Connect/` | El sub-wizard del paso 5: `ConnectFlow` (máquina de estados) y sus pantallas |
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
- En Debug, argumentos de arranque: `-galeno-claude-missing` finge que `claude` no está
  instalado; `-galeno-fake-connect` pone conectores con guion en el paso 5 (éxito, dato tardío,
  un fallo en Fathom, QR que rota, sincronización) sin tocar cuentas; con él,
  `-galeno-fake-name-clash` deja `notion` y `slack` ocupados por otro servidor del usuario para ver
  la pregunta de qué hacer; `-galeno-bridge-path <ruta>` usa otro binario del bridge; `-galeno-skills-path <ruta>` (o `GALENO_SKILLS_PATH`)
  usa otra carpeta de skills. Con `-galeno-fake-connect`, generar el agente escribe en una carpeta temporal
  (nunca en `~/Galeno`) y «abrir» no lanza nada.
- El bridge se compila aparte y una fase de Run Script lo copia a `Contents/Resources`; sin él
  la compilación avisa (Debug) o falla (Release).
- Diseño: nativo primero. Ver `docs/04-design-system.md`.

Flujo del wizard: `docs/03-especificacion-v0.0.1.md` §3.
