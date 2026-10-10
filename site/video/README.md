# site/video

Los videos del sitio, hechos con [Remotion](https://www.remotion.dev) (React → MP4). Son composiciones, no grabaciones de
pantalla: salen nítidos (1920×1080, H.264) y el ritmo lo decide el código.

| Composición | Qué es | Origen |
|---|---|---|
| `Hero-es`, `Hero-en` | El producto en ~23 s: rol → nombre → herramientas → conexión → WhatsApp → skills → reglas → listo | **Capturas reales** de la app (`public/shots/<idioma>/`) con cursor, resaltados y cortes animados |
| `WhatsApp-es`, `WhatsApp-en` | Del chat al mensaje aprobado, en 15 s | Animación **ilustrativa** (lleva el rótulo «Ejemplo ilustrativo») |

## Correr

```bash
cd site/video && source ~/.nvm/nvm.sh && nvm use 22   # Node 22 o más
npm install
npm run studio          # vista previa interactiva
./render.sh             # los cuatro videos y sus pósters → out/ (no va a git)
```

Usa el Chrome que ya tienes (`CHROME=…` cambia la ruta); si no existe, Remotion baja el suyo la primera vez.
Los textos están en `src/copy.ts` (mismo tono que `site/src/i18n`); los tiempos y los clics, en `src/Hero.tsx`.

## Cómo se toman las capturas de entrada

1. Compila la app en Debug y ábrela con `-galeno-fake-connect` (conexiones simuladas: nada toca tus cuentas ni `~/Galeno`).
   Antes: tema claro y sonidos apagados (`defaults write com.galeno.Galeno GalenoAppearance light`,
   `GalenoSoundsEnabled -bool false`). La ventana tiene que estar en la pantalla Retina (si queda en un monitor externo
   sale a 1x).
2. Recorre el asistente y, en cada pantalla, `screencapture -o -x -l <id de ventana> archivo.png` (1600×1304).
3. Conviértelas a JPEG calidad 80 (`sips -s format jpeg -s formatOptions 80`) en `public/shots/es` y `public/shots/en`.
   Las que usa `src/Hero.tsx`: `01-rol`, `03-nombre`, `04-herramientas-0…3`, `05-jira-antes`, `07-jira-ok`, `08-whatsapp`,
   `10-skills-documentos`, `11-skills-informes`, `12-reglas`, `15-listo`.
4. Al terminar, borra `~/Library/Application Support/Galeno/` si la prueba dejó un borrador y `defaults delete com.galeno.Galeno`.

## Licencia

Remotion es gratis, también para uso comercial, para individuos y organizaciones con fines de lucro de **hasta 3
empleados**; con más gente hace falta su licencia de empresa (`node_modules/remotion/LICENSE.md`, remotion.pro). Es una
herramienta de desarrollo: no va dentro de la app ni del sitio, solo produce los MP4.
