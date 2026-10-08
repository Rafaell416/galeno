import type { es } from './es';

export const en: typeof es = {
  htmlLang: 'en',
  skip: 'Skip to content',
  meta: {
    siteName: 'Galeno',
    description: 'Galeno builds an agent that reads your chats, tickets and documents and leaves the work ready. A Mac app. One-time payment.',
  },
  nav: {
    label: 'Main',
    how: 'How it works',
    price: 'Price',
    docs: 'Documentation',
  },
  langSwitch: { label: 'Language', es: 'ES', en: 'EN', esName: 'Español', enName: 'English' },
  footer: {
    label: 'Footer',
    privacy: 'Privacy',
    terms: 'Terms',
    docs: 'Documentation',
    contact: 'Write to me',
    credit: 'Portrait: lithograph by Vigneron, public domain.',
    disclaimer:
      'Galeno is an independent product of Galeno LLC. It is not affiliated with or endorsed by Anthropic, Meta, Slack, Notion, Atlassian or Google: their names are used only to say what it works with.',
  },
};
