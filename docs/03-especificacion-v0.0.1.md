# Galeno v0.0.1 — Especificación del MVP
### App de escritorio (Mac) que crea y configura tu agente en Claude Code, para Product Managers

**Fecha:** 2 de octubre de 2026 · **Nombre del producto:** **Galeno**
**Complementa:** `01-plan-producto.md` · `02-perfil-pm.md` · `04-design-system.md`
**Es la fuente de verdad del alcance:** si otro documento dice algo distinto, manda este.

---

## 1. Decisiones cerradas (no se reabren en v0.0.1)

| Decisión | Valor |
|---|---|
| Nombre | **Galeno**. La app es la marca; cada usuario nombra a *su* agente en el wizard |
| Perfil | **Solo Product Managers** (dev, legal, salud: después) |
| Plataforma | **Solo Mac** |
| Motor | **Solo genera configuración de Claude Code** (Codex/Cursor/Grok: después) |
| Modelo de negocio | **Pago único: USD 200** (precio inicial) |
| Marketplace de skills | **A futuro**, no en v0.0.1 |
| WhatsApp | **Solo lectura** (read-only por estructura de código). Envío: v0.2 |
| Varios proyectos | **Un agente por proyecto**, cada uno en su carpeta (`~/Galeno/<agente>/`). En v0.0.1 se pueden crear varios; la **separación garantizada de contexto** entre ellos es v0.2. Ver §3b |
| Envío de mensajes | Solo por **Slack y email** (APIs oficiales) |
| Secretos del usuario | **Nunca tocan infraestructura propia.** Todo local |
| Arquitectura | **La app Mac es la única interfaz del usuario.** Por debajo, un motor (librería/binario interno) genera la config; el usuario nunca lo ve ni lo usa. Motor y app se construyen en paralelo |
| Framework de la app | **Swift + SwiftUI, nativa de Mac.** Rafa ya domina Swift; es la app que mejor se siente en Mac y no requiere Rust ni contenedor web. Trade-off aceptado: no portable a Windows (Mac-only es firme) |

---

**Sobre la arquitectura con Swift:** Galeno.app es un orquestador de procesos. Swift/SwiftUI hace el wizard y genera la config; lanza y supervisa un binario Go para WhatsApp; y corre `claude mcp add` para los MCP hospedados. Ver §4c.

**Sobre la marca:** Galeno es el nombre del producto (la app que crea agentes), no del agente. Cada usuario nombra el suyo. El Galeno de MediClub es el primer agente nacido del producto y sirve como caso de referencia: "el primer Galeno fue el mío, para una clínica". Narrativa: *Galeno te crea tu agente.*

## 2. Qué hace la v0.0.1 (y nada más)

Un usuario con Claude Code instalado abre la app, responde un wizard, y queda con un agente que:

**Lee de:**
- WhatsApp — grupos y chats que el usuario elija (vinculación por QR, read-only)
- Slack — canales que el usuario elija
- Notion — páginas y bases que el usuario comparta
- Google Drive / Docs / Sheets — carpetas que el usuario autorice
- Jira — proyectos que el usuario autorice
- **Claude Design** — los diseños del usuario: el agente abre el enlace de un diseño, o el nombre de un proyecto, que el usuario le pase. Servidor `api.anthropic.com/v1/design/mcp`, **no verificado**: Claude Code ya lo inyecta solo como `claude_design` y Anthropic no lo documenta como servidor que se registre; hay reportes de 404/401 con algunas cuentas. Decidido por Rafa añadirlo igual, registrado como `claude-design` y con aviso `unverifiedEndpoint` al generar. No tiene OAuth propio: entra con la sesión de Claude Code, así que Galeno lo registra y comprueba el estado sin abrir ningún navegador (`claude mcp login` responde que no hay nada que autorizar). Puede crear, editar y borrar archivos, así que de fábrica **pregunta** (el resto de escrituras internas van sin preguntar). Sin logo propio: un símbolo genérico hasta tener uno con licencia
- Email — **Gmail** (OAuth oficial de Google; mismo flujo que Drive)
- Transcripciones de reuniones — **directo por MCP oficial**: Fireflies (`api.fireflies.ai/mcp`), Granola (`mcp.granola.ai/mcp`), Fathom (`api.fathom.ai/mcp`, gratis en todos los planes). Google Meet: vía el MCP de Google Drive (las transcripciones de Gemini caen ahí)

**Escribe en (con aprobación humana para lo externo):**
- Notion y Jira — crear/actualizar tareas y docs
- Google Docs — escribir documentos
- Slack — enviar informes a canales
- Email — redactar y enviar (con aprobación)

**NO hace en v0.0.1:**
- Enviar por WhatsApp
- Garantizar la separación de contexto entre agentes. Se pueden crear varios agentes, uno por proyecto (§3b), pero salvo en WhatsApp la separación es por instrucción, no por estructura (ver §5)
- Trabajar por su cuenta: el agente solo actúa dentro de una sesión que abre el usuario. Sin tareas programadas
- Generar config para otros agentes que no sean Claude Code

---

## 3. El flujo del wizard (pantallas)

1. **Idioma y bienvenida** — el usuario elige **español o inglés** (preseleccionado según el Mac). Define el idioma de todo el wizard y el que el motor inyecta en la config. Luego: qué es, qué va a configurar, cuánto tarda (~10-15 min según cuántas tools conecte).
2. **Detección** — verifica que Claude Code esté instalado; si no, guía para instalarlo.
3. **Tu agente** — el usuario le pone nombre a *su* agente ("¿Cómo quieres llamarlo?"), rol (en v0.0.1 solo "Product Manager"), y **una línea que describe el proyecto** ("App de citas para la clínica X, lanzamos en noviembre"). Galeno es la app; el agente es del usuario. La descripción es deliberadamente corta: el agente la completa en su primera sesión (§3b).
4. **Elige tus herramientas** — una sola pantalla con la grilla de todas las tools disponibles (WhatsApp, Slack, Notion, Google Drive/Docs/Sheets, Jira, Claude Design, Gmail, Fireflies, Granola, Fathom, Google Meet). El usuario marca **solo las que usa**. Esto define cuántos pasos tendrá el sub-wizard siguiente: si marca 4, son 4 conexiones; si marca 8, son 8. Al pie, un texto tipo "Vas a conectar 5 herramientas · ~8 min".

5. **Conecta una por una (sub-wizard dentro del wizard)** — patrón de onboarding tipo Cal AI / Duolingo. Es el paso más largo del producto, así que está diseñado para **mantener el enganche**:
   - **Barra de progreso siempre visible** arriba: "3 de 5 conectadas", con los logos de las tools marcados a medida que se completan.
   - **Una conexión por pantalla**, en orden. Cada pantalla: logo grande, una línea de qué va a poder hacer el agente con esa tool ("Leerá tus canales de Slack para hacerte seguimiento"), botón "Conectar" que lanza el OAuth (o el QR en WhatsApp, con su advertencia explícita, ver §4).
   - **Feedback inmediato al conectar:** animación corta de éxito (check que se dibuja, el logo "encendiéndose"; con trazo y opacidad, sin rebotes ni confeti de colores — ver `04-design-system.md` §8), texto tipo "¡Slack conectado! Encontré 12 canales". **Mostrar un dato real** de lo que se conectó (cuántos canales, cuántos grupos, cuántas reuniones) hace que el usuario sienta que el agente ya "ve" su mundo.
   - **Transición automática** a la siguiente conexión tras ~1.5 s, sin que el usuario tenga que dar "siguiente" (puede saltar con un botón discreto "Conectar después").
   - **Pantallas de dopamina intercaladas** cada 2-3 conexiones, para romper la sensación de proceso largo: una pantalla a pantalla completa, sin botones de OAuth, que celebra el avance y anticipa valor. Ejemplos:
     - Tras las 2 primeras: "Tu agente ya tiene memoria de tus reuniones y tu Slack. Esto es lo que va a poder hacer…" con 3 ejemplos concretos de comandos.
     - A mitad: "Ya vas por la mitad. La mayoría de los PMs recupera ~1 hora al día con esto."
     - Antes de la última: "Una más y tu agente queda listo."
   - **Si un OAuth falla**, no se rompe el flujo: mensaje claro, botón "Reintentar" y botón "Saltar por ahora" (la tool queda marcada para conectar después desde la app). El usuario nunca se queda atrapado.
   - **Al terminar todas:** pantalla de celebración grande ("¡Listo! Tu agente ve X canales, Y grupos, Z reuniones") que da paso al siguiente paso.

   **Principio de diseño:** el usuario siempre sabe dónde va, cada conexión le devuelve algo tangible, y nunca hay más de ~2 min sin una pequeña recompensa visual.

6. **Elige tus skills** — dos niveles, en una sola pantalla:
   - **Las nuestras:** la lista de skills del perfil PM (§6.1), en columnas por grupo; la descripción de cada una aparece al pasar el puntero. Todas marcadas por defecto; el usuario desmarca las que no quiere.
   - **Curadas de la comunidad:** una lista seleccionada por nosotros de skills de terceros que le pueden servir (de pm-skills, phuryn, el plugin oficial de Anthropic…). Cada una con **crédito al creador y link a su GitHub**. Es buena ética y buen marketing: los creadores se enteran de que los recomendamos.
   - *("Trae la tuya" —pegar un link de GitHub— queda para una versión posterior. Ver §5 y §6.3.)*

