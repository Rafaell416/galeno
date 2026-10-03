# AGENTS.md — Galeno

Guía para el agente que trabaja en este repo. Contexto de producto: `HANDOFF.md`.
Fuente de verdad: `docs/03-especificacion-v0.0.1.md`. Si algo aquí la contradice, gana la spec.

## Qué es

App nativa de Mac que, con un wizard, crea y configura un agente en Claude Code para
Product Managers. La app orquesta procesos locales: genera la config, lanza un binario Go
para WhatsApp (solo lectura) y registra MCP hospedados con `claude mcp add`.

## Stack

- **Swift + SwiftUI**: la app y el motor que genera la config.
- **Go**: un único binario para WhatsApp (puente `whatsmeow` + servidor MCP read-only).
- **Nada más**: ni Python, ni Node, ni Rust, ni contenedor web dentro de la app.
- **Sparkle** para las actualizaciones de la app (framework estándar de Mac fuera del App
  Store). Va desde el primer build. Ver `docs/03` §4f.
- Los MCP hospedados (Notion, Slack, Gmail, Drive, Jira, Fireflies, Granola, Fathom) no se
  empaquetan: se conectan por OAuth contra los servidores de cada proveedor.

## Estructura

```
GalenoApp/         App SwiftUI: wizard, pantallas, localización ES/EN, supervisión de procesos
GalenoCore/        Motor: paquete Swift que genera la config a partir de las respuestas del wizard
whatsapp-bridge/   Fork de lharries/whatsapp-mcp: binario Go con puente + MCP read-only
skills/            Skills del perfil PM (nuestras) y el catálogo de curadas
site/              Sitio web de venta
docs/              Plan, perfil, especificación y design system
```

Límites entre carpetas:

- `GalenoApp/` no contiene lógica de generación de config; la pide a `GalenoCore/`.
- `GalenoCore/` no importa SwiftUI ni depende de la UI; se prueba solo.
- `whatsapp-bridge/` es autocontenido; habla con Claude Code por stdio y con la app como
  proceso hijo.
- `skills/` es contenido, no código de la app; el motor lo copia a la config del usuario.
  No se hornea en el binario: se publica como fuente remota versionada, con un fallback
  local (`docs/03` §4f, capa 3).

## Comandos

`GalenoCore/` ya tiene comportamiento (el generador de config). `whatsapp-bridge/` también:
el puente (lectura de WhatsApp) y las 9 herramientas MCP de solo lectura, con subcomandos
`pair`/`sync`/`serve`/`status`/`install-launchd` — ver `whatsapp-bridge/README.md`.
`GalenoApp/` aún no tiene proyecto Xcode: ese comando es el previsto. El CI corre los jobs `swift` y `go` en cada PR y
en cada push a `main` (`.github/workflows/ci.yml`).

`GalenoCore` tiene además `galeno-gen`, una herramienta de desarrollo para probar el
generador a mano (un `AgentConfig` en JSON → una carpeta con la config). **No se
distribuye** —no es "la CLI del producto"—; ver `docs/DEV.md`.

```bash
# Motor
swift build --package-path GalenoCore
swift test  --package-path GalenoCore

# App
xcodebuild -project GalenoApp/Galeno.xcodeproj -scheme Galeno build
xcodebuild -project GalenoApp/Galeno.xcodeproj -scheme Galeno test

# Bridge de WhatsApp
cd whatsapp-bridge && go build ./... && go vet ./... && go test ./...
make -C whatsapp-bridge universal   # build universal arm64+amd64 (requiere macOS + Xcode)

# Verificación de solo lectura: no debe devolver nada. El test de símbolos
# (go test, arriba) ya corre esto cada vez, acotado al binario compilado;
# esta es la versión de texto para revisar el código fuente a mano.
grep -rnE 'client\.SendMessage\(|client\.Upload\(|/api/send|MarkRead|SendPresence|SendChatPresence' whatsapp-bridge --include="*.go"

# Búsqueda de secretos antes de commitear
git diff --cached | grep -nEi "token|secret|api[_-]?key|xox[bp]-|BEGIN [A-Z ]*PRIVATE KEY"
```

## Reglas

### Secretos

- Nunca commitear tokens, claves, `.env`, sesiones de WhatsApp ni bases SQLite del puente.
- Ningún token del usuario se envía a infraestructura propia. No se añade telemetría,
  analítica ni backend que reciba credenciales o contenido del usuario.
- La config generada nunca lleva tokens en texto plano: solo referencias a variables de entorno.
- **`client_id` no es secreto** (es un identificador público, como un nombre de usuario) y sí
  puede vivir en texto plano en `AgentConfig` y en `.mcp.json` — es el caso de Slack, Gmail y
  Google Workspace, cuya app OAuth trae el propio cliente. El **`client_secret` nunca entra a
  este modelo ni a ningún archivo generado**: Claude Code lo guarda en el keychain del sistema.
