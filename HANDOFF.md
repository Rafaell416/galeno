# Galeno — HANDOFF

Resumen ejecutivo para cualquier sesión futura. Léelo antes de tocar nada.
Fuente de verdad: `docs/03-especificacion-v0.0.1.md`. Este archivo la resume, no la reemplaza.

**Estado (3 oct 2026):** el motor (`GalenoCore`) genera la config y el bridge de WhatsApp
(`whatsapp-bridge`) está probado a mano contra una cuenta real (vincular, sincronizar, leer
desde Claude Code, confirmar que no puede enviar); falta probar que `sync` sobrevive a un
reinicio vía `launchd`. Tras la sesión de descubrimiento del 3 de octubre quedan ajustes
pendientes (probar `sync` tras un reinicio): ver §6 y §12. El motor ya tiene subagentes,
descripción y memoria del proyecto, varios agentes y regeneración. La app (`GalenoApp`) ya
tiene proyecto Xcode, el esqueleto del wizard y las **pantallas 1–10** (idioma en caliente,
detección de Claude Code, tu agente, la grilla de herramientas, el sub-wizard de conexión,
qué leer, skills, reglas, generar la carpeta del agente y abrirlo en la app de Claude o en
Terminal). **Slack ya crea su propia app
OAuth y el usuario solo inicia sesión** (ventana de Galeno que captura el token de configuración);
Gmail y Google siguen en "conectar
después" y su automatización de navegador está diseñada, no construida (`docs/03` §4e,
"Diseño de la conexión con app propia"). Las 17 skills nuestras ya están escritas completas
(Fase 5, 5 oct 2026); las curadas con su licencia siguen pendientes. Sparkle está integrado (falta la dirección del
appcast). Faltan la fuente remota
de skills y la distribución.
Repo privado: `github.com/Rafaell416/galeno`, rama por defecto `main`.

---

## 1. Qué es y para quién

**Galeno** es una app de escritorio nativa para Mac que, con un wizard, crea y configura
un agente en Claude Code para **gente de producto, marketing y comercial** (tres roles desde el 5 oct 2026; nació solo para
Product Managers). El usuario ya tiene (o instala) Claude
Code; Galeno le conecta sus herramientas y escribe toda la configuración (reglas,
subagentes, skills, hooks, MCP) con los guardrails ya puestos.

- **Usuario:** PM no técnico que vive en reuniones y mensajería (WhatsApp, Slack, correo,
  Jira, Notion, Google Suite), no en la terminal. Dolor: "tengo Claude Code pero no sé
  convertirlo en un asistente que conozca mi trabajo sin romper nada".
- **Promesa:** tu propio agente en ~10-15 minutos, sin saber configurar nada.
- **Marca:** Galeno es el producto (la app), no el agente. Cada usuario nombra el suyo.
  Narrativa: *Galeno te crea tu agente.* El Galeno de MediClub (el agente de Rafa para una
  clínica) es el caso de referencia.
- **Diferencial:** instalador visual para no técnicos + guardrails + WhatsApp (el mundo de
  LatAm). A futuro, separación de contexto por proyecto. El foso son los guardrails, no el wizard.
- **Hipótesis de valor:** un PM recupera ~1 hora al día de informes y seguimiento manual.

---

## 2. Decisiones CERRADAS (no se reabren en v0.0.1)

| Tema | Decisión |
|---|---|
| Nombre | **Galeno** |
| Precio | **USD 200, pago único** |
| Varios proyectos | **Un agente por proyecto**, cada uno en `~/Galeno/<agente>/`. En v0.0.1 se pueden crear varios; la separación **garantizada** de contexto es v0.2. Las conexiones se hacen una vez y se comparten. Detalle: `docs/03` §3b |
| Después del wizard | Home con la lista de agentes: abrir (en la app de Claude o en Terminal), crear otro (wizard corto), gestionar la config, salud y mantenimiento |
| Contexto del proyecto | Una línea en el wizard (y, opcional, material traído de claude.ai que queda en `memoria/contexto/`); en la primera sesión el agente **contesta primero** y luego ofrece armar un resumen del proyecto, que el usuario confirma |
| Memoria | El agente mantiene notas en `memoria/proyecto.md` (`CLAUDE.md` la importa). Es el único lugar donde escribe sin que nadie lo apruebe; lo que Galeno genera está bloqueado por regla y cualquier otra ruta pide permiso |
| Dueño de la config | **Galeno**: regenera los archivos completos al cambiar algo; nunca toca `memoria/` |
| Proactividad | Tareas programadas de alcance acotado (decisión de Rafa, 5 oct 2026, `docs/03` §3b): leen, escriben en `memoria/` y hacen las escrituras internas permitidas; **todo envío queda de borrador hasta que alguien lo apruebe**. Sin construir todavía (tras el rediseño). Envío desatendido: v0.2 |
| Actualizaciones | **De por vida, gratis**, sin renovación. Tres capas independientes: app (Sparkle), bridge de WhatsApp (viaja en la app, con versión propia) y skills (remotas, sin reinstalar). Sparkle va desde el primer build. Detalle: `docs/03` §4f |
| Perfil | **Tres roles: producto, marketing y comercial** (decisión de Rafa, 5 oct 2026; antes solo Product Managers). Un cuarto rol es reabrir la decisión |
| Plataforma | **Solo Mac** (firme; no portabilidad a Windows) |
| App | **Swift + SwiftUI nativa**. Es la única interfaz del usuario |
| Motor | **Interno**: librería que genera la config; el usuario nunca lo ve. Solo genera config de **Claude Code**. Se construye en paralelo a la app, no antes |
| WhatsApp | **Solo lectura por estructura de código**, sobre fork de `lharries/whatsapp-mcp` (MIT). Se eliminan las 3 herramientas de envío y el servidor MCP se **porta de Python a Go** dentro del binario del puente: un solo ejecutable Go. Nunca empaquetar Python |
| Email | **Gmail** (OAuth oficial de Google) |
| Transcripciones | **MCP oficiales hospedados**, directo de la fuente: Fireflies, Granola, Fathom. Google Meet vía el MCP de Google Drive |
| Envío de mensajes | Solo **Slack y email**, por APIs oficiales, con aprobación |
| Idioma del wizard | **Español e inglés** (`Localizable.strings`), elegido en el paso 1, preseleccionado según el Mac |
| Idioma de las skills | Skills nuestras **en inglés**, con la instrucción explícita de responder en el idioma del usuario |
| Niveles de skills | **Dos**: las nuestras y las curadas de la comunidad. Ambas revisadas por nosotros |
| Secretos | **Nunca tocan infraestructura propia.** Todo local |
| Stack total | Swift (app) + un binario Go (WhatsApp). Nada de Python, Node, Rust ni contenedor web |
| App OAuth de Slack/Gmail/Google Workspace | **La trae el cliente, nunca Galeno.** Para Slack: creación de la app **por API, sin pantallas** (`SlackManifestRenderer` + `SlackAppProvisioner`, ya en `GalenoCore`); lo único que Slack no deja evitar —generar el primer token de configuración— **también lo hace la automatización de navegador de Galeno** (Fase 4), no el usuario a mano: un solo clic en una sola pantalla, una vez por workspace. Para Google: automatización de navegador de principio a fin, Fase 4, varias pantallas, riesgo aceptado. Detalle: `docs/03` §4e |

### Alternativas descartadas (no proponerlas de nuevo)

Los cuatro documentos se conciliaron el 2 de octubre de 2026 y ya dicen lo mismo. `docs/01`
y `docs/02` conservan, marcado como *Descartado*, lo que el plan original proponía:

| Descartado | Vigente |
|---|---|
| Carcasa en Tauri | Swift + SwiftUI |
| Motor CLI primero, y venderlo o validarlo como CLI | Motor interno, en paralelo a la app; se valida con la app |
| Freemium o suscripción | Pago único USD 200 |
| WhatsApp sin lectura, solo salida por Business API | WhatsApp solo lectura (no oficial, con advertencia); sin envío |
| Transcripciones vía export a Notion/Docs | MCP oficial de cada proveedor |
| Skills adaptadas al español | Skills en inglés + instrucción de idioma |
| Un solo agente para todos los proyectos | Un agente por proyecto |
| Wizard completo para cada agente nuevo; duplicar un agente existente | Wizard corto, reutilizando conexiones |
| Carpeta oculta en Application Support, o elegida por el usuario | `~/Galeno/<agente>/`, visible |
| Chat propio dentro de Galeno | Se abre en la app de Claude o en Terminal |
| Zonas editables a mano en la config, o detectar cambios y preguntar | Galeno regenera todo, salvo `memoria/` |
| Selección de chats de WhatsApp como barrera (lista de permitidos en el bridge) | La selección es el foco del agente; ve todo lo sincronizado. Una lista fija obliga a reconfigurar con cada grupo nuevo |
| MCP de WhatsApp en TypeScript o Python | Un solo binario Go |
| Confeti de colores y rebotes en las animaciones | Trazo y opacidad (`docs/04` §8) |

Si aun así aparece una contradicción, gana `docs/03`.

---

## 3. Arquitectura

Galeno.app es un **orquestador de procesos locales**.

```
Galeno.app  (Swift / SwiftUI)
  ├── Wizard y UX            → SwiftUI nativo (pantallas de dopamina, QR en pantalla)
  ├── Generador de config    → el motor; escribe AGENTS.md, .claude/*, .mcp.json   (FileManager)
  ├── WhatsApp               → lanza y supervisa un binario Go empaquetado          (Process)
  │                             puente whatsmeow + SQLite + servidor MCP read-only
  │                             "sync" (conexión persistente, vía launchd) y "serve"
  │                             (MCP por sesión, sin conexión propia) son subcomandos
  │                             separados — nunca dos conexiones simultáneas
  └── MCP hospedados         → `claude mcp add --transport http …` + abre el OAuth  (Process)
                                Notion · Slack · Gmail · Drive · Jira · Fireflies · Granola · Fathom
```

