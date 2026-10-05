# Plan de producto — Galeno
### Una app de escritorio que crea y configura tu agente en Claude Code. Empieza por Product Managers; la visión son plantillas por industria

**Fecha:** 1 de octubre de 2026 · **Actualizado:** 2 de octubre de 2026 (conciliado con la especificación v0.0.1)
**Autor:** Rafa
**Estado:** plan de producto y visión de largo plazo. El alcance de lo que se construye primero está en `03-especificacion-v0.0.1.md`; si hay duda, manda la especificación.

> **Cómo leer este documento.** Conserva el problema, el mercado, el diferencial y la visión. Donde el plan original proponía algo que después se decidió distinto (Tauri, CLI primero, freemium, WhatsApp sin lectura, transcripciones vía Notion), el texto ya refleja la decisión vigente y lo descartado queda anotado como tal.

---

## 1. El problema

Mucha gente ya tiene Claude Code instalado, pero montar un agente *útil y seguro* —con AGENTS.md, guardrails, subagentes, skills y MCPs conectados a Slack, Notion, GitHub— requiere conocimiento técnico que la mayoría no tiene. Rafa lo vivió: le tomó semanas y el acompañamiento de un copiloto de planeación. Un PM o un fundador no técnico no puede hacerlo solo.

**El dolor concreto:** "tengo Claude Code pero no sé convertirlo en un asistente que conozca mi negocio y trabaje con mis herramientas, sin romper nada."

---

## 2. La solución

Una app de escritorio para Mac que, con un flujo tipo wizard:
1. Detecta que el usuario tiene Claude Code instalado, al día y con sesión (y si no, lo instala, lo actualiza o inicia la sesión por él, con un botón).
2. Le pregunta por *su* agente: cómo se llama y qué rol tiene. En v0.0.1 el único rol es **Product Manager**; a futuro, el rol elige una **plantilla** por industria (§4).
3. Conecta sus herramientas una por una: OAuth para Slack, Notion, Google, Jira y las de transcripción; QR para WhatsApp.
4. Genera toda la configuración de Claude Code (AGENTS.md, .claude/settings.json, hooks, skills, subagentes, .mcp.json) con los **guardrails de ese perfil ya puestos**.
5. Deja al usuario con su agente funcionando y una guía de primeros pasos.

**La frase de venta:** "Tu propio agente en 15 minutos, sin saber configurar nada."

**Sobre la marca:** Galeno es el producto (la app que crea agentes), no el agente. Cada usuario nombra el suyo. El Galeno de MediClub es el primer agente nacido de este método y sirve como caso de referencia. Narrativa: *Galeno te crea tu agente.*

El flujo completo del wizard (10 pasos) está en `03-especificacion-v0.0.1.md` §3.

---

## 3. El diferenciador (por qué esto y no lo que ya existe)

La investigación de mercado (oct 2026) muestra un espacio saturado de marketplaces de skills y plantillas CLI, pero con un hueco claro:

| Lo que ya existe | Lo que les falta |
|---|---|
| Marketplaces de skills (Agensi, MCP Market, OpenClaw) | Son piezas sueltas; el usuario arma el rompecabezas |
| Colecciones de plugins (wshobson/agents, pm-skills) | Requieren saber Claude Code; son para técnicos |
| Templates CLI (claude-code-templates, my-claude-code-setup) | Línea de comandos; no para no-técnicos |
| SaaS starters de pago ($99-299) | Son para construir apps, no para configurar tu agente |

**El hueco:** nadie ofrece un **instalador visual, para no-técnicos, con guardrails por industria.** Todos asumen que sabes usar la terminal. Tu producto asume que no.

**El foso defensivo no es el instalador — son los guardrails.** Cualquiera copia un wizard. Lo difícil de replicar es el conocimiento de *qué reglas* necesita un agente de salud (Resolución 1644, no datos de pacientes en logs), uno de finanzas, uno de legal. Ahí está el valor y la razón para cobrar.

