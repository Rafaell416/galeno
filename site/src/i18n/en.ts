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
  home: {
    metaTitle: 'Galeno · An assistant that reads your work and leaves it ready',
    hero: {
      title: 'An assistant that reads your chats, tickets and documents, and leaves the work ready.',
      lead: 'Galeno is a Mac app that builds your agent in Claude Code: it connects your tools, sets its permissions and teaches it your role’s work. For product, marketing and sales.',
      buy: 'Buy · USD 200',
      how: 'See how it works',
      fine: 'One-time payment. Lifetime updates. For Mac.',
      portraitAlt: 'Portrait of Galen of Pergamon, lithograph by Vigneron',
    },
    video: {
      kicker: 'On video',
      title: 'From the first click to your first question.',
      pendingLabel: 'Video pending',
      pending: 'The product video goes here.',
      noVideo: 'Your browser cannot play this video.',
    },
    shot: { pending: 'Screenshot pending' },
    features: {
      tools: {
        kicker: 'Tools',
        title: 'Connect your tools, once.',
        body: [
          'Notion, Jira, Slack, Gmail, Google Drive and Calendar, and your meeting recordings in Fathom, Fireflies or Granola. You sign in to each one as usual and Galeno leaves your agent ready to use them.',
          'What it reads, it reads without asking. What it sends to other people, it always asks you first.',
        ],
        shot: 'Screenshot of the “Your tools” step in the setup assistant',
        shotAlt: 'The Galeno setup step where you choose the tools your agent will read',
      },
      whatsapp: {
        kicker: 'WhatsApp',
        title: 'Your agent reads your WhatsApp groups.',
        body: [
          'You link your WhatsApp with a QR code and your agent can read your chats and groups: what was asked, what was promised, who is waiting for an answer. It can propose a message and, if you approve it, send it. Every message asks for your permission, one by one.',
          'Your chats are stored on your Mac.',
        ],
        warningTitle: 'Before you link.',
        warning:
          'WhatsApp does not offer this connection officially. There is a risk that Meta restricts your number. Galeno limits sending (by default, up to 40 a day) and never writes to broadcast lists or channels, but the risk does not go away.',
        shot: 'Screenshot of your agent reading a WhatsApp group',
        shotAlt: 'A conversation with the Galeno agent summarising a WhatsApp group',
      },
      docs: {
        kicker: 'Documents and tickets',
        title: 'PRDs, stories and tickets, without starting from scratch.',
        body: [
          'Ask for a PRD, the user stories or the tickets for an epic and it writes them reading what you already have in Notion, Jira and your meetings. It comes with skills ready for each role, and you can create or add your own.',
          'You decide whether your agent can write in each tool or only read.',
        ],
        shot: 'Screenshot of a PRD or tickets written by the agent',
        shotAlt: 'A PRD written by the Galeno agent from the project notes',
      },
      reports: {
        kicker: 'Reports',
        title: 'Reports ready for Slack.',
        body: [
          'Your agent gathers what changed this week in your tickets, meetings and chats, writes the report and shows it to you exactly as it will go out. You read it and, if you say yes, it posts it in the channel. It appears under your name.',
          'Scheduled tasks leave the report prepared: they never post for you.',
        ],
        shot: 'Screenshot of a report ready to approve',
        shotAlt: 'A weekly report prepared by the Galeno agent, waiting for your approval',
      },
    },
    about: {
      kicker: 'Who makes it',
      title: 'Hi, I’m Rafa.',
      photoAlt: 'Rafa, creator of Galeno',
      pending: 'Still to be written in the first person: three paragraphs.',
    },
    testimonials: {
      kicker: 'What they say',
      title: 'People already using it.',
      pending: 'Real testimonials go here, with permission from whoever gave them. None is made up.',
    },
    price: {
      kicker: 'Price',
      title: 'One payment. No renewal.',
      amount: 'USD 200',
      per: 'one time',
      points: [
        'Lifetime updates, including patches for the WhatsApp connection.',
        'One agent per project: create as many as you like.',
        'Runs on your Mac. Your keys and your chats do not go through our servers.',
      ],
      requirementsTitle: 'What you need',
      requirements: [
        'macOS 14 or later, on Apple Silicon or Intel',
        'A Claude account (not included in the price)',
        'An internet connection',
      ],
      buy: 'Buy · USD 200',
    },
    faq: {
      kicker: 'Questions',
      title: 'What people usually ask.',
      items: [
        {
          q: 'Do I need a Claude account?',
          a: 'Yes. Galeno sets up the agent and it runs in Claude Code, with your own Claude account; Galeno’s price does not include it. If you do not have Claude Code installed, Galeno installs it when you ask and opens the sign-in.',
        },
        {
          q: 'Does my data leave my Mac?',
          a: 'Galeno has no servers that receive your data or your keys, and there is no account or analytics. What your agent reads goes through Claude, as in any conversation with Claude, and through the tools you connect. Your WhatsApp chats are stored on your Mac.',
        },
        {
          q: 'Is it safe to connect WhatsApp?',
          a: 'It is an unofficial connection: WhatsApp does not offer it, and there is a risk that Meta restricts your number. That is why every outgoing message needs your approval, there are daily limits, and nothing is ever sent to broadcast lists or channels. If you do not want that risk, do not link WhatsApp: the rest of Galeno works the same.',
        },
        {
          q: 'What if Meta changes something and it stops working?',
          a: 'The WhatsApp connection can stop working until a patch is out. Patches arrive with updates, which are free for life.',
        },
        {
          q: 'Does it work on Windows?',
          a: 'No. Galeno is Mac only, on macOS 14 or later.',
        },
        {
          q: 'How many agents can I have?',
          a: 'One per project, as many as you like. Each agent is a folder on your Mac, with its own rules and its own memory.',
        },
      ],
    },
  },
};
