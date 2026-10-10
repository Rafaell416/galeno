import { existsSync } from 'node:fs';
import { Config } from '@remotion/cli/config';

// H.264 con yuv420p (lo reproduce cualquier navegador). CRF 20: nítido sin pesar de más.
Config.setVideoImageFormat('png');
Config.setCodec('h264');
Config.setPixelFormat('yuv420p');
Config.setCrf(20);
Config.setOverwriteOutput(true);

// Usa el Chrome que ya tienes instalado (CHROME=… lo cambia). Si no existe, Remotion baja el suyo la primera vez.
const chrome = process.env.CHROME ?? '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
if (existsSync(chrome)) Config.setBrowserExecutable(chrome);