7. **Reglas** — el pacto: lo que nunca hace (enviar por WhatsApp), lo que siempre pregunta (todo envío externo) y lo que el usuario decide (escrituras dentro de sus herramientas).
8. **Revisión** — todo lo decidido en una página (herramientas, skills, reglas), con un «Cambiar» por bloque que vuelve a su paso. Nada se escribe hasta pulsar «Escribir a ⟨nombre⟩».
9. **Escribiendo** — el motor escribe la config. Los pasos se ven mientras ocurren (escribiendo reglas, conectando herramientas, creando skills, guardando) para que la espera también sea parte de la experiencia.
10. **Listo** — cómo usarlo, primeros comandos sugeridos, dónde está la config. Y la primera invitación a probarlo: "Pídele: resume lo que pasó esta semana en Slack". El usuario elige dónde abrir su agente: **en la app de Claude o en Terminal**. Desde aquí se llega al home (§3b).

> **Cambio del rediseño B1 (4 oct 2026, decidido por Rafa):** la pantalla «Elige qué leer» (el foco por herramienta) **sale del wizard**; en su lugar entra «Revisión». Sin ella, lo conectado se lee entero: el `AGENTS.md` dice «todo lo que la herramienta expone». El modelo (`SourceSelection`) y el código que lista fuentes (`SourcesFlow`, `SourceListing`) se conservan para ofrecer el foco más adelante, desde el home.

### Complementos del asistente (rediseño B1, 4 oct 2026)

Decididos por Rafa a partir de `docs/07-ideas-ux.md` (las que no chocan con `AGENTS.md`):

| Qué | Cómo |
|---|---|
| **Reanudar** | `WizardState` guarda un borrador en `~/Library/Application Support/Galeno/draft.json` (permisos 0600) en cada cambio. **Sin credenciales**: solo lo que lleva un `AgentConfig` (nombres, herramientas con su estado, `client_id` público, skills, reglas) y el paso. Al abrir, si hay uno con avance: «Ibas por el paso N… ¿Seguimos?» → *Continuar* o *Empezar de nuevo*. Se borra al llegar a «Listo». Nunca se reanuda dentro de «Escribiendo»: vuelve a «Revisión». |
| **Teclado** | `Return` avanza; `Esc` vuelve (salvo en bienvenida, conexión y escritura; en las ventanas de Slack cancela); menú «Paso»: `⌘→` / `⌘←` y `⌘1…⌘0` para saltar a un paso **ya visitado**; en la grilla de herramientas, flechas para moverse y espacio para marcar. |
| **Ayuda** | Un «?» en la cabecera con un popover de tres preguntas por paso (`help.<paso>.<n>.q/.a`); ninguno en «Escribiendo». Sin tour ni globos. |
| **Vista previa viva** | Desde el paso 3, un botón en la cabecera abre el `AGENTS.md` que el motor escribiría **ahora** (`AgentPreview`, solo lectura), con lo nuevo desde la última vez marcado. No escribe nada. |
| **Pacto a la vista** | En «Listo», una línea: lo que nunca hace, lo que siempre pregunta y lo que escribe sin preguntar, con «Cambiar» (vuelve a «Reglas»). |
| **Sello como icono** | El ex libris del paso 3 se exporta como PNG cuadrado de 1024 px desde la tarjeta de la app de Slack («Guardar el icono»), sobre papel claro. |
| **«Lo que verás»** | Cuatro esquemas de línea: navegador (OAuth), ventana de Slack para entrar, ventana de Slack para permitir y teléfono (WhatsApp). |
| **Ajustes (⌘,)** | Apariencia Sistema/Claro/Oscuro, «Menos movimiento», «Sonidos» (tres: conexión lograda, algo falló y el sello de «Listo»; encendidos de fábrica) y grano. Cerrar la ventana del asistente cierra la app aunque Ajustes esté abierto. |
| **Portada** | La primera vez, el retrato y «Galeno.» un momento. Sin cita: solo entra una frase verificada en su fuente. |

### Detalles de las pantallas 1–4 (decididos al construirlas, Fase 4)

La línea de cada pantalla de arriba no bastaba para construirlas. Esto es lo que se decidió; cualquier punto se puede cambiar.

| Tema | Decisión |
|---|---|
| Idioma | Selector segmentado en la pantalla 1, con cada idioma en su propio idioma ("Español" / "English"). Cambia **toda la app en caliente**, sin reiniciar. |
| Detectar `claude` | Una app abierta desde Finder hereda un PATH mínimo (sin Homebrew ni `~/.local/bin`). Se miran primero las rutas de los instaladores (`~/.local/bin/claude`, `/opt/homebrew/bin`, `/usr/local/bin`, `~/.claude/local/claude`) y, si no está, un shell de login (`zsh -lic 'command -v claude'`, máx. 5 s) que cubre npm/nvm. Luego `claude --version` y `claude auth status` (solo se lee `loggedIn`; el correo no se guarda ni se muestra). |
| Versión mínima | Ninguna. Solo se muestra la versión. |
| Si no está instalado | Galeno **no lo instala** (sería descargar y ejecutar un script remoto). Muestra el comando oficial (`curl -fsSL https://claude.ai/install.sh \| bash`) con botón Copiar, el enlace a `https://code.claude.com/docs/en/setup` y "Comprobar de nuevo". |
| Sin sesión iniciada | Aviso **no bloqueante**: se necesita para usar el agente, no para configurarlo. |
| Siguiente se bloquea | Pantalla 2: hasta encontrar `claude` (el paso 5 usa `claude mcp add`). Pantalla 3: sin nombre válido. Pantalla 4: sin ninguna herramienta. |
| Nombre del agente | Obligatorio, máx. 60 caracteres (el tope de `AgentFolder`). El rol se muestra fijo ("Product Manager"). |
| Descripción | Opcional, una línea, máx. 140 caracteres. |
| Google Meet | Se lee con Drive (`Tool.requires`): marcar Meet marca "Google Drive, Docs y Sheets", que no se puede desmarcar mientras Meet siga marcado. |
| Tiempo por herramienta | Estimación (no medida): WhatsApp 3 min; Slack, Gmail y Google Workspace (traen su propia app OAuth) 2; las demás 1; Meet 0. El "~X min" es la suma. Se calibra con la prueba de la Fase 4. |
| Logos | Monocromos `ink-700`: Simple Icons (CC0) para WhatsApp, Notion, Google Drive, Gmail, Jira, Google Meet y Fathom; un SF Symbol para Slack, Fireflies y Granola, que no están en esa colección, hasta tener el SVG oficial. Ver `GalenoApp/THIRD_PARTY.md`. |

### Detalles de la pantalla 5 (decididos al construirla, Fase 4)

Probado con Claude Code 2.1.277. El paso 5 es un sub-wizard: oculta la barra Atrás/Siguiente y lleva sus propios botones; la barra vuelve en la celebración final.

