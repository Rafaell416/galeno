# Galeno — HANDOFF

Resumen ejecutivo para cualquier sesión futura. Léelo antes de tocar nada.
Fuente de verdad: `docs/03-especificacion-v0.0.1.md`. Este archivo la resume, no la reemplaza.

**Estado (2 oct 2026):** documentación y estructura del monorepo. Todavía no hay código.
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
  │                             launchd para arrancar al iniciar sesión
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

### Qué escribe el motor en la máquina del usuario

| Archivo | Contenido |
|---|---|
| `AGENTS.md` | Identidad del agente, rol PM, herramientas, reglas. En el idioma elegido, con la instrucción "responde y genera todos los documentos en [idioma]" |
| `.claude/settings.json` | Reglas deny/ask/allow: envíos externos en `ask`, nada de ejecutar código |
| `.mcp.json` | Los MCP conectados. Tokens como referencias a variables de entorno, nunca en texto plano |
| `.claude/agents/` | `scribe`, `tracker`, `reporter`: solo lectura + Notion/Jira; sin Bash ni Edit de código |
| `.claude/hooks/` | Hook de aprobación para todo envío externo |
| `.claude/skills/` | Las skills que el usuario dejó marcadas |

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
3. **Tu agente** — nombre del agente y rol (solo "Product Manager" en v0.0.1).
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
6. **Elige qué leer** — por cada tool, qué grupos/canales/carpetas/proyectos. Semilla del
   multi-proyecto futuro.
7. **Elige tus skills** — las nuestras (todas marcadas por defecto) y las curadas (con
   crédito al creador y link a su GitHub).
8. **Reglas** — qué puede enviar sin preguntar (nada externo por defecto) y qué requiere aprobación.
9. **Generando** — el motor escribe la config, con pasos visibles.
10. **Listo** — cómo usarlo, primeros comandos, dónde está la config. Invitación:
    "Pídele: resume lo que pasó esta semana en Slack".

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
- **Trabajo sobre el fork:** eliminar las 3 de envío; portar el MCP a Go dentro del binario
  del puente; añadir `launchd`; renderizar el QR rotativo en la app; empaquetar y firmar.
- **Quedan:** contactos, chats, mensajes, contexto, descarga de media.
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

**Bases reutilizables (no reinventar):** `product-on-purpose/pm-skills` (Apache 2.0) y
`phuryn/pm-skills` (MIT) como base; `snarktank/ralph` (MIT) por su `/prd`; el plugin
oficial de Anthropic (`anthropics/knowledge-work-plugins`) como estándar de estructura.

**Subagentes:** `scribe` (transcripciones → decisiones y acciones), `tracker` (detecta
qué cambió), `reporter` (arma informes).

---

## 8. Lo que NO está en v0.0.1

| Fuera | Cuándo |
|---|---|
| Envío por WhatsApp | v0.2 |
| Multi-proyecto con separación de contexto | v0.2 |
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
   también se firma.
5. **Validación con 5-10 PMs externos** antes de abrir la venta.

---

## 10. Riesgos de v0.0.1

| Riesgo | Mitigación |
|---|---|
| Ban de WhatsApp a un usuario | Read-only + advertencia explícita + sin promesa de "seguro" |
| Tokens expuestos | Nunca en texto plano ni en servidores propios |
| El agente envía algo mal a un cliente | Envíos externos en `ask` + hook de aprobación |
| Gatekeeper bloquea la app | Firmar y notarizar desde el inicio, incluido el binario Go |
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

- **Dónde vive la config generada:** la spec dice "en la máquina del usuario", sin carpeta.
- **Variables de entorno de los tokens:** dónde se guardan los valores a los que apunta `.mcp.json`.
- **Pagos y licenciamiento:** proveedor y mecanismo de activación sin definir.
- **MCP exactos de Slack, Notion, Jira, Gmail y Drive:** la spec no da endpoints; verificar al construir.
- **Granola:** confirmar si borra transcripciones a las ~72 h; si es así, sincronizar pronto.
- **Fathom:** la búsqueda lee títulos y resúmenes; la transcripción completa se pide por ID.
- **Licencias por verificar:** plugin PM de Anthropic y `Digidai/product-manager-skills`.
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
| `AGENTS.md` | Guía operativa para el agente en este repo | Vigente |
