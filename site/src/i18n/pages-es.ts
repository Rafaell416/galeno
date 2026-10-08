import type { LongPage } from './pages-types';

export const docsEs: LongPage = {
  title: 'Documentación',
  metaDescription: 'Cómo instalar Galeno, primeros pasos, qué hacer si algo falla y cómo desinstalarlo.',
  kicker: 'Documentación',
  intro: 'Lo necesario para instalar Galeno, crear tu primer agente y resolver lo que pueda fallar.',
  sections: [
    {
      id: 'requisitos',
      h: 'Requisitos',
      blocks: [
        { ul: [
          'Un Mac con **macOS 14 o superior**, con Apple Silicon o Intel.',
          'Una **cuenta de Claude**. Galeno crea el agente, pero este corre en Claude Code con tu cuenta; el precio de Galeno no la incluye.',
          'Conexión a internet.',
          'Las cuentas de las herramientas que quieras conectar (Notion, Jira, Slack, Gmail…).',
        ] },
      ],
    },
    {
      id: 'instalar',
      h: 'Instalar',
      blocks: [
        { ol: [
          'Descarga el disco de Galeno (`Galeno-<versión>.dmg`) desde el enlace de tu compra.',
          'Ábrelo y arrastra **Galeno** a la carpeta **Aplicaciones**.',
          'Abre Galeno desde Aplicaciones. Como lo descargaste de internet, macOS puede preguntarte una vez si quieres abrirlo.',
        ] },
        { p: 'La app va firmada con un certificado de desarrollador de Apple y revisada por Apple (notarizada). Si macOS te dice que no puede comprobar que no contiene software malicioso, no sigas: escríbenos.' },
      ],
    },
    {
      id: 'primeros-pasos',
      h: 'Primeros pasos',
      blocks: [
        { p: 'La primera vez, Galeno te guía por un asistente. No hay licencia ni código que activar: pagas, descargas y usas.' },
        { ol: [
          '**Tu rol.** Producto, marketing o comercial. Decide qué skills vienen marcadas y en qué orden se te ofrecen las herramientas.',
          '**Tu cuenta de Claude.** Galeno comprueba si Claude Code está instalado y al día. Si no, lo instala o lo actualiza cuando tú lo pides y abre el inicio de sesión en tu navegador.',
          '**El nombre de tu agente** y, si quieres, algo de contexto del proyecto.',
          '**Tus herramientas.** Eliges cuáles va a leer y las conectas una por una.',
          '**Skills y reglas.** Qué sabe hacer y qué puede escribir.',
          '**Revisión.** Ves qué se va a crear y confirmas.',
        ] },
        { p: 'Al terminar, tu agente es una carpeta en `~/Galeno/` y lo abres desde Galeno, en la app de Claude o en Terminal. Cada proyecto puede tener su propio agente.' },
      ],
    },
    {
      id: 'herramientas',
      h: 'Conectar tus herramientas',
      blocks: [
        { p: 'Notion, Jira y Fathom se autorizan en tu navegador predeterminado. Slack se conecta en una ventana propia de Galeno, donde inicias sesión. Gmail, Google Drive, Docs, Sheets y Calendar se conectan desde tu cuenta de Claude (en claude.ai), y Galeno te guía.' },
        { p: 'Lo que tu agente lee, lo lee sin pedirte permiso. Lo que envía a otras personas (Slack, Gmail, WhatsApp), siempre te lo pregunta antes. Un borrador de correo no cuenta como envío: queda en tu buzón.' },
      ],
    },
    {
      id: 'whatsapp',
      h: 'Conectar WhatsApp',
      blocks: [
        { note: '**Es una conexión no oficial.** WhatsApp no la ofrece, y existe el riesgo de que Meta restrinja tu número. Galeno te lo explica antes de vincular y lo aceptas tú.' },
        { ol: [
          'En Galeno, elige WhatsApp y lee el aviso.',
          'Escanea el código QR con tu teléfono, desde WhatsApp → Ajustes → Dispositivos vinculados.',
          'Espera a que baje tu historial. Tus chats se guardan en tu Mac.',
        ] },
        { p: 'Tu agente puede leer todos los chats sincronizados. Para escribir, propone el mensaje y WhatsApp **te pide permiso cada vez**. Hay topes diarios (por defecto 40 mensajes, 15 a contactos nuevos y 10 a grupos), solo se escribe a una persona o a un grupo tuyo, y nunca a listas de difusión ni a canales. En Salud puedes pausar los envíos o bajar los topes.' },
        { p: 'De vez en cuando WhatsApp cierra la sesión vinculada. Si pasa, en **Salud** pulsa «Re-vincular».' },
      ],
    },
    {
      id: 'actualizaciones',
      h: 'Actualizaciones',
      blocks: [
        { p: 'Las actualizaciones son gratis para quien compró. Galeno las busca al abrirse y desde el menú Galeno → «Buscar actualizaciones…». Cada actualización va firmada: la app rechaza un disco que no lo esté.' },
        { p: 'La conexión con WhatsApp puede romperse cuando Meta cambia algo. Los parches llegan con las actualizaciones, y al abrir la app nueva se ponen al día solos.' },
      ],
    },
    {
      id: 'problemas',
      h: 'Si algo falla',
      blocks: [
        { p: 'Abre **Salud** en Galeno: enseña el estado de cada herramienta y de WhatsApp, y te ofrece la acción que corresponde.' },
        { ul: [
          '**Una herramienta sale «Falta autorizar» o «No responde»:** pulsa «Reconectar».',
          '**No llegan mensajes de WhatsApp:** pulsa «Reiniciar servicio». Si no basta, «Re-vincular».',
          '**Un conector de Google sale «Sin saber»:** pulsa «Revisar de nuevo». Galeno nunca dice «Conectada» si no pudo comprobarlo.',
          '**«Abrir» enseña unos segundos una conversación vieja:** es normal. La app de Claude restaura su última vista mientras carga.',
          '**«Abrir» te pide cerrar la app de Claude:** ciérrala con Cmd+Q y vuelve a pulsar «Abrir».',
        ] },
        { p: 'Si sigue sin funcionar, [escríbenos](mailto:{email}) contando qué estabas haciendo y, si puedes, una captura de pantalla.' },
      ],
    },
    {
      id: 'desinstalar',
      h: 'Desinstalar',
      blocks: [
        { ol: [
          'Cierra Galeno y arrastra **Galeno** de Aplicaciones a la Papelera.',
          'Si usaste WhatsApp, en tu teléfono quita el dispositivo en WhatsApp → Ajustes → Dispositivos vinculados.',
          'Tus agentes son carpetas en `~/Galeno/` y el estado de Galeno está en `~/Library/Application Support/Galeno/`. Son tuyos: llévalos a la Papelera cuando quieras.',
        ] },
        { p: 'Las conexiones a Notion, Jira y las demás las guarda Claude Code, no Galeno. Se quitan desde Claude Code.' },
      ],
    },
  ],
};

