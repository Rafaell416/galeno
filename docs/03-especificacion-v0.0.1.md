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
- Email — **Gmail** (OAuth oficial de Google; mismo flujo que Drive)
- Transcripciones de reuniones — **directo por MCP oficial**: Fireflies (`api.fireflies.ai/mcp`), Granola (`mcp.granola.ai/mcp`), Fathom (`api.fathom.ai/mcp`, gratis en todos los planes). Google Meet: vía el MCP de Google Drive (las transcripciones de Gemini caen ahí)

**Escribe en (con aprobación humana para lo externo):**
- Notion y Jira — crear/actualizar tareas y docs
- Google Docs — escribir documentos
- Slack — enviar informes a canales
- Email — redactar y enviar (con aprobación)

**NO hace en v0.0.1:**
- Enviar por WhatsApp
- Multi-proyecto con separación de contexto (ver §5)
- Generar config para otros agentes que no sean Claude Code

---

## 3. El flujo del wizard (pantallas)

1. **Idioma y bienvenida** — el usuario elige **español o inglés** (preseleccionado según el Mac). Define el idioma de todo el wizard y el que el motor inyecta en la config. Luego: qué es, qué va a configurar, cuánto tarda (~10-15 min según cuántas tools conecte).
2. **Detección** — verifica que Claude Code esté instalado; si no, guía para instalarlo.
3. **Tu agente** — el usuario le pone nombre a *su* agente ("¿Cómo quieres llamarlo?"), rol (en v0.0.1 solo "Product Manager"). Galeno es la app; el agente es del usuario.
4. **Elige tus herramientas** — una sola pantalla con la grilla de todas las tools disponibles (WhatsApp, Slack, Notion, Google Drive/Docs/Sheets, Jira, Gmail, Fireflies, Granola, Fathom, Google Meet). El usuario marca **solo las que usa**. Esto define cuántos pasos tendrá el sub-wizard siguiente: si marca 4, son 4 conexiones; si marca 8, son 8. Al pie, un texto tipo "Vas a conectar 5 herramientas · ~8 min".

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

6. **Elige qué leer** — para cada tool conectada, qué grupos/canales/carpetas/proyectos. (Esto es la semilla del multi-proyecto futuro.)
7. **Elige tus skills** — dos niveles, en una sola pantalla:
   - **Las nuestras:** la lista de skills del perfil PM (§6.1), con una línea de qué hace cada una. Todas marcadas por defecto; el usuario desmarca las que no quiere.
   - **Curadas de la comunidad:** una lista seleccionada por nosotros de skills de terceros que le pueden servir (de pm-skills, phuryn, el plugin oficial de Anthropic…). Cada una con **crédito al creador y link a su GitHub**. Es buena ética y buen marketing: los creadores se enteran de que los recomendamos.
   - *("Trae la tuya" —pegar un link de GitHub— queda para una versión posterior. Ver §5 y §6.3.)*

8. **Reglas** — qué puede enviar sin preguntar (nada externo por defecto) y qué requiere aprobación.
9. **Generando** — el motor escribe la config. Con una animación de "construyendo tu agente" (pasos visibles: escribiendo reglas, conectando herramientas, creando skills) para que la espera también sea parte de la experiencia.
10. **Listo** — cómo usarlo, primeros comandos sugeridos, dónde está la config. Y la primera invitación a probarlo: "Pídele: resume lo que pasó esta semana en Slack".

---

## 4. WhatsApp — reglas de producto (innegociables)

- **Read-only por estructura de código.** El MCP de WhatsApp del producto **no tiene herramienta de envío**. Ni un prompt malicioso ni el propio agente pueden enviar.
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
| **Wizard (la app)** | Se traduce: i18n nativa de Swift (`Localizable.strings`), español e inglés. El usuario elige al inicio; preseleccionado según el idioma del Mac. Los textos de dopamina se escriben **nativamente en cada idioma**, no como traducción literal: "¡Vas por la mitad!" tiene que sonar a alguien que te habla. |
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

## 5. Lo que queda para después (y por qué)

| Qué | Cuándo | Por qué no ahora |
|---|---|---|
| Multi-proyecto con separación de contexto | v0.2 | Es lo más difícil del producto; primero validar que un proyecto aporta valor |
| Envío por WhatsApp | v0.2 | Riesgo de ban; decidir entre Business API o riesgo aceptado por el usuario |
| Plantillas dev / legal / salud | v0.3+ | Validar PM primero |
| Soporte Codex / Cursor / Grok | v0.3+ | Leen AGENTS.md, así que será barato cuando toque |
| Skills externas ("trae la tuya", link de GitHub) | v0.2 | Única puerta de código no revisado; se añade con su guardrail cuando haya demanda |
| Marketplace de skills | futuro | Mercado saturado; primero el instalador |
| Windows | futuro | Mac primero |