| Tema | Decisión |
|---|---|
| Conectar un MCP hospedado | (1) `claude mcp get <nombre>`: si ya está `Connected`, éxito inmediato ("ya estaba conectada"); si pide autorización, solo el paso 3. (2) Si no existe: `claude mcp add --transport http -s user <nombre> <url>`. (3) `claude mcp login <nombre>`, que abre el navegador y espera el OAuth. Nunca se hace `remove` (puede ser configuración del usuario). Es idempotente: cerrar la app a mitad y volver no repite trabajo. |
| Ya existe otro servidor con ese nombre | Si `get` encuentra un servidor con el nombre pero otra dirección (p. ej. uno local de `npx`), Galeno **nunca lo borra ni lo pisa por su cuenta**: pregunta. Lo predeterminado es **«Usar otro nombre»**: registra el suyo como `galeno-<nombre>` (`galeno-slack`) y el motor genera `.mcp.json`, reglas de permisos, matcher del hook y subagentes con ese mismo nombre (`ToolConnection.serverNamePrefix`). Borrar el existente es una opción aparte: pide una segunda confirmación que dice qué se borra (su configuración, para todos sus proyectos; nada de la herramienta en sí), con «Mejor no» como botón por defecto. Si también `galeno-<nombre>` está ocupado, falla con el nombre a la vista. |
| Alcance `-s user` | La conexión se hace una vez y la comparten todos los agentes (§3b). Comprobado: un servidor registrado así se ve `Connected` desde cualquier carpeta. |
| `login` pide un terminal | Sin terminal se niega ("stdin isn't a terminal"), aunque el OAuth se complete solo por el navegador (callback en `localhost`). La app lo lanza bajo un pseudo-terminal que ella misma crea. |
| Cómo se sabe que conectó | Por el **texto** de `claude mcp get` (`Status: ✔ Connected` / `! Needs authentication` / `✘ Failed to connect`): sale con código 0 en todos los casos. Se usa `get` por servidor y no `list` (7 s con 8 servidores, y comprueba también los del usuario). |
| Dato real ("Encontré 12 canales") | Galeno no toca el token (lo guarda Claude Code), así que le pide a Claude Code que mire: `claude -p` con solo ese servidor permitido, modelo `haiku`, `--output-format json`, sin guardar sesión y con tope de gasto de $0,15, pidiendo **solo un entero** (con `+` si fue una primera página). **Costo medido:** entre $0,01 y $0,06 por consulta (Notion: $0,058) y 10–20 s, de la cuota del usuario. Va en segundo plano: la pantalla de éxito espera como máximo 4 s y, si no llegó, muestra solo el éxito; lo que llegue tarde suma a los totales. `--bare` no sirve (no lee el llavero). Todo lo que no sea un entero se descarta. **Notion no lleva dato**: contar sus páginas tardaba ~17 s y costaba ~$0,06, y la búsqueda devuelve una primera página, no un total fiable; se muestra solo el éxito. |
| Transición | 1,5 s tras el éxito. "Conectar después" (discreto) y, si falla, "Reintentar" y "Saltar por ahora": la herramienta queda `skipped`. |
| Dopamina | Pantalla completa tras las 2 primeras, a la mitad y antes de la última; nunca pegadas ni con 1–2 conexiones. Botón Continuar y avance a los 3 s. |
| Meet | Sin pantalla propia: queda como Google Workspace. "N de M" no la cuenta. |
| Slack, Gmail, Google | Necesitan la app OAuth del cliente (§4e), que es el paso siguiente de la fase. Aquí solo el punto de entrada: una pantalla que lo explica y las deja `skipped`. El secreto irá por la variable `MCP_CLIENT_SECRET` del `Process`, nunca en argumentos. |
| WhatsApp | (1) Advertencia de §4 **antes** del QR, con "Entiendo, continuar". (2) `status`: si ya hay sesión se salta el QR (`pair` solo diría "Ya hay una sesión vinculada"). (3) `pair` como proceso hijo; el QR se lee del PNG `~/Library/Application Support/Galeno/whatsapp/pair-qr.png` cada ~0,7 s (el bridge lo reescribe cada ~60 s, sin atomicidad: si no es un PNG completo se conserva el anterior). (4) `install-launchd` —siempre, también si ya estaba vinculado: es idempotente y `sync` tiene que estar corriendo—. (5) La sincronización inicial **no tiene progreso ni señal de fin**: barra indeterminada con los chats que van apareciendo (`chats --json`); se da por estable tras 3 lecturas iguales o a los 3 min, y siempre se puede "Seguir mientras sincroniza". "Encontré N grupos" cuenta `is_group`. |
| Ruta estable del bridge | `install-launchd` escribe en el plist la ruta del propio ejecutable: dentro de `Galeno.app` (que se mueve y se actualiza) o de DerivedData se rompería. La app copia el bridge empaquetado a `~/Library/Application Support/Galeno/bin/galeno-whatsapp` (de nuevo si cambia `version`) y desde ahí corre todo y apunta `.mcp.json`. Es la capa 2 de §4f. |
| Al cerrar la app | Los procesos hijo (`pair`, `login`) se matan: un `pair` huérfano seguiría hasta agotar sus 3 minutos. Un cierre brusco no se cubre. |
| Persistencia | Los estados (`connected`/`skipped`) viven en `WizardState` y se guardan en `GalenoInstallation` al generar (pantalla 9). |

### Detalles de las pantallas 6–10 (decididos al construirlas, Fase 4)

| Tema | Decisión |
|---|---|
| Foco (fuera del wizard desde B1) · de dónde salen las listas | **WhatsApp:** `galeno-whatsapp chats --json` (los grupos primero, luego los chats, cada bloque del más reciente al más antiguo; se descartan los `@broadcast`, que son el estado y las listas de difusión; máximo 500). **Las demás:** se le pide a Claude Code que mire el servidor (`claude -p`, solo ese servidor permitido, `haiku`, `--output-format json`, sin guardar sesión, tope de $0,15) y devuelva un arreglo JSON `[{id, name}]` (con `{"more": true}` si había más; máximo 100). Google Meet comparte la lista de Drive. Corre **en segundo plano al entrar**, de 3 en 3 y con WhatsApp primero. Misma cuota y tiempo que el "dato real" del paso 5 (≈$0,01–0,06 y 10–20 s por herramienta; **sin medir** para esta consulta). |
| Foco (fuera del wizard desde B1) · qué se guarda | `SourceSelection`: marcar fuentes = `only`, ninguna = `nothing` ("sin foco concreto"), y `everything` solo si el usuario lo pide cuando no se pudo listar o si la herramienta no tiene nada que elegir (las de transcripción). **No es una barrera**: la pantalla lo dice y queda en el `AGENTS.md`. Nunca bloquea: si una lista falla se ofrece «Reintentar» o «Que lea todo». |
| Foco (fuera del wizard desde B1) · nombres de terceros | Un canal o un chat puede llamarse como quiera y su nombre acaba dentro del `AGENTS.md`: se sanea (una sola línea, sin caracteres de control ni invisibles —ancho cero, dirección del texto—, 80 caracteres) y los ids se validan. |
| Pantalla 6 · el catálogo | `skills/catalog.json` (formato 1): las 17 skills nuestras de §6.1 en 4 grupos, con nombre y resumen en español e inglés, dónde escriben y qué herramienta necesitan; y las curadas, con autor, repositorio, ruta, licencia y `available`. **Todas las nuestras vienen marcadas.** Una skill que necesita una herramienta que el usuario no conectó se muestra con «todavía no te sirve», sin ocultarla. Se valida al leerlo (ids únicos y seguros, grupos que existen, licencia solo Apache-2.0 o MIT, repositorio de GitHub, autor). |
| Pantalla 6 · curadas | Ocho entradas verificadas en GitHub: `product-on-purpose/pm-skills` (Apache-2.0), `phuryn/pm-skills` (MIT) y `snarktank/ralph` (MIT). **Todas `available: false`**: se ven con crédito, licencia y enlace a su GitHub pero no se pueden marcar hasta traer su contenido (Fase 5), porque generar con una marcada sin carpeta falla. |
| Pantalla 6 · el contenido de las nuestras | `SKILL.md` **mínimos pero válidos** (instrucción de idioma arriba, qué hacer, dónde escribir preguntando, aprobación para lo que sale, reglas); la Fase 5 los reemplaza por los buenos. |
| Pantalla 6 · cómo llegan a la app | Una fase del proyecto copia `skills/` a `Galeno.app/Contents/Resources/skills`: es el **respaldo local** de la capa 3 de §4f (la fuente remota llega después). En Debug, `-galeno-skills-path <ruta>` o `GALENO_SKILLS_PATH` la reemplazan. |
| Pantalla 7 | Arriba, fijo: todo envío externo (Slack, email) siempre pide aprobación y no se puede cambiar (`SendingRules` no tiene forma de expresarlo); WhatsApp es de solo lectura. **Leer Slack no pide permiso** (la pantalla lo dice): solo enviar o cambiar algo. Debajo, lo elegible: las escrituras internas de **las herramientas conectadas** (Notion, Jira, Google Docs, Google Sheets), «Preguntarme» o «Sin preguntar» (de fábrica, sin preguntar). Y la nota de que en su computador solo escribe sin preguntar en `memoria/`. |
| Pantalla 9 | Cuatro pasos visibles (reglas, herramientas, skills, guardado), cada uno al menos 0,7 s. El motor corre en segundo plano y es lo que decide: si falla, se para en ese paso y lo dice, con «Reintentar» y «Volver a las reglas»; no avanza a «Listo». **Primero se genera y después se guarda** `installation.json`: un error no deja un agente apuntando a una carpeta que no existe. Un `installation.json` ilegible no se pisa. Las conexiones compartidas se guardan solo si quedaron conectadas (una saltada solo si nadie la había conectado). |
| Pantalla 5 · volver del navegador | Las herramientas que se autorizan en el navegador del sistema (Notion, Jira, las de reuniones) dejan una pestaña abierta que Galeno no puede cerrar. Cuando la autorización termina bien, **Galeno vuelve solo al frente** (`AppFocus`). Si falla o se agota el tiempo, no roba el foco. Se descartó hacer la autorización de Notion en una ventana propia: con sesión efímera habría que iniciar sesión en Notion otra vez, y Google no deja entrar desde ventanas de apps (decisión de Rafa, 4 oct 2026). |
| Pantalla 5 · botones (B1) | El paso 5 lleva sus propios botones de principio a fin: la barra Atrás/Siguiente no aparece. Tras un éxito hay «Continuar» (además de avanzar sola a los 1,5 s, o cuando llega el dato); las pausas y la celebración final terminan con «Continuar». |
| Pantalla 8 (Revisión) | Tres tarjetas: herramientas conectadas (y «Para después»), skills marcadas (las seis primeras y el total) y, destacada, las reglas. «Cambiar» lleva al paso correspondiente (`WizardState.jump(to:)`, solo hacia atrás). El botón principal es «Escribir a ⟨nombre⟩». Al armar la config, toda herramienta conectada sin fuentes elegidas queda como `everything`. |
| Pantalla 9 · volver a generar | Desde «Listo», «Atrás» lleva a la revisión; al avanzar se regenera **el mismo agente en la misma carpeta** (no crea «Hera 2») y `memoria/` no se toca. |
| Pantalla 10 | Un solo bloque para **probar el agente ya** (decisión de Rafa tras la prueba real, 4 oct 2026): la primera pregunta según lo conectado (WhatsApp › Slack › Notion › Jira › reuniones › Claude Design), **corta y acotada** («¿Qué hay de nuevo en mis 3 chats más recientes de WhatsApp?», no «resume la semana»: tiene que responder en segundos), los botones «Abrir en la app de Claude» y «Abrir en Terminal» —se abre con la pregunta ya escrita— y «Copiar». La tarjeta de la ruta («Mostrar en Finder», «Copiar ruta») queda **oculta** (`DoneContent.showsFolderCard`): a quien acaba de crear su agente le importa probarlo, no la carpeta. **App de Claude:** `claude://code/new?folder=<ruta>&q=<texto>` (la app siempre pide confirmar la carpeta; el texto queda escrito, no enviado). **Terminal:** `claude-cli://open?cwd=<ruta>&q=<texto>` si Claude Code ya registró su manejador (`~/Applications/Claude Code URL Handler.app`, lo hace al enviar su primer mensaje); si no, un `.command` en `$TMPDIR` (0700) que Terminal.app ejecuta, que entra a la carpeta y arranca `claude` con la primera pregunta citada (ahí la pregunta se envía: no hay forma de dejarla solo escrita). Ambos enlaces son los documentados por Anthropic y no ejecutan nada. |
| Probar sin tocar nada | Con `-galeno-fake-connect`, el agente se genera en una carpeta temporal (ni `~/Galeno` ni tu `installation.json`) y «abrir» no lanza nada. Las pruebas usan siempre un instalador en carpeta temporal: `ConnectServices.installer` no tiene valor por defecto. |

