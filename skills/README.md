# skills

Las skills del perfil Product Manager y el catálogo de skills curadas de la comunidad.

**Fase 5.** El contenido bueno de las skills se escribe en esa fase. Por ahora hay lo mínimo para
que el wizard funcione de punta a punta:

- `catalog.json`: lo que muestra la pantalla 7 (las 17 nuestras en 4 grupos, con textos en español e
  inglés, y las curadas con autor, licencia y enlace a su GitHub). Se valida al leerlo y en las pruebas
  (`SkillCatalogTests`): ids únicos y seguros, solo licencias Apache-2.0 o MIT, y cada skill
  disponible tiene su carpeta.
- `galeno/<id>/SKILL.md`: las 17 nuestras, **mínimas pero válidas** (instrucción de idioma arriba,
  qué hacer, dónde escribir preguntando, aprobación para lo que sale). La Fase 5 las reemplaza.
- `curated/`: vacía. Las curadas están en el catálogo con `"available": false` (se ven con su
  crédito, no se pueden marcar) hasta traer su contenido con su `LICENSE`.

El proyecto de la app copia esta carpeta a `Galeno.app/Contents/Resources/skills` al compilar.

- **Nuestras:** se escriben en inglés, con la instrucción de responder en el idioma del usuario.
- **Curadas:** de terceros, revisadas antes de entrar, con crédito y link a su autor.
- Antes de reutilizar contenido de terceros se verifica su licencia.

**Cómo llegan al usuario.** No se hornean dentro de la app: se publican como contenido
remoto versionado, y la app las descarga al configurar el agente
(con un fallback local por si no hay internet). Mejorar una skill o añadir una nueva no
exige un build nuevo de la app. Ver `docs/03-especificacion-v0.0.1.md` §4f, capa 3. La
ruta de publicación y cómo se verifica la integridad están sin definir (`HANDOFF.md` §12).

Lista de skills y fuentes reutilizables: `docs/03-especificacion-v0.0.1.md` §6.1 y §6.2.
