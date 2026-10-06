# AGENTS.md — Galeno

Guía para el agente que trabaja en este repo. Contexto de producto: `HANDOFF.md`.
Fuente de verdad: `docs/03-especificacion-v0.0.1.md`. Si algo aquí la contradice, gana la spec.

## Qué es

App nativa de Mac que, con un wizard, crea y configura un agente en Claude Code para
gente de producto, marketing y comercial (tres roles; decisión de Rafa, 5 oct 2026). La app orquesta procesos locales: genera la config, lanza un binario Go
para WhatsApp (solo lectura) y registra MCP hospedados con `claude mcp add`.

## Stack

- **Swift + SwiftUI**: la app y el motor que genera la config.
- **Go**: un único binario para WhatsApp (puente `whatsmeow` + servidor MCP read-only).
- **Nada más**: ni Python, ni Node, ni Rust, ni contenedor web dentro de la app.
- **Sparkle** para las actualizaciones de la app (framework estándar de Mac fuera del App
  Store). Va desde el primer build. Ver `docs/03` §4f.
- Los MCP hospedados (Notion, Slack, Jira, Fireflies, Granola, Fathom, y Claude Design, que es la excepción: su endpoint no está documentado, ver `docs/03`) no se
  empaquetan: se conectan por OAuth contra los servidores de cada proveedor.
- **Gmail, Google Drive/Docs/Sheets y Google Calendar** van por los conectores de la cuenta de Claude del usuario (`docs/03` §4e):
  Galeno no registra nada ni trae app OAuth; solo guía al usuario a conectarlos y escribe sus reglas de permiso.
  El estado de un conector se lee con `ClaudeSessionProbe` (el arranque de una sesión real), **nunca con `claude mcp get`**,
  que da por conectado uno al que le falta la autorización.
  El sondeo arranca sin la caché de descubrimiento y esperando a que los servidores conecten (`ClaudeSessionProbe.environment`):
  sin eso, un conector que el usuario ya tenía conectado sale `pending` o ni aparece. Un arranque sin ningún `claude.ai …` se
  vuelve a mirar antes de decir «no está en la cuenta», y `pending` nunca se trata como «falta autorizar» **ni como
  «conectado»**: solo cuenta un `connected` de verdad, o que el usuario pulse «Ya lo conecté, comprobar» (`confirmConnector`).
  El paso del tiempo nunca marca un conector (demo de Aquiles, 5 oct 2026).
  En la app de Claude (escritorio) los conectores se encienden por conversación y nada del proyecto los enciende:
  el `AGENTS.md` generado le dice al agente cómo encender **solo los suyos**; los demás de la cuenta se heredan apagados.
  Allí sus herramientas se llaman `mcp__<uuid>__…` y ninguna regla de permiso coincide: lo cubren dos hooks por nombre de
  herramienta (`SettingsRenderer.desktopConnectorPrefix`): aprobación para todo lo que no sea una lectura conocida, y paso
  libre **solo a lecturas**. No añadir escrituras al hook de lecturas; la única excepción, decidida con las tareas programadas
  (`docs/03` §3b, 5 oct 2026), son los **borradores de Gmail** (`create_draft`, `update_draft`, `MCPServerDefinition.draftTools`):
  van en su **propio** hook de paso libre, con nombres exactos, porque un borrador queda en el buzón del propio usuario y no le
  llega a nadie (es como una corrida nocturna deja un correo listo). `delete_draft` y los envíos siguen preguntando. «Abrir en la app de Claude» es el botón principal.
  Las listas de herramientas del catálogo son las vistas en una cuenta real; una nueva de Google cae en el hook hasta revisarla.
  El comando de un hook va siempre entre comillas (`SettingsRenderer.hookCommand`): la carpeta del agente puede llevar espacios.
  No registrar la URL del servidor de Google (`*.googleapis.com/mcp/v1`) en `.mcp.json`: pide una app de Google Cloud (`docs/03` §4e).

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
`pair`/`sync`/`serve`/`status` (con `--json`)/`unlink`/`install-launchd` — ver `whatsapp-bridge/README.md`.
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
  puede vivir en texto plano en `AgentConfig` y en `.mcp.json` — es el caso de Slack, cuya app
  OAuth trae el propio cliente. El **`client_secret` nunca entra a
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

