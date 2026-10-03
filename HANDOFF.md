# Galeno — HANDOFF

Resumen ejecutivo para cualquier sesión futura. Léelo antes de tocar nada.
Fuente de verdad: `docs/03-especificacion-v0.0.1.md`. Este archivo la resume, no la reemplaza.

**Estado (3 oct 2026):** el motor (`GalenoCore`) genera la config y el bridge de WhatsApp
(`whatsapp-bridge`) está probado a mano contra una cuenta real (vincular, sincronizar, leer
desde Claude Code, confirmar que no puede enviar); falta probar que `sync` sobrevive a un
reinicio vía `launchd`. Tras la sesión de descubrimiento del 3 de octubre quedan ajustes
pendientes en el motor y el bridge (descripción y memoria del proyecto, subagentes, varios
agentes, filtro de chats): ver §6 y §12. Faltan la app (`GalenoApp`), las skills, Sparkle
y la distribución.
Repo privado: `github.com/Rafaell416/galeno`, rama por defecto `main`.

---

## 1. Qué es y para quién

**Galeno** es una app de escritorio nativa para Mac que, con un wizard, crea y configura
un agente en Claude Code para **Product Managers**. El usuario ya tiene (o instala) Claude
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
| Contexto del proyecto | Una línea en el wizard; en la primera sesión el agente lee las fuentes y propone un resumen que el usuario confirma |
| Memoria | El agente mantiene notas en `memoria/proyecto.md` (`CLAUDE.md` la importa). Es el único lugar donde escribe sin que nadie lo apruebe; lo que Galeno genera está bloqueado por regla y cualquier otra ruta pide permiso |
| Dueño de la config | **Galeno**: regenera los archivos completos al cambiar algo; nunca toca `memoria/` |
| Proactividad | El agente solo trabaja cuando se lo piden. Sin tareas programadas en v0.0.1 |
| Actualizaciones | **De por vida, gratis**, sin renovación. Tres capas independientes: app (Sparkle), bridge de WhatsApp (viaja en la app, con versión propia) y skills (remotas, sin reinstalar). Sparkle va desde el primer build. Detalle: `docs/03` §4f |
| Perfil | **Solo Product Managers** |
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
| Freemium o suscripción; tres plantillas de entrada | Pago único USD 200, solo PM |
| WhatsApp sin lectura, solo salida por Business API | WhatsApp solo lectura (no oficial, con advertencia); sin envío |
| Transcripciones vía export a Notion/Docs | MCP oficial de cada proveedor |
| Skills adaptadas al español | Skills en inglés + instrucción de idioma |
| Un solo agente para todos los proyectos | Un agente por proyecto |
| Wizard completo para cada agente nuevo; duplicar un agente existente | Wizard corto, reutilizando conexiones |
| Carpeta oculta en Application Support, o elegida por el usuario | `~/Galeno/<agente>/`, visible |
| Chat propio dentro de Galeno | Se abre en la app de Claude o en Terminal |
| Zonas editables a mano en la config, o detectar cambios y preguntar | Galeno regenera todo, salvo `memoria/` |
| Selección de chats de WhatsApp solo por instrucción | El bridge la impone |
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
   distingue a un agente de otro. En WhatsApp lo impone el bridge.
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
- **Falta (bridge):** un número de versión propio (`docs/03` §4f, capa 2). Hoy el binario
  no tiene subcomando ni constante de versión del producto.
- **Falta (bridge):** el filtro de chats. Hoy `serve` le entrega al agente **todos** los
  chats sincronizados, incluidos los personales. Decidido: `serve` recibe la lista de chats
  permitidos para ese agente y sin lista no expone ninguno; más un subcomando que liste los
  chats para que la app arme "elige qué leer". Ojo con los contactos que aparecen con dos
  JID (número y `@lid`): el filtro debe tratarlos como el mismo chat.
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
| Tareas programadas | después |
| Skills externas, "trae la tuya" (link de GitHub) | v0.2, con su guardrail |
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

---

## 12. Puntos abiertos (no decididos en los docs)

- **Variables de entorno de los tokens:** dónde se guardan los valores a los que apunta `.mcp.json`.
- **Pagos y licenciamiento:** la spec ya da por hechos un webhook de Stripe y una clave
  privada de licencias (§4f los menciona de pasada), pero el mecanismo de activación sigue
  sin estar escrito en ningún documento.