const updated = 'Última actualización: 8 de octubre de 2026.';

export const privacyEs: LongPage = {
  title: 'Privacidad',
  metaDescription: 'Qué datos recoge el sitio de Galeno, qué hace la app con ellos y qué pasa por terceros.',
  kicker: 'Privacidad',
  updated,
  intro: 'Resumen: Galeno no tiene cuenta, ni analítica, ni servidores que reciban tus chats, tus claves o lo que lee tu agente. Aquí está el detalle.',
  sections: [
    {
      id: 'quien',
      h: 'Quién es responsable',
      blocks: [{ p: 'Galeno LLC, que vende y publica Galeno. Para cualquier asunto de privacidad, [escríbenos](mailto:{email}).' }],
    },
    {
      id: 'sitio',
      h: 'El sitio web',
      blocks: [
        { p: 'El sitio no usa cookies, no tiene analítica y no carga scripts, fuentes ni imágenes de terceros. Las tipografías se sirven desde el propio sitio.' },
        { p: 'Como cualquier servidor web, el que aloja el sitio (Vercel) y el que aloja las descargas (Supabase) registran en sus bitácoras técnicas la dirección IP y los datos de la petición. Los usan para operar y proteger el servicio, no para identificarte.' },
        { p: 'Si nos escribes, usamos tu correo y tu mensaje solo para responderte.' },
      ],
    },
    {
      id: 'app',
      h: 'La app de Galeno',
      blocks: [
        { p: 'Galeno no tiene cuentas, no manda telemetría y no envía a Galeno LLC tus chats, tus claves ni lo que lee o escribe tu agente. Todo eso queda en tu Mac.' },
        { p: 'La app solo hace descargas desde servidores de Galeno: busca actualizaciones (el servidor ve la dirección IP, el nombre y la versión de la app, como en cualquier petición web) y, más adelante, las skills. No sube nada.' },
        { p: 'En tu Mac, Galeno guarda: la lista de tus agentes y sus conexiones, la sesión de WhatsApp y tus mensajes de WhatsApp (en `~/Library/Application Support/Galeno/`) y las carpetas de tus agentes (en `~/Galeno/`). Las claves de acceso de tus herramientas no las guarda Galeno: las guarda Claude Code en tu Mac.' },
      ],
    },
    {
      id: 'terceros',
      h: 'Lo que pasa por terceros',
      blocks: [
        { p: 'Tu agente corre en Claude Code, con tu cuenta de Claude. Lo que el agente lee y escribe se envía a Anthropic para que Claude lo procese, bajo las condiciones y la política de privacidad de Anthropic. Eso no pasa por Galeno.' },
        { p: 'Cada herramienta que conectas (Notion, Jira, Slack, Google, tus servicios de reuniones, WhatsApp) tiene sus propias condiciones y su propia política. Galeno solo prepara la conexión. Los datos que tu agente lee de ellas los procesa Claude, como se indica arriba.' },
        { p: 'WhatsApp: Galeno usa una conexión no oficial, como dispositivo vinculado a tu cuenta. Meta puede restringir un número que la use.' },
      ],
    },
    {
      id: 'compra',
      h: 'Tu compra',
      blocks: [
        { p: 'El pago lo procesa un proveedor de pagos independiente, con sus propias condiciones. De él recibimos los datos mínimos para entregarte el producto: tu correo y la confirmación del pago. Nunca vemos el número de tu tarjeta.' },
      ],
    },
    {
      id: 'derechos',
      h: 'Tus derechos',
      blocks: [
        { p: 'Puedes pedirnos que te digamos qué datos personales tenemos de ti (hoy, el correo y el registro de tu compra), que los corrijamos o que los eliminemos. [Escríbenos](mailto:{email}).' },
      ],
    },
    {
      id: 'cambios',
      h: 'Cambios',
      blocks: [{ p: 'Si esta política cambia, se actualiza aquí y cambia la fecha de arriba. Un cambio que reduzca tu privacidad no se aplica a lo que ya compraste sin avisarte antes.' }],
    },
  ],
};