- El bridge todavía **no descarga adjuntos** (`download_media` solo mira lo que ya está en disco). Su mensaje y el `AGENTS.md`
  generado lo dicen tal cual; no volver a un texto que mande a «reintentar».
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
- **Galeno registra sus conexiones con nombre propio** (`galeno-notion`, `galeno-slack`…; `MCPServerCatalog.defaultNamePrefix`,
  `ToolConnection.serverNamePrefix`), nunca con el genérico (decisión de Rafa, 5 oct 2026). Los servidores de Claude Code son de
  **todo el usuario**: cerrar su sesión (`claude mcp logout`) o quitarlo (`claude mcp remove -s user`) lo desconecta en cualquier
  otro proyecto que use el mismo nombre y dirección (a Rafa se le cayó Notion en su agente de MediClub). **Regla de propiedad:
  Galeno solo cierra sesión o quita lo que lleva su prefijo (`galenoOwnsServers`)**; un servidor con el nombre genérico no se mira,
  no se registra, no se autoriza y no se desconecta, ni en el instalador ni en los scripts. Antes de pedir (o de escribir un script
  que haga) cualquier `logout` o `remove` de alcance de usuario, se mira qué proyectos lo usan (`~/.claude.json`, `.mcp.json`) y se
  avisa de que afecta a todos. **Galeno nunca borra ni pisa un servidor MCP del usuario sin preguntar** (`docs/03` §3, pantalla 5).
  Las conexiones guardadas antes de este cambio (sin prefijo) siguen con su nombre. Lo que Galeno no registra en Claude Code
  (WhatsApp, los conectores de la cuenta de Claude) no lleva prefijo.
- Un agente es una carpeta (`~/Galeno/<agente>/`); varios proyectos son varios agentes.
  Galeno es el dueño de la config: guarda las respuestas del wizard y regenera los archivos
  completos. Lo único que el motor nunca toca al regenerar es `memoria/`; la excepción es el material que el usuario trae al crear el agente (paso 3, «Traer contexto»), que el motor deja en `memoria/contexto/` solo si ese archivo no existe, y el que añade después desde la sección «Contexto» del detalle (`ContextFolder`: cada uno toma el siguiente número libre y nunca pisa a otro; quitar uno lo manda a la **Papelera**, nunca lo borra). Ese material es dato de terceros: no va en `AgentConfig` ni en el borrador, y nunca se escribe en `AGENTS.md`.
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
  `GalenoApp/THIRD_PARTY.md`. Lo mismo vale para las **fuentes embebidas** (EB Garamond y Cormorant
  Garamond, OFL), los **grabados** de las láminas y el **retrato**: nada entra sin licencia y crédito
  anotados ahí.
- El `client_secret` y los tokens de configuración viven en un `OAuthSecret` (no es `Codable`,
  se oculta en `print`/`dump`, se borra al terminar). Nunca en un `String` que se guarde, y las
  credenciales de `GalenoCore` ya ocultan sus secretos en `description` y en el espejo.
- **Las únicas vistas web de la app** son las dos ventanas de Slack, decididas por Rafa
  (`docs/03` §4e): la de inicio de sesión (`SlackSignInWindow`) y la de autorización de la app
  (`SlackAuthorizeWindow`), que comparten una sesión efímera en memoria (`SlackWebSession`) que se
  descarta al terminar la conexión. La de autorización solo abre páginas `https` de `slack.com` y
  la vuelta exacta `http://localhost:51820/callback` (`SlackAuthorization`); la dirección le llega
  por la variable `BROWSER` del proceso `claude mcp login` (`BrowserInterceptor`: script en una
  carpeta 0700 de `$TMPDIR`, solo `https`), y cualquier dirección que no sea de Slack se abre en el
  navegador del sistema como siempre. Las demás herramientas no se tocan. La interfaz sigue siendo nativa: "ni
  contenedor web" se refiere a no hacer la app con tecnología web. Esa ventana cumple siempre:
  sesión efímera (`WKWebsiteDataStore.nonPersistent()`); el script de captura solo actúa en
  `api.slack.com` y nunca lee campos de contraseña; el token va a un `OAuthSecret`, no al
  portapapeles; el dominio está a la vista; el inicio de sesión de Google se bloquea (no se
  esquiva su política); y no se aceptan cookies ni términos por el usuario. Añadir otra vista
  web, o relajar cualquiera de estas condiciones, exige preguntar antes.
