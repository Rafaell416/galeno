// La lista de «listo para vender». Corre sobre el build (`npm run build`) hecho con las mismas variables que Vercel producción:
//   PUBLIC_SITE_LIVE=1 PUBLIC_CHECKOUT_URL=… PUBLIC_VIDEO_URL=… npm run build && npm run check:launch
// Sale con error mientras falte algo. Un sitio puede estar publicado (y servir el appcast) sin pasar esta lista:
// mientras PUBLIC_SITE_LIVE no valga 1, nada se indexa.
import { readFileSync, readdirSync, existsSync, statSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const dist = path.join(root, 'dist');
if (!existsSync(dist)) {
  console.error('No hay dist/. Corre `npm run build` primero (con las variables de producción).');
  process.exit(2);
}

const htmlFiles = [];
(function walk(dir) {
  for (const name of readdirSync(dir)) {
    const p = path.join(dir, name);
    if (statSync(p).isDirectory()) walk(p);
    else if (name.endsWith('.html')) htmlFiles.push(p);
  }
})(dist);
const rel = (p) => path.relative(dist, p);
const read = (p) => readFileSync(p, 'utf8');

const problems = [];
const check = (ok, text) => { console.log(`${ok ? '✓' : '✗'} ${text}`); if (!ok) problems.push(text); };

// 1. Nada provisional a la vista
const withPlaceholder = htmlFiles.filter((f) => read(f).includes('data-placeholder'));
check(withPlaceholder.length === 0, `Sin huecos de captura, video, foto o texto (${withPlaceholder.map(rel).join(', ') || 'ninguno'})`);
const withMarker = htmlFiles.filter((f) => /\[[A-ZÁÉÍÓÚÑ][A-ZÁÉÍÓÚÑ ]{5,}\]/.test(read(f)));
check(withMarker.length === 0, `Sin marcadores [ASÍ] en el texto (${withMarker.map(rel).join(', ') || 'ninguno'})`);
check(!existsSync(path.join(dist, 'estilo.html')), 'La página de muestra /estilo no está en el build');

// 2. Configuración de producción
const home = read(path.join(dist, 'index.html'));
check(!/<meta name="robots"/.test(home), 'PUBLIC_SITE_LIVE=1: la home se puede indexar');
check(!/class="btn btn--primary" href="#precio"/.test(home), 'PUBLIC_CHECKOUT_URL apunta a la compra de verdad (no al ancla de relleno)');
check(/<video[^>]+>/.test(home), 'PUBLIC_VIDEO_URL: el video está puesto');
check(existsSync(path.join(dist, 'og.png')) && existsSync(path.join(dist, 'og-en.png')), 'Las imágenes Open Graph existen (og.png y og-en.png)');

// 3. Infraestructura y revisión
check(!read(path.join(root, 'vercel.json')).includes('PROJECT_REF'), 'vercel.json: /download/ apunta al proyecto de Supabase (no a PROJECT_REF)');
check(/legalReviewed:\s*true/.test(read(path.join(root, 'src/site.ts'))), 'Privacidad y términos revisados por un abogado (legalReviewed en src/site.ts)');
const cast = read(path.join(dist, 'appcast.xml'));
check(cast.includes('<rss') && cast.includes('<channel>'), 'El appcast es un feed válido');

console.log(problems.length ? `\n${problems.length} cosa(s) por resolver antes de vender.` : '\nListo para vender.');
process.exit(problems.length ? 1 : 0);
