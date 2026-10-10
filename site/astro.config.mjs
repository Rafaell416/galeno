// @ts-check
import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';
import { readFileSync } from 'node:fs';

// Las páginas legales son borradores mientras `legalReviewed` no sea true: llevan noindex y no van al sitemap.
const legalReviewed = /legalReviewed:\s*true/.test(readFileSync(new URL('./src/site.ts', import.meta.url), 'utf8'));

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
      filter: (page) => !page.includes('/estilo') && (legalReviewed || !/\/(privacy|terms)\/?$/.test(page)),
      i18n: { defaultLocale: 'es', locales: { es: 'es', en: 'en' } },
    }),
  ],
});