- Las demás herramientas con OAuth en el navegador (Notion, Jira, Fathom, Fireflies, Granola) se autorizan en el **navegador
  predeterminado del usuario** (decisión de Rafa, 5 oct 2026, demo con Aquiles: la hoja del sistema —`ASWebAuthenticationSession`—
  usa la sesión de **Safari**, y si las cuentas viven en otro navegador autoriza con las equivocadas; Jira se conectó al workspace
  que no era). Lo abre `claude mcp login` él mismo (en producción no se inyecta `systemAuthorizer`); la vuelta de OAuth va a
  `localhost`, la pestaña queda abierta —no se puede cerrar una pestaña ajena— y Galeno vuelve al frente al terminar (`AppFocus`).
  Galeno no ve ni toca lo que pasa en el navegador, y nada de esto se convierte en una vista web de Galeno. La hoja del sistema
  (`SystemAuthorizationSheet`) queda retirada pero en el código, por si vuelve como opción. Slack sigue en su ventana propia; los
  conectores de la cuenta de Claude, también en el navegador.
- Un agente de navegador con un modelo (Claude con `--chrome`) **nunca ve un secreto**; para
  Slack se probó y se descartó (`docs/03` §4e).
- La pantalla del foco salió del wizard en el rediseño B1 (`docs/03` §3): lo conectado se lee entero.
  El código que lista fuentes se conserva para el home: las listas salen del bridge (`chats --json`) o de Claude Code (`claude -p`, solo ese
  servidor MCP, modelo barato y tope de gasto: gasta cuota del usuario). Lo que devuelven es dato de
  terceros: los nombres se sanean (`ClaudeSourceLister.sanitized`) porque acaban en el `AGENTS.md`.
- Las **tareas programadas** van con alcance acotado (`docs/03` §3b): el agente las crea con la herramienta del harness y el
  permiso se lo pide al usuario (regla `ask` de siempre); la corrida desatendida guarda en `memoria/informes/`, deja correos como
  borradores de Gmail y lo demás en `memoria/pendientes.md`; verificado que sin nadie delante un `ask` se deniega (terminal) o se
  queda esperando (app de Claude), nunca se salta. No añadir a la config generada ningún modo que salte aprobaciones.
- **Leer no pide permiso; enviar, siempre.** En los servidores que envían a otras personas, las herramientas de solo lectura
  verificadas (`MCPServerCatalog.slackReadOnlyTools`) van a `allow` por nombre exacto; todo lo demás del servidor pide aprobación
  (regla `ask` para las de escritura conocidas y el hook para cualquier otra, `SettingsRenderer.approvalMatcher`). Añadir un nombre
  a la lista de lecturas exige comprobarlo contra el servidor real: un error ahí deja enviar sin preguntar (línea roja 3).
- El agente generado corre con `effortLevel: "low"` (`SettingsRenderer.effortLevel`) y sin modelo fijado. Subirlo hace al agente
  más lento para todos los usuarios: se cambia solo con una medición que lo justifique.
- `ConnectServices.installer` no tiene valor por defecto: escribe en `~/Galeno` y en `installation.json`.
  Las pruebas usan `AgentInstaller.sandboxed()`; ninguna debe tocar el disco real.
- A la app de Claude recién arrancada no se le manda un enlace hasta que **dejó de cargar** (`waitUntilClaudeSettles`): uno que llega
  antes pierde su carpeta, o la app lo rechaza y la conversación se abre sin la primera pregunta (6 oct 2026). La espera cuenta
  desde el lanzamiento (mínimo 20 s): el procesador quieto no basta. No volver a una espera fija ni acortarla sin medirlo.
