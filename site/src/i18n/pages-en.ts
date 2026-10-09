import type { LongPage } from './pages-types';

export const docsEn: LongPage = {
  title: 'Documentation',
  metaDescription: 'How to install Galeno, first steps, what to do if something fails and how to uninstall it.',
  kicker: 'Documentation',
  intro: 'What you need to install Galeno, create your first agent and fix what can go wrong.',
  sections: [
    {
      id: 'requirements',
      h: 'Requirements',
      blocks: [
        { ul: [
          'A Mac with **macOS 14 or later**, on Apple Silicon or Intel.',
          'A **Claude account**. Galeno creates the agent, but it runs in Claude Code with your account; Galeno’s price does not include it.',
          'An internet connection.',
          'Accounts for the tools you want to connect (Notion, Jira, Slack, Gmail…).',
        ] },
      ],
    },
    {
      id: 'install',
      h: 'Install',
      blocks: [
        { ol: [
          'Download the Galeno disk (`Galeno-<version>.dmg`) from the link you received.',
          'Open it and drag **Galeno** to the **Applications** folder.',
          'Open Galeno from Applications. Because you downloaded it from the internet, macOS may ask once whether you want to open it.',
        ] },
        { p: 'The app is signed with an Apple developer certificate and reviewed by Apple (notarized). If macOS says it cannot verify that the app is free of malware, do not continue: write to us.' },
      ],
    },
    {
      id: 'first-steps',
      h: 'First steps',
      blocks: [
        { p: 'The first time, Galeno walks you through a setup assistant. There is no license or code to activate: you download and use it.' },
        { ol: [
          '**Your role.** Product, marketing or sales. It decides which skills come checked and the order in which tools are offered.',
          '**Your Claude account.** Galeno checks that Claude Code is installed and up to date. If not, it installs or updates it when you ask and opens the sign-in in your browser.',
          '**Your agent’s name** and, if you like, some project context.',
          '**Your tools.** You choose which ones it will read and connect them one by one.',
          '**Skills and rules.** What it knows how to do and what it may write.',
          '**Review.** You see what will be created and confirm.',
        ] },
        { p: 'When it finishes, your agent is a folder in `~/Galeno/` and you open it from Galeno, in the Claude app or in Terminal. Each project can have its own agent.' },
      ],
    },
    {
      id: 'tools',
      h: 'Connect your tools',
      blocks: [
        { p: 'Notion, Jira and Fathom are authorized in your default browser. Slack connects in a window of Galeno’s own, where you sign in. Gmail, Google Drive, Docs, Sheets and Calendar connect from your Claude account (on claude.ai), and Galeno guides you.' },
        { p: 'What your agent reads, it reads without asking. What it sends to other people (Slack, Gmail, WhatsApp), it always asks you first. An email draft does not count as sending: it stays in your mailbox.' },
      ],
    },
    {
      id: 'whatsapp',
      h: 'Connect WhatsApp',
      blocks: [
        { note: '**This is an unofficial connection.** WhatsApp does not offer it, and there is a risk that Meta restricts your number. Galeno explains this before linking and you accept it.' },
        { ol: [
          'In Galeno, choose WhatsApp and read the notice.',
          'Scan the QR code with your phone, from WhatsApp → Settings → Linked devices.',
          'Wait for your history to download. Your chats are stored on your Mac.',
        ] },
        { p: 'Your agent can read all synced chats. To write, it proposes the message and WhatsApp **asks for your permission every time**. There are daily limits (by default 40 messages, 15 to new contacts and 10 to groups), it only writes to one person or to a group of yours, and never to broadcast lists or channels. In Health you can pause sending or lower the limits.' },
        { p: 'Now and then WhatsApp closes the linked session. If that happens, in **Health** press “Link again”.' },
      ],
    },
    {
      id: 'updates',
      h: 'Updates',
      blocks: [
        { p: 'Updates are free. It looks for them when it opens and from the Galeno menu → “Check for Updates…”. Every update is signed: the app rejects a disk that is not.' },
        { p: 'The WhatsApp connection can break when Meta changes something. Patches arrive with updates, and when you open the new app they apply themselves.' },
      ],
    },
    {
      id: 'problems',
      h: 'If something fails',
      blocks: [
        { p: 'Open **Health** in Galeno: it shows the state of each tool and of WhatsApp, and offers the right action.' },
        { ul: [
          '**A tool shows “Needs authorization” or “Not responding”:** press “Reconnect”.',
          '**WhatsApp messages are not arriving:** press “Restart service”. If that is not enough, “Link again”.',
          '**A Google connector shows “Unknown”:** press “Check again”. Galeno never says “Connected” if it could not verify it.',
          '**“Open” shows an old conversation for a few seconds:** that is normal. The Claude app restores its last view while it loads.',
          '**“Open” asks you to close the Claude app:** close it with Cmd+Q and press “Open” again.',
        ] },
        { p: 'If it still does not work, [write to us](mailto:{email}) with what you were doing and, if you can, a screenshot.' },
      ],
    },
    {
      id: 'uninstall',
      h: 'Uninstall',
      blocks: [
        { ol: [
          'Quit Galeno and drag **Galeno** from Applications to the Trash.',
          'If you used WhatsApp, on your phone remove the device in WhatsApp → Settings → Linked devices.',
          'Your agents are folders in `~/Galeno/` and Galeno’s state is in `~/Library/Application Support/Galeno/`. They are yours: move them to the Trash whenever you like.',
        ] },
        { p: 'The connections to Notion, Jira and the others are kept by Claude Code, not Galeno. They are removed from Claude Code.' },
      ],
    },
  ],
};

