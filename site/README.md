# site

El sitio web de Galeno (Fase 9): Astro estático, desplegado en Vercel, en `getgaleno.com`. Sin JavaScript en el navegador,
sin cookies ni analítica.

Además de las páginas, sirve tres cosas que la app descarga (solo descargas: no reciben ningún dato del usuario):

| Ruta | Qué es |
|---|---|
| `/appcast.xml` | El appcast de Sparkle. Lo escribe `scripts/build-release.sh` en `public/appcast.xml` |
| `/skills/v1/index.json` | El índice de skills remotas (Fase 5). Reservado, hoy vacío |
| `/download/<disco>.dmg` | Redirige al disco en el bucket público `releases` de Supabase (`vercel.json`) |

Cómo correrlo, las variables de entorno y la lista de «listo para vender»: `README.md` de la raíz, §10.2b.
Estilo: `docs/04-design-system.md` §9 y §10. Reglas: `AGENTS.md`.
