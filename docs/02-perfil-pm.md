# Anexo — El agente de PM multi-proyecto
### Perfil del usuario, el reto central, y el stack de herramientas

**Complementa:** `01-plan-producto.md` · `03-especificacion-v0.0.1.md`
**Actualizado:** 2 de octubre de 2026 (conciliado con la especificación v0.0.1)

> **Cómo leer este documento.** Describe al usuario completo y la visión del perfil PM, que es multi-proyecto. En la v0.0.1 el usuario puede crear **un agente por proyecto**, cada uno con sus fuentes y su memoria (`03-especificacion-v0.0.1.md` §3b); la separación **garantizada** de contexto entre ellos llega en v0.2 (en v0.0.1 solo WhatsApp la impone por estructura). Cada sección indica qué entra en v0.0.1 y qué queda para después.

---

## 1. El perfil del usuario (PM multi-proyecto)

No es un PM de un solo producto. Es alguien que lleva **varios proyectos a la vez**, cada uno con su propio mundo de herramientas y conversaciones:

- **Comunicación:** WhatsApp (varios grupos, uno por proyecto/cliente), email (varios hilos), Slack (varios canales/workspaces).
- **Documentación y datos:** Google Suite (Drive, Sheets, Slides, Docs), Notion.
- **Gestión:** Jira (tickets, sprints), Notion (backlog, docs).
- **Reuniones:** herramientas de transcripción (Granola, Fathom, Fireflies, Google Meet).

**Lo que quiere automatizar:**
- Crear tareas recurrentes.
- Mandar informes por Slack.
- Llevar seguimiento de lo que se habla y ocurre en Slack, WhatsApp, Notion, Jira, Docs y llamadas.
- Todo esto **a través de múltiples proyectos distintos**.
- Y **enviar**: mensajes por WhatsApp y Slack, correos, escribir en Notion, Jira, Docs, Drive.

**Qué de esto cubre la v0.0.1:** leer de todas esas fuentes y escribir en Notion, Jira y Google Docs; enviar por Slack y email con aprobación. Con varios proyectos, se crea un agente por proyecto. Quedan para v0.2 la **separación garantizada de contexto** entre agentes y el **envío por WhatsApp**.

---

## 2. El reto central (lo que hace esto difícil y valioso) — v0.2

**El Galeno de MediClub vive en un proyecto. Este agente vive en muchos a la vez.** El reto no es conectar herramientas — es la **separación de contexto por proyecto**. El agente tiene que saber que el grupo de WhatsApp "Cliente A", el canal de Slack "#cliente-a", el tablero de Jira "CLA" y la carpeta de Drive "Cliente A" son **el mismo proyecto**, y no mezclarlos con los del Cliente B.

Si esto falla, el producto no sirve: un informe del Cliente A que llega al Slack del Cliente B es un desastre que puede costar una cuenta. Por eso la **arquitectura de proyectos** (cómo el agente mapea qué fuente pertenece a qué proyecto) es el corazón del perfil PM, más que la lista de integraciones.

**Diseño propuesto para la separación:**
- Un "registro de proyectos": cada proyecto declara sus fuentes (este grupo de WA, este canal de Slack, este tablero de Jira, esta carpeta de Drive).
- Toda acción del agente está *scoped* a un proyecto: "resume lo de esta semana del Proyecto A" solo mira las fuentes de A.
- Los envíos confirman el proyecto destino antes de mandar: "voy a enviar este informe al Slack del Proyecto A — ¿confirmas?"

**Estado:** es lo más difícil del producto y queda para **v0.2**; primero se valida que un proyecto aporta valor. En v0.0.1 la semilla es el paso 6 del wizard ("Elige qué leer"), donde el usuario escoge qué grupos, canales, carpetas y proyectos ve el agente.

---

## 3. Leer vs. enviar — la línea de riesgo

El usuario quiere que el agente **envíe**. Enviar es más peligroso que leer:

- Un agente que **lee** y resume mal → pierdes tiempo.
- Un agente que **envía** mal → mandas el mensaje equivocado al cliente equivocado. Pierdes la cuenta.

**Regla de producto:** todo envío a un canal externo (correo a cliente, Slack de cliente) pasa por **aprobación humana** antes de salir. Igual que el muro de producción del Galeno de MediClub, pero para comunicación. Los envíos internos de bajo riesgo (escribir un borrador en Notion propio) pueden ser más libres. Cuando llegue el multi-proyecto, la aprobación incluirá además el proyecto destino confirmado.

**En v0.0.1** los únicos canales de envío son **Slack y email**, por APIs oficiales. WhatsApp no envía: su MCP no tiene herramientas de envío.

---

## 4. Las herramientas, por categoría (lo que el usuario ya usa + lo que falta)

