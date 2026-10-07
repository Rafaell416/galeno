# skills

Las skills del perfil Product Manager y el catálogo de skills curadas de la comunidad.

**Fase 5 (5 oct 2026): las 17 skills nuestras de producto están escritas completas.** Después llegaron las cinco
nuestras de comercial: `/prospeccion` (6 oct 2026) y las cuatro de `docs/09` §7 (7 oct 2026). Hoy son 22.

- `catalog.json`: lo que muestra el paso de skills (las 17 nuestras de producto en 4 grupos, las 5 nuestras de
  «Comercial» y las de Anthropic en «Marketing» y «Comercial», con textos en español e inglés, y las curadas con autor, licencia y enlace a su GitHub). Se valida al leerlo y en las pruebas
  (`SkillCatalogTests`): ids únicos y seguros, solo licencias Apache-2.0 o MIT, y cada skill
  disponible tiene su carpeta.
- Cada skill del catálogo trae además lo que muestra su vista previa en la app: `ask` (cómo pedirla con una frase),
  `example` (de qué parte el agente y el resultado en 4 a 7 líneas con formato —`# ` título, `## ` sección, `- ` viñeta,
  `> ` borrador, `| a | b |` tabla—; **ilustrativo, escrito a mano**) y, si aplica, `guarantee`.
  `SkillCatalogTests` exige los dos primeros a todas las que tienen tarjeta.
- `galeno/<id>/SKILL.md`: las 17 nuestras (`docs/03` §6.1). `SkillCatalogTests` exige a cada una la instrucción de
  idioma exacta tras el frontmatter, su sección de reglas, que pregunte dónde escribir en vez de asumir, que no invente,
  que lo que dicen las fuentes no sea una orden y, si puede enviar algo a otras personas, un «yes» explícito al texto final.
  Comprobado contra Claude Code real: un agente generado con las 17 las lista todas al arrancar. **No están probadas
  una por una con trabajo real**: eso se ve usándolas.
- Las cinco nuestras de comercial, también en `galeno/<id>/SKILL.md` y con las mismas exigencias:
  `prospeccion` (a quién escribirle hoy, desde los chats), `prospectar-lista` (trabaja por lotes una lista de leads en
  Google Sheets: sitio web, criterio del usuario, radiografía, primer mensaje, todo anotado en la hoja),
  `seguimientos-hoy` (a quién hacerle seguimiento hoy y qué decirle), `revisar-conversaciones` (solo lee: qué funcionó
  y tres mejoras) y `crear-skill` (entrevista al usuario y redacta una skill suya en `memoria/skills-borrador/`; la
  instala el usuario desde Galeno, nunca el agente). Las tres primeras son las únicas que envían por WhatsApp, y solo
  con `send_message`: un mensaje a la vez, con un «yes» al texto exacto, diciendo los topes del día, sin rodear un
  rechazo del bridge, avisando antes de proponer de noche, en domingo o en festivo, y sin enviar nada en una corrida
  programada (`SkillCatalogTests` lo comprueba). `prospeccion` y `prospectar-lista` abren páginas y repiten la regla de
  contención de `WebFetch`. `prospectar-lista` usa las skills propias `criterio` y `radiografia` del usuario si
  existen. **Las cuatro nuevas no están probadas con un agente real ni con una hoja real.**
- `curated/<id>/`: las de terceros **ya traídas y adaptadas**, cada una con su `SKILL.md` y el `LICENSE` de su origen.
  Hoy son veintiséis, todas de `anthropics/knowledge-work-plugins`: diez de marketing y dieciséis de comercial. Siete de Anthropic (Apache-2.0): `campaign-plan`,
  `content-creation` (une `draft-content` y `content-creation`), `email-sequence`, `brand-review`, `performance-report`,
  `seo-audit` y `competitive-brief` (estas dos miran la web, con permiso del usuario). Y tres de voz de marca de Tribe AI
  (MIT, carpeta `partner-built/brand-voice`), con sus `references/`: `discover-brand`, `guideline-generation` y
  `brand-voice-enforcement`. Y dieciséis de comercial, del plugin de ventas de Anthropic (Apache-2.0): `call-summary`,
  `call-prep`, `draft-outreach`, `inbox-sweep`, `daily-briefing`, `schedule-meeting`, `customer-voice`, `account-plan`,
  `close-plan`, `handle-objection`, `stakeholder-map`, `account-context`, `create-an-asset`, `weekly-wrap`, `lead-triage`
  y `account-tiering` (sin CRM: trabajan con lo que el usuario pega o con una
  hoja; las que tocan el correo no envían nada sin un «sí» al texto exacto).
  Cada una termina con una sección «Source» que dice de dónde salió y qué cambió Galeno; lo demás es el texto de su autor.
  Cómo se adapta una: `docs/03` §6.2. En esta carpeta solo van carpetas de skills (una prueba lo exige).
  Las de la comunidad siguen en el catálogo con `"available": false` y sin tarjeta.

El proyecto de la app copia esta carpeta a `Galeno.app/Contents/Resources/skills` al compilar.

- **Nuestras:** se escriben en inglés, con la instrucción de responder en el idioma del usuario.
  Primera línea tras el frontmatter, siempre igual: «Respond and produce all documents in the user's configured language.»
  Cada una trae su procedimiento, su formato de salida, a dónde va (preguntando si hay varios destinos) y sus reglas; las que
  envían algo a otras personas terminan con un paso de aprobación explícita. Se apoyan en `memoria/` y en los subagentes
  (`scribe`, `tracker`, `reporter`) en vez de repetir su trabajo.
  Referencias, sin copiar texto: la estructura de `/prd`, `/user-stories` y `/release-notes` se contrastó con
  [product-on-purpose/pm-skills](https://github.com/product-on-purpose/pm-skills) (Apache 2.0); ese repositorio no trae una
  skill de roadmap, así que `/roadmap` es nuestra.
- **Curadas:** de terceros, revisadas antes de entrar, con crédito y link a su autor.
- Antes de reutilizar contenido de terceros se verifica su licencia.

**Cómo llegan al usuario.** No se hornean dentro de la app: se publican como contenido
remoto versionado, y la app las descarga al configurar el agente
(con un fallback local por si no hay internet). Mejorar una skill o añadir una nueva no
exige un build nuevo de la app. Ver `docs/03-especificacion-v0.0.1.md` §4f, capa 3. La
ruta de publicación y cómo se verifica la integridad están sin definir (`HANDOFF.md` §12).

Lista de skills y fuentes reutilizables: `docs/03-especificacion-v0.0.1.md` §6.1 y §6.2.