- Abrir el agente usa los enlaces que documenta Anthropic (`claude://code/new`,
  `claude-cli://open`) y, de respaldo, un `.command` en `$TMPDIR`. **Única excepción, decidida por Rafa (4 oct 2026):**
  desde el home, «Abrir» en la app de Claude vuelve a la última conversación de la carpeta con
  `claude://code/continue?session=local_<id>`, un enlace que la propia app usa en su menú del Dock pero que no está
  documentado. El id sale de `ClaudeSessionStore`, que lee en solo lectura la carpeta de datos de la app de Claude y solo
  cuatro campos (`sessionId`, `cwd`, `isArchived`, `lastActivityAt`); nunca títulos ni conversaciones. Si algo falla o
  no hay sesión, se abre una nueva con el enlace documentado. **Desde el home y el detalle no se escribe ninguna pregunta**
  (decisión de Rafa, 6 oct 2026); solo la pantalla «Listo» abre con la primera pregunta escrita. No ampliar lo que se lee de esa carpeta. **Segunda excepción, decidida por
  Rafa (4 oct 2026):** al *eliminar* un agente, `AgentRemover` manda a la **Papelera** (nunca borra) su carpeta, la carpeta de proyecto de
  Claude Code que corresponde a esa ruta y las sesiones de la app de Claude cuyo `cwd` es esa carpeta, tras una confirmación que lo lista.
  La carpeta solo si está dentro de `~/Galeno` y no es un enlace; jamás `~/.claude.json`. Nada se escribe dentro de la
  carpeta del agente y nada se ejecuta con datos que no sean la ruta (citada) y el texto sugerido.
  Único caso en que Galeno cierra otra app: si el agente usa conectores de la cuenta de Claude y la app de Claude lleva
  abierta desde antes, «Abrir en la app de Claude» le pide salir (como Cmd+Q, nunca matarla) y la reabre en el agente,
  avisándolo antes en la pantalla (`docs/03` §4e). Si no sale, **no se abre el agente en la app que quedó**: se le dice al
  usuario que la cierre (`AgentOpenOutcome.claudeDidNotQuit`). **Segundo momento, decidido por Rafa (4 oct 2026):** si «Gestionar»
  le cambió las herramientas a un agente y la app de Claude lleva abierta desde antes, «Abrir» desde el home hace lo mismo
  (salir, reabrir y volver a su conversación), porque la conversación abierta arrancó con las herramientas de antes; el aviso de
  la tarjeta dice ese motivo (`AgentOpenPolicy.RestartReason.toolsChanged`, anotado en `Prefs.toolsChangedAt`). Guardar sin
  cambiar las herramientas no reinicia nada, y en Terminal nunca. No extenderlo a otras apps ni a otros momentos.
- Procesos hijo (`claude`, el bridge): un secreto va **solo** por el entorno del `Process`
  (`MCP_CLIENT_SECRET`), nunca en argumentos, logs ni archivos. Los hijos de larga duración se
  lanzan con `ManagedProcess` (queda en `ProcessRegistry` y muere con la app). La app **no
  ejecuta scripts remotos**, con **una excepción decidida por Rafa (5 oct 2026):** el instalador oficial de Claude Code
  (`ClaudeCodeSetup`), que sirve para instalarlo y para actualizarlo. Sus límites no se relajan sin preguntar: la dirección
  (`https://claude.ai/install.sh`) está fija en el código, solo `https`, sin `sudo`, y solo tras el clic del usuario en
  «Instalar» o «Actualizar». Nada se instala al abrir la app, y ninguna otra cosa se descarga y ejecuta.
- **Claude Code lo deja listo Galeno** (paso 2 y la puerta «Antes de conectar» del wizard corto y de «Gestionar»): instalar,
  actualizar (versión mínima `ClaudeCodeDetector.minimumVersion`; se usa el `claude` más nuevo del Mac) e iniciar sesión
  (`claude auth login`, en el navegador del usuario). El usuario no ve comandos ni la Terminal, y no se sigue hasta que esté
  listo. Nunca mostrar ni guardar lo que imprime `claude auth login`. `ConnectServices.claudeSetup` no hace nada por defecto
  (`NoClaudeCodeSetup`): el de verdad solo lo pone `live()`, para que ninguna prueba instale nada.
- Un error dice su causa real cuando se conoce (`MCPConnectError.claudeOutdated`, sin internet…), no una genérica que mande
  a buscar donde no es. En «Conectar», los iconos de la tira llevan a cada conexión (`ConnectFlow.jump`): la que se deja a
  medias no queda saltada y se vuelve a ella antes de terminar.
