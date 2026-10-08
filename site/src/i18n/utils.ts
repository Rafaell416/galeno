import { es } from './es';
import { en } from './en';

export type Lang = 'es' | 'en';
export const languages: Lang[] = ['es', 'en'];

const dictionaries = { es, en };
export const t = (lang: Lang) => dictionaries[lang];

/** La dirección de una ruta (`/docs`, `/#precio`) en un idioma. El español no lleva prefijo; el inglés, `/en`. */
export function path(lang: Lang, route = '/'): string {
  const [pathname, hash] = route.split('#');
  const clean = pathname === '/' || pathname === '' ? '' : pathname;
  const base = lang === 'es' ? clean || '/' : `/en${clean}`;
  return hash ? `${base}#${hash}` : base;
}

export const other = (lang: Lang): Lang => (lang === 'es' ? 'en' : 'es');