- **Única excepción, documentada a propósito:** `SlackAppProvisioner` (crea la app de Slack
  del cliente por API) sí recibe el `client_secret` de vuelta en la respuesta de Slack, en
  memoria. Quien lo llame tiene que entregarlo de inmediato a `claude mcp add
  --client-secret` y descartarlo — nunca escribirlo, nunca loggearlo, nunca guardarlo en una
  propiedad que sobreviva más de esa llamada. Sigue sin tocar infraestructura propia (no sale
  de la máquina del usuario); es Galeno viéndolo de paso, no reteniéndolo.
- Los fixtures de prueba usan valores falsos evidentes.
- La clave privada EdDSA de Sparkle y la de licencias viven fuera del repo. Nunca se
  commitean, ni siquiera cifradas.

### Actualizaciones

- Tres capas independientes (`docs/03` §4f): la app por Sparkle, el bridge dentro de la app
  pero con versión propia, y las skills desde una fuente remota.
- El appcast y las skills remotas son **solo descargas**. No se les añade nada que suba
  datos del usuario: ni perfil del sistema, ni identificadores, ni conteos de uso.
- Las skills remotas siguen siendo solo nuestras y curadas, revisadas antes de publicarse.
  Que sean remotas no abre la puerta a contenido de terceros sin revisar.
- Cambiar una skill no exige build nuevo de la app; cambiar el bridge sí sube su versión.

### WhatsApp

- Nunca añadir herramientas de envío al bridge. Ni detrás de un flag, ni desactivadas,
  ni "para pruebas". El solo lectura es estructural: el código de envío no existe.
- Al sincronizar con upstream, revisar que no reentren `send_message`, `send_file` ni
  `send_audio_message`.
- Conservar los avisos de licencia MIT del fork.
- No tocar el texto de advertencia de la pantalla de vinculación sin que Rafa lo apruebe.

### Flujo de trabajo

- Todo cambio va por rama + PR. Nada directo a `main`.
- Ramas cortas y con un solo propósito: `feat/…`, `fix/…`, `docs/…`, `chore/…`.
- El PR describe qué cambia, por qué, y cómo se verificó.
- No commitear ni hacer push sin que Rafa lo pida.
- Repo: `github.com/Rafaell416/galeno` (privado), rama por defecto `main`. La única
  excepción a rama + PR fue el commit inicial.
- **`main` no está protegida en GitHub**: la protección de ramas en repos privados exige
  plan Pro. Nada del lado del servidor impide un push directo, así que la regla se sostiene
  por disciplina. No la aproveches: abre un PR igual.

### Código

- La app consume el motor y no duplica su lógica.
- Los textos de la UI van en `Localizable.strings`, en español e inglés. Los textos de
  dopamina se escriben nativos en cada idioma, no traducidos literalmente.
- Las skills nuestras se escriben en inglés, con la instrucción de idioma arriba.
- UI: nativo primero. Controles de macOS, SF Symbols, serif del sistema (New York), tokens
  de color de `docs/04-design-system.md`. Sin fuentes embebidas, sin texturas, sin
  controles custom que imiten lo antiguo.
- El motor se prueba con respuestas del wizard como entrada y la config esperada como salida.
- Lo que se distribuye va firmado y notarizado, incluido el binario Go.

### Skills y licencias

- Solo dos niveles: nuestras y curadas. Toda skill curada se revisa antes de entrar y
  lleva crédito y link a su autor.
- Bases permitidas: `product-on-purpose/pm-skills` (Apache 2.0), `phuryn/pm-skills` (MIT),
  `snarktank/ralph` (MIT).
- Prohibido usar `deanpeters/Product-Manager-Skills` (CC BY-NC-SA, no comercial).
- Antes de incorporar código o contenido de terceros, verificar su licencia.

## Líneas rojas

Parar y preguntar a Rafa antes de hacer cualquiera de estas cosas, aunque parezca razonable:

1. Enviar por WhatsApp, en cualquier forma.
2. Hacer que un token o un dato del usuario salga de su máquina hacia servidores nuestros.
3. Permitir un envío externo (Slack, email) sin aprobación humana, o debilitar la regla
   `ask` o el hook de aprobación en la config generada.
4. Empaquetar Python, Node o cualquier runtime en la app.
5. Dar a los subagentes generados Bash o edición de código.
6. Abrir una puerta a código no revisado ("trae tu skill", plugins de terceros sin revisar).
7. Reabrir una decisión cerrada: nombre, precio, solo PM, solo Mac, Swift, Go para
   WhatsApp, solo Claude Code.
8. Construir algo fuera de v0.0.1: multi-proyecto, otras plantillas, Windows, soporte
   para Codex/Cursor/Grok, marketplace, CLI de cara al usuario.
9. Prometer en la UI o en el sitio que WhatsApp es "seguro" u "oficial", o que hay
   cumplimiento garantizado.

## Cuando haya dudas

- Si los documentos se contradicen: gana `docs/03`, y se corrige el otro en el mismo PR.
  `HANDOFF.md` §2 lista las alternativas ya descartadas; no proponerlas de nuevo.
- Si cambia una decisión: actualizar `docs/03`, los documentos que la mencionen y `HANDOFF.md`.
- Si algo no está decidido: revisar `HANDOFF.md` §12 y preguntar; no inventar.
- Si un cambio toca una regla innegociable: no se hace sin confirmación explícita.