- El bridge se usa desde su copia estable en `~/Library/Application Support/Galeno/bin/`, no
  desde dentro de `Galeno.app` ni de DerivedData (`BridgeInstaller`). Compilarlo antes que la
  app: `make -C whatsapp-bridge universal` (una fase de Run Script lo copia a `Resources`). Los textos de
  dopamina se escriben nativos en cada idioma, no traducidos literalmente.
- Las skills nuestras se escriben en inglés, con la instrucción de idioma arriba.
- **Skills propias del usuario** (`docs/03` §6.3): viven en `skills-propias/<id>/` de la carpeta del agente
  (`OwnSkills`), que es del usuario como `memoria/`: el motor **nunca** la escribe ni la borra; solo instala desde
  ahí las marcadas (`SkillSource.own`) a `.claude/skills/`. La app las copia al crear o guardar
  (`AgentInstaller.install(ownSkills:ownSkillsToTrash:)`, `OwnSkillImporter`): solo archivos locales del selector,
  nada se descarga ni se ejecuta, y quitar una la manda a la Papelera. El agente no puede editarlas
  (`protectedPaths`). No añadir ninguna forma de traerlas por enlace, catálogo ni descarga sin preguntar a Rafa.
- UI: el rediseño B1 «El impresor» (`docs/04` §12) manda en la app. Ventana estándar de macOS,
  SF Symbols y tokens de color de `docs/04`, pero **con fuentes embebidas** (Cormorant y EB Garamond,
  vía `Typo` en `Typography.swift`; New York solo como respaldo), **controles propios** de tinta
  (`InkButtonStyle`, `InkControls`, `RuleProgress`: usar estos, no `.bordered` ni `.borderedProminent`),
  **láminas** de grabado de línea (`Plate`, `PortraitMark`; nunca junto a formularios, errores ni la
  advertencia de WhatsApp) y un **grano** tenue que se apaga con `GalenoGrainEnabled`. El lacre
  (`seal-700`) aparece como máximo una vez por pantalla. Todo movimiento (`Motion.swift`) tiene su
  alternativa en «Reducir movimiento». Ninguna otra textura, ornamento de relleno ni control que
  imite lo antiguo. **La referencia es el archivo `Galeno B1 Impresor.dc.html` del proyecto de Claude
  Design** (medidas, disposición y textos). **Desde el 6 oct 2026 (Rafa), todo diseño que se pase es una guía y no una
  camisa de fuerza**: se toman la estructura, los patrones, el copy y los flujos, y se construye con los componentes, tokens
  y micro-interacciones que Galeno ya tiene, para que siga viéndose y sintiéndose Galeno; donde el diseño choca con la app
  real (la ventana fija, un servicio que ya existe, una regla de este archivo) se adapta y se dice. Esquinas rectas.
  La ventana es fija, de **800 × 620 pt** (`WindowMetrics`; decisión de Rafa, 5 oct 2026). Los archivos de Claude Design
  siguen dibujados a 720 × 560: mandan en disposición y proporciones, no en el tamaño exacto (`docs/04` §12).
- El texto de la UI sigue el copy v2 de `docs/04` §12: botones con verbo, el nombre del agente desde
  el paso 3, errores en tres partes y sin signos de exclamación. La advertencia de WhatsApp no se
  reescribe; cambiarle la presentación no es cambiarle el texto.
- El borrador del asistente (`draft.json`, `WizardDraft`) **nunca lleva credenciales**: solo lo mismo que un
  `AgentConfig`. Las pruebas usan `MemoryDraftStore`; ninguna escribe el disco real.
- El home (`HomeModel`) lee la instalación con `InstallationStore.load()` y no escribe nunca. Ilegible = error visible con
  «Reintentar»: no se sobrescribe ni se vuelve al wizard en silencio. «Abrir» y «Listo» comparten `AgentOpenPolicy`; no
  duplicar la lógica de reiniciar la app de Claude.
