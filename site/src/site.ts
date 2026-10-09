// Datos del negocio y de despliegue que el sitio usa en más de un lugar.
// Los marcadores [ASÍ] bloquean `npm run check:launch`: no se abre al público con ellos.
export const site = {
  name: 'Galeno',
  company: 'Galeno LLC',
  email: 'rvillarreal416@gmail.com',
  url: 'https://getgaleno.com',
  price: 'USD 200',
  // Días de garantía de devolución (decidido: 30; la revisa un abogado antes de vender). Solo se muestra con las ventas abiertas.
  guaranteeDays: 30,
  // Se conecta en la Fase 10 (Stripe). Mientras tanto, el botón lleva a la sección de precio.
  // Ventas cerradas (por ahora): el sitio dice «Descargar», sin precio, y el disco se da gratis a un grupo cercano.
  // PUBLIC_SALES_OPEN=1 enciende todo lo de precio: botón de compra, oferta, cuenta de horas y garantía.
  salesOpen: import.meta.env.PUBLIC_SALES_OPEN === '1',
  // El disco, por la ruta propia del sitio (redirige al bucket de Supabase; ver vercel.json).
  downloadUrl: import.meta.env.PUBLIC_DOWNLOAD_URL || '/download/Galeno-0.0.1.dmg',
  checkoutUrl: import.meta.env.PUBLIC_CHECKOUT_URL || '#precio',
  // Video de ~20 s en el almacenamiento público (Supabase). Vacío = se muestra el hueco.
  videoUrl: import.meta.env.PUBLIC_VIDEO_URL || '',
  // Hasta que sea '1', todas las páginas llevan noindex.
  live: import.meta.env.PUBLIC_SITE_LIVE === '1',
  // Privacidad y términos son borradores técnicos: se pone en true cuando un abogado los revisó.
  legalReviewed: false,
  // Las direcciones de lo que el sitio sirve además de las páginas. Ver HANDOFF.md.
  appcastPath: '/appcast.xml',
  skillsIndexPath: '/skills/v1/index.json',
} as const;
