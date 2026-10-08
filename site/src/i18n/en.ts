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
    contact: 'Write to us',
    credit: 'Portrait: lithograph by Vigneron, public domain.',
    disclaimer:
      'Galeno is an independent product of Galeno LLC. It is not affiliated with or endorsed by Anthropic, Meta, Slack, Notion, Atlassian or Google: their names are used only to say what it works with.',
  },
  home: {
    metaTitle: 'Galeno · Never let a WhatsApp message go cold',
    hero: {
      title: 'Stop losing clients and tasks in your WhatsApp messages.',
      lead: 'Galeno builds an agent that reads your chats, your tickets and your documents, and tells you who to write to today, what you promised and what is still unanswered. You approve every message.',
      buy: 'Buy · USD 200',
      how: 'See how it works',
      fine: 'One-time payment · Lifetime updates · Ready in about ten minutes · For Mac',
      portraitAlt: 'Portrait of Galen of Pergamon, lithograph by Vigneron',
    },
    problem: {
      kicker: 'The problem',
      title: 'Your work happens in chat. And in chat, everything gets lost.',
      items: [
        'A client asks on Tuesday and nobody answers until Friday. By then they have bought somewhere else.',
        'You promise a proposal in a group, and a week later nobody knows who was going to send it.',
        'On Friday you lose the afternoon putting together a report of things already said in your chats, your tickets and your meetings.',
      ],
      closing: 'It is not a lack of discipline. The information is spread over ten places and you are the only one who pulls it together.',
    },
    solution: {
      kicker: 'The solution',
      title: 'An agent that reads for you and leaves what matters ready.',
      body: 'Galeno is not another chat or another subscription. It is an assistant that lives on your Mac, reads what you already have and hands you three things: what is unanswered, what you promised and what to say. Whatever goes out to another person, you always approve.',
    },
    flow: {
      label: 'How Galeno sees it',
      alt: 'Diagram: three WhatsApp chats go into Galeno, which returns what is unanswered, what you promised and a proposed message that you approve',
      chatsTitle: 'Your WhatsApp chats',
      chats: [
        { who: 'Group · Clients', msg: 'Can you confirm the price for Thursday?' },
        { who: 'Chat · Supplier', msg: 'I’ll send you the proposal this week.' },
        { who: 'Group · Team', msg: 'Does anyone have yesterday’s report?' },
      ],
      readsLabel: 'Galeno reads',
      outTitle: 'What it gives back',
      waiting: { label: 'Unanswered', text: 'A client has been waiting 3 days for your confirmation.' },
      promised: { label: 'What you promised', text: 'Send the proposal this week.' },
      proposal: { label: 'Proposed message', text: '“Hi, I’m confirming the price for Thursday. I’ll send you the proposal today.”' },
      approve: 'Approve',
      edit: 'Edit',
      note: 'Illustrative example. Nothing is sent without your approval.',
    },
    steps: {
      kicker: 'How it works',
      title: 'Three steps, about ten minutes.',
      items: [
        { title: 'Pick your role', text: 'Product, marketing or sales. Galeno prepares the skills for your work.' },
        { title: 'Connect your tools', text: 'WhatsApp with a QR code; Notion, Jira, Slack and Gmail by signing in as usual. No terminal, no commands.' },
        { title: 'Ask it', text: '“Who do I write to today?”, “Summarise the week”, “Write me the PRD”.' },
      ],
    },
    video: {
      kicker: 'On video',
      title: 'How your tools get connected.',
      pendingLabel: 'Video pending',
      pending: 'The product video goes here.',
      noVideo: 'Your browser cannot play this video.',
    },
    shot: { pending: 'Screenshot pending' },
    features: {
      tools: {
        kicker: 'Tools',
        title: 'All your work in one place, no copy and paste.',
        body: [
          'Notion, Jira, Slack, Gmail, Google Drive and Calendar, and your meeting recordings in Fathom. You sign in to each one as usual and Galeno leaves your agent ready to use them.',
          'What it reads, it reads without asking. What it sends to other people, it always asks you first.',
        ],
        shot: 'Screenshot of the “Pick your tools” step in the setup assistant',
        shotAlt: 'The “Pick your tools” step of the Galeno setup, with Jira, Notion, Slack, Google Drive, Gmail and WhatsApp checked',
      },
      whatsapp: {
        kicker: 'WhatsApp',
        title: 'Never let a message go cold.',
        body: [
          'You link your WhatsApp with a QR code and your agent can read your chats and groups: what was asked, what was promised, who is waiting for an answer. It can propose a message and, if you approve it, send it. Every message asks for your permission, one by one.',
          'Your chats are stored on your Mac.',
        ],
        warningTitle: 'Before you link.',
        warning:
          'WhatsApp does not offer this connection officially. There is a risk that Meta restricts your number. Galeno limits sending (by default, up to 40 a day) and never writes to broadcast lists or channels, but the risk does not go away.',
        shot: 'Screenshot of the screen for linking WhatsApp',
        shotAlt: 'The Galeno setup screen for connecting WhatsApp: it will read your groups and chats, and send messages only with your approval',
      },
      docs: {
        kicker: 'Documents and tickets',
        title: 'From chat to PRD to tickets, without starting from scratch.',
        body: [
          'Ask for a PRD, the user stories or the tickets for an epic and it writes them reading what you already have in Notion, Jira and your meetings. It comes with skills ready for each role, and you can create or add your own.',
          'You decide whether your agent can write in each tool or only read.',
        ],
        shot: 'Screenshot of the skills step with PRD, stories and tickets',
        shotAlt: 'The “Skills” step of the Galeno setup, with PRD, user stories, roadmap, epics and tickets',
      },
      reports: {
        kicker: 'Reports',
        title: 'This week’s report, ready for your approval.',
        body: [
          'Your agent gathers what changed this week in your tickets, meetings and chats, writes the report and shows it to you exactly as it will go out. You read it and, if you say yes, it posts it in the channel. It appears under your name.',
          'Scheduled tasks leave the report prepared: they never post for you.',
        ],
        shot: 'Screenshot of the tracking and reports skills',
        shotAlt: 'The “Skills” step of the Galeno setup, with the tracking and reports skills, including the Slack report',
      },
    },
    offer: {
      kicker: 'The offer',
      title: 'All of this, for a single payment of USD 200.',
      intro: 'This is what you get the day you buy:',
      items: [
        { title: 'Your agent, set up in about ten minutes.', text: 'Role, tools and permissions ready, without touching the terminal.' },
        { title: 'It reads your WhatsApp chats and groups.', text: 'Who is waiting for an answer, what you promised and who to write to today.' },
        { title: 'More than 20 ready-made skills.', text: 'PRD, stories, roadmap, tickets, reports, follow-ups and prospecting.' },
        { title: 'Your own skills.', text: 'Add yours, or create a new one with a short conversation.' },
        { title: 'One agent per project.', text: 'Create as many as you like, each with its own rules and memory.' },
        { title: 'Your number, protected.', text: 'Approval on every send and daily limits that the agent cannot get around.' },
        { title: 'Lifetime updates.', text: 'Including WhatsApp patches when Meta changes something.' },
      ],
      costTitle: 'Do the math with your own hour.',
      cost: 'If you lose an hour a day pulling reports together and hunting for who to write to, that is about 20 hours a month. If an hour of yours is worth USD 25, that is USD 500 every month. Galeno costs USD 200, once. A USD 20 a month subscription is USD 240 a year.',
      guarantee: '{days}-day guarantee: if it does not work for you, we refund you.',
      buy: 'Buy · USD 200',
      fine: 'One payment. No renewal.',
      requirementsTitle: 'What you need',
      requirements: [
        'macOS 14 or later, on Apple Silicon or Intel',
        'A Claude account (not included in the price)',
        'An internet connection',
      ],
    },
    fit: {
      kicker: 'Who it is for',
      title: 'Galeno is not for everyone.',
      yesTitle: 'It is for you if…',
      yes: [
        'You work in product, marketing or sales, and your day goes between WhatsApp, Slack, tickets and meetings.',
        'You want someone to tell you what is pending without you having to tell them first.',
        'You would rather approve every message than lose control of what goes out.',
      ],
      noTitle: 'It is not for you if…',
      no: [
        'You want to send bulk or automatic messages: Galeno does not do that.',
        'You do not have a Mac with macOS 14 or later.',
        'You are looking for something that acts on its own, without asking you.',
      ],
    },
    testimonials: {
      kicker: 'What they say',
      title: 'People already using it.',
      pending: 'Real testimonials go here, with permission from whoever gave them. None is made up.',
    },
    principles: {
      kicker: 'How it is built',
      title: 'Three decisions that are not up for negotiation.',
      items: [
        { title: 'Your data stays on your Mac.', text: 'Galeno has no servers that receive your chats or your keys. What your agent reads is processed with your own Claude account.' },
        { title: 'Nothing goes out without your approval.', text: 'Every message to another person asks for your permission, one by one. This cannot be turned off.' },
        { title: 'No subscription.', text: 'You pay once. Updates are free for whoever bought Galeno, for as long as it continues to be published.' },
      ],
    },
    faq: {
      kicker: 'Questions',
      title: 'What people usually ask.',
      items: [
        {
          q: 'Do I need to know how to code?',
          a: 'No. Galeno installs and prepares everything; you see no commands and no Terminal. If you can find your way around a Mac app, you can use it.',
        },
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
