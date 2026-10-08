// Todo el texto del sitio vive aquí y en en.ts, con las mismas claves. Escrito nativo en cada idioma, no traducido.
export const es = {
  htmlLang: 'es',
  skip: 'Saltar al contenido',
  meta: {
    siteName: 'Galeno',
    description: 'Galeno crea un agente que lee tus chats, tickets y documentos, y te deja el trabajo listo. App para Mac. Pago único.',
  },
  nav: {
    label: 'Principal',
    how: 'Cómo funciona',
    price: 'Precio',
    docs: 'Documentación',
  },
  langSwitch: { label: 'Idioma', es: 'ES', en: 'EN', esName: 'Español', enName: 'English' },
  footer: {
    label: 'Pie de página',
    privacy: 'Privacidad',
    terms: 'Términos',
    docs: 'Documentación',
    contact: 'Escríbeme',
    credit: 'Retrato: litografía de Vigneron, dominio público.',
    disclaimer:
      'Galeno es un producto independiente de Galeno LLC. No está afiliado ni respaldado por Anthropic, Meta, Slack, Notion, Atlassian ni Google: sus nombres se usan solo para decir con qué funciona.',
  },
  home: {
    metaTitle: 'Galeno · Un asistente que lee tu trabajo y te lo deja listo',
    hero: {
      title: 'Un asistente que lee tus chats, tickets y documentos, y te deja el trabajo listo.',
      lead: 'Galeno es una app para Mac que crea tu agente en Claude Code: conecta tus herramientas, le pone los permisos y le enseña el trabajo de tu rol. Para producto, marketing y comercial.',
      buy: 'Comprar · USD 200',
      how: 'Ver cómo funciona',
      fine: 'Pago único. Actualizaciones de por vida. Para Mac.',
      portraitAlt: 'Retrato de Galeno de Pérgamo, litografía de Vigneron',
    },
    video: {
      kicker: 'En video',
      title: 'Del primer clic a tu primera pregunta.',
      pendingLabel: 'Video pendiente',
      pending: 'Aquí va el video del producto.',
      noVideo: 'Tu navegador no puede reproducir este video.',
    },
    shot: { pending: 'Captura pendiente' },
    features: {
      tools: {
        kicker: 'Herramientas',
        title: 'Conecta tus herramientas, una sola vez.',
        body: [
          'Notion, Jira, Slack, Gmail, Google Drive y Calendar, y tus grabaciones de reuniones en Fathom. Inicias sesión en cada una como siempre y Galeno deja a tu agente listo para usarlas.',
          'Lo que lee, lo lee sin pedirte permiso. Lo que envía a otras personas, siempre te lo pregunta antes.',
        ],
        shot: 'Captura del paso «Elige tus herramientas» del asistente',
        shotAlt: 'El paso «Elige tus herramientas» del asistente de Galeno, con Jira, Notion, Slack, Google Drive, Gmail y WhatsApp marcadas',
      },
      whatsapp: {
        kicker: 'WhatsApp',
        title: 'Tu agente lee tus grupos de WhatsApp.',
        body: [
          'Vinculas tu WhatsApp con un código QR y tu agente puede leer tus chats y grupos: qué se pidió, qué se prometió, quién quedó esperando respuesta. Puede proponerte un mensaje y, si tú lo apruebas, enviarlo. Cada mensaje te pide permiso, uno por uno.',
          'Tus chats se guardan en tu Mac.',
        ],
        warningTitle: 'Antes de vincular.',
        warning:
          'WhatsApp no ofrece esta conexión de forma oficial. Existe el riesgo de que Meta restrinja tu número. Galeno limita los envíos (por defecto, hasta 40 al día) y nunca escribe a listas de difusión ni a canales, pero el riesgo no desaparece.',
        shot: 'Captura de la pantalla para vincular WhatsApp',
        shotAlt: 'La pantalla del asistente de Galeno para conectar WhatsApp: leerá tus grupos y chats, y enviará mensajes solo con tu aprobación',
      },
      docs: {
        kicker: 'Documentos y tickets',
        title: 'PRDs, historias y tickets, sin empezar de cero.',
        body: [
          'Pídele un PRD, las historias de usuario o los tickets de una épica y los escribe leyendo lo que ya tienes en Notion, Jira y tus reuniones. Trae skills listas para cada rol y puedes crear o añadir las tuyas.',
          'Tú decides si tu agente puede escribir en cada herramienta o solo leer.',
        ],
        shot: 'Captura del paso de skills con PRD, historias y tickets',
        shotAlt: 'El paso «Skills» del asistente de Galeno, con PRD, historias de usuario, roadmap, épicas y tickets',
      },
      reports: {
        kicker: 'Informes',
        title: 'Informes listos para Slack.',
        body: [
          'Tu agente junta lo que cambió esta semana en tus tickets, reuniones y chats, redacta el informe y te lo enseña tal como va a salir. Lo lees y, si dices que sí, lo publica en el canal. Aparece con tu nombre.',
          'Las tareas programadas dejan el informe preparado: nunca publican por ti.',
        ],
        shot: 'Captura de las skills de seguimiento y reportes',
        shotAlt: 'El paso «Skills» del asistente de Galeno, con las skills de seguimiento y reportes, entre ellas el informe a Slack',
      },
    },
    about: {
      kicker: 'Quién lo hace',
      title: 'Hola, soy Rafa.',
      photoAlt: 'Rafa, creador de Galeno',
      pending: 'Falta escribirlo en primera persona: tres párrafos.',
    },
    testimonials: {
      kicker: 'Lo que dicen',
      title: 'Quienes ya lo usan.',
      pending: 'Aquí van testimonios reales, con permiso de quien los dio. No se publica ninguno inventado.',
    },
    price: {
      kicker: 'Precio',
      title: 'Pago único. Sin renovación.',
      amount: 'USD 200',
      per: 'una sola vez',
      points: [
        'Actualizaciones de por vida, incluidos los parches de la conexión con WhatsApp.',
        'Un agente por proyecto: crea los que quieras.',
        'Funciona en tu Mac. Tus claves y tus chats no pasan por servidores nuestros.',
      ],
      requirementsTitle: 'Qué necesitas',
      requirements: [
        'macOS 14 o superior, en Apple Silicon o Intel',
        'Una cuenta de Claude (no está incluida en el precio)',
        'Conexión a internet',
      ],
      buy: 'Comprar · USD 200',
    },
    faq: {
      kicker: 'Preguntas',
      title: 'Lo que suelen preguntar.',
      items: [
        {
          q: '¿Necesito una cuenta de Claude?',
          a: 'Sí. Galeno configura el agente y este corre en Claude Code, con tu propia cuenta de Claude; el precio de Galeno no la incluye. Si no tienes Claude Code instalado, Galeno lo instala cuando tú lo pides y abre el inicio de sesión.',
        },
        {
          q: '¿Mis datos salen de mi Mac?',
          a: 'Galeno no tiene servidores que reciban tus datos ni tus claves, y no hay cuenta ni analítica. Lo que tu agente lee pasa por Claude, como en cualquier conversación con Claude, y por las herramientas que tú conectas. Tus chats de WhatsApp se guardan en tu Mac.',
        },
        {
          q: '¿Es seguro conectar WhatsApp?',
          a: 'Es una conexión no oficial: WhatsApp no la ofrece, y existe el riesgo de que Meta restrinja tu número. Por eso cada mensaje que sale necesita tu aprobación, hay topes diarios, y nunca se escribe a listas de difusión ni a canales. Si no quieres ese riesgo, no vincules WhatsApp: el resto de Galeno funciona igual.',
        },
        {
          q: '¿Qué pasa si Meta cambia algo y deja de funcionar?',
          a: 'La conexión con WhatsApp puede dejar de funcionar hasta que sale un parche. Los parches llegan con las actualizaciones, que son gratis de por vida.',
        },
        {
          q: '¿Funciona en Windows?',
          a: 'No. Galeno es solo para Mac, con macOS 14 o superior.',
        },
        {
          q: '¿Cuántos agentes puedo tener?',
          a: 'Uno por proyecto, los que quieras. Cada agente es una carpeta en tu Mac, con sus propias reglas y su propia memoria.',
        },
      ],
    },
  },
};
