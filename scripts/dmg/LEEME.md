# Galeno: cómo instalarla

Versión de prueba · {{FECHA}}

Tarda unos cinco minutos. Solo vas a hacer una cosa en la Terminal, y te digo exactamente cuál.

## Antes de empezar

- Un Mac con macOS 14 (Sonoma) o más nuevo y conexión a internet.
- Tu cuenta de Claude (correo y contraseña).
- Si ya habías probado Galeno antes, no hay problema: este instalador la quita primero y empieza de cero. Los agentes que hayas creado y sus conversaciones van a la Papelera, no se borran para siempre.

## Instalar, paso a paso

**1. Deja abierta esta ventana.** Es la del disco de Galeno. Dentro hay un archivo que se llama `instalar-galeno.sh`. Lo vas a necesitar en el paso 4.

**2. Abre la Terminal.** Pulsa a la vez las teclas Comando (⌘) y Barra espaciadora. Escribe la palabra Terminal y pulsa Intro. Se abre una ventana con texto. Es normal: no tienes que entender lo que dice.

**3. Escribe la palabra `bash` y un espacio.** Solo eso: `bash` y, después, un espacio. No pulses Intro todavía.

**4. Arrastra el archivo.** Con el ratón, agarra `instalar-galeno.sh` de la ventana del disco de Galeno y suéltalo encima de la ventana de la Terminal. Va a aparecer escrita su dirección, a continuación de la palabra `bash`. Eso es lo que queremos.

**5. Pulsa Intro.**

**6. Lee la lista y responde.** Si ya tenías Galeno, te muestra lo que va a quitar. Escribe `si` y pulsa Intro. Si no tenías nada, sigue solo.

**7. Espera un minuto.** Verás líneas con una marca ✓ a medida que avanza. Si macOS pregunta si «Terminal» puede acceder a datos de otras apps o a Finder, pulsa «Permitir».

**8. Listo.** Cuando diga «Listo», Galeno se abre sola. Ya puedes cerrar la Terminal.

A partir de ahora Galeno se abre con doble clic desde la carpeta Aplicaciones, como cualquier otra app.

## Si ya habías conectado cosas antes

Al terminar, el instalador te recuerda dos cosas que solo se pueden hacer a mano. Hazlas solo si quieres volver a conectarlo todo desde cero:

- **WhatsApp:** en el teléfono, abre WhatsApp → Ajustes → Dispositivos vinculados, y cierra la sesión del dispositivo de Galeno.
- **Google (Gmail, Drive, Calendar):** entra en claude.ai → Ajustes → Conectores y desconéctalos.

## Si algo no sale como dice aquí

**Al soltar el archivo no pasa nada, o no veo la dirección escrita.**
Comprueba que escribiste `bash` y un espacio antes de arrastrar. Si te equivocaste, borra lo escrito y empieza otra vez desde el paso 3.

**Dice «No such file or directory» o «no encuentro».**
Probablemente cerraste la ventana del disco. Ábrelo otra vez con doble clic en el archivo `.dmg` y repite desde el paso 3.

**Dice «Operation not permitted».**
macOS está protegiendo una carpeta. Abre Ajustes del Sistema → Privacidad y seguridad → Acceso total al disco, activa «Terminal» y repite desde el paso 2.

**Galeno no se abre, o dice que no se puede abrir.**
Abre la Terminal, pega esta línea y pulsa Intro. No muestra nada: es normal. Después abre Galeno con doble clic.

    xattr -dr com.apple.quarantine /Applications/Galeno.app

**Prefiero instalarla a mano, sin la Terminal.**
Arrastra el icono de Galeno de la ventana del disco a la carpeta «Applications» de esa misma ventana. La primera vez que la abras, macOS la va a bloquear: usa la línea de arriba (la de `xattr`) en la Terminal y vuelve a abrirla.

**Dentro de Galeno me dice que falta Claude Code, que hay que actualizarlo o que falta iniciar sesión.**
Pulsa el botón que te muestra: Galeno lo instala, lo actualiza o abre tu navegador para que entres con tu cuenta de Claude.

**Nada funciona.**
Haz una captura de la ventana de la Terminal con lo que dice y mándasela a Rafa.

## Qué necesitas dentro de Galeno

Cuando abras Galeno te va a guiar paso a paso. Ten a mano la cuenta de las herramientas que quieras conectar (Notion, Jira, Slack, Google…) y, si vas a conectar WhatsApp, el teléfono.

## Qué hace Galeno en tu Mac

- Crea la carpeta «Galeno» en tu carpeta de usuario, con tu agente dentro.
- Guarda sus ajustes en Biblioteca → Application Support → Galeno.
- Si conectas WhatsApp, solo puede leerlo: Galeno no puede enviar mensajes.
- No envía tus datos ni tus contraseñas a ningún servidor nuestro.

## Para quitarla del todo

Repite los pasos 2 a 4, pero antes de pulsar Intro escribe un espacio y luego `--solo-limpiar` al final de la línea. Quita Galeno, tus agentes y sus ajustes, y no instala nada.
