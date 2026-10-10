// Textos de los videos. Mismo tono y mismas palabras que el sitio (site/src/i18n); escritos nativos en cada idioma.
export type Lang = 'es' | 'en';

export const hero = {
  es: {
    steps: [
      { k: '01', t: 'Elige tu rol.', s: 'Producto, marketing o comercial.' },
      { k: '02', t: 'Ponle nombre.', s: 'Un nombre corto, el que tú quieras.' },
      { k: '03', t: 'Elige tus herramientas.', s: 'Notion, Jira, Slack, Gmail, WhatsApp…' },
      { k: '04', t: 'Conéctalas.', s: 'Autorizas como siempre y vuelves.' },
      { k: '05', t: 'WhatsApp, con un QR.', s: 'Leerá tus grupos; enviará solo con tu aprobación.' },
      { k: '06', t: 'Skills listas.', s: 'PRD, historias, tickets e informes.' },
      { k: '07', t: 'Nada sale sin tu aprobación.', s: 'Leer no pide permiso. Enviar, siempre.' },
      { k: '08', t: 'Listo.', s: 'Tu agente, en unos diez minutos.' },
    ],
    endTag: 'Para Mac.',
    end2: 'Tu agente, listo en unos diez minutos.',
  },
  en: {
    steps: [
      { k: '01', t: 'Pick your role.', s: 'Product, marketing or sales.' },
      { k: '02', t: 'Name your agent.', s: 'A short name, whatever you like.' },
      { k: '03', t: 'Pick your tools.', s: 'Notion, Jira, Slack, Gmail, WhatsApp…' },
      { k: '04', t: 'Connect them.', s: 'Sign in as usual and come back.' },
      { k: '05', t: 'WhatsApp, with a QR.', s: 'It reads your groups; sends only with your approval.' },
      { k: '06', t: 'Skills, ready.', s: 'PRD, stories, tickets and reports.' },
      { k: '07', t: 'Nothing goes out without you.', s: 'Reading needs no permission. Sending always does.' },
      { k: '08', t: 'Ready.', s: 'Your agent, in about ten minutes.' },
    ],
    endTag: 'For Mac.',
    end2: 'Your agent, ready in about ten minutes.',
  },
} as const;

export const whatsapp = {
  es: {
    h1: 'Tu trabajo pasa en el chat.',
    h2: 'Galeno lo lee por ti.',
    h3: 'Tú decides qué sale.',
    chatsTitle: 'Tus chats de WhatsApp',
    chats: [
      { who: 'Grupo · Clientes', msg: '¿Me confirmas el precio para el jueves?' },
      { who: 'Chat · Proveedor', msg: 'Te mando la propuesta esta semana.' },
      { who: 'Grupo · Equipo', msg: '¿Alguien tiene el informe de ayer?' },
    ],
    reads: 'Galeno lee',
    outTitle: 'Lo que te devuelve',
    waiting: { l: 'Sin respuesta', t: 'Un cliente lleva 3 días esperando tu confirmación.' },
    promised: { l: 'Lo que prometiste', t: 'Enviar la propuesta esta semana.' },
    proposal: { l: 'Mensaje propuesto', t: '«Hola, te confirmo el precio para el jueves. Hoy te comparto la propuesta.»' },
    approve: 'Aprobar',
    edit: 'Editar',
    sent: 'Enviado con tu aprobación',
    endLine: 'Nada se envía sin tu aprobación.',
    note: 'Ejemplo ilustrativo',
  },
  en: {
    h1: 'Your work happens in chat.',
    h2: 'Galeno reads it for you.',
    h3: 'You decide what goes out.',
    chatsTitle: 'Your WhatsApp chats',
    chats: [
      { who: 'Group · Clients', msg: 'Can you confirm the price for Thursday?' },
      { who: 'Chat · Supplier', msg: 'I’ll send you the proposal this week.' },
      { who: 'Group · Team', msg: 'Does anyone have yesterday’s report?' },
    ],
    reads: 'Galeno reads',
    outTitle: 'What it gives back',
    waiting: { l: 'Unanswered', t: 'A client has been waiting 3 days for your confirmation.' },
    promised: { l: 'What you promised', t: 'Send the proposal this week.' },
    proposal: { l: 'Proposed message', t: '“Hi, I’m confirming the price for Thursday. I’ll send you the proposal today.”' },
    approve: 'Approve',
    edit: 'Edit',
    sent: 'Sent with your approval',
    endLine: 'Nothing goes out without your approval.',
    note: 'Illustrative example',
  },
} as const;