---

## 3b. Después del wizard

El wizard termina, pero el producto no. Un agente de Galeno es **una carpeta** (`~/Galeno/<agente>/`) con la config que el motor escribió; Claude Code la carga cuando se abre ahí. Todo lo que sigue sale de esa idea.

**El home.** Al abrir Galeno después del primer setup, el usuario ve la lista de sus agentes. Desde ahí puede:

| Acción | Qué hace |
|---|---|
| Abrir un agente | En la app de Claude o en Terminal, a elección del usuario, ya ubicado en la carpeta del agente |
| Crear otro agente | Un agente por proyecto. Lanza el **wizard corto** (abajo) |
| Gestionar la config | Cambiar fuentes, skills o reglas de un agente, sin repetir el wizard |
| Salud y mantenimiento | Conexiones caídas, re-vincular WhatsApp (~cada 20 días), estado de la sincronización, actualizar skills y la app (§4f) |

**Varios agentes, uno por proyecto.** Un PM con tres clientes crea tres agentes. Cada uno tiene su carpeta, su descripción, sus fuentes y su memoria. **Las conexiones se hacen una sola vez y se comparten**: el OAuth de cada herramienta lo guarda Claude Code por usuario, y WhatsApp es un solo dispositivo vinculado con una sola base local.

**Wizard corto** (del segundo agente en adelante): nombre, descripción del proyecto, qué leer y qué skills. No repite idioma, detección ni conexiones; solo pide conectar una herramienta si el proyecto usa una que todavía no está conectada. El motor arma el punto de partida del agente nuevo con las herramientas ya conectadas, con su `client_id`, y el idioma de la instalación (el del paso 1); qué lee de cada una queda por elegir.

**Qué se garantiza y qué no.** En ninguna herramienta la selección de fuentes es una barrera: es una instrucción en el `AGENTS.md`, que el agente obedece pero nada impide técnicamente. En WhatsApp, el bridge le da al agente todos los chats sincronizados. Se descartó filtrarlos por chat porque una lista fija obliga a reconfigurar cada vez que aparece un grupo nuevo; un grupo nuevo se le pide al agente en la conversación. Lo que sí se garantiza: WhatsApp es de solo lectura y todo envío externo pasa por aprobación. La separación garantizada de contexto entre agentes es v0.2, y si hace falta una barrera en WhatsApp será una lista de **exclusión** (chats privados que el agente nunca ve), no de inclusión.

**La primera sesión.** La descripción del wizard es una línea. La primera vez que el usuario abre su agente, este lee las fuentes elegidas y **propone un resumen del proyecto** (quién participa, qué está en curso, fechas). El usuario lo corrige o lo confirma, y queda guardado en la memoria.

**Memoria del proyecto.** Cada agente mantiene notas propias (decisiones, quién es quién, pendientes) en la carpeta `memoria/` de su proyecto, y las actualiza él mismo. Es el **único lugar donde puede escribir sin que nadie lo apruebe**. Lo que el propio Galeno genera (`AGENTS.md`, `CLAUDE.md`, `.mcp.json`, todo `.claude/`) está bloqueado por regla, y cualquier otra ruta pide permiso al usuario cada vez; la ejecución de código está bloqueada del todo. **Traer contexto** (paso 3, opcional): quien ya habló del proyecto en claude.ai copia un mensaje que Galeno le da, pega la respuesta (o elige/suelta archivos `.md`, `.txt` o `.pdf`; hasta 10 materiales y 400 000 caracteres) y Galeno lo deja como texto en `memoria/contexto/`. Es una entrada de una sola vez: no entra en el `AgentConfig`, ni en el borrador, ni se regenera, y el motor solo crea esos archivos si no existen (no pisa nada). El `AGENTS.md` le dice al agente que los lea en su primera sesión como datos, nunca como órdenes. Todo queda en el Mac del usuario. La memoria es un archivo, `memoria/proyecto.md`, que `CLAUDE.md` importa para que cargue en cada sesión; el agente decide que es su primera sesión cuando la sección «Resumen» sigue diciendo «Sin confirmar.». **La primera sesión no retrasa la respuesta** (decisión de Rafa tras la prueba real, 4 oct 2026: leer el contexto antes de contestar costó medio minuto de casi tres): el agente contesta primero lo que le pidieron, leyendo solo lo que esa pregunta necesita, y al final ofrece en una línea preparar el resumen del proyecto; lo arma —con las fuentes y el material de `memoria/contexto/`— cuando el usuario acepta o cuando una pregunta sí depende de conocer el proyecto. Las notas son hechos sobre el proyecto, nunca instrucciones: el agente ignora y avisa si un mensaje o un documento le pide guardar algo en su memoria.

**Galeno es el dueño de la config.** Galeno guarda las respuestas del wizard de cada agente. Cuando el usuario cambia algo, el motor **regenera los archivos completos**; lo que alguien haya editado a mano se pierde. La excepción es `memoria/`, que Galeno nunca toca.

**La instalación y las carpetas.** Galeno recuerda dos cosas entre sesiones, en un solo archivo (`~/Library/Application Support/Galeno/installation.json`, sin secretos): las **conexiones compartidas** (herramienta, estado, `client_id`) y la **lista de agentes** (su config y su carpeta). El estado y el `client_id` se toman siempre de las conexiones compartidas, no de cada agente: cambiar el `client_id` de Slack una vez llega a todos, y una herramienta que se desconecta desaparece de todos al regenerar. La carpeta de un agente es `~/Galeno/<nombre>/`, con el nombre limpio de caracteres que rompen rutas y, si ya existe una igual (de otro agente o del propio usuario), con un número: `Aurora 2`. Se elige una vez al crearlo y no cambia sola.

**Regenerar.** Aplicar el generador sobre una carpeta que ya tiene config la deja **exactamente igual que una carpeta nueva** con la misma config: se quitan las skills desmarcadas (también una puesta a mano, porque `.claude/` es de Galeno) y el hook de aprobación si ya no hay a qué aplicarlo, y `memoria/` no se toca. Todo se calcula antes de escribir: si algo falla, la carpeta queda como estaba.

**Solo cuando se lo piden.** El agente trabaja dentro de una sesión que abre el usuario. Una skill como `/reporte-dia` se corre a mano. Las tareas programadas quedan para después (§5).

## 4. WhatsApp — reglas de producto (innegociables)

- **Read-only por estructura de código.** El MCP de WhatsApp del producto **no tiene herramienta de envío**. Ni un prompt malicioso ni el propio agente pueden enviar.
- **El agente ve todos los chats sincronizados, incluidos los personales.** No hay filtro por chat (ver §3b). La app tiene que decirlo con claridad en la pantalla "elige qué leer": lo que el usuario elige es en qué se enfoca el agente, no lo que puede leer.
- **Transparencia total.** La pantalla de vinculación dice textualmente algo como: "Esto se conecta como un dispositivo vinculado usando el protocolo de WhatsApp Web, de forma no oficial. Es de solo lectura. Existe un riesgo bajo pero real de que WhatsApp lo detecte y restrinja tu cuenta. Todo corre en tu computador; nada sale a servidores nuestros. Tú decides si continuar."
- **Base técnica (decidida):** fork de **`lharries/whatsapp-mcp`** — **MIT verificada**, 5.9k estrellas, 1.2k forks: el estándar del espacio. Dos componentes: puente en Go (`whatsmeow`, QR, SQLite) + servidor MCP en Python. Trae **12 herramientas, 3 de envío** (`send_message`, `send_file`, `send_audio_message`) → **se eliminan**. Quedan las de lectura: contactos, chats, mensajes, contexto, descarga de media. El propio autor advierte la trifecta letal; quitar el envío es la mitigación.
  - **Decisión de empaquetado (cerrada):** reescribir el servidor MCP de Python a **Go**, dentro del mismo binario del puente → **un solo ejecutable Go, sin Python**, empaquetado en la .app. Cero dependencias para el usuario. Por qué Go y no Swift: `whatsmeow` (el puente, la parte difícil) solo existe en Go; el MCP va junto al puente para que el componente de WhatsApp sea un binario autocontenido que Claude Code lanza como cualquier MCP por stdio. Nunca empaquetar Python.
  - Operativo para la UX: re-autenticación cada ~20 días (aviso de "re-vincular"); la carga inicial del historial puede tardar minutos (barra de "sincronizando" en la primera conexión).
  - **Alternativas en TypeScript, evaluadas y descartadas** por la decisión de Go: `exomind-tmi/whatsapp-mcp` (Baileys; buen diseño de daemon único + shims) e `ionutsss1/whatsapp-mcp`. Más maduros que joaohts, pero obligarían a empaquetar Node.
  - **`joaohts/whatsapp-mcp` (MIT) solo como referencia de UX**, no de código: 0 estrellas, 0 forks, pre-alpha, un solo autor. Tomar sus ideas (QR en pantalla, toggles por herramienta, variante DMG), no heredar código sin probar.