- **El detalle del agente** (`AgentDetailView`, `AgentDetailModel`; diseño «Galeno B1 Agente», 6 oct 2026) es donde se
  gestiona un agente: un clic en su tarjeta o en «Gestionar» lo abre, con cinco secciones (General, Herramientas, Skills, Reglas,
  Contexto) y «Abrir» siempre arriba. Sin pasos ni «Siguiente»: rol, reglas y herramientas se aplican **al momento** (se vuelve a
  escribir la carpeta del mismo agente por `AgentInstaller`; `memoria/` no se toca), y skills y contexto, al guardar. No duplica
  lo que ya existe: abrir, renombrar y eliminar son los del `HomeModel`; el estado de las herramientas, reconectar y re-vincular
  WhatsApp, los del `HealthModel`; el catálogo de skills, el del asistente. **«Quitar» tiene dos intenciones**: «Quitar de este
  agente» (la cuenta sigue conectada) y «Desconectar la cuenta», que **solo** existe si los servidores son de Galeno
  (`galeno-…`, `AgentDetailModel.canDisconnectAccount`) y quita **esos** (`claude mcp remove`) para todos los agentes que la
  usan, regenerándolos; un conector de la cuenta de Claude, WhatsApp o un servidor con el nombre genérico de otro proyecto del
  usuario nunca se desconectan desde aquí (regla de propiedad). **Eliminar** pide escribir el nombre del agente y manda a la
  Papelera lo de siempre (`AgentRemover`); **no** quita conexiones, que son compartidas. «Añadir herramienta» **conecta ahí mismo**:
  elegir una abre su conexión (la de siempre, `ConnectFlow`, en un `WizardState` en modo «Gestionar» que solo hospeda el flujo)
  encima del detalle; al quedar conectada se guarda en el agente y su fila entra a la lista (la nueva, al final). Las skills se
  marcan y se guardan en el propio detalle con las mismas cards del asistente (`SkillsStepView`, versión embebida).
- «Gestionar» como asistente (`WizardState.Mode.edit`) sigue existiendo para conectar herramientas nuevas: regenera la carpeta **del
  mismo agente** y la Revisión avisa antes de guardar que lo editado a mano se pierde y que `memoria/` no se toca. No pasar contexto
  traído (`importedContext`) al guardar, y no habilitarlo si la carpeta no existe.
- La vista de salud (`HealthModel`, `docs/03` §3b) **diagnostica y solo actúa si el usuario lo pide**: «Reconectar» una herramienta y
  «Re-vincular» WhatsApp. El estado de un **conector de la cuenta de Claude** nunca sale de `claude mcp list` (lo da por conectado sin
  estarlo): sale del arranque de una sesión (`ClaudeSessionProbe`). Si no se pudo averiguar, se dice «Sin saber», jamás «Conectada».
  Reconectar no pisa un servidor ajeno con el mismo nombre ni registra a ciegas una herramienta con app OAuth propia (Slack: se rehace
  desde «Gestionar»). Re-vincular WhatsApp enseña antes la advertencia de siempre (el mismo texto) y, para cerrar la sesión, detiene `sync`
  y corre `unlink`; **no borra** `messages.db`. El aviso de rotación (18 días, «~20») es una estimación: sin fecha de vinculación leída
  por el bridge no se avisa. «Actualizar skills» es solo el punto de entrada (`SkillUpdating`) hasta la Fase 5.
- Una carpeta de agente borrada a mano nunca tumba el home: se ofrece «Regenerar la carpeta» (misma ruta, tras confirmar, sin pisar si
  reapareció) o «Quitar el agente» (el diálogo de Eliminar).
- La vista previa del `AGENTS.md` (`AgentPreview`) es solo lectura: devuelve texto y no escribe nada.
- El asistente sigue el rediseño «Activación» (`docs/03` §3; archivo `Galeno B1 Activación.dc.html` de Claude Design): **manda en estructura y
  textos, no en estilo**, que sigue siendo el de B1 (decisión de Rafa, 5 oct 2026). Siete pasos a la vista (`WizardStep.phase`); antes, tres
  pantallas que se ven una sola vez (`OnboardingView`, `Prefs.onboardingSeen`). El **rol** (`AgentRole`: producto, marketing, comercial) fija las
  skills que vienen marcadas (`SkillCatalog.defaultSelection(for:)`) y el orden de las herramientas (`AgentRole.toolOrder`); el paso
  «Skills» sigue al crear un agente (el boceto lo quitaba; Rafa lo pidió de vuelta). La preselección de herramientas del rol nunca pisa lo que el usuario marcó. «Darle contexto» va
  después del nombre y antes de las herramientas, y es opcional. Una espera larga usa `WaitingTicker`, no una rueda sola: sus frases
  dicen cosas ciertas pase lo que pase y **nunca fingen un avance que Galeno no conoce**. El agente se «crea», no se «escribe». Una pantalla nueva no promete lo
  que la app todavía no hace (p. ej. «se cambia después» para el rol).