Para el perfil PM, el diferencial concreto es la integración con **WhatsApp** (el mundo de LatAm) y, a futuro, la **separación de contexto por proyecto** (ver `02-perfil-pm.md`).

---

## 4. Las plantillas (la visión de largo plazo)

Cada plantilla = un roster de subagentes + skills + guardrails + MCPs sugeridos, afinado a un perfil o industria.

| Plantilla | Cuándo | Para quién | Guardrails distintivos | MCPs típicos |
|---|---|---|---|---|
| **Product Manager** | **v0.0.1** | PMs en cualquier industria | Aprobación humana para todo envío externo; no ejecuta ni toca código; WhatsApp solo lectura | Slack, Notion, Google Drive/Docs/Sheets, Jira, Gmail, WhatsApp (solo lectura), transcripción de reuniones (Fireflies/Granola/Fathom por MCP oficial) |
| **Dev / ingeniería** | v0.3+ | Devs solos o equipos pequeños | main protegida, PR obligatorio, no secretos en repo | GitHub, Supabase, CI |
| **Salud / clínica** | v0.3+ | Clínicas digitales, telemedicina | No datos de pacientes en logs/prompts; aprobación humana en producción; auditoría | Supabase, Notion, Slack |
| **Legal** | v0.3+ | Firmas, abogados | Confidencialidad, no compartir datos de clientes | Docs, Drive |
| **Finanzas** | futuro | Contadores, fintech | No mover dinero sin aprobación, auditoría | Sheets, bancos (lectura) |

**Decisión:** se empieza **solo con Product Manager**. Las demás se validan después de PM.
*(Descartado: empezar con tres plantillas a la vez —salud, PM y dev—.)*

---

## 4b. Fuentes de contexto para perfiles no técnicos

Los perfiles no técnicos (PM, fundadores, operaciones) no viven en el código: viven en reuniones y mensajería. Por eso la fuente de contexto más valiosa para ellos no es el repo, sino **las transcripciones de sus llamadas** y sus chats. El producto las trata como ciudadano de primera clase.

**Transcripción de reuniones (Fireflies, Granola, Fathom, Google Meet):**
- Se leen **directo de la fuente**, por el MCP oficial que hospeda cada proveedor, con OAuth. Google Meet no tiene MCP propio: sus transcripciones caen en Drive y se leen con el MCP de Google Drive.
- En el wizard: el usuario marca qué herramienta de transcripción usa y la conecta con un OAuth.
- Detalle por proveedor en `03-especificacion-v0.0.1.md` §4b.
- **Guardrail por industria:** la plantilla de salud debe advertir de fábrica que NUNCA se transcriben reuniones clínicas con pacientes (dato sensible). Otro ejemplo de por qué los guardrails por industria son el foso.
- *(Descartado: leer las transcripciones vía export a Notion/Docs. Más fricción y menos confiable que un OAuth directo.)*

**WhatsApp — solo lectura, con expectativas honestas:**
- WhatsApp personal NO tiene API oficial. La única forma de leerlo es conectarse como dispositivo vinculado usando el protocolo de WhatsApp Web, de forma **no oficial**. Eso es frágil y existe un riesgo bajo pero real de que WhatsApp restrinja la cuenta.
- **Decisión:** Galeno lee WhatsApp **en solo lectura**, con esa advertencia explícita en la pantalla de vinculación y el usuario decidiendo si continúa. El riesgo de ban se dispara sobre todo por envío automatizado; la lectura es de bajo riesgo, y el valor para el PM (seguimiento de grupos) está en la lectura.
- **Sin envío en v0.0.1.** El MCP de WhatsApp no tiene herramientas de envío: es read-only por estructura de código. El envío se decide en v0.2.
- WhatsApp Business API sí existe, pero es para empresas, cuesta, requiere aprobación de Meta, y desde enero 2026 Meta prohíbe chatbots de IA de propósito general sobre ella. Es una de las dos opciones a evaluar para el envío en v0.2.
- **Regla de pitch:** nunca prometer que es "seguro" ni "oficial". Se dice lo que es: no oficial, solo lectura, todo local, con un riesgo que el usuario acepta.
- Reglas completas en `03-especificacion-v0.0.1.md` §4.
- *(Descartado: no ofrecer lectura y usar WhatsApp solo como canal de salida vía Business API.)*