- **Re-vinculación:** el protocolo rota la sesión ~cada 20 días; la app debe avisar y ofrecer re-escanear.
- **Por qué solo lectura:** el riesgo de ban se dispara principalmente por envío automatizado. La lectura es bajo riesgo. El valor para el PM (seguimiento de grupos) está en la lectura.

---

## 4c. Arquitectura de Galeno.app (Swift)

```
Galeno.app  (Swift / SwiftUI)
  ├── Wizard y UX           → SwiftUI nativo (animaciones de dopamina, QR en pantalla)
  ├── Generador de config   → escribe AGENTS.md, .claude/settings.json, .mcp.json, skills, hooks  (FileManager)
  ├── WhatsApp              → lanza y supervisa un binario Go empaquetado (puente + MCP read-only)  (Process)
  │                            · launchd para que arranque solo al iniciar sesión
  └── Demás MCP (hospedados) → corre `claude mcp add --transport http …` + abre el OAuth  (Process)
                               Notion · Slack · Gmail · Drive · Jira · Fireflies · Granola · Fathom
```

**Stack final:** Swift (app) + un binario Go (WhatsApp). Nada de Python, Node, Rust ni contenedor web. Los MCP hospedados no se empaquetan: viven en los servidores de cada proveedor y se conectan por OAuth.

**Por qué funciona bien en Swift:** `Process` lanza y supervisa binarios; `FileManager` escribe la config; SwiftUI hace el wizard fluido y nativo. Es la arquitectura natural para un orquestador de procesos locales.

## 4b. Transcripción de reuniones — la integración más limpia del stack

A diferencia de WhatsApp, aquí **todo es oficial y sin riesgo**: los tres proveedores principales hospedan su propio MCP con OAuth.

| Herramienta | MCP | Notas para el producto |
|---|---|---|
| Fireflies | Oficial, en el directorio de conectores de Claude | El más maduro. Transcripciones, resúmenes, action items |
| Granola | Oficial (reciente) | No guarda en nube. **Verificar**: una fuente dice que borra transcripciones a las ~72 h; si es así, el agente debe sincronizar pronto |
| Fathom | Oficial, 9 tools read-only | **Gratis en todos los planes.** Límite: la búsqueda lee títulos/resúmenes, no transcripciones; la transcripción completa se pide por ID |
| Google Meet | Sin MCP propio | Las transcripciones de Gemini caen en Drive → se leen con el MCP de Google Drive que ya está en el stack |

**Decisión de diseño:** las transcripciones se leen **directo de la fuente**, no vía export a Notion. Menos fricción (un OAuth y listo) y más confiable (nada reverse-engineered).

**Guardrail que se hereda a plantillas futuras:** la plantilla de salud debe advertir que nunca se transcriben consultas clínicas con pacientes.

## 4d. Internacionalización (español e inglés)

El modelo es multilingüe: un usuario hispanohablante obtiene la misma calidad que uno anglohablante. Las decisiones de i18n son de producto, no de capacidad.

| Capa | Decisión |
|---|---|
| **Wizard (la app)** | Se traduce: i18n nativa de Swift (String Catalog, `Localizable.xcstrings`), español e inglés. El usuario elige al inicio; preseleccionado según el idioma del Mac, y el cambio es en caliente (`\.locale`). Los textos de dopamina se escriben **nativamente en cada idioma**, no como traducción literal: "¡Vas por la mitad!" tiene que sonar a alguien que te habla. |
| **AGENTS.md y config generada** | El motor los genera en el idioma elegido, e inyecta la instrucción explícita: *"responde y genera todos los documentos en [idioma]"*. Esto evita que el agente devuelva un PRD en inglés porque el ticket de Jira estaba en inglés. |
| **Skills nuestras** | Se escriben **en inglés** (estándar del ecosistema, una sola fuente que mantener), con la instrucción de idioma arriba. Una skill en inglés funciona para un usuario en español: el agente lee la instrucción y responde en la lengua del usuario. |
| **Skills curadas** | Se ofrecen **tal cual**, sin tratamiento de idioma en v0.0.1. |

**Nota de diseño:** las fuentes del PM suelen estar mezcladas (WhatsApp en español, Jira en inglés, docs en inglés). El agente lee todo sin problema; lo que fija el idioma del **output** es la instrucción explícita en la config, no el idioma de la fuente.

## 4e. Slack y Google Workspace/Gmail — la app OAuth es del cliente, nunca de Galeno

Investigando los MCP reales de Slack, Notion, Google Workspace y Atlassian (oct 2026) se encontró que no todos son "solo OAuth":

- **Notion y Jira** registran el cliente al vuelo (*dynamic client registration*): nadie crea nada de antemano. Endpoints confirmados: `mcp.notion.com/mcp` y `mcp.atlassian.com/v2/mcp` (la `v1/sse` que se había anotado antes se apaga el 30 de junio de 2026).
- **Slack y Google Workspace/Gmail exigen una app registrada con el proveedor** antes de que cualquier cliente pueda conectarlos. Eso no es un token del usuario — es una credencial del fabricante del software.

**Decisión: esa app la trae el propio cliente, nunca Galeno.** Coherente con "los secretos del usuario nunca tocan tu infraestructura", un paso más allá: ni el `client_id` es de Galeno. La alternativa —Galeno registra una sola app para todos los clientes— exigiría pasar la revisión del Marketplace de Slack y la verificación de scopes sensibles de Google (semanas, y una app compartida que mantener). Trayendo cada cliente la suya, ninguna de las dos hace falta.

**Cómo se resuelve cada una, sin pedirle al usuario que configure nada a mano:**

| | Slack | Google Workspace / Gmail |
|---|---|---|
| **Mecanismo** | **Por API, sin pantallas.** `apps.manifest.create` recibe el manifiesto y devuelve el `client_id`/`client_secret` directamente en la respuesta (confirmado contra la referencia oficial del método) — Galeno nunca muestra una pantalla de Slack ni pide copiar nada | No existe un atajo equivalente (Google apagó en marzo de 2026 la única API parecida que existía, para un caso de uso distinto). Se resuelve con **automatización real de navegador**: la app maneja los clics de crear el proyecto y la credencial en la consola de Google, parando solo para que el usuario inicie sesión |
| **El único paso que Slack no deja evitar del todo** | Generar el primer "token de configuración de apps" exige entrar a `api.slack.com/apps` → "Your App Configuration Tokens" → "Generate Token": Slack mismo dice que no hay forma programática de arrancar ese primer token. **Decisión: lo hace la automatización de navegador de Galeno**, igual que con Google —parando solo para que el usuario inicie sesión en Slack—, no el usuario a mano. Es un paso único **por workspace**, no por conexión ni por app: de ahí en adelante `SlackAppProvisioner.rotate(refreshToken:)` lo renueva solo, sin volver a tocar el navegador | Crear el proyecto y la credencial en la consola de Google, de principio a fin |
| **Dónde vive** | `GalenoCore`: `SlackManifestRenderer` (el manifiesto) + `SlackAppProvisioner` (la llamada a la API). La automatización que consigue el primer token de configuración es de `GalenoApp`, Fase 4 — un solo clic en una sola pantalla ("Generate Token"), mucho más acotado que el flujo de Google | GalenoApp, Fase 4. Varias pantallas (proyecto, consentimiento, credencial) |
| **El riesgo que se acepta** | Que Slack detecte la sesión como automatizada en una acción sensible (genera un token con permiso para crear apps en el workspace), y que la interfaz de esa pantalla cambie. Menor que el de Google: es un solo botón, no un flujo de varias pantallas con muchos campos | Frágil ante cambios de la consola; riesgo real de que Google detecte la sesión como automatizada en una pantalla sensible |
| **Qué guarda Galeno** | El `client_id` (texto plano: no es secreto), en `ToolConnection.oauthClientID`. El `client_secret` **pasa por `GalenoApp` en memoria, una sola vez**, directo de la respuesta de Slack a `claude mcp add --client-secret` (que Claude Code guarda en el keychain del sistema): nunca se escribe a disco, nunca se registra, nunca entra a `AgentConfig` ni a ningún archivo generado | Solo `client_id` |