const updated = 'Last updated: October 8, 2026.';

export const privacyEn: LongPage = {
  title: 'Privacy',
  metaDescription: 'What data the Galeno website collects, what the app does with it and what goes through third parties.',
  kicker: 'Privacy',
  updated,
  intro: 'In short: Galeno has no account, no analytics, and no servers that receive your chats, your keys or what your agent reads. Here are the details.',
  sections: [
    {
      id: 'who',
      h: 'Who is responsible',
      blocks: [{ p: 'Galeno LLC, which sells and publishes Galeno. For any privacy matter, [write to us](mailto:{email}).' }],
    },
    {
      id: 'site',
      h: 'The website',
      blocks: [
        { p: 'The site uses no cookies, has no analytics and loads no third-party scripts, fonts or images. Typefaces are served from the site itself.' },
        { p: 'Like any web server, the one hosting the site (Vercel) and the one hosting the downloads (Supabase) record the IP address and request details in their technical logs. They use them to run and protect the service, not to identify you.' },
        { p: 'If you write to us, we use your email and your message only to reply.' },
      ],
    },
    {
      id: 'app',
      h: 'The Galeno app',
      blocks: [
        { p: 'Galeno has no accounts, sends no telemetry and does not send Galeno LLC your chats, your keys or what your agent reads or writes. All of that stays on your Mac.' },
        { p: 'The app only downloads from Galeno’s servers: it looks for updates (the server sees the IP address and the app’s name and version, as in any web request) and, later, skills. It uploads nothing.' },
        { p: 'On your Mac, Galeno stores: the list of your agents and their connections, the WhatsApp session and your WhatsApp messages (in `~/Library/Application Support/Galeno/`) and your agents’ folders (in `~/Galeno/`). Galeno does not store the access keys for your tools: Claude Code keeps them on your Mac.' },
      ],
    },
    {
      id: 'third-parties',
      h: 'What goes through third parties',
      blocks: [
        { p: 'Your agent runs in Claude Code, with your Claude account. What the agent reads and writes is sent to Anthropic for Claude to process, under Anthropic’s terms and privacy policy. That does not go through Galeno.' },
        { p: 'Each tool you connect (Notion, Jira, Slack, Google, your meeting services, WhatsApp) has its own terms and its own policy. Galeno only prepares the connection. The data your agent reads from them is processed by Claude, as described above.' },
        { p: 'WhatsApp: Galeno uses an unofficial connection, as a device linked to your account. Meta may restrict a number that uses it.' },
      ],
    },
    {
      id: 'purchase',
      h: 'Your purchase',
      blocks: [
        { p: 'Payment is processed by an independent payment provider, under its own terms. From it we receive the minimum data to deliver the product: your email and the payment confirmation. We never see your card number.' },
      ],
    },
    {
      id: 'rights',
      h: 'Your rights',
      blocks: [
        { p: 'You can ask us what personal data we hold about you (today, your email and your purchase record), to correct it or to delete it. [Write to us](mailto:{email}).' },
      ],
    },
    {
      id: 'changes',
      h: 'Changes',
      blocks: [{ p: 'If this policy changes, it is updated here and the date above changes. A change that reduces your privacy does not apply to what you already bought without telling you first.' }],
    },
  ],
};