## 5. Arquitectura — el principio que no se negocia

**Los secretos del usuario NUNCA tocan tu infraestructura.** Todo se queda en la máquina del usuario (su configuración local de Claude Code). La app orquesta los OAuth y genera archivos locales, pero no almacena ni transmite tokens ajenos. Esto es innegociable para un producto que pide credenciales de Slack/Notion/GitHub a desconocidos — es la diferencia entre un producto confiable y una bomba de responsabilidad legal.

**Dos piezas, construidas en paralelo:**
- **El motor (interno):** una librería que, dadas las respuestas del wizard, genera toda la config. No es una interfaz de usuario: el usuario nunca lo ve ni lo usa. Se separa de la app por razones de ingeniería (testeable, reutilizable, la app no acumula lógica).
- **La app:** **Swift + SwiftUI, nativa de Mac.** Es lo único que el usuario ve. Hace el wizard, consume el motor, lanza y supervisa un binario Go para WhatsApp, y corre `claude mcp add` para los MCP hospedados.

Arquitectura detallada en `03-especificacion-v0.0.1.md` §4c.

*(Descartado: Tauri como carcasa —Rafa ya domina Swift y la app nativa es la que mejor se siente en Mac, sin Rust ni contenedor web—; y construir primero un CLI para usarlo o venderlo por separado —quien valide un CLI valida una experiencia que el usuario final nunca tendrá—.)*

**Lo que la app puede y no puede automatizar:**
- ✅ Claude Code (terminal): genera archivos, corre `claude mcp add`. Totalmente automatizable.
- ⚠️ Claude.ai (web/desktop app): su configuración vive en su interfaz y la app no puede meter mano. Queda fuera de v0.0.1, que solo configura Claude Code.

---

## 6. Modelo de negocio

**Decisión: pago único de USD 200** (precio inicial).

Opciones que se evaluaron:

| Modelo | Cómo | Pros | Contras | Estado |
|---|---|---|---|---|
| **Pago único** | Un pago por la app | Simple, "compra una vez" | No hay ingreso recurrente | **Elegido** |
| **Suscripción** | $X/mes por acceso + actualizaciones | Ingreso recurrente; cubre mantener plantillas al día | Más fricción de compra | Descartado por ahora |
| **Freemium** | Plantilla dev gratis; salud/PM de pago | Lead magnet + conversión | Hay que dar valor real gratis | Descartado: v0.0.1 tiene un solo perfil |

**Qué incluye el pago único:** la app y **todas las actualizaciones futuras, de por vida, sin renovación**. No es un detalle menor: el mantenimiento —parches del bridge de WhatsApp cuando Meta cambia su protocolo, compatibilidad con Claude Code y con los MCP— es una obligación perpetua que no trae ingreso recurrente. Las features nuevas son gratis por elección. Mecanismo y arquitectura de 3 capas en `03-especificacion-v0.0.1.md` §4f.

**Argumento de precio:** no vendes un configurador, vendes tiempo recuperado y *no meter la pata*. Para un PM que lleva varios proyectos, recuperar ~1 hora al día de informes y seguimientos son ~20 horas al mes. Para una plantilla futura de salud, evitar una multa de la SIC vale mucho más que el precio. El precio se justifica por los guardrails, no por el software.

---

## 7. Riesgos y cómo mitigarlos