**Sobre el `client_secret` de Slack:** es la única vez que algo que no es del propio usuario pasa, de paso, por el software de Galeno. Sigue siendo cierto que "los secretos nunca tocan infraestructura propia" —nada de esto sale de la máquina del usuario, ni se envía a ningún servidor de Galeno—, pero es una matización real que vale la pena tener presente al construir `GalenoApp`: ese valor se recibe, se entrega de inmediato al almacenamiento seguro de Claude Code, y se descarta. Nunca se loggea, nunca se persiste.

**Slack, además, solo soporta token de usuario.** Confirmado contra la documentación oficial: sus endpoints de autorización son específicamente para tokens de usuario (`oauth/v2_user/authorize`), y su tabla de scopes documentada es toda "user token". **Consecuencia:** todo lo que el agente haga en Slack aparece con el nombre y la foto de quien aprobó la conexión — no existe una identidad de bot separada dentro de esta integración, y construir una exigiría abandonar el MCP oficial de Slack por una integración propia. Para v0.0.1 se acepta esto tal cual: es, de hecho, un resultado natural y no un compromiso.

Los scopes que v0.0.1 pide a la app de Slack del cliente (verificados contra la tabla oficial, solo lo que usa el producto): `channels:read`, `groups:read` (listar canales), `channels:history`, `groups:history` (leer historial), `search:read.public`, `search:read.private` (buscar), `chat:write` (enviar, con aprobación). Los scopes de Google quedan pendientes de verificar cuando se diseñe la automatización de Fase 4.

**Google Workspace no es un servidor, son tres:** Drive, Docs y Sheets tienen cada uno su propio endpoint del lado de Google (`drivemcp`/`docsmcp`/`sheetsmcp.googleapis.com/mcp/v1`). El wizard sigue mostrando "Google Drive, Docs y Sheets" como una sola tool (§3 paso 4); por debajo, el motor escribe tres entradas en `.mcp.json`, las tres con el mismo `client_id` del cliente.

### Diseño de la conexión con app propia (Fase 4, octubre 2026)

Al diseñar la Fase 4 se verificó contra las fuentes oficiales y varias suposiciones de arriba cambiaron. **Esta subsección manda sobre lo anterior donde lo contradiga** (en particular: la automatización del primer token y la rotación del token de Slack).

**Lo verificado**

| Hecho | Efecto |
|---|---|
| Google **no tiene API** para crear clientes OAuth: solo la consola. | La consola se resuelve con un agente de navegador o a mano; no hay atajo. |
| Google **bloquea el inicio de sesión en webviews embebidos** (`disallowed_useragent`, desde 2021). | Nada de `WKWebView`; además sería escribir contraseñas dentro de Galeno. |
| Chrome ≥ 136 ignora `--remote-debugging-port` sobre el perfil real. | No se controla Chrome por DevTools sobre la sesión del usuario. |
| Una app OAuth de Google en modo **Testing** emite refresh tokens que **caducan a los 7 días**. | **Decidido: publicarla "En producción" sin verificar** (una advertencia al autorizar, tope de 100 usuarios, sin caducidad semanal). Con Workspace de empresa: tipo **Interna**. |
| Los MCP de Google Workspace están en **Developer Preview** (hay que pertenecer al programa), con cliente tipo **aplicación web** y scopes `gmail.readonly`/`gmail.compose`, `drive.readonly`/`drive.file`, `documents*`, `spreadsheets*`. | Inscribirse en el programa es un paso manual. Por defecto se piden solo los de lectura; los de escritura solo si las reglas del usuario permiten escribir. |
| Slack solo permite MCP a apps **internas o del directorio**, y **el administrador debe aprobar** el cliente MCP. El interruptor «Model Context Protocol» (página *Agents & AI Apps* de la app) tiene campo de manifiesto: `settings.is_mcp_enabled` (referencia del manifiesto). **Comprobado con una app real:** sin él, Slack acepta la autorización y luego rechaza la conexión con «App is not enabled for Slack MCP server access». | Un PM sin rol de admin se bloquea: pantalla "Pide aprobación a tu administrador" con un mensaje listo para copiar. El manifiesto de Galeno lleva `is_mcp_enabled: true`; si aun así falla, Galeno dice dónde activarlo (`api.slack.com/apps/<id>/app-assistant`). |
| `claude mcp add` acepta `--client-id`, `--callback-port` y `--client-secret`; el secreto se toma de `MCP_CLIENT_SECRET` **sin terminal**, y queda en el llavero (no en `~/.claude.json`). | El secreto viaja solo por el entorno del proceso. |

**Lo decidido**

- **Principios:** contraseñas, 2FA y CAPTCHAs siempre los hace el usuario; **el modelo nunca ve un secreto**; aceptar términos, publicar la app, "Crear" el cliente y cada "Permitir" los confirma el usuario; todo paso automático tiene su equivalente manual; nada se persiste ni sale de la máquina salvo el `client_id`; detener siempre disponible.
- **Slack, hoy (implementado): el usuario solo inicia sesión.** Galeno abre **su propia ventana** (`WKWebView`) con `api.slack.com/apps`; el usuario se autentica ahí y Galeno pulsa «Generate Token», **elige el workspace en el que el usuario acaba de entrar** (lo sabe por el identificador que Slack anuncia en el enlace `slack://…`, que la ventana reconoce y no abre; el desplegable de Slack es propio, no un `<select>`; si ninguna opción coincide, pregunta) y **captura el token directo a memoria** (del texto o los atributos de la página, de la respuesta que lo genera o del botón «Copy», que se intercepta para que no llegue al portapapeles del sistema). Si un clic automático falla porque Slack cambió la pantalla, el usuario pulsa él mismo en esa ventana y la captura funciona igual. Al reconocer ese `slack://` la ventana vuelve a la página de tokens; las rutas `app.slack.com/t/<equipo>/login/…` se dejan terminar (interrumpirlas deja la sesión sin completar). No hay camino de «pegar el token a mano». **La autorización de la app también ocurre en Galeno** (decidido por Rafa tras ver que obligaba a entrar dos veces y dejaba una pestaña abierta en su navegador): `claude mcp login` abre la página de «Permitir» con `$BROWSER` (comprobado: lo respeta); Galeno le da un «navegador» que solo anota la dirección y la muestra en una segunda ventana con la **misma sesión efímera**, y la cierra sola cuando carga `http://localhost:51820/callback`. Solo `https` de `slack.com` y esa vuelta exacta; lo que no sea de Slack va al navegador del sistema. Una barra de 4 pasos con texto de lo que hace Galeno (y de cuándo es el turno del usuario) acompaña todo el proceso. Garantías: sesión **efímera** (no queda nada en el disco); el script **solo actúa en `api.slack.com`** (en las páginas de contraseña no hace nada); solo se aceptan mensajes del documento principal de ese sitio; la ventana navega solo por `https` y muestra siempre el dominio. La ventana se identifica como el Safari del sistema (Slack rechaza un WebKit anónimo: «your browser is not supported»), y **el inicio de sesión de Google se bloquea a propósito**: Google no lo permite en ventanas embebidas y no se esquiva; a esos usuarios se les dice que usen «Sign in with email» (Slack envía un código). Para saber que ya hay sesión se mira que **exista** la cookie `d` de Slack, sin leer su valor. Respaldo: generar el token a mano y pegarlo en un campo seguro. Después, en los dos casos: `apps.manifest.validate` (comprueba el token sin crear nada) → `apps.manifest.create` → `claude mcp add --client-id --callback-port --client-secret` con el secreto en `MCP_CLIENT_SECRET` → `claude mcp login`. El **token de configuración no se guarda ni se rota** (cambia respecto a lo anterior): una app por workspace, compartida por todos los agentes. Un servidor homónimo que no sea el nuestro (por ejemplo uno local de `npx`) ni se pisa ni se da por conectado.
- **Agente de navegador con Claude (`claude --chrome`): probado y descartado para Slack.** Cowork no tiene API; lo programable es `claude -p --chrome`, que habla con la extensión por un puente en la nube de Anthropic. Se probó 4 veces contra una réplica local de la página de tokens y **falló las 4**: en Arc crear la pestaña se cuelga 60 s, la extensión de Chrome no conectó, con `haiku` no puede abrir pestañas (no hay "auto mode") y cada intento fallido costó **$0,22–0,37 y 75–150 s**. Además exige Chrome/Edge/Brave, la extensión y un plan de pago, y el modelo vería la página. Puede volver a evaluarse para la consola de Google, donde no hay un token que capturar y un agente sí aporta.
- **Google (diferido):** pasos G0 inscribirse en el programa · G1 proyecto · G2 activar APIs · G3 pantalla de consentimiento (Interna o Externa en producción) · G4 cliente OAuth web, que **el usuario crea** y cuyo ID y secreto pega en Galeno · G5 registrar los 4 servidores y autorizar. Siempre con guía manual; el agente es un acelerador.

## 4f. Actualizaciones · arquitectura de 3 capas + Sparkle