**En v0.0.1:**
| Herramienta | Rol | Lectura / Envío |
|---|---|---|
| WhatsApp | Comunicación con clientes/equipo | **Solo lectura** de los grupos y chats elegidos (dispositivo vinculado, no oficial, con advertencia explícita). Envío: v0.2 |
| Email (Gmail) | Hilos por proyecto | Leer, redactar y enviar (con aprobación) |
| Slack | Canales por proyecto | Leer, resumir, enviar informes (con aprobación) |
| Google Drive/Docs/Sheets | Documentación y datos | Leer y escribir |
| Notion | Backlog, docs, PRDs | Leer y escribir |
| Jira | Tickets, sprints | Leer, crear tickets, actualizar estados |
| Transcripción (Fireflies/Granola/Fathom) | Reuniones | Leer directo por el MCP oficial de cada proveedor |
| Google Meet | Reuniones | Leer las transcripciones de Gemini desde Drive |

**Herramientas de PM que la investigación (2026) señala como importantes y que vale considerar para versiones futuras:**
- **Roadmap / priorización:** Productboard, Jira Product Discovery, Linear, Aha!
- **Analítica de producto:** Amplitude, Mixpanel, Pendo, PostHog (lenguaje natural para funnels/retención/cohortes sin analista).
- **Feedback / discovery:** Dovetail, Productboard, Lane.
- **Diseño:** Figma.
- **Dashboards:** Power BI, Looker, Tableau.

El consenso 2026 del stack PM: "usa menos herramientas, dale a cada una un trabajo, y deja que la IA haga el trabajo mecánico." Eso es exactamente lo que vende este producto.

---

## 5. El roster del agente de PM

Siguiendo el patrón del Galeno de MediClub (subagentes + skills + guardrails):

**Subagentes:**
- `scribe` — lee transcripciones de reuniones y extrae decisiones y acciones.
- `tracker` — vigila Slack/Jira/Notion y detecta qué cambió.
- `reporter` — arma informes.

Los tres son de solo lectura + Notion/Jira; sin Bash y sin edición de código.

**Skills:** la lista vigente, de 17 skills, está en `03-especificacion-v0.0.1.md` §6.1. Las que nacieron de este perfil:
- `/resumen-proyecto` — qué pasó esta semana en todas las fuentes del proyecto.
- `/informe-slack` — arma y envía (con aprobación) el informe al canal del proyecto.
- `/tareas-recurrentes` — crea las tareas que se repiten cada semana/sprint.
- `/acta` — transcripción → decisiones → tareas en Jira/Notion.
- `/seguimiento` — estado de lo pendiente en Slack, Jira y Docs.

**Guardrails:**
- Aprobación humana para todo envío externo.
- WhatsApp solo lectura: el MCP no tiene herramientas de envío.
- El agente no ejecuta código.
- Separación estricta por proyecto, nunca mezclar fuentes de proyectos distintos (v0.2).

---

## 6. Por qué esto encaja en el producto que vas a vender

Esto no es un producto aparte — es **el perfil con el que Galeno sale al mercado**, y a futuro la plantilla "PM multi-proyecto", probablemente la más valiosa y la más difícil de replicar. La separación de contexto por proyecto es conocimiento de arquitectura que un configurador genérico no tiene. Y el perfil (alguien que malabarea 5 clientes entre WhatsApp, Slack, Jira y correos) es un dolor enorme y muy común — más gente sufre esto que la que lleva un repo de código.

**Hipótesis de valor:** si un PM que lleva 5 proyectos recupera 1 hora al día dejando de armar informes y seguimientos a mano, eso es ~20 horas/mes. A eso se le puede poner precio.

---

## 7. Advertencia honesta (sobrealcance)

Este es el perfil más ambicioso de todos los que has planteado. Enviar a múltiples canales, sobre múltiples proyectos, sin mezclar, con aprobación — es mucha superficie. **No lo construyas todo de una.** El orden:

1. **v0.0.1 — un agente por proyecto, sin garantías de separación.** Cada agente es una carpeta con sus fuentes y su memoria; lo único impuesto por estructura es qué chats de WhatsApp lee. Leer de todas las fuentes (WhatsApp en solo lectura, Slack, Notion, Google, Jira, Gmail, transcripciones), producir documentos y tareas en Notion/Jira/Docs, y enviar por Slack y email con aprobación. Validar que el resumen y los informes son útiles.
2. **v0.2 — la separación garantizada entre proyectos** en todas las herramientas, y la vista transversal.
3. **v0.2 — el envío por WhatsApp**, decidiendo entre Business API o riesgo aceptado por el usuario.

Si intentas el multi-proyecto-multi-canal-con-envío desde el día 1, te vas a enredar. La separación de contexto es lo más difícil; déjala para cuando lo básico funcione.

*(Descartado del plan original: dejar WhatsApp, Jira y correo para el final, y usar WhatsApp solo como canal de salida por Business API. La v0.0.1 conecta todas las fuentes de lectura desde el inicio.)*
