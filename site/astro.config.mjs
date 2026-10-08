// @ts-check
import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';

// El sitio es estático y no manda JavaScript al navegador: ni analítica, ni cookies, ni scripts de terceros.
export default defineConfig({
  site: 'https://getgaleno.com',
  trailingSlash: 'never',
  build: { format: 'file' },
  compressHTML: true,
  i18n: {
    defaultLocale: 'es',
    locales: ['es', 'en'],
    routing: { prefixDefaultLocale: false },
  },
  integrations: [
    sitemap({
      // La página de muestra del sistema de diseño no se publica en el sitemap.
      filter: (page) => !page.includes('/estilo'),
      i18n: { defaultLocale: 'es', locales: { es: 'es', en: 'en' } },
    }),
  ],
});