**Política de negocio:** actualizaciones **de por vida, gratis** para quien compró. Pago único, sin renovación. Internamente se distingue (aunque todo sea gratis): el *mantenimiento* —bug fixes, parches del bridge de WhatsApp cuando Meta cambia su protocolo, compatibilidad con cambios de Claude Code y de los MCP— es una obligación perpetua; las *features nuevas* son gratis por elección. La distinción no cambia nada para el usuario; sirve para razonar costos a futuro. El mecanismo técnico es el mismo cualquiera sea la política, así que esta decisión no ata la arquitectura.

**Galeno se actualiza en 3 capas independientes:**

| Capa | Qué contiene | Cómo se actualiza |
|---|---|---|
| 1 · App Mac (Swift) | Wizard, UI, motor de config | **Sparkle**: la app revisa un appcast (XML) en el servidor, avisa al usuario, descarga el build firmado y se reemplaza con un clic. Soporta deltas (solo lo que cambió). |
| 2 · Bridge de WhatsApp (Go) | Puente whatsmeow + MCP read-only | Viaja empaquetado en la .app, así que se actualiza vía Sparkle con ella. **Tiene su propio número de versión** para poder sacar un parche urgente del bridge sin re-releasear toda la app. Es la capa que más se rompe por causas externas (Meta). |
| 3 · Skills, catálogo y config | Las skills del perfil PM, el catálogo curado, prompts, plantillas | **Remoto, sin reinstalar.** La app las descarga del servidor/repo al configurar el agente y ofrece "actualizar skills" a usuarios existentes. Mejorar una skill o agregar una nueva NO requiere nuevo build de la app. Es lo que mantiene a Galeno vivo entre releases. |

**Sparkle — detalles que importan:**
- Framework open source estándar para apps Mac fuera del App Store.
- Actualizaciones **firmadas con clave EdDSA propia** (además de la firma de notarización de Apple): nadie puede inyectar una versión falsa. Crítico porque Galeno maneja tokens del usuario.
- El appcast, los DMG y las skills remotas se sirven desde la **misma infraestructura que ya existe** para el sitio y el webhook de Stripe. No es infraestructura nueva.

**Por qué va en la v0.0.1 aunque se lance una sola versión:** si la primera app sale sin Sparkle, esos usuarios tienen una app que no sabe actualizarse, y sacar la v0.0.2 obliga a contactarlos uno por uno. El mecanismo debe venir desde el primer build. Montarlo después, con usuarios ya instalados, es mucho más caro.

**Implicación para el motor (capa 3):** las skills NO se hornean dentro del binario de la app; se cargan desde una fuente remota versionada. El motor de config debe leerlas de ahí, con un fallback local por si el usuario está sin internet al configurar.

**Esto no contradice "nada sale a servidores nuestros":** las tres capas son *descargas* desde infraestructura propia hacia la máquina del usuario. Ni el appcast ni las skills remotas reciben tokens, contenido ni datos de uso.

## 5. Lo que queda para después (y por qué)

| Qué | Cuándo | Por qué no ahora |
|---|---|---|
| Separación garantizada de contexto entre agentes (más allá de WhatsApp) | v0.2 | Es lo más difícil del producto. v0.0.1 ya deja crear un agente por proyecto (§3b); falta imponer la separación en Slack, Notion, Drive y demás |
| Vista transversal ("¿qué tengo pendiente en todos mis proyectos?") | v0.2 | Depende de resolver primero la separación |
| Ver actividad (qué hizo el agente, qué envió) | v0.0.2 | Exige leer el historial de Claude Code; primero validar el uso básico |
| Tareas programadas (reporte diario que corre solo) | después | Necesita una cola de aprobaciones y ejecución sin sesión abierta; va de la mano con "ver actividad" |
| Envío por WhatsApp | v0.2 | Riesgo de ban; decidir entre Business API o riesgo aceptado por el usuario |
| Plantillas dev / legal / salud | v0.3+ | Validar PM primero |
| Soporte Codex / Cursor / Grok | v0.3+ | Leen AGENTS.md, así que será barato cuando toque |
| Skills externas ("trae la tuya", link de GitHub) | v0.2 | Única puerta de código no revisado; se añade con su guardrail cuando haya demanda |
| Marketplace de skills | futuro | Mercado saturado; primero el instalador |
| Windows | futuro | Mac primero |

**Idiomas:** español e inglés **sí están en v0.0.1** (ver §4d). Lo único que queda fuera es el tratamiento de idioma de las skills curadas, que se ofrecen tal cual.

**Actualizaciones:** **sí están en v0.0.1**, de por vida y gratis. El pago único da la app y todas las actualizaciones futuras, sin renovación. Mecanismo: Sparkle, desde el primer build (ver §4f).

---

## 6. Qué genera el motor (la config de Claude Code)

Para el perfil PM, el motor escribe en la máquina del usuario:

- `AGENTS.md` — identidad del agente, rol PM, la descripción del proyecto, qué herramientas tiene, reglas, y cómo usar la memoria.
- `.claude/settings.json` — `effortLevel: "low"` (decisión de Rafa, 4 oct 2026: el agente sobre todo lee y resume, y con esfuerzo bajo responde de 2 a 3 veces más rápido que con el `high` que el usuario suele traer; manda sobre su ajuste personal y `/effort` lo sube dentro de una sesión; **el modelo no se fija**, cada quien usa el de su plan) y reglas deny/ask/allow: envíos externos en `ask` (en Slack, las 14 herramientas de solo lectura van a `allow` por su nombre exacto, las 13 que envían o escriben a `ask`, y el hook de aprobación cubre todo lo del servidor que no sea una lectura conocida, también una herramienta que Slack añada después; las listas salen del servidor real, 4 oct 2026, y viven en `MCPServerCatalog`. Gmail sigue entero en `ask` hasta verificar las suyas), nada de ejecutar código, `Edit(/memoria/**)` en `allow`, y en `deny` por nombre lo que el motor genera fuera de `memoria/`. (Un patrón que niegue todo el proyecto y deje `memoria/` como excepción no funciona: probado contra Claude Code, la excepción `!` no reabre un directorio bloqueado entero.)
- `memoria/` — las notas del proyecto que mantiene el agente (§3b). El motor la crea si no existe y **nunca la sobrescribe** al regenerar.
- `.mcp.json` — los MCP conectados (WhatsApp read-only, Slack, Notion, Google Drive/Docs/Sheets, Jira, Gmail, Fireflies/Granola/Fathom), con tokens como referencias a variables de entorno, nunca en texto plano.
- `.claude/agents/` — subagentes del perfil PM: `scribe`, `tracker`, `reporter` (solo lectura + Notion/Jira; sin Bash, sin Edit de código). Su lista de herramientas es una lista blanca. Reciben los servidores de las herramientas conectadas que no pueden enviar (WhatsApp, transcripciones, Notion, Jira, Google Drive/Docs/Sheets) y **nunca los de Slack ni Gmail**: un servidor se concede entero, así que un subagente con Slack tendría también la herramienta de enviar. El agente principal lee Slack y el correo, les pasa lo relevante, y es el único que envía.
- `.claude/hooks/` — hook de aprobación para todo envío externo.
- `.claude/skills/` — **la lista de skills de abajo.** No vienen horneadas en la app: el motor las toma de una fuente remota versionada, con un fallback local (§4f, capa 3).

### 6.1 Las skills del perfil PM (lista para v0.0.1)

El PM no solo lee y resume: **produce**. La lista cubre el ciclo completo, agrupada por lo que el usuario quiere hacer.

**Producir documentos de producto**
| Skill | Qué hace | Dónde escribe |
|---|---|---|
| `/prd` | Convierte una idea o reunión en un PRD con la estructura del equipo (problema, métrica, usuarios, criterios, fuera de alcance) | Notion o Google Docs (el usuario elige) |
| `/user-stories` | Del PRD saca historias de usuario con criterios de aceptación | Notion / Jira |
| `/roadmap` | Arma o actualiza un roadmap por trimestre a partir de épicas | Notion / Google Sheets |
| `/release-notes` | De los tickets cerrados del sprint, redacta notas de versión para clientes | Notion / Docs / Slack |

**Gestionar el trabajo (Jira / Notion)**
| Skill | Qué hace | Dónde escribe |
|---|---|---|
| `/epics` | Del PRD crea las épicas | Jira o Notion |
| `/tickets` | De cada épica crea los tickets, estimados y priorizados, en estado "Propuesto" | Jira o Notion |
| `/tareas-recurrentes` | Crea las tareas que se repiten cada semana/sprint | Jira / Notion |
| `/groom` | Revisa el backlog: duplicados, tickets sin criterios, huérfanos sin épica | Jira / Notion (solo reporta) |
| `/sprint-log` | Abre el doc del sprint semanal: objetivo, qué se entrega, fechas | Notion |

**Seguimiento y reportes**
| Skill | Qué hace | Dónde escribe |
|---|---|---|
| `/resumen-proyecto` | Qué pasó esta semana en todas las fuentes del proyecto (Slack, WhatsApp, Jira, Docs, reuniones) | Notion / Slack |
| `/seguimiento` | Estado de los pendientes: qué sigue abierto, quién debe qué, qué se venció | Notion / Slack |
| `/informe-slack` | Arma y envía (con aprobación) un informe al canal del proyecto | Slack |
| `/reporte-excel` | Genera un reporte de métricas o estado en una hoja de cálculo | Google Sheets / Excel |
| `/reporte-dia` | Reporte diario de lo trabajado | Slack |

