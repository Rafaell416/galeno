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
`GalenoApp/` ya tiene proyecto Xcode con el esqueleto del wizard (pantallas vacías por ahora).
El CI corre los jobs `swift`, `go`, `go-universal` y `app` en cada PR y en cada push a `main`
(`.github/workflows/ci.yml`); `app` corre solo `GalenoTests`, no los UI tests.

`GalenoCore` tiene además `galeno-gen`, una herramienta de desarrollo para probar el
generador a mano (un `AgentConfig` en JSON → una carpeta con la config). **No se
distribuye** —no es "la CLI del producto"—; ver `docs/DEV.md`.

```bash
# Motor
swift build --package-path GalenoCore
swift test  --package-path GalenoCore

# App (-only-testing: los UI tests piden entorno gráfico y no corren en CI)
xcodebuild -project GalenoApp/Galeno.xcodeproj -scheme Galeno -destination 'platform=macOS' build
xcodebuild -project GalenoApp/Galeno.xcodeproj -scheme Galeno -destination 'platform=macOS' -only-testing:GalenoTests test

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
- Un agente es una carpeta (`~/Galeno/<agente>/`); varios proyectos son varios agentes.
  Galeno es el dueño de la config: guarda las respuestas del wizard y regenera los archivos
  completos. Lo único que el motor nunca toca al regenerar es `memoria/`.
- Regenerar deja la carpeta idéntica a una nueva con la misma config (`ConfigGenerator` calcula
  todo antes de escribir; un error no la deja a medias). Las conexiones, la lista de agentes y
  sus carpetas viven en `GalenoInstallation`; el estado y el `client_id` de cada herramienta se
  toman de ahí (`resolvedConfig`), no del `AgentConfig` del agente.
- El agente generado no ejecuta código y solo escribe archivos dentro de `memoria/`. Eso
  lo imponen reglas de permiso por ruta (`SettingsRenderer`), que niegan por nombre lo que
  el motor genera. Si el generador empieza a escribir un archivo nuevo fuera de `memoria/`,
  hay que añadirlo a `SettingsRenderer.protectedPaths`; un test falla si se olvida.
- El bridge de WhatsApp es de solo lectura y el agente ve todos los chats sincronizados: no
  hay lista de chats permitidos (se descartó: obligaba a volver a sincronizar cada vez que
  aparecía un grupo nuevo). Lo que lo protege es que no existe código de envío.
- Los textos de la UI van en `Localizable.xcstrings` (String Catalog), en español e inglés,
  con claves simbólicas (`step.agent.title`), nunca el texto a mano en la vista. El idioma
  cambia en caliente con `\.locale`: **no usar** `String(localized:)` ni `NSLocalizedString`
  (no lo siguen); los nombres de herramienta salen de `Tool.displayName(in:)`.
- Logos de terceros solo monocromos y con licencia verificada, listados en
  `GalenoApp/THIRD_PARTY.md`.
- El `client_secret` y los tokens de configuración viven en un `OAuthSecret` (no es `Codable`,
  se oculta en `print`/`dump`, se borra al terminar). Nunca en un `String` que se guarde, y las
  credenciales de `GalenoCore` ya ocultan sus secretos en `description` y en el espejo.
- **La única vista web de la app** es la ventana de inicio de sesión de Slack
  (`SlackSignInWindow`, decidida por Rafa; `docs/03` §4e). La interfaz sigue siendo nativa: "ni
  contenedor web" se refiere a no hacer la app con tecnología web. Esa ventana cumple siempre:
  sesión efímera (`WKWebsiteDataStore.nonPersistent()`); el script de captura solo actúa en
  `api.slack.com` y nunca lee campos de contraseña; el token va a un `OAuthSecret`, no al
  portapapeles; el dominio está a la vista; el inicio de sesión de Google se bloquea (no se
  esquiva su política); y no se aceptan cookies ni términos por el usuario. Añadir otra vista
  web, o relajar cualquiera de estas condiciones, exige preguntar antes.
- Un agente de navegador con un modelo (Claude con `--chrome`) **nunca ve un secreto**; para
  Slack se probó y se descartó (`docs/03` §4e).
- Procesos hijo (`claude`, el bridge): un secreto va **solo** por el entorno del `Process`
  (`MCP_CLIENT_SECRET`), nunca en argumentos, logs ni archivos. Los hijos de larga duración se
  lanzan con `ManagedProcess` (queda en `ProcessRegistry` y muere con la app). La app **no
  ejecuta scripts remotos** (`curl … | bash`): muestra el comando y lo corre el usuario.
- El bridge se usa desde su copia estable en `~/Library/Application Support/Galeno/bin/`, no
  desde dentro de `Galeno.app` ni de DerivedData (`BridgeInstaller`). Compilarlo antes que la
  app: `make -C whatsapp-bridge universal` (una fase de Run Script lo copia a `Resources`). Los textos de
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
5. Dar a los subagentes generados Bash o edición de código, o dejar que el agente
   generado escriba archivos fuera de `memoria/`.
6. Abrir una puerta a código no revisado ("trae tu skill", plugins de terceros sin revisar).
7. Reabrir una decisión cerrada: nombre, precio, solo PM, solo Mac, Swift, Go para
   WhatsApp, solo Claude Code.
8. Construir algo fuera de v0.0.1: separación garantizada de contexto entre agentes,
   vista transversal, tareas programadas, ver
   actividad, otras plantillas, Windows, soporte para Codex/Cursor/Grok, marketplace, CLI
   de cara al usuario. Crear varios agentes, uno por proyecto, **sí** es v0.0.1
   (`docs/03` §3b).
9. Prometer en la UI o en el sitio que WhatsApp es "seguro" u "oficial", o que hay
   cumplimiento garantizado.

## Cuando haya dudas

- Si los documentos se contradicen: gana `docs/03`, y se corrige el otro en el mismo PR.
  `HANDOFF.md` §2 lista las alternativas ya descartadas; no proponerlas de nuevo.
- Si cambia una decisión: actualizar `docs/03`, los documentos que la mencionen y `HANDOFF.md`.
- Si algo no está decidido: revisar `HANDOFF.md` §12 y preguntar; no inventar.
- Si un cambio toca una regla innegociable: no se hace sin confirmación explícita.