- **Por qué Go para WhatsApp:** `whatsmeow` solo existe en Go. El MCP va en el mismo
  binario para que el componente sea autocontenido y Claude Code lo lance por stdio como
  cualquier MCP.
- **MCP hospedados:** no se empaquetan. Viven en los servidores de cada proveedor; el
  OAuth lo gestiona Claude Code. Endpoints citados en la spec: `api.fireflies.ai/mcp`,
  `mcp.granola.ai/mcp`, `api.fathom.ai/mcp`.
- **Motor separado de la app** por ingeniería (testeable, la app no acumula lógica), no
  para que alguien lo use directo. La app consume el motor y no duplica lógica.

### Cómo se actualiza (3 capas, `docs/03` §4f)

| Capa | Qué contiene | Cómo se actualiza |
|---|---|---|
| 1 · App Mac | Wizard, UI, motor de config | **Sparkle**: appcast en el servidor, build firmado, un clic. Soporta deltas |
| 2 · Bridge de WhatsApp | `whatsmeow` + MCP read-only | Viaja dentro de la .app, así que llega con Sparkle. **Versión propia**, para sacar un parche urgente sin re-releasear la app. Es la capa que más se rompe por causas externas (Meta) |
| 3 · Skills, catálogo y config | Skills PM, catálogo curado, prompts, plantillas | **Remoto, sin reinstalar**: se descargan al configurar el agente, y la app ofrece "actualizar skills". Fallback local si no hay internet |

- **Sparkle firma con clave EdDSA propia**, además de la notarización de Apple. La clave
  privada vive fuera del repo.
- **Sin infraestructura nueva:** appcast, DMG y skills remotas se sirven desde la misma
  infraestructura del sitio y del webhook de Stripe.
- **Solo descargas.** Nada de esto recibe tokens, contenido ni datos de uso del usuario:
  la regla de §5.1 sigue intacta.