**Reuniones y descubrimiento**
| Skill | Qué hace | Dónde escribe |
|---|---|---|
| `/acta` | Transcripción → decisiones, acciones y responsables → tareas en Jira/Notion | Notion + Jira |
| `/sintesis-research` | De varias transcripciones de entrevistas, extrae temas y hallazgos | Notion / Docs |
| `/priorizar` | Aplica un marco (RICE, ICE) a una lista de ideas con los criterios del equipo | Sheets / Notion |

**Diseño clave de las skills:** cada una pregunta en qué herramienta escribir si el usuario tiene varias (Jira y Notion, Docs y Notion). No asumen. Y todo lo que sale hacia afuera (Slack a clientes, email) pasa por aprobación.

### 6.2 Skills existentes que vale la pena reutilizar o adaptar (no reinventar)

La investigación (oct 2026) muestra un ecosistema maduro de skills de PM para Claude Code. **No escribir desde cero lo que ya está probado:**

| Fuente | Qué aporta | Licencia | Para qué usarlo |
|---|---|---|---|
| **Anthropic Product Management Plugin** (`anthropics/knowledge-work-plugins`) | Plugin **oficial** de Anthropic: 6 skills + 6 comandos del flujo PM. Construido para Cowork, funciona en Claude Code | Verificar | Base de referencia: cómo Anthropic estructura un PRD, una historia, un roadmap |
| **pm-skills** (`product-on-purpose/pm-skills`) | 68 skills por fase (Triple Diamond), 10 workflows orquestadores, 6 subagentes (pm-critic, pm-release-conductor…), 200+ outputs de ejemplo | Apache 2.0 | La más completa. Candidata a base del catálogo; incluye `/pm-skills:deliver-prd`, `/deliver-user-stories` |
| **Product-Manager-Skills** (`deanpeters/Product-Manager-Skills`) | 77 frameworks PM (JTBD, RICE, etc.) + 6 workflows | CC BY-NC-SA 4.0 | ⚠️ **No comercial** — no se puede usar en un producto de pago sin permiso. Solo como referencia |
| **phuryn/pm-skills** | 100+ skills, comandos y plugins, de discovery a growth | MIT | Reutilizable comercialmente |
| **Ralph** (`snarktank/ralph`) | `/prd` + implementación autónoma. 9.7k estrellas | MIT | Su `/prd` es muy bueno como punto de partida |
| **product-manager-skills** (`Digidai`) | Crítica de PRDs, diagnóstico de métricas SaaS, planeación de roadmaps | Verificar | Skills de "crítico": pressure-test antes de entregar |

**Estrategia:** tomar como base **pm-skills (Apache 2.0)** y **phuryn (MIT)** —ambas comerciales—, **adaptarlas a los flujos de Jira/Notion/Sheets manteniéndolas en inglés, con la instrucción de idioma arriba (§4d)**, y referenciar el plugin oficial de Anthropic para el estándar. **Evitar deanpeters** en el producto por su licencia no comercial.

### 6.3 Skills externas ("trae la tuya") — fuera de la v0.0.1

En v0.0.1 **solo hay dos niveles de skills: las nuestras y las curadas**, ambas revisadas por nosotros antes de entrar a la lista. Así no existe ninguna puerta por la que entre código no revisado.

El nivel "trae la tuya" (pegar un link de GitHub) se pospone. Cuando se añada, tendrá que traer este guardrail: una skill le dice al agente cómo comportarse, y una maliciosa puede intentar que ignore sus reglas o envíe datos afuera (prompt injection servido en bandeja). Reglas mínimas para esa versión futura: advertencia explícita antes de instalar; una skill nunca eleva permisos (las reglas `deny`, el `ask` y el hook aplican aunque la skill diga lo contrario); el motor inspecciona el SKILL.md y rechaza instrucciones de exfiltrar datos o desactivar reglas; y registro del origen de cada skill instalada.

**Lo que ninguna de estas trae y es tu diferencial:** la integración con **WhatsApp** y la **separación por proyecto** (futura). Las skills de PM existentes asumen un solo producto y herramientas de escritorio; tú añades el mundo de LatAm (WhatsApp) y el multi-cliente.

## 7. Orden de construcción

1. **Motor interno** — librería/binario que genera toda la config a partir de las respuestas del wizard. **No es una interfaz de usuario**: es la lógica que la app invoca por debajo. Se separa de la app por razones de ingeniería (testeable, reutilizable, la app no acumula lógica), no para que alguien lo use directo.
   - [x] Modelo (`AgentConfig`) y generadores de `AGENTS.md`, `settings.json`, `.mcp.json`, hook de aprobación y skills, con snapshots.
   - [x] Subagentes `scribe`, `tracker` y `reporter` en `.claude/agents/` (§6).
   - [x] Descripción del proyecto y memoria (`memoria/`, con la escritura limitada a esa carpeta) (§3b).
   - [x] Varios agentes: la instalación (conexiones compartidas + lista de agentes, en `~/Library/Application Support/Galeno/installation.json`), el punto de partida del wizard corto, la carpeta `~/Galeno/<agente>/` y la regeneración sobre una carpeta existente sin tocar `memoria/` (§3b).
2. **App Swift/SwiftUI (en paralelo al motor)** — el wizard de §3 y el home de §3b. **Es lo único que el usuario ve.** Consume el motor; no duplica lógica.
   - **Validación con los 2 PMs del equipo:** con una versión temprana de la app, aunque tenga solo dos pantallas y sea fea. Validan el wizard, no el motor. Darles un CLI no sirve: validarían una experiencia que nunca tendrán.
3. **MCP de WhatsApp read-only** — fork de lharries (MIT).
   - [x] Eliminar las 3 herramientas de envío (y todo lo que solo existía para ellas).
   - [x] Portar el MCP de Python a Go dentro del binario del puente: 9 herramientas de
     solo lectura, SDK oficial (`modelcontextprotocol/go-sdk`), subcomandos
     `pair`/`sync`/`serve`/`status`/`install-launchd`, estado en
     `~/Library/Application Support/Galeno/whatsapp/`, build universal arm64+amd64.
     Detalle en `whatsapp-bridge/README.md`.
   - [x] `launchd`: `install-launchd` instala un LaunchAgent que mantiene `sync` corriendo
     tras el login. `pair` escribe además el QR rotativo como PNG para que la app lo muestre.
   - [x] Darle al bridge **su propio número de versión** (§4f, capa 2): subcomando
     `version`. Falta decidir el esquema y cómo se parchea sin re-releasear la app.
   - [x] Subcomando `chats --json`, que lista los chats para la pantalla "elige qué leer".
   - ~~Filtro de chats por agente~~ — **descartado**: obliga a reconfigurar con cada grupo
     nuevo (§3b).
   - [ ] Renderizar el QR dentro de la app, disparar `install-launchd` tras un `pair`
     exitoso, empaquetar y firmar el binario. Tomar de joaohts las ideas de UX. Esto es
     trabajo de `GalenoApp` (Fase 4): el puente ya expone lo necesario para que la app lo
     invoque como proceso.
   - Conservar los avisos de licencia MIT (ya en `whatsapp-bridge/LICENSE`/`NOTICE`).
4. **Pagos + distribución** — pago único, DMG firmado y notarizado (Apple lo exige para que abra sin sustos). **Sparkle va desde el primer build** (§4f): una app que sale sin él no sabe actualizarse.
5. **Validación con 5-10 PMs externos** antes de abrir la venta.

---

## 8. Riesgos específicos de la v0.0.1

| Riesgo | Mitigación |
|---|---|
| Ban de WhatsApp a un usuario | Read-only + advertencia explícita + sin promesa de "seguro" |
| Tokens expuestos | Nunca en texto plano; referencias a env; nunca en servidores propios |
| Agente envía algo mal a un cliente | Todo envío externo en `ask` + hook de aprobación |
| Apple bloquea la app (Gatekeeper) | Firmar y notarizar el DMG desde el inicio; el binario Go embebido también debe firmarse |
| Meta rompe el protocolo de WhatsApp | El bridge deja de leer; se saca parche urgente de la capa 2 vía Sparkle (por eso tiene versión propia). Mantenimiento de por vida, no opcional |
| Claude Code cambia formato de config | Motor desacoplado; actualizaciones como parte del soporte |
| Usuario no técnico se traba en un OAuth | Cada pantalla con captura de qué hacer y botón de "ayuda" |

---

## Pendientes antes de construir

- [ ] Generar el par de claves EdDSA de Sparkle (la privada fuera del repo, como la de licencias)
- [ ] Definir la URL del appcast y la ruta de las skills remotas (en el dominio del sitio)

- [x] Nombre del producto → **Galeno**
- [x] Precio del pago único → **USD 200**
- [x] MCP de email → **Gmail** (API oficial)
- [x] Base del fork de WhatsApp → **`lharries/whatsapp-mcp`** (MIT verificada). joaohts no se forkea: solo referencia de UX
- [ ] Verificar la licencia del plugin PM de Anthropic y de `Digidai/product-manager-skills` antes de reutilizarlos (§6.2)
- [ ] Verificar si Granola borra las transcripciones a las ~72 h (§4b)
- [x] Cuenta de Apple Developer → ya existe
