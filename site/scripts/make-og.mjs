// Genera public/og.png y public/og-en.png con Chrome sin ventana. Solo se corre a mano cuando cambia el titular.
import { execFileSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { existsSync } from 'node:fs';
import path from 'node:path';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const chrome = process.env.CHROME ?? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
if (!existsSync(chrome)) throw new Error(`No encuentro Chrome en ${chrome}. Pasa su ruta en CHROME=…`);

for (const [lang, out] of [['es', 'og.png'], ['en', 'og-en.png']]) {
  const url = `${pathToFileURL(path.join(root, 'scripts/og.html')).href}?lang=${lang}`;
  execFileSync(chrome, [
    '--headless=new', '--disable-gpu', '--hide-scrollbars', '--force-device-scale-factor=1',
    '--allow-file-access-from-files', '--virtual-time-budget=3000', '--window-size=1200,630',
    `--screenshot=${path.join(root, 'public', out)}`, url,
  ], { stdio: 'ignore' });
  console.log(`public/${out}`);
}
