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
    contact: 'Escríbenos',
    credit: 'Retrato: litografía de Vigneron, dominio público.',
    disclaimer:
      'Galeno es un producto independiente de Galeno LLC. No está afiliado ni respaldado por Anthropic, Meta, Slack, Notion, Atlassian ni Google: sus nombres se usan solo para decir con qué funciona.',
  },
  home: {
    metaTitle: 'Galeno · Que ningún mensaje de WhatsApp se enfríe',
    hero: {
      title: 'Deja de perder clientes y tareas entre los mensajes de WhatsApp.',
      lead: 'Galeno crea un agente que lee tus chats, tus tickets y tus documentos, y te dice a quién escribirle hoy, qué prometiste y qué quedó sin respuesta. Tú apruebas cada mensaje.',
      buy: 'Comprar · USD 200',
      how: 'Ver cómo funciona',
      fine: 'Pago único · Actualizaciones de por vida · Listo en unos diez minutos · Para Mac',
      portraitAlt: 'Retrato de Galeno de Pérgamo, litografía de Vigneron',
    },
    problem: {
      kicker: 'El problema',
      title: 'Tu trabajo pasa en el chat. Y en el chat todo se pierde.',
      items: [
        'Un cliente pregunta el martes y nadie le responde hasta el viernes. Para entonces ya compró en otro lado.',
        'Prometes una propuesta en un grupo, y a la semana nadie sabe quién la iba a mandar.',
        'El viernes pierdes la tarde armando un informe con cosas que ya se dijeron en tus chats, tus tickets y tus reuniones.',
      ],
      closing: 'No es falta de disciplina. Es que la información está repartida en diez sitios y tú eres el único que los junta.',
    },
    solution: {
      kicker: 'La solución',
      title: 'Un agente que lee por ti y te deja lo importante, listo.',
      body: 'Galeno no es otro chat ni otra suscripción. Es un asistente que vive en tu Mac, lee lo que ya tienes y te entrega tres cosas: qué quedó sin respuesta, qué prometiste y qué decir. Lo que sale hacia otra persona, siempre lo apruebas tú.',
    },
    flow: {
      label: 'Cómo lo ve Galeno',
      alt: 'Esquema: tres chats de WhatsApp entran a Galeno, que devuelve lo que quedó sin respuesta, lo que prometiste y un mensaje propuesto que tú apruebas',
      chatsTitle: 'Tus chats de WhatsApp',
      chats: [
        { who: 'Grupo · Clientes', msg: '¿Me confirmas el precio para el jueves?' },
        { who: 'Chat · Proveedor', msg: 'Te mando la propuesta esta semana.' },
        { who: 'Grupo · Equipo', msg: '¿Alguien tiene el informe de ayer?' },
      ],
      readsLabel: 'Galeno lee',
      outTitle: 'Lo que te devuelve',
      waiting: { label: 'Sin respuesta', text: 'Un cliente lleva 3 días esperando tu confirmación.' },
      promised: { label: 'Lo que prometiste', text: 'Enviar la propuesta esta semana.' },
      proposal: { label: 'Mensaje propuesto', text: '«Hola, te confirmo el precio para el jueves. Hoy te comparto la propuesta.»' },
      approve: 'Aprobar',
      edit: 'Editar',
      note: 'Ejemplo ilustrativo. Nada se envía sin tu aprobación.',
    },
    steps: {
      kicker: 'Cómo funciona',
      title: 'Tres pasos, unos diez minutos.',
      items: [
        { title: 'Elige tu rol', text: 'Producto, marketing o comercial. Galeno prepara las skills de tu trabajo.' },
        { title: 'Conecta tus herramientas', text: 'WhatsApp con un código QR; Notion, Jira, Slack y Gmail iniciando sesión como siempre. Sin terminal ni comandos.' },
        { title: 'Pregúntale', text: '«¿A quién le escribo hoy?», «Resume la semana», «Hazme el PRD».' },
      ],
    },
    video: {
      kicker: 'En video',
      title: 'Así se conectan tus herramientas.',
      pendingLabel: 'Video pendiente',
      pending: 'Aquí va el video del producto.',
      noVideo: 'Tu navegador no puede reproducir este video.',
    },
    shot: { pending: 'Captura pendiente' },
    features: {
      tools: {
        kicker: 'Herramientas',
        title: 'Todo tu trabajo en un solo lugar, sin copiar y pegar.',
        body: [
          'Notion, Jira, Slack, Gmail, Google Drive y Calendar, y tus grabaciones de reuniones en Fathom. Inicias sesión en cada una como siempre y Galeno deja a tu agente listo para usarlas.',
          'Lo que lee, lo lee sin pedirte permiso. Lo que envía a otras personas, siempre te lo pregunta antes.',
        ],
        shot: 'Captura del paso «Elige tus herramientas» del asistente',
        shotAlt: 'El paso «Elige tus herramientas» del asistente de Galeno, con Jira, Notion, Slack, Google Drive, Gmail y WhatsApp marcadas',
      },
      whatsapp: {
        kicker: 'WhatsApp',
        title: 'Que ningún mensaje se enfríe.',
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
        title: 'Del chat al PRD y a los tickets, sin empezar de cero.',
        body: [
          'Pídele un PRD, las historias de usuario o los tickets de una épica y los escribe leyendo lo que ya tienes en Notion, Jira y tus reuniones. Trae skills listas para cada rol y puedes crear o añadir las tuyas.',
          'Tú decides si tu agente puede escribir en cada herramienta o solo leer.',
        ],
        shot: 'Captura del paso de skills con PRD, historias y tickets',
        shotAlt: 'El paso «Skills» del asistente de Galeno, con PRD, historias de usuario, roadmap, épicas y tickets',
      },
      reports: {
        kicker: 'Informes',
        title: 'El informe de la semana, listo para tu aprobación.',
        body: [
          'Tu agente junta lo que cambió esta semana en tus tickets, reuniones y chats, redacta el informe y te lo enseña tal como va a salir. Lo lees y, si dices que sí, lo publica en el canal. Aparece con tu nombre.',
          'Las tareas programadas dejan el informe preparado: nunca publican por ti.',
        ],
        shot: 'Captura de las skills de seguimiento y reportes',
        shotAlt: 'El paso «Skills» del asistente de Galeno, con las skills de seguimiento y reportes, entre ellas el informe a Slack',
      },
    },
    offer: {
      kicker: 'La oferta',
      title: 'Todo esto, por un solo pago de USD 200.',
      intro: 'Esto es lo que recibes el día que compras:',
      items: [
        { title: 'Tu agente, configurado en unos diez minutos.', text: 'Rol, herramientas y permisos listos, sin tocar la terminal.' },
        { title: 'Lectura de tus chats y grupos de WhatsApp.', text: 'Quién espera respuesta, qué prometiste y a quién escribirle hoy.' },
        { title: 'Más de 20 skills listas.', text: 'PRD, historias, roadmap, tickets, informes, seguimientos y prospección.' },
        { title: 'Tus propias skills.', text: 'Añade las tuyas, o crea una nueva con una conversación corta.' },
        { title: 'Un agente por proyecto.', text: 'Crea los que quieras, cada uno con sus reglas y su memoria.' },
        { title: 'Tu número, protegido.', text: 'Aprobación en cada envío y topes diarios que el agente no puede saltarse.' },
        { title: 'Actualizaciones de por vida.', text: 'Incluidos los parches de WhatsApp cuando Meta cambie algo.' },
      ],
      costTitle: 'Haz la cuenta con tu hora.',
      cost: 'Si pierdes una hora al día juntando informes y buscando a quién escribirle, son unas 20 horas al mes. Si una hora tuya vale USD 25, son USD 500 cada mes. Galeno cuesta USD 200, una sola vez. Una suscripción de USD 20 al mes son USD 240 al año.',
      guarantee: 'Garantía de {days} días: si no te sirve, te devolvemos el dinero.',
      buy: 'Comprar · USD 200',
      fine: 'Pago único. Sin renovación.',
      requirementsTitle: 'Qué necesitas',
      requirements: [
        'macOS 14 o superior, en Apple Silicon o Intel',
        'Una cuenta de Claude (no está incluida en el precio)',
        'Conexión a internet',
      ],
    },
    fit: {
      kicker: 'Para quién es',
      title: 'Galeno no es para todo el mundo.',
      yesTitle: 'Es para ti si…',
      yes: [
        'Trabajas en producto, marketing o ventas, y tu día pasa entre WhatsApp, Slack, tickets y reuniones.',
        'Quieres que alguien te diga qué quedó pendiente sin que tú se lo cuentes.',
        'Prefieres aprobar cada mensaje a perder el control de lo que se envía.',
      ],
      noTitle: 'No es para ti si…',
      no: [
        'Quieres mandar mensajes masivos o automáticos: Galeno no los hace.',
        'No tienes un Mac con macOS 14 o superior.',
        'Buscas algo que actúe solo, sin pedirte permiso.',
      ],
    },
    testimonials: {
      kicker: 'Lo que dicen',
      title: 'Quienes ya lo usan.',
      pending: 'Aquí van testimonios reales, con permiso de quien los dio. No se publica ninguno inventado.',
    },
    principles: {
      kicker: 'Cómo está hecho',
      title: 'Tres decisiones que no se negocian.',
      items: [
        { title: 'Tus datos se quedan en tu Mac.', text: 'Galeno no tiene servidores que reciban tus chats ni tus claves. Lo que tu agente lee se procesa con tu propia cuenta de Claude.' },
        { title: 'Nada sale sin tu aprobación.', text: 'Cada mensaje a otra persona te pide permiso, uno por uno. Esto no se puede apagar.' },
        { title: 'Sin suscripción.', text: 'Pagas una vez. Las actualizaciones son gratis para quien compró, mientras Galeno se siga publicando.' },
      ],
    },
    faq: {
      kicker: 'Preguntas',
      title: 'Lo que suelen preguntar.',
      items: [
        {
          q: '¿Tengo que saber programar?',
          a: 'No. Galeno instala y prepara todo; no ves comandos ni la Terminal. Si te sabes mover en una app de Mac, puedes usarlo.',
        },
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