- **Sparkle, pendiente de arrancar:** generar el par de claves EdDSA (la privada fuera del
  repo) y definir la URL del appcast y la ruta de las skills remotas, en el dominio del sitio.
- **Skills remotas, sin diseño:** quién descarga (¿`GalenoApp` llena el directorio que ya
  recibe el motor, o el motor aprende a hablar con la red?), cómo se versionan, dónde vive
  el fallback local y **cómo se verifica su integridad**. La spec exige firma EdDSA para
  la app, pero no dice nada equivalente para las skills, y una skill es instrucciones para
  el agente: un canal remoto sin verificación sería una puerta de entrada de contenido no
  revisado (regla §5.5).
- **Abrir el agente en la app de Claude:** decidido que el usuario elige entre la app de
  Claude y Terminal, pero falta verificar cómo se abre una carpeta concreta en la app de
  Claude desde Galeno y que cargue toda la config generada (hooks, `.mcp.json`, skills).
- **Licencia y número de agentes:** falta decidir si una licencia cubre agentes ilimitados.
- **Carpetas visibles:** `~/Galeno/<agente>/` está a la vista; falta decidir qué hace el
  home si el usuario la borra, la mueve o la renombra, y cómo se renombra o elimina un
  agente desde Galeno.
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
- **Versión propia del bridge:** falta decidir el esquema y cómo permite parchear el
  bridge "sin re-releasear toda la app" si viaja empaquetado dentro de ella.
- ~~MCP exactos de Slack, Notion, Jira, Gmail y Drive~~ — **resuelto** (oct 2026): todos
  verificados contra la documentación oficial. Google Workspace resultó ser tres servidores
  (Drive, Docs, Sheets), no uno. Ver `docs/03` §4e para el detalle y la decisión de
  bring-your-own-app para Slack y Google.
- **Automatización de navegador para Google** (Fase 4, GalenoApp): decidido construirla
  —crea el proyecto y la credencial OAuth en la consola de Google en nombre del cliente—,
  con el riesgo aceptado de que sea frágil ante cambios de esa consola y de que Google
  detecte la sesión como automatizada en una pantalla sensible. Sin diseño todavía: es un
  proyecto de ingeniería propio, no una extensión del motor.
- **Granola:** confirmar si borra transcripciones a las ~72 h; si es así, sincronizar pronto.
- **Fathom:** la búsqueda lee títulos y resúmenes; la transcripción completa se pide por ID.
- **Licencias por verificar:** plugin PM de Anthropic y `Digidai/product-manager-skills`.
- **Protección de `main`:** pendiente. Exige GitHub Pro en un repo privado; se decidió
  dejarlo así por ahora y sostener la regla de rama + PR por disciplina.
- **Lista concreta de skills curadas:** sin definir.
- **Nombres de las skills:** el contenido va en inglés, pero la lista mezcla nombres en
  inglés (`/prd`, `/groom`) y en español (`/acta`, `/seguimiento`). Falta decidir cómo se
  llaman para un usuario que eligió inglés.
- **`/reporte-excel`:** la spec dice que escribe en "Google Sheets / Excel", pero Excel no
  es una herramienta conectada y el agente no ejecuta código. Falta decidir si es solo Sheets.
- **Tecnología de `site/`:** sin definir. Estructura y estilo sí (`docs/04` §9).
- **Tiempo de Rafa:** MediClub lanza el 15 de noviembre de 2026 y compite por su atención.

---

## 13. Documentos

| Archivo | Qué es | Vigencia |
|---|---|---|
| `docs/01-plan-producto.md` | Problema, mercado, diferencial, visión de plantillas, roadmap | Vigente; conciliado con 03 |
| `docs/02-perfil-pm.md` | Perfil del PM multi-proyecto, leer vs. enviar | Vigente; indica qué es v0.0.1 y qué es v0.2 |
| `docs/03-especificacion-v0.0.1.md` | Especificación del MVP | **Fuente de verdad** |
| `docs/04-design-system.md` | Sistema de diseño | Vigente para app y sitio |
| `docs/DEV.md` | Cómo usar `galeno-gen`, la herramienta de desarrollo del motor | Vigente |
| `AGENTS.md` | Guía operativa para el agente en este repo | Vigente |