- Cuatro sonidos en toda la app (`Sounds`): una conexión lograda, algo que falló, el sello al llegar a «Listo» y, desde el 6 oct 2026 (petición de Rafa), un toque suave al pulsar «Siguiente» desde el onboarding y en el asistente (`paso.wav`). Breves, a volumen bajo, **encendidos de fábrica** y con un solo interruptor en Ajustes. No se añaden otros: nada suena en casillas, «Atrás» ni copiar. Suenan igual al conectar en el asistente, al «Reconectar»
  o «Re-vincular» desde Salud, y sea cual sea la autorización (hoja del sistema, navegador o ventana de Slack); mirar el estado o cancelar no suena.
- El paso «Skills» (y «Gestionar» → Skills) se construye desde el archivo **`Galeno B1 Skills.dc.html`** del proyecto de Claude Design: cards
  en una lista por grupos que se desplaza (la variante «scroll»; Rafa la eligió sobre las pestañas) y una hoja de vista previa. Lo que dicen las cards y la vista previa sale de `skills/catalog.json`
  (`SkillPresentation`) y **nunca afirma más que el catálogo**. La vista previa lleva una demostración animada (`SkillDemoView`: se escribe
  la pregunta, el agente «lee» y sale el resultado con su formato): es **ilustrativa**, sus textos se escriben a mano en el catálogo, no
  llama a ningún modelo, y el rótulo «Ejemplo ilustrativo · no se ejecuta nada» va siempre a la vista. Responde el agente del usuario por
  su nombre: no usar la marca ni el logo de Claude ahí. No ejecutar nada para producir el ejemplo. Los iconos de skill (`Assets.xcassets/SkillIcons`) son dibujos propios de línea, sin metadatos incrustados. Las
  skills de la comunidad no se muestran; las de Anthropic entran revisadas, con licencia y crédito, en el grupo de su rol
  (hoy «Marketing»). Las tarjetas salen de `SkillCatalog.cards` y cada una sabe de dónde se instala (`CatalogSkill.source`):
  no escribir `.galeno` a mano en la vista. Toda skill con tarjeta lleva su dibujo propio (una prueba lo exige): el símbolo genérico es solo el respaldo de una
  que llegue por el catálogo remoto antes que su dibujo.
- **Lo que SwiftUI o AppKit llaman fuera del hilo principal no puede heredar el aislamiento del actor principal** (la app lo lleva por
  defecto, `SWIFT_DEFAULT_ACTOR_ISOLATION`): el color dinámico del tema (`Color.dynamic`) es `nonisolated` porque el renderizado asíncrono de
  macOS 15 lo resuelve en `com.apple.SwiftUI.DisplayLink`, y con el aislamiento heredado la app se caía (`EXC_BREAKPOINT`) al pasar de las
  pantallas previas al asistente. Un cierre nuevo que reciba AppKit/SwiftUI se prueba en un hilo de fondo (`ThemeColorTests`). Se
  prueba también en un Mac con **macOS 15**: en el de desarrollo (macOS 26) no se vio.
- Los glifos de sección (`Glyphs.swift`) son dibujos propios de línea a 1,5 pt; cuelgan en el margen junto al título de algunos pasos y nunca van en la misma fila que un SF Symbol.
- El movimiento lee `\.galenoReduceMotion` (sistema **o** «Menos movimiento» de Ajustes), no
  `\.accessibilityReduceMotion`. Cada ventana lleva `.motionPreference()` en su raíz.
- Una cita de Galeno solo entra a la interfaz si está verificada en su fuente; las apócrifas circulan mucho.
- El motor se prueba con respuestas del wizard como entrada y la config esperada como salida.
- Lo que se distribuye va firmado y notarizado, incluido el binario Go.

### Skills y licencias