export const termsEn: LongPage = {
  title: 'Terms',
  metaDescription: 'The terms of use and purchase for Galeno.',
  kicker: 'Terms',
  updated,
  intro: 'These terms govern your purchase and use of Galeno. If you do not agree with any of them, do not buy or use Galeno.',
  sections: [
    {
      id: 'what',
      h: 'What Galeno is and who sells it',
      blocks: [{ p: 'Galeno is a Mac app, published by Galeno LLC, that creates and configures an agent in Claude Code. It is not the agent or Claude Code: it is the tool that prepares its folder, its permissions and its connections.' }],
    },
    {
      id: 'license',
      h: 'Your license',
      blocks: [
        { p: 'When you buy, you receive a personal, non-exclusive, non-transferable license to use Galeno in your work. You may not resell the installer or share it with someone who did not buy it.' },
        { p: 'Payment is one-time, with no renewal. Updates to Galeno are free for whoever bought it, for as long as Galeno continues to be published.' },
      ],
    },
    {
      id: 'third-parties',
      h: 'Third-party services',
      blocks: [
        { p: 'Galeno works with services that are not ours: Claude (Anthropic), WhatsApp (Meta), Slack, Notion, Atlassian, Google and others. You need your own accounts and to accept their terms. We do not control those services or their changes, and they may stop working with Galeno.' },
        { note: '**WhatsApp.** Galeno connects to WhatsApp in an unofficial way. Meta may restrict or block a number that uses it. You accept this when you link it, and Galeno LLC is not responsible for that restriction.' },
      ],
    },
    {
      id: 'your-responsibility',
      h: 'Your responsibility',
      blocks: [
        { ul: [
          'Your agent proposes, and **you approve** what goes out to other people. What you approve is yours.',
          'You comply with the laws that apply to your messages, including those on commercial contact and on the data protection of the people you write to.',
          'You review what the agent produces before using it: it can be wrong.',
          'You do not use Galeno for spam, harassment or anything illegal.',
        ] },
      ],
    },
    {
      id: 'warranty',
      h: 'Warranty and liability',
      blocks: [
        { p: 'Galeno is provided “as is”, with no warranty that it will work without interruption or errors, or that it is fit for a particular purpose. To the extent the law allows, Galeno LLC’s total liability for any claim is limited to what you paid for Galeno, and does not cover indirect losses or the loss of data or business.' },
      ],
    },
    {
      id: 'changes',
      h: 'Changes to these terms',
      blocks: [{ p: 'If these terms change, this page and the date above are updated. Changes do not apply to what you already bought without telling you first.' }],
    },
    {
      id: 'law',
      h: 'Governing law',
      blocks: [{ p: '[GOVERNING LAW AND JURISDICTION]' }],
    },
    {
      id: 'contact',
      h: 'Contact',
      blocks: [{ p: 'Galeno LLC · [write to us](mailto:{email}).' }],
    },
  ],
};