- **Estado hoy:** nada de esto está construido. `GalenoCore` ya recibe las skills como un
  directorio (`skillsDirectory`), no las lleva embebidas, así que la capa 3 es cuestión de
  quién llena ese directorio. El bridge todavía no expone una versión propia. La capa 2 ya
  se ejercitó una vez a mano: el `whatsmeow` fijado en marzo de 2025 dejó de conectar y
  hubo que actualizarlo (PR #9) — exactamente el caso que esta capa existe para cubrir.

### Qué escribe el motor en la máquina del usuario

| Archivo | Contenido |
|---|---|
| `AGENTS.md` | Identidad del agente, rol PM, descripción del proyecto, herramientas, reglas y uso de la memoria. En el idioma elegido, con la instrucción "responde y genera todos los documentos en [idioma]" |
| `.claude/settings.json` | Reglas deny/ask/allow: envíos externos en `ask`, nada de ejecutar código, `Edit(/memoria/**)` en `allow`, y en `deny` por nombre lo que el motor genera fuera de `memoria/` |
| `memoria/` | Notas del proyecto que mantiene el agente. El motor la crea si falta y nunca la sobrescribe |
| `.mcp.json` | Los MCP conectados. Tokens como referencias a variables de entorno, nunca en texto plano |
| `.claude/agents/` | `scribe`, `tracker`, `reporter`: solo lectura + Notion/Jira; sin Bash ni Edit de código |
| `.claude/hooks/` | Hook de aprobación para todo envío externo |
| `.claude/skills/` | Las skills que el usuario dejó marcadas, tomadas de la fuente remota versionada (o del fallback local) |

### Qué puede hacer el agente generado

- **Lee:** WhatsApp (grupos y chats elegidos), Slack, Notion, Google Drive/Docs/Sheets,
  Jira, Gmail, transcripciones (Fireflies, Granola, Fathom, Meet vía Drive).
- **Escribe:** Notion y Jira (tareas y docs), Google Docs, Slack (informes), email
  (redactar y enviar). Todo lo externo, con aprobación humana.

---

## 4. El wizard (10 pasos)

> **Rediseño «Activación» (5 oct 2026):** el usuario ve **seis pasos** —rol, cuenta de Claude, nombre, herramientas, reglas y
> creación— y antes, una sola vez, tres pantallas de presentación. El rol fija las skills (ya no hay paso «Skills» al crear) y el
> orden de las herramientas; la descripción y el contexto salen del asistente. El detalle y lo que falta por construir está en
> `docs/03` §3, que manda sobre la lista de abajo.

1. **Idioma y bienvenida** — español o inglés. Define el idioma del wizard y el que el
   motor inyecta en la config. Qué es, qué configura, cuánto tarda.
2. **Detección** — verifica que Claude Code esté instalado; si no, guía para instalarlo.
3. **Tu agente** — nombre del agente, rol (solo "Product Manager" en v0.0.1) y una
   línea que describe el proyecto.
4. **Elige tus herramientas** — grilla única; marca solo las que usa. Al pie:
   "Vas a conectar 5 herramientas · ~8 min".
5. **Conecta una por una** — sub-wizard y paso más largo; diseñado para mantener el enganche:
   - Barra de progreso siempre visible ("3 de 5 conectadas").
   - Una conexión por pantalla: logo, una línea de valor, botón "Conectar" (OAuth, o QR en WhatsApp).
   - Feedback inmediato con **un dato real** ("¡Slack conectado! Encontré 12 canales").
   - Transición automática a la siguiente tras ~1.5 s; botón discreto "Conectar después".
   - Pantallas de dopamina cada 2-3 conexiones, sin botones de OAuth.
   - Si un OAuth falla: "Reintentar" y "Saltar por ahora". El usuario nunca queda atrapado.
   - Celebración final con el conteo de lo que el agente ya ve.
6. **Elige qué leer** — por cada tool, qué grupos/canales/carpetas/proyectos. Es lo que
   distingue a un agente de otro: es el foco del agente, no una barrera. En WhatsApp el agente
   ve todos los chats sincronizados.
7. **Elige tus skills** — las nuestras (todas marcadas por defecto) y las curadas (con
   crédito al creador y link a su GitHub).
8. **Reglas** — qué puede enviar sin preguntar (nada externo por defecto) y qué requiere aprobación.
9. **Generando** — el motor escribe la config, con pasos visibles.
10. **Listo** — cómo usarlo, primeros comandos, dónde está la config. Invitación:
    "Pídele: resume lo que pasó esta semana en Slack". El usuario elige abrir su agente en
    la app de Claude o en Terminal.

### Después del wizard (`docs/03` §3b)

- **Home:** la lista de agentes. Abrir, crear otro, gestionar la config, salud y
  mantenimiento (conexiones caídas, re-vincular WhatsApp, estado de `sync`, actualizar
  skills y la app).
- **Wizard corto** para el segundo agente en adelante: nombre, descripción, qué leer, skills.
  Las conexiones ya hechas se reutilizan.
- **Primera sesión:** el agente lee las fuentes y propone un resumen del proyecto; el
  usuario lo confirma y queda en `memoria/`.
- **Cambios de config:** Galeno regenera los archivos completos a partir de las respuestas
  guardadas. `memoria/` no se toca.

**Principio de diseño:** el usuario siempre sabe dónde va, cada conexión devuelve algo
tangible, y nunca pasan más de ~2 minutos sin una recompensa visual.

---

## 5. Reglas innegociables

1. **Los tokens nunca van a infraestructura propia.** Todo queda en la máquina del usuario.
   La app orquesta OAuth y escribe archivos locales; no almacena ni transmite credenciales
   ajenas. Nunca en texto plano en la config: referencias a variables de entorno.
2. **WhatsApp sin envío, por estructura de código.** El MCP no tiene herramientas de
   envío: se eliminan `send_message`, `send_file` y `send_audio_message` del fork. Ni un
   prompt malicioso ni el propio agente pueden enviar. No es una regla de configuración:
   el código no existe.
3. **Aprobación humana para todo envío externo** (Slack, email): regla `ask` + hook.
   Por defecto, nada externo sale sin preguntar.
4. **Transparencia sobre WhatsApp.** La pantalla de vinculación dice que es un dispositivo
   vinculado por el protocolo de WhatsApp Web, no oficial, de solo lectura, con riesgo bajo
   pero real de restricción de la cuenta, que todo corre local, y que el usuario decide.
   Nunca se promete que es "seguro".
5. **Ningún código no revisado entra al agente.** Solo skills nuestras y curadas.
6. **Licencias:** conservar los avisos MIT del fork de lharries. No usar
   `deanpeters/Product-Manager-Skills` (CC BY-NC-SA, no comercial).
7. **Sin promesas de cumplimiento garantizado** ni sobreventa.

---

## 6. WhatsApp — detalle operativo

- **Base:** fork de `lharries/whatsapp-mcp` (MIT). Original: puente en Go (`whatsmeow`,
  QR, SQLite) + servidor MCP en Python con 12 herramientas, 3 de envío.
- **Hecho:** las 3 de envío eliminadas (no comentadas); el MCP portado a Go dentro del
  mismo binario, con el SDK oficial (`modelcontextprotocol/go-sdk`); subcomandos
  `pair`/`sync`/`serve`/`status`/`install-launchd`; estado en
  `~/Library/Application Support/Galeno/whatsapp/`; build universal arm64+amd64. `pair`
  escribe el QR también como PNG (`pair-qr.png`, lo reescribe en cada rotación, lo borra al
  terminar) para que la app lo muestre en pantalla sin parsear la terminal.
  `install-launchd` instala un LaunchAgent que mantiene `sync` (nunca `serve`) corriendo tras
  el login — `sync` sostiene la única conexión viva a WhatsApp; `serve` (el que lanza Claude
  Code por sesión) solo lee lo que `sync` ya guardó, para que nunca haya dos conexiones
  simultáneas con el mismo dispositivo vinculado. Detalle: `whatsapp-bridge/README.md`.
- **Falta (Fase 4, GalenoApp):** que la app dispare `install-launchd` tras un `pair` exitoso;
  renderizar el QR (ya disponible como PNG) dentro de la app en vez del terminal; empaquetar
  y firmar el binario.
- **Hecho (bridge):** `version` (número propio del bridge, hoy `0.2.0`) y `chats --json`
  (la lista para "elige qué leer": una entrada por persona aunque tenga fila de número y de
  `@lid`, y los nombres que la base guardó como número se completan al leer con los contactos
  de whatsmeow).
- **Decidido (bridge): el agente ve todos los chats sincronizados**, incluidos los
  personales. Se diseñó un filtro por chat (`serve --allow-chat`) y se descartó antes de
  construirlo: una lista fija obliga a reconfigurar con cada grupo nuevo. Hay que decirlo con
  claridad en el wizard. Si algún día hace falta una barrera, será una lista de **exclusión**.
- **Falta (bridge):** probar que `sync` sobrevive a un reinicio del Mac, y compilar el
  binario universal en CI (el job de Go corre en Ubuntu y solo hace `go build`).
- **Mantenimiento perpetuo:** `whatsmeow` hay que mantenerlo al día. Con una versión de
  año y medio de antigüedad el socket se cerraba (1006) antes de mostrar el QR; al
  actualizar cambiaron varias firmas (ahora piden `context.Context`) y el requisito pasó a
  Go 1.26. Cuando el bridge deje de conectar, lo primero es revisar esto.
- **Las 9 herramientas que quedan:** `search_contacts`, `list_messages`, `list_chats`,
  `get_chat`, `get_direct_chat_by_contact`, `get_contact_chats`, `get_last_interaction`,
  `get_message_context`, `download_media`.
- **UX obligatoria:** re-vinculación cada ~20 días (aviso y re-escaneo); la carga inicial
  del historial tarda minutos (barra de "sincronizando").
- **Referencias, no código:** `joaohts/whatsapp-mcp` solo por ideas de UX (QR en pantalla,
  toggles por herramienta, DMG). Alternativas TypeScript descartadas por la decisión de Go.

---

## 7. Skills

**Nuestras (17, perfil PM).** En inglés, con instrucción de idioma. Cada una pregunta en
qué herramienta escribir si el usuario tiene varias; no asumen.

| Grupo | Skills |
|---|---|
| Documentos de producto | `/prd` · `/user-stories` · `/roadmap` · `/release-notes` |
| Gestión del trabajo | `/epics` · `/tickets` · `/tareas-recurrentes` · `/groom` · `/sprint-log` |
| Seguimiento y reportes | `/resumen-proyecto` · `/seguimiento` · `/informe-slack` · `/reporte-excel` · `/reporte-dia` |
| Reuniones y descubrimiento | `/acta` · `/sintesis-research` · `/priorizar` |

**Curadas.** Lista seleccionada de terceros, ofrecidas tal cual, con crédito y link.

**Distribución.** Las skills no van horneadas en la app: se cargan de una fuente remota
versionada, con fallback local, para poder mejorarlas o añadir nuevas sin un build nuevo
(`docs/03` §4f, capa 3). Siguen siendo solo dos niveles, ambos revisados por nosotros:
remoto no significa abierto a terceros.

**Bases reutilizables (no reinventar):** `product-on-purpose/pm-skills` (Apache 2.0) y
`phuryn/pm-skills` (MIT) como base; `snarktank/ralph` (MIT) por su `/prd`; el plugin
oficial de Anthropic (`anthropics/knowledge-work-plugins`) como estándar de estructura.

**Subagentes:** `scribe` (transcripciones → decisiones y acciones), `tracker` (detecta
qué cambió), `reporter` (arma informes). El motor los genera en `.claude/agents/`, en
inglés y con la instrucción de idioma arriba. Su campo `tools` es una lista blanca: leen
archivos locales y reciben el servidor MCP de cada herramienta conectada que no puede
enviar. **Nunca reciben Slack ni Gmail**: un servidor se concede entero, y con él vendría
la herramienta de enviar. El agente principal lee Slack y el correo y les pasa lo
relevante; ellos devuelven un borrador y solo el principal envía, con aprobación.

---

## 8. Lo que NO está en v0.0.1

| Fuera | Cuándo |
|---|---|
| Envío por WhatsApp | v0.2 |
| Separación garantizada de contexto entre agentes (más allá de WhatsApp) | v0.2 |
| Vista transversal de todos los proyectos | v0.2 |
| Ver actividad (qué hizo el agente, qué envió) | v0.0.2 |
| Slack con identidad de bot propia (el agente envía con su nombre, no con el del usuario) | v0.0.2 |
| Tareas programadas de alcance acotado (envíos solo como borrador) | v0.0.1, tras el rediseño (`docs/03` §3b) |
| Tareas programadas con envío desatendido | v0.2 |
| Skills externas, "trae la tuya" (link de GitHub) | v0.2, con su guardrail. Las propias del usuario (archivos de su Mac) ya entran (6 oct 2026, `docs/03` §6.3) |
| Plantillas dev / legal / salud | v0.3+ |
| Config para Codex / Cursor / Grok | v0.3+ |
| Marketplace de skills | futuro |
| Windows | futuro |
| CLI de cara al usuario | nunca: el motor es interno |
| Tratamiento de idioma para skills curadas | no en v0.0.1 |
| Automatizar la config de Claude.ai (web/desktop) | fuera; solo Claude Code |

---

## 9. Orden de construcción

1. **Motor interno** — genera toda la config a partir de las respuestas del wizard.
2. **App Swift/SwiftUI, en paralelo** — el wizard. Validación temprana con los 2 PMs del
   equipo usando la app (aunque tenga dos pantallas y sea fea), no un CLI.
3. **MCP de WhatsApp read-only** — ver §6.
4. **Pagos y distribución** — pago único; DMG firmado y notarizado. El binario Go embebido
   también se firma. **Sparkle desde el primer build**: una app que sale sin él no sabe
   actualizarse, y montarlo con usuarios ya instalados obliga a contactarlos uno por uno.
5. **Validación con 5-10 PMs externos** antes de abrir la venta.

---

## 10. Riesgos de v0.0.1

| Riesgo | Mitigación |
|---|---|
| Ban de WhatsApp a un usuario | Read-only + advertencia explícita + sin promesa de "seguro" |
| Tokens expuestos | Nunca en texto plano ni en servidores propios |
| El agente envía algo mal a un cliente | Envíos externos en `ask` + hook de aprobación |
| Gatekeeper bloquea la app | Firmar y notarizar desde el inicio, incluido el binario Go |
| Meta rompe el protocolo de WhatsApp | El bridge deja de leer; parche urgente de la capa 2 vía Sparkle (por eso tiene versión propia). Mantenimiento de por vida, no opcional |
| Claude Code cambia el formato de config | Motor desacoplado |
| El usuario se traba en un OAuth | Captura de qué hacer, botón de ayuda, "Saltar por ahora" |

---

## 11. Diseño (resumen de `docs/04-design-system.md`)

Estética de "libro antiguo bien impreso": pergamino, tinta gris cálida, un solo acento
rojo lacre (`seal-700` `#8B3A3A`), mucho espacio. En la app: **nativo primero, estética
encima**. Controles nativos, SF Symbols, serif del sistema (New York) sin fuentes
embebidas, fondo `parchment-50`, `.tint` en `seal-700`. Sin texturas, sin sombras
decorativas, sin controles custom que imiten lo viejo. Animaciones de 150-300 ms con trazo
y opacidad. Leer el documento completo antes de tocar UI o el sitio.

**Ventana de 800 × 620 pt (decisión de Rafa, 5 oct 2026):** a 720 × 560 se sentía pequeña. Sigue fija. Los archivos del
proyecto de Claude Design siguen dibujados a 720 × 560: siguen siendo la referencia de disposición y proporciones, no del
tamaño exacto. Detalle en `docs/04` §12 («Pantallas»).

---

## 12. Puntos abiertos (no decididos en los docs)

- **Variables de entorno de los tokens:** dónde se guardan los valores a los que apunta `.mcp.json`.
- **Pagos:** falta la compra (Stripe) y cómo se entrega el enlace de descarga. Sin licencias en v0.0.1 (decisión de
  Rafa, 6 oct 2026; el trabajo está aparcado en la rama `feat/licencias`).
- **Sparkle: integrado, falta la dirección del appcast.** La clave está generada y el script publica el appcast, pero
  la URL es de relleno hasta que exista el sitio (Fase 9). Falta también la ruta de las skills remotas.
- **Skills remotas, sin diseño:** quién descarga (¿`GalenoApp` llena el directorio que ya
  recibe el motor, o el motor aprende a hablar con la red?), cómo se versionan, dónde vive
  el fallback local y **cómo se verifica su integridad**. La spec exige firma EdDSA para
  la app, pero no dice nada equivalente para las skills, y una skill es instrucciones para
  el agente: un canal remoto sin verificación sería una puerta de entrada de contenido no
  revisado (regla §5.5).
- **Abrir el agente en la app de Claude:** decidido que el usuario elige entre la app de
  Claude y Terminal, pero falta verificar cómo se abre una carpeta concreta en la app de
  Claude desde Galeno y que cargue toda la config generada (hooks, `.mcp.json`, skills).
- **Licencia y número de agentes: decidido.** No hay licencia en v0.0.1; si llega a haberla, cubre agentes ilimitados
  (se paga por la app, no por agente).
- **Carpetas visibles:** `~/Galeno/<agente>/` está a la vista y el motor ya asigna la ruta
  (sin choques, con `Aurora 2` si hace falta). Falta decidir qué hace el home si el usuario
  la borra, la mueve o la renombra, y cómo se renombra o elimina un agente desde Galeno. Una
  carpeta borrada a mano se puede recrear desde la instalación, pero su memoria se pierde.
- **Regenerar borra skills a mano:** quitar las skills desmarcadas borra cualquier carpeta de
  `.claude/skills/` que no esté marcada, también una puesta a mano. Es lo que dice la spec
  (Galeno es el dueño) y el resultado lista lo quitado (`removedFiles`) para que la app avise;
  no se puede deshacer. Un manifiesto de lo que Galeno instaló lo evitaría; no hace falta
  mientras "trae tu skill" no exista (v0.2).
- **Memoria, cómo se limita la escritura (resuelto):** reglas de permiso por ruta, no un
  hook (un hook necesita `jq` para leer su entrada, y la documentación no dice si su
  `allow` puede más que un `deny`). Un patrón que niegue todo el proyecto con `memoria/`
  como excepción `!` **no funciona**: se probó contra Claude Code y la excepción no reabre
  un directorio bloqueado entero. Se niega por nombre lo que genera el motor
  (`SettingsRenderer.protectedPaths`; un test falla si el generador escribe algo fuera de
  `memoria/` que no esté ahí) y se permite `Edit(/memoria/**)`. Consecuencia: una
  escritura en cualquier otra ruta no está bloqueada, **pide permiso al usuario**.
- **Memoria, la regla `allow` necesita confianza:** Claude Code ignora las reglas `allow`
  de un `settings.json` de proyecto hasta que el usuario acepta el diálogo de confianza de
  la carpeta. Sin eso, cada nota de `memoria/` pide permiso; el `deny` sigue en pie.
- **Memoria y prompt injection:** el agente lee mensajes de terceros y escribe notas que
  se cargan en todas las sesiones. El primer resumen exige confirmación del usuario y el
  `AGENTS.md` dice que una nota es un hecho, nunca una orden; todo envío externo sigue
  pidiendo aprobación. El riesgo de que una instrucción escondida se vuelva permanente
  no desaparece: queda registrado.
- **Memoria, crecimiento:** un solo archivo se carga entero en cada sesión. Falta decidir
  qué se hace cuando crece (resumir, archivar, partir en archivos).
- **Subagentes y reglas `ask`:** falta confirmar a mano que una regla `ask` de
  `settings.json` también detiene a un subagente (por ejemplo, `scribe` creando una tarea
  en Jira con Jira en "pedir confirmación"). La documentación confirma que los hooks sí
  corren dentro de los subagentes, pero no dice lo mismo, con todas las letras, de las
  reglas de permiso. Si no preguntara, hay que cubrirlo con el hook.
- **Subagentes y Slack:** `tracker` no puede leer Slack ni Gmail por su cuenta. Darle solo
  las herramientas de lectura exige conocer sus nombres exactos, que Slack no documenta:
  habría que listarlos con una cuenta conectada. Mejora posible, no bloquea v0.0.1.
- **Carpeta sin confiar:** en una carpeta que Claude Code todavía no marcó como confiable,
  las reglas `allow` del `settings.json` generado se ignoran (visto al probar los
  subagentes, que sí cargan). El usuario acepta el diálogo de confianza la primera vez que abre su agente;
  la app tiene que contar con ese paso al diseñar "abrir mi agente".
- **Wizard y acceso a WhatsApp:** el agente ve todos los chats sincronizados. La pantalla
  "elige qué leer" tiene que decirlo con claridad y presentar lo elegido como foco. Aparte,
  en la base de Rafa 152 de 246 chats individuales siguen sin nombre aunque `chats` ya
  completa los que puede (la gente que nunca guardó ni escribió con nombre): la pantalla
  tiene que mostrar bien un número, y conviene buscar por número.
- **Versión propia del bridge:** falta decidir el esquema y cómo permite parchear el
  bridge "sin re-releasear toda la app" si viaja empaquetado dentro de ella.
- ~~MCP exactos de Slack, Notion, Jira, Gmail y Drive~~ — **resuelto** (oct 2026): todos
  verificados contra la documentación oficial. Google Workspace resultó ser tres servidores
  (Drive, Docs, Sheets), no uno. Ver `docs/03` §4e para el detalle y la decisión de
  bring-your-own-app para Slack y Google.
- ~~Automatización de navegador para Google~~ — **resuelto de otra forma** (4 oct 2026): Gmail y
  Google Drive van por los conectores de la cuenta de Claude del usuario; no hay app de Google Cloud
  ni automatización de su consola. El porqué (Developer Preview con aprobación de días, solo
  Workspace) está en `docs/03` §4e. Los cinco conectores ya se verificaron en una cuenta
  real (herramientas exactas en el catálogo). En la app de Claude los conectores se encienden por
  conversación y sus herramientas llevan otro nombre: el agente sabe encender los suyos y dos hooks
  cubren los permisos (`docs/03` §4e). Los demás conectores de la cuenta se heredan apagados. La app de
  Claude solo ve los conectores que estaban conectados cuando arrancó: tras conectar Google hay que
  reiniciarla (confirmado); «Abrir en la app de Claude» lo hace solo cuando hace falta.
- **Granola:** confirmar si borra transcripciones a las ~72 h; si es así, sincronizar pronto.
- **Fathom:** la búsqueda lee títulos y resúmenes; la transcripción completa se pide por ID.
- **Licencias por verificar:** plugin PM de Anthropic y `Digidai/product-manager-skills`.
- **Protección de `main`:** pendiente. Exige GitHub Pro en un repo privado; se decidió
  dejarlo así por ahora y sostener la regla de rama + PR por disciplina.
- **Lista concreta de skills curadas:** sin definir.
- **Nombres de las skills:** el contenido va en inglés, pero la lista mezcla nombres en
  inglés (`/prd`, `/groom`) y en español (`/acta`, `/seguimiento`). Falta decidir cómo se
  llaman para un usuario que eligió inglés.
- **`/reporte-excel`:** resuelto al escribir la skill (5 oct 2026): **solo Google Sheets**; la skill le dice al
  usuario que no puede crear `.xlsx` y que lo descargue desde Sheets. El nombre de la skill no cambió. Rafa lo vio
  al revisar la tanda y no lo objetó; si quiere otra cosa, es una línea en la skill y en `docs/03` §6.1.
- **Tecnología de `site/`:** sin definir. Estructura y estilo sí (`docs/04` §9).
- **Tiempo de Rafa:** MediClub lanza el 15 de noviembre de 2026 y compite por su atención.

**Fase 5, primer paso — las 17 skills, escritas (5 oct 2026, rama `feat/skills-pm`):** `skills/galeno/<id>/SKILL.md`, en
cuatro tandas que Rafa fue revisando. Detalle y reglas comunes en `docs/03` §6.1; `SkillCatalogTests` las exige a todas.
Verificado que Claude Code lista las 17 en un agente generado con `galeno-gen --skills-dir skills`. **Falta:** probarlas una
por una con trabajo real, las curadas (siguen `available: false`), la fuente remota de skills y «Actualizar skills»,
y Sparkle. Decisiones tomadas al escribirlas, para que Rafa las confirme o cambie: `/groom` solo reporta; `/tickets`
usa la etiqueta `proposed` si el proyecto no tiene estado «Propuesto»; `/tareas-recurrentes` no se programa sola;
antes de publicar en Slack se aparta lo que viene de lugares privados.

**Paso «Skills» como cards (5 oct 2026, misma rama `feat/skills-pm`):** construido desde `Galeno B1 Skills.dc.html`, en la variante
«scroll con rótulos fijos» (Claude Design recomendaba pestañas; Rafa eligió el scroll): cards con icono, vista previa al pasar el cursor (cómo pedirla, ejemplo ilustrativo, qué
necesita), estados «todavía no te sirve» y foco de teclado. El catálogo ganó `ask`, `example` y `guarantee`. **Sin construir
todavía, aunque están en el diseño:** el marco propio de «Gestionar → Skills» (cabecera «Hera · Skills» y «Guardar cambios»; hoy se
llega por el asistente de «Gestionar» de siempre), el grupo «De Anthropic» (falta revisar y traer esas skills con su licencia, y que
Rafa confirme a Anthropic como fuente) y el resultado por skill de «Actualizar skills» en Salud (falta el mecanismo). Las curadas de
la comunidad dejaron de mostrarse. Sin probar a mano: el teclado (↩ sobre una card frente a «Siguiente») y el hover real. **Después (5 oct):** la vista previa pasó a
estar centrada y a llevar una demostración animada (pregunta que se escribe, el agente «lee», resultado con el formato de la skill);
los 17 ejemplos del catálogo se reescribieron con formato. Vista en renders fuera de pantalla; la animación en vivo, sin ver.

**Fase 4b (home) hecha (4 oct 2026):** lista de agentes, «Abrir» en la app de Claude o Terminal (recuerda la última elección, botón
partido), «Nuevo agente» por el wizard corto y «Gestionar» (cambiar qué lee, skills y reglas; recupera una herramienta saltada).
«Salud» hecha (ver abajo); falta el mecanismo de «Actualizar skills» y la actualización de la app (Fase 5).

**Salud (4 oct 2026, rama `feat/salud`, sin commit):** enlace «Salud» en el home → conexiones con su estado y «Reconectar» (`claude mcp list`
para servidores propios; los conectores de la cuenta de Claude, por el arranque de una sesión), panel de WhatsApp (sesión, `sync`
corriendo, días vinculado, aviso a los 18 días, versión del puente, «Re-vincular» con QR), entrada de «Actualizar skills» (deshabilitada
hasta la Fase 5) y carpetas borradas a mano («Regenerar la carpeta» / «Quitar el agente»). **Tocó el bridge: 0.2.2 → 0.3.0** (`status --json`
y `unlink`), así que hay que compilarlo antes de la app. Detalle en `docs/03` §3b.

**Renombrar y eliminar un agente — hecho (4 oct 2026), según lo que decidió Rafa:** renombrar cambia solo el nombre (la carpeta no
se mueve, `memoria/` no se toca). Eliminar manda a la Papelera, tras confirmar, la carpeta del agente, sus conversaciones de Claude
Code y las de la app de Claude (`AgentRemover`); si era el último agente se abre el wizard corto. Detalle en `docs/03` §3b.

### Aloha en la carpeta de Jarvi (4 oct 2026)

Al crear a «Aloha» (Google), Galeno reinició Claude y su primera pregunta cayó en la carpeta de «Jarvi»: el historial de «Jarvi» ganó una
conversación que no es suya, y la app pidió permiso para leer el calendario porque esa carpeta no tiene las reglas de Google. Los agentes son
independientes; fue la conversación la que cayó mal. *Arreglo hecho (rama `feat/gestionar-agente`, sin verificar con la app real):* abrir
Claude y esperar a que cargue antes de mandarle el enlace (`docs/03` §4e). Esa conversación mal archivada queda en Jarvi hasta que se
elimine desde la app de Claude; **ojo: «Eliminar» sobre Jarvi la mandaría a la Papelera con el resto de su historial.**

### Demo con Aquiles (5 oct 2026): fallido, no se activó

Instaló desde `build/Galeno-demo-2026-10-05.dmg` (ventana 800 × 620, skills en cards; todo sin commit en `feat/skills-pm`).
Solo le funcionó WhatsApp. Rafa lo da por fallido y fija la dirección: **rehacer el camino de activación pensando en un
usuario nada técnico**, con un onboarding antes del asistente y los casos de error bien resueltos (qué pasa cuando falla,
cómo reintento, cómo deshago y vuelvo a hacer). Nada de esto está construido ni decidido en detalle.

Fallos (causa leída en el código; **ninguno reproducido en su Mac**):

1. **No abría.** En macOS 26 el aviso fue «no se puede abrir» y «Abrir igualmente» no apareció en Privacidad y seguridad.
   Abrió con `xattr -dr com.apple.quarantine /Applications/Galeno.app`. El `LÉEME.md` del DMG ya no trae ese comando: hay
   que devolverlo mientras no haya notarización.
2. **«Instalado, pero sin sesión» sin salida.** Tenía la app de escritorio de Claude (sesión aparte) y `claude` no estaba en
   el PATH de su Terminal: el texto del paso 2 manda a «escribir claude» y eso dio `command not found`. Galeno sí sabe la
   ruta (`ClaudeCodeStatus.found(path:)`) y no la usa para ayudar.
3. **Slack: `error: unknown command 'login'`**, en el asistente y otra vez al «Reconectar» desde Salud. El `claude` de su Mac
   no tiene `claude mcp login` (versión vieja; no se anotó cuál). Galeno no comprueba la versión ni esa capacidad en el paso
   2, y el panel de error culpa a las ventanas emergentes. Toda herramienta con OAuth pasa por ese comando
   (`ClaudeMCP.swift`), así que con ese `claude` no habría conectado ninguna.
4. **Calendar marcado «conectado» sin terminar.** Abrió la página del conector, pulsó «Connect» y se quedó en el selector de
   cuentas de Google; Galeno lo dio por conectado. Es la regla que se añadió tras el demo de Felipe: después de abrir el
   navegador, tres lecturas `pending` seguidas cuentan como conectado (`ConnectFlow.connectClaudeConnectors`). Con un
   `claude` viejo, además, puede que el sondeo no respete `MCP_CONNECTION_NONBLOCKING` y todo salga `pending` (sin comprobar).

*Arreglado en la rama `fix/activacion` (5 oct 2026), con pruebas; ver `docs/03` §3 y §4e:*

- Fallos 2 y 3: Galeno instala, actualiza e inicia la sesión de Claude Code con un botón (decisión de Rafa: «corramos
  nosotros el comando»). Versión mínima 2.1.281; con varios `claude`, el más nuevo. El wizard corto y «Gestionar» pasan
  por la misma puerta antes de conectar. El instalador real se probó en una carpeta aislada; **el inicio de sesión real
  completo está sin probar** (hay que hacerlo en un Mac sin sesión).
- Fallo 4: solo cuenta un «conectado» de verdad; «Ya lo conecté, comprobar» y «Abrir la página otra vez» durante la espera.
  También en «Reconectar» de Salud. **Sin probar con una cuenta real.**
- Los iconos de la tira del paso 5 ya llevan a cada conexión.
- `unknown command 'login'` ya no culpa a las ventanas emergentes: dice que Claude Code está desactualizado.

*Sigue pendiente:* el fallo 1 (el `LÉEME.md` del DMG ya trae el comando de Terminal, pero la solución es notarizar);
Salud no ofrece actualizar Claude Code ni iniciar su sesión (solo lo dice); y todo lo de abajo, que espera el diseño de
Claude Design («Galeno B1 Activación») y la base de skills por rol que consigue Rafa. Decidido por Rafa el 5 oct 2026:
**tres roles (producto, marketing, comercial)**, lo que reabre «solo PM» y «otras plantillas»; documentado en `docs/03` §1 y §3.

*Rediseño «Activación», fase 1 (rama `feat/activacion-roles`, 5 oct 2026):* construido desde `Galeno B1 Activación.dc.html`, que
manda en estructura y textos pero no en estilo (pedido de Rafa: que siga viéndose como Galeno). Hecho: las tres pantallas
previas (una vez, se saltan), el paso del rol, el nombre solo, la grilla de herramientas en el orden del rol con las tres primeras
marcadas, la cabecera «Paso N de 6» y las skills por rol. **Decisiones tomadas al construir, por confirmar con Rafa:** «Reportes» y
«Reuniones» son comunes a los tres roles (producto 17 skills, marketing 18, comercial 24); se ofrecen todas las herramientas de
hoy, no solo las seis del boceto; la pantalla del rol no dice «se cambia después» porque «Gestionar» no cambia el rol; el idioma
se cambia con un enlace al pie de las pantallas previas. **Prueba de arranque limpio de Rafa (5 oct 2026, tarde):** el paso 2 se
quedaba «buscando» para siempre en un Mac sin instalación (venía del PR #32: nadie lanzaba la búsqueda la primera vez; corregido,
con prueba). De esa prueba salieron tres pedidos, ya hechos: esperas con texto animado en vez de una rueda (`WaitingTicker`),
«Darle contexto» como pantalla propia antes de las herramientas, y «crear» en vez de «escribir» al agente. **Segunda prueba
limpia (misma tarde): se activó de punta a punta** (siete herramientas conectadas, agente «Testing»), con tres hallazgos, ya
atendidos: Slack se quedó 37 s en la página de tokens porque, recién iniciada la sesión, Slack la pintó sin la sección de tokens
(confirmado en el registro de esa corrida); ahora Galeno la vuelve a cargar sola a los 5 s; «Abrir en la app de Claude» cayó en «Folder not found» porque el
enlace llegó mientras la app cargaba (ahora se espera a que deje de cargar, y «Listo» dice cómo repetirlo); y Rafa echó de menos
el paso «Skills», que el boceto quitaba: vuelve, con las del rol marcadas (siete pasos). Un borrador del asistente anterior se descarta (versión 2). Faltan las
fases 2 a 4 (`docs/03` §3). Sin probar a mano en la app real.
Y **las demás conexiones quedan en pausa** (Fireflies, Granola) hasta que lo que hay quede sólido.

*Skills por rol (rama `feat/skills-marketing`, 5 oct 2026):* **marketing completo, diez skills** adaptadas y con su licencia
(`skills/curated/`, `docs/03` §6.2): siete de Anthropic y tres de voz de marca de Tribe AI. Aparecen en el paso de skills en
un grupo «Marketing», sin marcar de fábrica, cada una con su dibujo. El agente **busca en la web sin pedir permiso**
(`WebSearch`; se ve en «Tus herramientas»). **Comercial completo: dieciséis** (rama `feat/skills-comercial`), las del plugin de ventas de Anthropic que funcionan sin
CRM. Ninguna envía nada (ni una invitación) sin un «sí», y `create-an-asset` escribe el contenido de un material, no el
archivo. Las otras veinte del plugin giran alrededor de un CRM y no se trajeron.
Faltan: que Rafa las revise, el resto de comercial, y **los roles**, que todavía no existen: hoy cualquier agente ve
marketing y comercial como dos grupos más. Por decidir: **si `WebFetch` (abrir una página concreta) también
va sin preguntar**, que hoy pide aprobación porque una dirección puede llevar datos; y si la copia de la guía anterior de
marca la debe hacer la app en vez del modelo (`guideline-generation` la reescribe a mano y puede no quedar fiel).

Lo que no entendió (UX):

- No hay onboarding: no sabía qué estaba haciendo ni para qué.
- La descripción y los archivos de contexto (paso 3) no se entienden ahí; irían en otro sitio.
- Las reglas son demasiado texto; las quiere más visuales. Y en general hay demasiado texto en toda la app.
- En el paso 5 quiso pasar de una conexión a otra pulsando los iconos de la tira (no son botones), no el botón del pie.
- Para reconectar o desconectar una cuenta fue por instinto al detalle del agente. No encontró «Gestionar» → herramientas:
  hace falta una entrada más visual (un icono).

### Demo con Felipe (4 oct 2026): Rafa lo considera no exitoso por Google

Instalación sin Terminal OK. Falló lo de Google, que es lo que más pesa:

1. **El paso 5 se pegó con la suite de Google ya conectada** (Felipe ya la tenía conectada en Claude Code antes de usar
   Galeno). La página del conector decía «Connected» y Galeno seguía girando; hubo que saltarlo, y **el agente se escribió sin
   Google**. Causa, reproducida: el arranque de sesión que lee el estado a veces no trae la lista de conectores de la cuenta, y
   con la caché de descubrimiento de Claude Code un conector ya usado sale `pending` siempre. *Arreglado en la rama
   `fix/conector-ya-conectado` (sin commit): sondeo sin caché y esperando conexiones, reintento si no llega la lista, `pending`
   no es «falta autorizar», y un solo arranque para conectores seguidos. Probado contra Claude Code real en el Mac de Rafa; falta
   probarlo en el de Felipe.* Detalle en `docs/03` §4e.
2. **«Abrir en la app de Claude» no reinició nada y el chat no tenía Gmail ni Drive**: consecuencia del punto 1 (confirmado por
   Rafa). Sin Google en el agente no hay reinicio de Claude (`AgentOpenPolicy.usesConnectors`), ni reglas `claude_ai_*`, ni la
   sección del `AGENTS.md` sobre conectores. No era un fallo del reinicio (con Simon funcionó).
   - Hueco que queda: un agente al que se le saltó una herramienta no puede recuperarla (falta «Gestionar la config»). Hoy la
     salida es crear otro con «Nuevo agente».
   - Resuelto (rama `fix/feedback-demos`): si Claude no sale al pedírselo, ya no se abre el agente en silencio; la pantalla
     pide cerrarlo con Cmd+Q y volver a pulsar «Abrir».
3. **Slack**: el mensaje salió con el nombre y la foto de Felipe (token de usuario). Identidad de bot: v0.0.2. La app de
   Slack ya se llama como el agente, sin «· Galeno» (abajo).

**No se regenera el DMG hasta que Rafa lo pida.**

*DMG de prueba con instalador (5 oct 2026, tarde; rama `chore/dmg-instalador`):* `scripts/hacer-dmg-demo.sh` arma `build/Galeno-demo-<fecha>-<commit>.dmg`
(bridge universal, app Release universal con firma ad hoc, comprobaciones, disco). El disco lleva `Galeno.app`, el acceso a Aplicaciones,
**`instalar-galeno.sh`** y el LÉEME (`scripts/dmg/LEEME.md`). El usuario no hace «arrastrar a Aplicaciones» ni pelea con Gatekeeper: abre la
Terminal, escribe `bash `, arrastra `instalar-galeno.sh` a la ventana y pulsa Intro. El script lista lo que va a quitar y pide `si`; manda **a la
Papelera** (nunca borra) la app anterior, `~/Galeno`, `Application Support/Galeno` (con la sesión de WhatsApp), cachés y preferencias, las
conversaciones de esos agentes en Claude Code y en la app de Claude; quita las conexiones de Claude Code **de Galeno** (`galeno-*` con dirección oficial) y, **solo si el usuario lo acepta aparte** (por defecto no;
`--yes` tampoco, salvo `--con-conexiones`), las de nombre genérico que pudo poner él o una versión anterior de Galeno; copia la app, le quita la cuarentena y la abre. No toca `~/.claude.json`
ni Claude Code. Solo usa lo que trae macOS (sin Python: el de macOS sin herramientas de desarrollo abre un aviso de instalación). Probado en un
HOME de mentira con dobles de `launchctl`, `defaults`, `claude`, `trash`…, con la app real; **sin correr de verdad en otro Mac**. `scripts/reset-pruebas.sh`
sigue siendo la versión para desarrollo (con `--dry`/`--yes`).

*Caída al pasar de las pantallas previas al asistente (5 oct 2026, noche, demo con Aquiles, macOS 15.6.1, Release):* `EXC_BREAKPOINT` en el hilo
`com.apple.SwiftUI.DisplayLink`, dentro de `Color.dynamic(light:dark:)`. El cierre del `NSColor` dinámico heredaba el aislamiento del actor
principal (la app lo lleva por defecto) y SwiftUI lo resuelve en un hilo de fondo con el renderizado asíncrono de macOS 15: Swift comprueba el
hilo y aborta. No se vio en el Mac de desarrollo (macOS 26). Arreglo: `nonisolated` en `Color.dynamic`; `ThemeColorTests` resuelve los colores
fuera del hilo principal (se comprobó que antes del arreglo tira el proceso de pruebas). **Falta probarlo en un Mac con macOS 15**, y revisar si
hay otros cierres para AppKit/SwiftUI con el mismo problema (por ahora el único es este). Convendría una máquina o una VM con macOS 15 para el QA.

### Segundo demo con Aquiles (5 oct 2026, noche): se activó, con nueve puntos de feedback

Con el DMG `-c` (arreglo del crash de macOS 15 incluido) Aquiles **se activó de punta a punta**. Su feedback, y qué se hizo
(rama `fix/feedback-aquiles-demo2`):

1. «Por qué:» sonaba raro dando una explicación → la línea del paso 2 ahora dice «Porque sin Claude Code…». **Hecho.**
2. Quería leer el mensaje que va a pegarle a Claude al traer contexto → la hoja muestra el mensaje completo junto a «Copiar». **Hecho.**
3. **Jira quedó conectado al workspace equivocado**: la hoja del sistema usa la sesión de **Safari** y sus cuentas de verdad estaban
   en otro navegador; y no había cómo cambiarlo desde Galeno. Decisión de Rafa: la autorización va al **navegador predeterminado**
   (la pestaña queda abierta: no se puede cerrar una pestaña ajena; Galeno vuelve al frente). **Hecho** (docs/03 §3 pantalla 5,
   `AGENTS.md`). Desconectar/cambiar una conexión desde la app sigue pendiente de la hoja «Herramientas» (rediseño, fase 4).
4. Tras instalar Claude Code pasó a «inicia sesión» sin confirmar que quedó instalado → línea «Claude Code quedó instalado
   (versión X)» antes de pedir la sesión. **Hecho.**
5. No vio Calendar porque quedaba lejos de Drive → las tres de Google van juntas en el orden de cada rol (la preselección por rol
   no cambia: ahora es lista propia, no «las tres primeras»). **Hecho.**
6. **Su organización de Claude no permite conectar Google Docs**: Galeno no puede saberlo ni arreglarlo (la política vive en
   claude.ai); el conector se salta y el administrador tendría que permitirlo. **Documentado** (QA E-10b); sin cambio de código.
7. Eligió producto y la pantalla de skills le enseñó también marketing y ventas → ahora enseña **solo los grupos del rol** (más
   cualquier grupo con una skill ya marcada, para agentes editados); los contadores y «Todas/Ninguna» cuentan solo lo visible. **Hecho.**
8. Las casillas del rol parecían de selección múltiple → radios, y el resumen dice «Elige uno». **Hecho.**
9. Las reglas nombraban Slack sin estar conectado → el texto fijo ya no nombra herramientas («Nada que vaya a otra persona…»);
   las listas («Aplica a: …») ya eran dinámicas. **Hecho.**

Sin probar en su Mac todavía; las pruebas de la app cubren 5, 7 y el aviso de instalado.

*Slack: «tu navegador no es compatible» (5 oct 2026, noche, demo con Aquiles, macOS 15.6.1, Safari 18.6):* **la causa no era la lectura de la versión de
Safari** (la hipótesis inicial; el Safari de esa Mac sí se lee, 18.6). Se comprobó pidiéndole a `slack.com/signin` con distintos identificadores: **responde
403 a todo Safari anterior al 26** (probados 15.6 a 25.6), y también a un Chrome 130 y un Firefox 130; con 26.0 o más, 200. Slack rechaza navegadores de
más de un año, así que un Mac con **Safari 18.6 no puede iniciar sesión en Slack** ni siquiera con Safari de verdad. Decisión: **no se disfraza la ventana**
(decir «Safari 26» en un Mac que tiene 18.6 sería mentir); se detecta el 403 de Slack y se le dice al usuario que actualice macOS/Safari (Ajustes del
Sistema → General → Actualización de software) o salte Slack. Arreglo para Aquiles: actualizar su Mac; Safari 26 existe para macOS 15. El umbral de Slack se
mueve con el tiempo: la detección es por la respuesta, no por un número. Además, la versión de Safari se lee ahora del *cryptex* primero y, si no es
creíble, se deduce de macOS (`SlackCapture.safariApplicationName`). Pendiente: probar en un Mac con macOS 15 ya actualizado.

*Conexiones con nombre propio (5 oct 2026, noche; rama `feat/conexiones-propias`; decisión de Rafa):* Galeno registra ahora sus conexiones como
`galeno-notion`, `galeno-jira`, `galeno-slack`…, nunca con el genérico, y **solo cierra sesión o quita lo que lleva su prefijo**
(`ToolConnection.galenoOwnsServers`). Motivo, un **incidente**: Rafa tiene un agente de Claude Code en `mediclub-monorepo` con su propio `notion` (alcance
local del proyecto) con la misma dirección que el de Galeno. Para empezar de cero se le pidió `claude mcp logout notion` y `claude mcp remove … -s user`
de Notion, Jira, Fathom y Claude Design: el `logout` borra las credenciales de OAuth, que Claude Code guarda por nombre y dirección (inferido: no
probado), así que ese otro agente, ya corriendo, perdió Notion. Se había avisado de que afectaría a las sesiones de desarrollo **de este repositorio**,
no de que podía afectar a otros, y no se miró antes quién más usaba esos servidores. Lección: **cerrar sesión o quitar un servidor de Claude Code
de alcance de usuario es una acción sobre todos los proyectos del Mac**; se mira qué proyectos lo usan y se avisa. Hecho: nombre propio por
defecto para las conexiones nuevas (el motor no cambia: el prefijo ya existía), una prueba de que el asistente registra `galeno-notion` y no toca
el `notion` del usuario, y el instalador, que ya solo quita lo propio sin preguntar. Las conexiones anteriores (sin prefijo) siguen con su nombre.
**Costo:** quien ya tenía Notion autorizado lo autoriza otra vez para Galeno. Pendiente (rediseño, fase 4): la hoja «Herramientas de <agente>» debe
usar la misma regla (en «Desconectar» solo se cierra sesión de lo propio; lo adoptado se desvincula del agente). Conexiones **por agente** (otro
workspace por cliente): v0.2, con la separación de contexto. Sin explicar todavía: el `slack` de la última prueba (y el conector `claude.ai Slack`)
quedaron en «Needs authentication».

### Slack: los mensajes salen con el nombre de la persona (demo de Felipe, 4 oct 2026)

El MCP de Slack solo acepta tokens de usuario: todo lo que el agente envía sale con el nombre y la foto de quien
autorizó la app, y solo la etiqueta «Sent using <agente>» (entonces «<agente> · Galeno») lo delata. Un compañero no puede saber que lo
escribió una IA, y el agente redacta en primera persona.

- **v0.0.2 (decidido por Rafa):** identidad de bot propia. Ya lo tiene armado a mano para su agente de MediClub
  (product engineer). Es un camino de envío propio con token de bot: línea roja 3 (cada envío con aprobación, el
  token de bot solo en la máquina del usuario). Está en `docs/03` §5.
- **Hecho (4 oct 2026):** la app de Slack se llama como el agente, sin «· Galeno» (`SlackManifestRenderer.appName`): era lo
  que aparecía en «Sent using …» bajo los mensajes. Las apps ya creadas con el nombre anterior lo conservan; se cambia a mano
  en api.slack.com/apps → la app → Basic Information → Display Information.
- **Por qué la app no aparece como miembro del workspace ni firma los mensajes:** la app que crea Galeno es de **token de
  usuario** y no tiene bot (`features.bot_user`). Slack solo muestra en la barra lateral las apps con bot, y un mensaje
  enviado con token de usuario es de la persona; la app solo deja su nombre en «Sent using». Cambiarlo es la identidad de bot
  de la v0.0.2: la app con bot y scope de bot, y un envío propio con el token de bot (el MCP de Slack no lo usa).

### Pendientes del primer demo (4 oct 2026, con Simon): la Fase 4b ya está

Primera prueba con alguien de fuera, instalando desde un DMG sin notarizar. Lo que salió:

**Fallos y huecos (se arreglan):**

- **WhatsApp no descarga adjuntos.** `download_media` solo mira la caché local y nadie llama a
  `downloadMedia` (`whatsapp-bridge/media.go`): `sync` recibe y guarda, pero no baja archivos. El
  agente encontró 5 documentos y no pudo abrirlos. **(1) Hecho** (bridge 0.2.2, rama `fix/feedback-demos`):
  el mensaje de la herramienta y el `AGENTS.md` generado dicen la verdad —todavía no se pueden abrir
  adjuntos, reintentar no sirve, el usuario los abre en WhatsApp—. **(2) Pendiente:** descargar de verdad,
  por el servicio de fondo (el único con conexión viva; `serve` no puede abrir otra). Los archivos viejos
  pueden pedir que el teléfono los vuelva a subir. Sigue siendo solo lectura.
- **Chats sin nombre.** Un chat salió como `106712858140679` en vez del nombre del contacto: es un
  identificador interno de WhatsApp (`@lid`) que el puente no cruza con la agenda.
- **Tono de lo que redacta.** Al pedirle cómo hacer seguimiento a un correo, propuso un texto
  agresivo (amenazar con denunciar ante la SIC). **Hecho** (rama `fix/feedback-demos`): regla 7 del
  `AGENTS.md` generado, «Tono cordial por defecto»: nada de amenazas, ultimátums ni escalamiento legal
  salvo que el usuario lo pida; si el caso lo amerita, se dice aparte como opción, no en el borrador.

**Peticiones del usuario (necesitan decisión de Rafa: tocan líneas rojas):**

- **Tareas repetitivas** («todos los días a las 8 am, haz tal cosa»). **Decidido y construido (Rafa,
  5 oct 2026; rama `feat/tareas-programadas`):** alcance acotado —leer, escribir en `memoria/`,
  escrituras internas; los envíos quedan de borrador y se aprueban por la mañana—; detalle y
  verificación de la puerta en `docs/03` §3b «Tareas programadas». La puerta pasó: un `ask` sin nadie
  delante se deniega (terminal, probado de primera mano) o queda esperando (tareas de la app de
  Claude, documentado); nada se la salta. Construido: la sección «Tareas programadas» del `AGENTS.md`
  generado, los borradores de Gmail en `allow` con su propio hook (la única excepción al paso libre
  de solo lecturas), y las skills `/tareas-recurrentes`, `daily-briefing` y `weekly-wrap` dicen cómo
  programarse. **Sin probar a mano una tarea real en la app de Claude.** El envío desatendido sigue
  en v0.2.
- **Prospección por WhatsApp.** **Decidido y construido (Rafa, 6 oct 2026; rama `feat/prospeccion`):**
  la skill nuestra `/prospeccion` (grupo «Comercial», marcada de fábrica para ese rol) deja cada mañana
  un archivo local en `memoria/informes/` con una fila por prospecto y un enlace `wa.me` que abre
  WhatsApp con el mensaje escrito; **Simon pulsa enviar**. Rafa decidió que eso no es enviar (línea
  roja 1 intacta: el puente no cambia). Prospectos de sus propios chats y, si pide un segmento, de la
  web, con el número solo si lo publica la propia empresa. Detalle en `docs/03` §6.3. **Sin probar
  con trabajo real.**
- **La mesa del home y los personajes (6 oct 2026; rama `feat/home-mesa`).** Cada rol tiene su personaje (Galeno,
  Wedgwood y Marco Polo, que en la app es «Marco»): su retrato sale en el selector de rol, en el ex libris, en las
  tarjetas y en la cabecera del detalle. El home gana la vista «Mesa» (de fábrica) con un interruptor a «Tarjetas»: una
  mesa de madera vista en diagonal —un paralelogramo, con la inclinación que eligió Rafa— con el personaje de cada
  agente apoyado en ella y su nombre encima. Un clic lo abre en Claude; al pasar el cursor aparece un engranaje que
  abre su detalle, y el clic derecho despliega un menú con nuestro estilo. Seis por mesa y una flecha a la siguiente.
  Solo escribe quien tuvo actividad en los últimos 3 minutos. La mesa y las figuras son láminas que Rafa generó con
  Adobe Firefly Image 4, preparadas en el Mac (`GalenoApp/arte-mesa/LEEME.md`). El reset de pruebas ahora también manda
  a la Papelera las conversaciones de Claude de los agentes, como «Eliminar». **Pendiente:** probarlo a mano (QA 6.14;
  el clic derecho, el engranaje al pasar el cursor y la mano escribiendo solo se vieron en renders), un Galeno sin el
  borde ovalado, una variación para dos agentes del mismo rol (hoy solo los distingue el nombre), el crédito CC BY del
  retrato de Wedgwood en «Acerca de» antes de distribuir, y el retrato en el sello exportado para Slack (hoy no lo lleva
  por esa licencia).
- **Correcciones al detalle tras la prueba de Rafa (6 oct 2026; rama `fix/detalle-conectar-y-skills`).** (1) «Añadir
  herramienta» conecta **ahí mismo** (la conexión de siempre encima del detalle; al quedar conectada, la fila entra con un
  destello) en vez de llevar al asistente. (2) Skills: las cards directamente, marcar/desmarcar, «Añadir skill…» y
  «Guardar skills»/«Descartar»; sin resumen ni «Elegir skills». Sin probar a mano contra cuentas reales.
- **«Listo»: abrir es terminar (6 oct 2026; rama `feat/listo-abrir-es-terminar`, apilada sobre el detalle).** De seis propuestas de
  Claude Design, Rafa eligió la A: **un solo botón, «Abrir en Claude Code»** (el nombre se mantiene por ahora), que abre el
  agente con su primera pregunta y, solo si se abrió, cierra el asistente y vuelve al home. Sin «Atrás» ni «Terminar»; una salida,
  «Ir a mis agentes sin abrir». Si falla, se queda y deja la pregunta a mano. Descartadas: abrir sola a los 3 s (cerraría Claude sin
  que el usuario pulse), dos pasos con «Terminar» apagado y terminar primero (posible mejora: marca «NUEVA» en la tarjeta). Pendiente
  de decidir: «está listo» (como hoy) o «está lista» (como las propuestas).
- **Detalle del agente (6 oct 2026; rama `feat/detalle-agente`, apilada sobre `feat/feedback-prueba-simon`).** Un clic en
  la tarjeta o en «Gestionar» abre `AgentDetailView`: cinco secciones (General, Herramientas, Skills, Reglas, Contexto) con
  «Abrir» arriba; rol, reglas y herramientas aplican al momento, skills y contexto al guardar. Reutiliza `HomeModel` (abrir,
  renombrar, eliminar con el nombre escrito), `HealthModel` (estado, reconectar, re-vincular) y el catálogo del asistente. «Quitar»
  una herramienta tiene dos intenciones: de este agente, o desconectar la cuenta (solo si es de Galeno: `galeno-…`; nunca un
  conector de la cuenta de Claude ni un servidor con nombre genérico). Contexto: `ContextFolder` (siguiente número libre, quitar a
  la Papelera). Rafa dijo al pasar el diseño: **los diseños son una guía, no una camisa de fuerza** (`AGENTS.md`). El diseño
  decía que eliminar quita las conexiones del agente: no se aplicó (son compartidas). **Sin probar a mano contra cuentas reales.**
- **Ajustes tras la prueba de Rafa (6 oct 2026; rama `feat/feedback-prueba-simon`).** (1) La sincronización
  de WhatsApp **espera a que termine**: se quitó «Seguir mientras sincroniza» (tope de seguridad de 10 min).
  (2) Un cuarto sonido, `paso.wav`, al pulsar «Siguiente» (reabre la decisión del 4 oct de «ningún sonido en
  cambios de paso», a petición de Rafa). (3) «Añadir skill…» pasa a la cabecera del paso Skills y «Tus skills»
  al principio de la lista. (4) Las reglas de escritura dejan el selector «Preguntarme / Sin preguntar» por dos
  radios con nombre y una frase que dice qué significa lo elegido. (5) La tira de conexión no numera («1 de 3»,
  «2 de 5»): iconos unidos por una línea punteada, tenues hasta conectarse.
- **Cargar sus propias skills.** **Decidido y construido con alcance acotado (Rafa, 6 oct 2026; rama
  `feat/skills-propias`):** solo archivos del propio usuario, de su Mac, elegidos en el selector del paso
  «Skills» («Tus skills» → «Añadir skill…»); viven en `skills-propias/` del agente, carpeta que el motor
  no toca; el agente no puede editarlas y no cambian ningún permiso. Nada remoto ni de terceros: «trae tu
  skill» por enlace sigue cerrado (línea roja 6). Detalle en `docs/03` §6.3. **Sin probar con una skill
  real de Simon.**

**Comprobado en el demo, en el Mac de Simon (un Mac limpio):**

- La instalación sin Terminal, por Ajustes del Sistema → Privacidad y seguridad → «Abrir igualmente».
  El puente de WhatsApp arrancó: macOS no bloqueó su copia.
- El reinicio de Claude desde «Listo»: se cierra, se reabre en el agente y ve los conectores.
- Las herramientas en «Próximamente» (`Tool.isComingSoon`) se quedan así hasta probarlas de punta a punta.
  Eran cinco; desde el 4 oct 2026 (rama `feat/herramientas-pendientes`): **Google Meet salió de la grilla**
  (se lee por Drive), **Jira y Fathom están desbloqueadas para probarlas** con las cuentas de Rafa, y quedan
  Fireflies y Granola. **Jira:** Rafa la conectó desde Galeno; ya tiene sus listas reales de herramientas y sus
  permisos (`docs/03` §4e); falta que la pruebe con una pregunta real. **Fathom:** conectada por Rafa; sus 12 herramientas (todas de lectura) ya están
  en el catálogo por nombre; falta su prueba con una pregunta real. El reinicio de Claude tras cambiar herramientas
  en «Gestionar» funcionó con Jira (prueba de Rafa). En la misma rama: el logo de Fathom se redibujó desde la imagen que
  aportó Rafa (el anterior era de Fathom Analytics, otra empresa), y las herramientas con OAuth en el navegador se autorizan
  ahora en la hoja de autenticación del sistema (`SystemAuthorizationSheet`), **sin probar aún con una autorización real**.

**Sigue sin verificar:**

- La aprobación al enviar un correo o crear un evento en la app de escritorio, en una sesión real
  (los hooks solo están probados con patrones).

**Firma y notarización (Fase 8, 6 oct 2026; rama `chore/firma-y-notarizacion`).** `scripts/build-release.sh` compila
el motor, el bridge universal y la app; firma el bridge y la app con hardened runtime (de dentro hacia fuera), crea el
DMG con `create-dmg`, lo notariza con `notarytool`, lo grapa y lo verifica con `spctl`. Explicado en `docs/RELEASE.md`.
Los entitlements van vacíos a propósito. **Corrido de punta a punta el 6 oct 2026**: Apple aceptó la notarización
y Gatekeeper (`spctl`) dio por buenos el disco y la app que va dentro («Notarized Developer ID»). **Va firmado con el
Developer ID de Aquiles Torres** (equipo `9TDS6NBM3F`), con su permiso, porque la cuenta de Rafa es gratuita: la app sale
a nombre de Aquiles. Es un puente hasta que Rafa inscriba su propia cuenta en el Apple Developer Program; cambiar de
certificado es barato mientras no esté Sparkle. Los datos de firma están en `scripts/release.env` (no se commitea) y la
contraseña de app de Aquiles, en el llavero de Rafa (perfil `galeno-notary`). **Sin probar:** abrir ese DMG en otro Mac,
descargado, que es la prueba de verdad (fila «Mac limpio» de `docs/QA.md`). Ojo: la app dice ser la versión **1.0**
(`MARKETING_VERSION`), no la 0.0.1 de los documentos; el DMG toma ese número. `scripts/hacer-dmg-demo.sh` sigue para
demos sin firma.

**Sparkle (Fase 8, 6 oct 2026; rama `feat/sparkle`).** La app lleva Sparkle 2.10.0: mira el appcast al abrir y desde
«Buscar actualizaciones…» (menú y Ajustes), sin perfil del sistema ni datos del usuario. La clave EdDSA se generó una
vez: **la privada está en el llavero de inicio de sesión de Rafa, cuenta `galeno`** (elemento «Private key for signing
Sparkle updates»); **falta que Rafa guarde una copia**, porque sin ella las apps instaladas se quedan sin
actualizaciones. No se subió como secreto de GitHub: hoy el release corre en su Mac y no hay flujo que la use; el
comando está en `docs/RELEASE.md`. `scripts/build-release.sh` firma las piezas de Sparkle, firma el disco y actualiza
`site/appcast.xml` con las notas, que dicen si el bridge cambió. **Comprobado:** Apple notarizó la app con Sparkle
dentro; el paso del appcast se probó contra un disco real con una dirección de prueba (entrada firmada, firma
verificada, historial conservado, cambio de versión del bridge detectado). **Sin probar:** una actualización de verdad
de punta a punta —una app instalada que vea una versión nueva, la descargue y se reemplace—, porque no hay sitio donde
publicar el appcast. **La dirección del appcast es de relleno** hasta la Fase 9: con ella la app no busca
actualizaciones y el script se niega a entregar salvo con `--sin-actualizaciones`. El bridge ya tenía su subcomando
`version` (va por la 0.3.0) y Salud ya lo mostraba.

**Licencias: aparcadas (decisión de Rafa, 6 oct 2026).** La v0.0.1 se vende como «paga, descarga y usa», sin clave ni
pantalla de activación. El trabajo (verificación Ed25519, herramienta de firma, pantalla con prueba de 7 días) está
guardado en la rama `feat/licencias`, sin mergear, por si hace falta una prueba gratis o cobrar una versión mayor. Lo
que se acepta a cambio: quien tenga el instalador, o dé con la dirección del appcast de Sparkle, puede usar Galeno sin
pagar. **Una licencia, si llega a haberla, cubre agentes ilimitados.** La clave privada que se generó sigue en
`~/.galeno-signing/` del Mac de Rafa, fuera del repo.

---

## 13. Documentos

| Archivo | Qué es | Vigencia |
|---|---|---|
| `docs/01-plan-producto.md` | Problema, mercado, diferencial, visión de plantillas, roadmap | Vigente; conciliado con 03 |
| `docs/02-perfil-pm.md` | Perfil del PM multi-proyecto, leer vs. enviar | Vigente; indica qué es v0.0.1 y qué es v0.2 |
| `docs/03-especificacion-v0.0.1.md` | Especificación del MVP | **Fuente de verdad** |
| `docs/04-design-system.md` | Sistema de diseño | Vigente para app y sitio |
| `docs/QA.md` | Matriz de pruebas de la v0.0.1: cada paso del asistente (caso feliz y errores), «Mac limpio», después del asistente (§3b), resistencia, seguridad y el registro de corridas | Escrita el 5 oct 2026 (Fase 6, paso 1). **Sin recorrer todavía en un usuario limpio** (paso 2) y con la actualización de la app bloqueada hasta Sparkle (Fase 8) |
| `docs/DEV.md` | Cómo usar `galeno-gen`, la herramienta de desarrollo del motor | Vigente |
| `AGENTS.md` | Guía operativa para el agente en este repo | Vigente |