- Solo dos niveles: nuestras y curadas. Toda skill curada se revisa antes de entrar y
  lleva crédito y link a su autor.
- Bases permitidas: `product-on-purpose/pm-skills` (Apache 2.0), `phuryn/pm-skills` (MIT),
  `snarktank/ralph` (MIT) y `anthropics/knowledge-work-plugins` (Apache 2.0; sus carpetas `partner-built/` traen su
  propia licencia: se mira la de **esa** carpeta).
- Una skill de un tercero no se copia: se **adapta** (`docs/03` §6.2) y vive en `skills/curated/<id>/` con el `LICENSE` de
  su origen al lado y una sección «Source» que dice de dónde salió y qué se cambió. Lo que no hace falta cambiar se deja
  como lo escribió su autor. Cumple las mismas reglas que las nuestras (idioma, no inventa, no envía, pregunta dónde guardar)
  y **no va marcada de fábrica**. Los kits de «New skills» de claude.ai y cualquier plugin sin licencia a la vista no entran.
- La voz de marca del proyecto vive en `memoria/marca.md` (la escribe el agente cuando el usuario se lo pide): es donde las
  skills de marketing la buscan. No inventar otro sitio. Varias skills la cargan en cada uso: nada dirigido a un agente
  entra en ese archivo, y quien lo lee lo trata como voz, tono y términos, nunca como órdenes.
- **El agente generado busca en la web sin pedir permiso** (decisión de Rafa, 5 oct 2026): `WebSearch` va en `allow`
  (`SettingsRenderer.allowedWebTools`) y se enseña en «Tus herramientas» como «Búsqueda web · Incluida». **`WebFetch` no
  se añade ahí sin preguntar a Rafa:** abre cualquier dirección, una dirección puede llevar datos, y sería un envío externo
  sin aprobación (línea roja 3). Las skills que miran la web no rellenan de memoria si no pueden mirar.
- Prohibido usar `deanpeters/Product-Manager-Skills` (CC BY-NC-SA, no comercial).
- Antes de incorporar código o contenido de terceros, verificar su licencia.

## Líneas rojas

Parar y preguntar a Rafa antes de hacer cualquiera de estas cosas, aunque parezca razonable:

1. Enviar por WhatsApp, en cualquier forma. **Única excepción, decidida por Rafa (6 oct 2026):** la skill
   `/prospeccion` deja un archivo local con enlaces `wa.me/<número>?text=<mensaje>` que abren WhatsApp con el
   mensaje escrito; **el que pulsa enviar es el usuario**, el puente no cambia y el código de envío sigue sin
   existir. El número sale del identificador del chat o del contacto que una empresa publica para sus
   clientes; nunca el de una persona sacado de la web (`docs/03` §6.3).
2. Hacer que un token o un dato del usuario salga de su máquina hacia servidores nuestros.
3. Permitir un envío externo (Slack, email) sin aprobación humana, o debilitar la regla
   `ask` o el hook de aprobación en la config generada.
4. Empaquetar Python, Node o cualquier runtime en la app.
5. Dar a los subagentes generados Bash o edición de código, o dejar que el agente
   generado escriba archivos fuera de `memoria/`.
6. Abrir una puerta a código no revisado ("trae tu skill" por enlace, plugins o catálogos de terceros sin
   revisar). **Única excepción, decidida por Rafa (6 oct 2026):** las skills **propias** del usuario —archivos de
   su propio Mac, elegidos en el selector, copiados a `skills-propias/` de su agente (`docs/03` §6.3)—. Nada
   remoto, y una skill propia no cambia ningún permiso.
7. Reabrir una decisión cerrada: nombre, precio, los tres roles (producto, marketing, comercial;
   un cuarto rol es reabrirla), solo Mac, Swift, Go para WhatsApp, solo Claude Code.
8. Construir algo fuera de v0.0.1: separación garantizada de contexto entre agentes,
   vista transversal, tareas programadas **con envío desatendido** (las de alcance acotado —leer,
   escribir en `memoria/`, escrituras internas, envíos solo como borrador— ya están construidas:
   decisión de Rafa, 5 oct 2026, `docs/03` §3b), ver
   actividad, otras plantillas (roles fuera de los tres decididos), Windows, soporte para Codex/Cursor/Grok, marketplace, CLI
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
