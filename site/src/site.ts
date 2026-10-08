// Datos del negocio y de despliegue que el sitio usa en más de un lugar.
// Los marcadores [ASÍ] bloquean `npm run check:launch`: no se abre al público con ellos.
export const site = {
  name: 'Galeno',
  company: 'Galeno LLC',
  email: 'rvillarreal416@gmail.com',
  url: 'https://getgaleno.com',
  price: 'USD 200',
  // Se conecta en la Fase 10 (Stripe). Mientras tanto, el botón lleva a la sección de precio.
  checkoutUrl: import.meta.env.PUBLIC_CHECKOUT_URL || '#precio',
  // Video de ~20 s en el almacenamiento público (Supabase). Vacío = se muestra el hueco.
  videoUrl: import.meta.env.PUBLIC_VIDEO_URL || '',
  // Hasta que sea '1', todas las páginas llevan noindex.
  live: import.meta.env.PUBLIC_SITE_LIVE === '1',
  // Las direcciones de lo que el sitio sirve además de las páginas. Ver HANDOFF.md.
  appcastPath: '/appcast.xml',
  skillsIndexPath: '/skills/v1/index.json',
} as const;