| Riesgo | Mitigación |
|---|---|
| **Seguridad de tokens ajenos** | Nunca tocan tu infra; todo local. Auditoría de seguridad antes de vender. |
| **Claude Code cambia su API/config** | El motor desacoplado facilita actualizar; las actualizaciones son parte del soporte. |
| **Meta rompe el protocolo de WhatsApp** | El bridge tiene versión propia y se parchea de urgencia vía Sparkle. Mantenimiento de por vida, no opcional. |
| **Mantenimiento perpetuo sin ingreso recurrente** | Riesgo aceptado con el pago único. Se distingue internamente mantenimiento (obligación) de features nuevas (elección) para poder razonar costos. |
| **Mercado saturado de skills** | No competir en skills sueltas; competir en "instalador + guardrails". El marketplace de skills queda a futuro. |
| **Soporte a no-técnicos** | Es lo más caro de un producto de pago. Empezar con un nicho pequeño (PMs) y documentación muy buena. |
| **Ban de WhatsApp a un usuario** | Solo lectura, advertencia explícita, sin promesa de "seguro". |
| **Responsabilidad legal (salud, futuro)** | Dejar claro que la plantilla ayuda pero el usuario es responsable de su cumplimiento; no prometer "cumplimiento garantizado". |
| **Dependencia de un solo proveedor (Anthropic)** | En v0.0.1 el motor solo genera config de Claude Code. Codex/Cursor/Grok leen AGENTS.md, así que soportarlos será barato cuando toque (v0.3+). |

Riesgos específicos del MVP en `03-especificacion-v0.0.1.md` §8.

---

## 8. Validación

La validación se hace **con la app**, no con un CLI:

1. **Los 2 PMs del equipo** prueban una versión temprana de la app, aunque tenga solo dos pantallas y sea fea. Validan el wizard, que es la experiencia real.
2. **5-10 PMs externos** la prueban antes de abrir la venta.
3. **Landing:** una página que describe el producto con botón de compra o lista de espera, para medir demanda.
4. **Entrevistas a no-técnicos** que tengan Claude Code: ¿qué les frena hoy? ¿pagarían por resolverlo?

*(Descartado: dar o vender el motor como CLI a conocidos antes de construir la app.)*

---

## 9. Roadmap

| Versión | Qué | Resultado |
|---|---|---|
| **v0.0.1** | Perfil PM, un agente por proyecto (sin separación garantizada), Mac. Motor interno + app SwiftUI en paralelo → MCP de WhatsApp read-only → pagos y DMG firmado y notarizado → validación con 5-10 PMs externos | Producto vendible para PMs |
| **v0.0.2** | Ver actividad: qué hizo el agente y qué envió | Confianza en el uso diario |
| **v0.2** | Separación garantizada de contexto entre agentes y vista transversal; decisión sobre envío por WhatsApp; skills externas ("trae la tuya") con su guardrail | El perfil PM completo |
| **v0.3+** | Plantillas dev / legal / salud; soporte Codex / Cursor / Grok | Más perfiles y más agentes |
| **Futuro** | Marketplace de skills; Windows; más industrias | Mercado más amplio |

El orden de construcción de v0.0.1 está en `03-especificacion-v0.0.1.md` §7.

---

## 10. Lo meta: constrúyelo con tu propio agente

Este producto es el candidato perfecto para ser **el primer producto construido con el flujo del Galeno de MediClub.** El mismo ciclo PRD → épicas → tickets → implementación que usas en MediClub aplica aquí. Sería la prueba viviente de tu propia tesis: un solo dev (tú) construyendo un producto vendible con un equipo de agentes. Eso, además, es parte del pitch de venta: "construido por el mismo método que te vendo."

---

## Decisiones

**Resueltas** (detalle en `03-especificacion-v0.0.1.md` §1):

- Nombre del producto → **Galeno**. La app es la marca; cada usuario nombra a su agente.
- Plataforma → **solo Mac**.
- Precio → **pago único, USD 200**.
- Alcance del motor → **solo config de Claude Code**; Codex/Cursor/Grok en v0.3+.
- Perfil inicial → **solo Product Managers**.
- Framework de la app → **Swift + SwiftUI**.

**Abierta:**

- ¿Cuánto del tiempo de Rafa puede ir aquí sin comprometer el lanzamiento de MediClub del 15 de noviembre?