**Idiomas:** español e inglés **sí están en v0.0.1** (ver §4d). Lo único que queda fuera es el tratamiento de idioma de las skills curadas, que se ofrecen tal cual.

---

## 6. Qué genera el motor (la config de Claude Code)

Para el perfil PM, el motor escribe en la máquina del usuario:

- `AGENTS.md` — identidad del agente, rol PM, qué herramientas tiene, reglas.
- `.claude/settings.json` — reglas deny/ask/allow: envíos externos en `ask`, nada de ejecutar código.
- `.mcp.json` — los MCP conectados (WhatsApp read-only, Slack, Notion, Google Drive/Docs/Sheets, Jira, Gmail, Fireflies/Granola/Fathom), con tokens como referencias a variables de entorno, nunca en texto plano.
- `.claude/agents/` — subagentes del perfil PM: `scribe`, `tracker`, `reporter` (solo lectura + Notion/Jira; sin Bash, sin Edit de código).
- `.claude/hooks/` — hook de aprobación para todo envío externo.
- `.claude/skills/` — **la lista de skills de abajo.**

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
2. **App Swift/SwiftUI (en paralelo al motor)** — el wizard de §3. **Es lo único que el usuario ve.** Consume el motor; no duplica lógica.
   - **Validación con los 2 PMs del equipo:** con una versión temprana de la app, aunque tenga solo dos pantallas y sea fea. Validan el wizard, no el motor. Darles un CLI no sirve: validarían una experiencia que nunca tendrán.
3. **MCP de WhatsApp read-only** — fork de lharries (MIT).
   - [x] Eliminar las 3 herramientas de envío (y todo lo que solo existía para ellas).
   - [x] Portar el MCP de Python a Go dentro del binario del puente: 9 herramientas de
     solo lectura, SDK oficial (`modelcontextprotocol/go-sdk`), subcomandos
     `pair`/`serve`/`status`, estado en `~/Library/Application Support/Galeno/whatsapp/`,
     build universal arm64+amd64. Detalle en `whatsapp-bridge/README.md`.
   - [ ] Añadir `launchd`, renderizar el QR rotativo en la app, empaquetar y firmar el
     binario. Tomar de joaohts las ideas de UX. Esto es trabajo de `GalenoApp` (Fase 4):
     el puente ya expone `pair` (QR por terminal) y `serve` (MCP por stdio) para que la
     app los invoque como procesos.
   - Conservar los avisos de licencia MIT (ya en `whatsapp-bridge/LICENSE`/`NOTICE`).
4. **Pagos + distribución** — pago único, DMG firmado y notarizado (Apple lo exige para que abra sin sustos).
5. **Validación con 5-10 PMs externos** antes de abrir la venta.

---

## 8. Riesgos específicos de la v0.0.1

| Riesgo | Mitigación |
|---|---|
| Ban de WhatsApp a un usuario | Read-only + advertencia explícita + sin promesa de "seguro" |
| Tokens expuestos | Nunca en texto plano; referencias a env; nunca en servidores propios |
| Agente envía algo mal a un cliente | Todo envío externo en `ask` + hook de aprobación |
| Apple bloquea la app (Gatekeeper) | Firmar y notarizar el DMG desde el inicio; el binario Go embebido también debe firmarse |
| Claude Code cambia formato de config | Motor desacoplado; actualizaciones como parte del soporte |
| Usuario no técnico se traba en un OAuth | Cada pantalla con captura de qué hacer y botón de "ayuda" |

---

## Pendientes antes de construir

- [x] Nombre del producto → **Galeno**
- [x] Precio del pago único → **USD 200**
- [x] MCP de email → **Gmail** (API oficial)
- [x] Base del fork de WhatsApp → **`lharries/whatsapp-mcp`** (MIT verificada). joaohts no se forkea: solo referencia de UX
- [ ] Verificar la licencia del plugin PM de Anthropic y de `Digidai/product-manager-skills` antes de reutilizarlos (§6.2)
- [ ] Verificar si Granola borra las transcripciones a las ~72 h (§4b)
- [x] Cuenta de Apple Developer → ya existe