export const termsEs: LongPage = {
  title: 'Términos',
  metaDescription: 'Las condiciones de uso y de compra de Galeno.',
  kicker: 'Términos',
  updated,
  intro: 'Estas condiciones rigen tu compra y tu uso de Galeno. Si no estás de acuerdo con alguna, no compres ni uses Galeno.',
  sections: [
    {
      id: 'que-es',
      h: 'Qué es Galeno y quién lo vende',
      blocks: [{ p: 'Galeno es una app para Mac, publicada por Galeno LLC, que crea y configura un agente en Claude Code. No es el agente ni Claude Code: es la herramienta que prepara su carpeta, sus permisos y sus conexiones.' }],
    },
    {
      id: 'licencia',
      h: 'Tu licencia',
      blocks: [
        { p: 'Al comprar, recibes una licencia personal, no exclusiva e intransferible para usar Galeno en tu trabajo. No puedes revender el instalador ni compartirlo con quien no lo compró.' },
        { p: 'El pago es único, sin renovación. Las actualizaciones de Galeno son gratuitas para quien compró, mientras Galeno se siga publicando.' },
      ],
    },
    {
      id: 'terceros',
      h: 'Servicios de terceros',
      blocks: [
        { p: 'Galeno funciona con servicios que no son nuestros: Claude (Anthropic), WhatsApp (Meta), Slack, Notion, Atlassian, Google y otros. Necesitas tus propias cuentas y aceptar sus condiciones. No controlamos esos servicios ni sus cambios, y pueden dejar de funcionar con Galeno.' },
        { note: '**WhatsApp.** Galeno se conecta a WhatsApp de una forma no oficial. Meta puede restringir o bloquear un número que la use. Lo aceptas al vincularlo, y Galeno LLC no responde por esa restricción.' },
      ],
    },
    {
      id: 'tu-responsabilidad',
      h: 'Tu responsabilidad',
      blocks: [
        { ul: [
          'Tu agente propone, y **tú apruebas** lo que sale a otras personas. Lo que apruebas es tuyo.',
          'Cumples las leyes que apliquen a tus mensajes, incluidas las de contacto comercial y las de protección de datos de las personas a quienes escribes.',
          'Revisas lo que el agente produce antes de usarlo: puede equivocarse.',
          'No usas Galeno para spam, acoso ni nada ilegal.',
        ] },
      ],
    },
    {
      id: 'garantia',
      h: 'Garantía y responsabilidad',
      blocks: [
        { p: 'Galeno se ofrece «tal cual», sin garantías de que funcione sin interrupciones o sin errores, o de que sirva para un fin concreto. En la medida que la ley lo permita, la responsabilidad total de Galeno LLC por cualquier reclamo se limita a lo que pagaste por Galeno, y no cubre pérdidas indirectas ni la pérdida de datos o de negocio.' },
      ],
    },
    {
      id: 'cambios',
      h: 'Cambios en estas condiciones',
      blocks: [{ p: 'Si estas condiciones cambian, se actualiza esta página y la fecha de arriba. Los cambios no se aplican a lo que ya compraste sin avisarte antes.' }],
    },
    {
      id: 'ley',
      h: 'Ley aplicable',
      blocks: [{ p: '[JURISDICCIÓN Y LEY APLICABLE]' }],
    },
    {
      id: 'contacto',
      h: 'Contacto',
      blocks: [{ p: 'Galeno LLC · [escríbenos](mailto:{email}).' }],
    },
  ],
};
