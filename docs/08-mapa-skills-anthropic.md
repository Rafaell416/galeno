# Mapa de las skills de Anthropic

Qué skills publica Anthropic, por categoría, y qué hace Galeno con cada una. Sirve para decidir cuáles se muestran
al usuario y para ir añadiendo las demás **según necesidad**: están mapeadas, no ocultas en la app.

**Fuente y fecha.** Leído el 5 de octubre de 2026 de los dos repositorios públicos de Anthropic:
[`anthropics/knowledge-work-plugins`](https://github.com/anthropics/knowledge-work-plugins) (252 skills en 22 categorías)
y [`anthropics/skills`](https://github.com/anthropics/skills) (19 skills sueltas). **No se pudo leer la página
`claude.ai/customize/skills`**, que exige la sesión del usuario: si allí aparecen categorías que no están aquí, hay que añadirlas a mano.

**Licencia.** `knowledge-work-plugins` es Apache-2.0 (archivo `LICENSE` en la raíz y en la mayoría de las carpetas); las carpetas
de terceros (`partner-built/`) traen la suya (la de `brand-voice` es MIT). En `anthropics/skills`, casi todo es Apache-2.0 **salvo
`docx`, `pdf`, `pptx` y `xlsx`**, que son de código visible pero no abiertas: no se pueden redistribuir. Antes de traer una skill se
confirma el archivo de licencia de **su** carpeta y se copia junto a ella.

**Qué hay que hacerle a cada una para traerla** (por eso entran de a pocas): revisarla entera; añadirle la instrucción de idioma de
Galeno; adaptar sus conectores genéricos (`~~project tracker`, `~~chat`…) a las herramientas que Galeno conecta; quitar o marcar lo que
suponga herramientas que no tenemos (analítica, CRM, búsqueda web); comprobar que respeta las reglas del agente (nada sale sin
aprobación, no ejecuta código, solo escribe en `memoria/`); y darle un id único, crédito y licencia en `skills/catalog.json`.

**Qué se leyó de verdad.** Solo las skills de `product-management`, `marketing` y `partner-built/brand-voice` (su descripción, sus
conectores y que no traen código). **Las demás categorías están clasificadas por su nombre y por la descripción de su plugin, sin
abrirlas**: su nota es una primera lectura, no una revisión.

**Traídas (5 oct 2026).** Marketing completo, diez skills adaptadas en `skills/curated/`: `campaign-plan`, `content-creation` (une `draft-content` y `content-creation`), `email-sequence`, `brand-review`, `performance-report`, `seo-audit` y `competitive-brief` (estas dos miran la web con permiso del usuario), y las tres de voz de marca de Tribe AI (`discover-brand`, `guideline-generation`, `brand-voice-enforcement`). De ventas, las dieciséis que funcionan sin CRM: `call-summary`, `call-prep`, `draft-outreach`, `inbox-sweep`, `daily-briefing`, `schedule-meeting`, `customer-voice`, `account-plan`, `close-plan`, `handle-objection`, `stakeholder-map`, `account-context`, `create-an-asset`, `weekly-wrap`, `lead-triage`, `account-tiering`. Las otras veinte del plugin giran alrededor de un CRM y siguen mapeadas. Además de este mapa hay un inventario de la página `claude.ai/customize/skills` hecho por Cowork el 5 oct 2026 (53 categorías, selección por rol); vive fuera del repo.

**Estados.** *Candidata*: propuesta para mostrarse, **pendiente de que Rafa la apruebe y de su revisión**. *Mapeada*: se conoce, no se
muestra. *Descartada*: no encaja con Galeno, con el motivo.

## `anthropics/knowledge-work-plugins`

| Categoría | Skills | Qué hace Galeno |
|---|---|---|
| **Investigación biomédica** (`bio-research`, 6) | `instrument-data-to-allotrope`, `nextflow-development`, `scientific-problem-selection`, `scvi-tools`, `single-cell-rna-qc`, `start` | Descartadas: fuera del público de Galeno y requieren ejecutar código. |
| **Plugins de Cowork** (`cowork-plugin-management`, 2) | `cowork-plugin-customizer`, `create-cowork-plugin` | Descartadas: son para construir plugins de Cowork. |
| **Soporte** (`customer-support`, 5) | `customer-escalation`, `customer-research`, `draft-response`, `kb-article`, `ticket-triage` | Mapeadas. Suponen un sistema de tickets (Zendesk, Intercom) que Galeno no conecta. |
| **Datos** (`data`, 10) | `analyze`, `build-dashboard`, `create-viz`, `data-context-extractor`, `data-visualization`, `explore-data`, `sql-queries`, `statistical-analysis`, `validate-data`, `write-query` | Mapeadas. La mayoría escribe y ejecuta SQL o código: el agente de Galeno no ejecuta código. |
| **Diseño** (`design`, 7) | `accessibility-review`, `design-critique`, `design-handoff`, `design-system`, `research-synthesis`, `user-research`, `ux-copy` | Mapeadas. `research-synthesis` y `user-research` se solapan con `/sintesis-research`. `design-critique` y `ux-copy` encajarían con Claude Design. |
| **Ingeniería** (`engineering`, 10) | `architecture`, `code-review`, `debug`, `deploy-checklist`, `documentation`, `incident-response`, `standup`, `system-design`, `tech-debt`, `testing-strategy` | Mapeadas. Fuera del perfil: el agente de Galeno no ejecuta código. |
| **Búsqueda** (`enterprise-search`, 5) | `digest`, `knowledge-synthesis`, `search-strategy`, `search`, `source-management` | Mapeadas. Se solapa con lo que el agente ya hace al leer sus fuentes. |
| **Finanzas** (`finance`, 8) | `audit-support`, `close-management`, `financial-statements`, `journal-entry-prep`, `journal-entry`, `reconciliation`, `sox-testing`, `variance-analysis` | Mapeadas. Suponen un ERP o sistema contable. |
| **Personas** (`human-resources`, 9) | `comp-analysis`, `draft-offer`, `interview-prep`, `onboarding`, `org-planning`, `people-report`, `performance-review`, `policy-lookup`, `recruiting-pipeline` | Mapeadas. Datos sensibles de personas: no antes de decidirlo aparte. |
| **Legal** (`legal`, 9) | `brief`, `compliance-check`, `legal-response`, `legal-risk-assessment`, `meeting-briefing`, `review-contract`, `signature-request`, `triage-nda`, `vendor-check` | Mapeadas. Riesgo de que se lea como asesoría legal: no antes de decidirlo aparte. |
| **Marketing** (`marketing`, 8) | `brand-review`, `campaign-plan`, `competitive-brief`, `content-creation`, `draft-content`, `email-sequence`, `performance-report`, `seo-audit` | **Candidatas (7):** `campaign-plan`, `content-creation`, `brand-review`, `email-sequence`, `seo-audit`, `performance-report`, `competitive-brief`. `draft-content` se solapa con `content-creation`: se queda mapeada. `seo-audit` y `competitive-brief` rinden poco sin búsqueda web, que el agente de Galeno hoy no tiene permitida. |
| **Operaciones** (`operations`, 9) | `capacity-plan`, `change-request`, `compliance-tracking`, `process-doc`, `process-optimization`, `risk-assessment`, `runbook`, `status-report`, `vendor-review` | Mapeadas. Buen encaje con las herramientas de hoy (Jira, Notion, Slack): base de un futuro rol de operaciones o project manager. `status-report` se solapa con `/informe-slack`. |
| **Apollo (terceros)** (`partner-built/apollo`, 3) | `enrich-lead`, `prospect`, `sequence-load` | Mapeadas. Requieren una cuenta de Apollo. |
| **Voz de marca (Tribe AI, MIT)** (`partner-built/brand-voice`, 3) | `brand-voice-enforcement`, `discover-brand`, `guideline-generation` | Mapeadas. `brand-voice-enforcement` y `guideline-generation` complementarían a marketing. Son de un tercero (licencia MIT): requieren su propia revisión. |
| **Common Room (terceros)** (`partner-built/common-room`, 6) | `account-research`, `call-prep`, `compose-outreach`, `contact-research`, `prospect`, `weekly-prep-brief` | Mapeadas. Requieren una cuenta de Common Room. |
| **Slack (terceros)** (`partner-built/slack`, 2) | `slack-messaging`, `slack-search` | Descartadas: Galeno ya conecta Slack con sus propias reglas de aprobación. |
| **Zoom (terceros)** (`partner-built/zoom-plugin`, 57) | 57 skills de desarrollo sobre Zoom (SDK de reuniones, video, webhooks…) | Descartadas: son para desarrolladores que integran Zoom. |
| **PDF** (`pdf-viewer`, 1) | `view-pdf` | Descartada: depende de un visor propio de Cowork. |
| **Producto** (`product-management`, 8) | `competitive-brief`, `metrics-review`, `product-brainstorming`, `roadmap-update`, `sprint-planning`, `stakeholder-update`, `synthesize-research`, `write-spec` | **Candidatas (5):** `competitive-brief`, `metrics-review`, `product-brainstorming`, `sprint-planning`, `stakeholder-update`. **No se añaden (3), porque ya tenemos la nuestra:** `write-spec` (≈ `/prd`), `roadmap-update` (≈ `/roadmap`), `synthesize-research` (≈ `/sintesis-research`). |
| **Productividad** (`productivity`, 4) | `memory-management`, `start`, `task-management`, `update` | Mapeadas. `memory-management` y `task-management` chocan con cómo Galeno maneja `memoria/`: no se añaden sin revisarlas a fondo. |
| **Ventas** (`sales`, 36) | `account-context`, `account-plan`, `account-research`, `account-tiering`, `call-prep`, `call-summary`, `close-plan`, `competitive-intelligence`, `create-an-asset`, `crm-hygiene-check`, `customer-health`, `customer-voice`, `daily-briefing`, `deal-advance-gap`, `deal-review`, `deal-signals`, `deal-slip-scenario`, `draft-outreach`, `end-of-day`, `expansion-whitespace`, `forecast`, `handle-objection`, `inbox-sweep`, `lead-triage`, `log-activity`, `pipeline-review`, `renewal-radar`, `rep-context`, `route-lead`, `schedule-meeting`, `setup`, `stakeholder-map`, `team-pipeline`, `update-opportunity`, `weekly-wrap`, `win-loss-review` | Mapeadas. Casi todas suponen un CRM conectado (Salesforce, HubSpot), que Galeno no tiene. Sin CRM servirían `call-prep`, `call-summary`, `account-research`, `draft-outreach` y `handle-objection`. |
| **Pequeña empresa** (`small-business`, 44) | `ad-manager`, `ap-processor`, `brand-style`, `build-agent`, `build-connector`, `business-pulse`, `call-list`, `canva-creator`, `cash-flow-snapshot`, `close-month`, `content-strategy`, `contract-review`, `crm-autopilot`, `grant-rfp-writer`, `grow-pipeline`, `growth-pulse`, `hiring-screener`, `inbox-manager`, `inventory-planner`, `invoice-chase`, `job-post-builder`, `lead-finder`, `lead-triage`, `marketing-monday`, `monday-brief`, `month-end-prep`, `outreach-composer`, `pay-the-bills`, `payroll-prep`, `plan-payroll`, `proposal-builder`, `reactivate`, `report-builder`, `report-pack`, `restock`, `review-reputation`, `seo-ai-visibility`, `smb-onboard`, `smb-router`, `social-content-engine`, `speed-to-lead`, `tax-prep`, `tax-season-organizer`, `ticket-deflector` | Mapeadas. Muy amplias (marketing, ventas, finanzas, contratación de una pyme); varias suponen contabilidad, nómina o inventario. Candidatas futuras para marketing: `content-strategy`, `social-content-engine`, `marketing-monday`, `review-reputation`. |

## `anthropics/skills`

| Skill | Qué hace Galeno |
|---|---|
| `docx`, `pdf`, `pptx`, `xlsx` | **Descartadas.** No son de licencia abierta y funcionan ejecutando código, que el agente de Galeno no hace. |
| `internal-comms`, `doc-coauthoring`, `brand-guidelines` | Mapeadas. Las tres son de escritura y podrían servir a producto y marketing; `brand-guidelines` describe la marca de Anthropic, habría que vaciarla. |
| `algorithmic-art`, `canvas-design`, `frontend-design`, `theme-factory`, `slack-gif-creator`, `web-artifacts-builder`, `webapp-testing`, `mcp-builder`, `claude-api`, `skill-creator` | Descartadas: generan o ejecutan código. |
| `academy-guide`, `discernment-nudge` | Mapeadas. Sin revisar. |

## Resumen

- **Candidatas a mostrarse: 12** (5 de producto y 7 de marketing). Irían en un grupo «De Anthropic» del paso «Skills», con su crédito.
- **Las demás quedan mapeadas** en esta tabla y se traen cuando haga falta, una por una.
- Hoy la app **no muestra ninguna**: no hay ninguna revisada ni traída.
