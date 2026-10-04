# Galeno — Brief de rediseño de interfaz
### Contexto + prompt para Claude Design

**Cómo usar este documento.** Pégalo completo en Claude Design. Todo lo que necesita está aquí: el prompt (§1), el contexto de producto y de usuario (§2–3), la investigación sobre Galeno de Pérgamo (§4), el sistema de diseño actual y qué se reabre (§5), las restricciones técnicas (§6), el inventario de pantallas con sus estados (§7), lo que se espera de la guía y del copy (§8) y los entregables (§9). El apéndice A trae **todo el copy actual en español e inglés**.

**Qué adjuntar junto al documento** (si Claude Design acepta archivos):
- `galeno-retrato-1200.jpg` y `galeno-app-icon-1024-rounded.png` (en `docs/` de marca).
- La portada de *Galeni Pergameni opera omnia* (Basilea, 1538) y la litografía de Vigneron, si las tienes sueltas.
- Capturas de la app actual: las 10 pantallas, la de conexión de Slack, la advertencia de WhatsApp con el QR, y las dos ventanas web de Slack (inicio de sesión y «Permitir»). Se generan con `-galeno-fake-connect` (ver `GalenoApp/README.md`).
- `docs/04-design-system.md` (el sistema actual, completo).

---

## 1. El prompt

> **Rol.** Eres el diseñador principal de **Galeno**, una app nativa de Mac que crea y configura, con un asistente de 10 pasos, un agente de Claude Code para Product Managers. Quiero un **rediseño completo de la interfaz**: que no solo funcione bien, sino que se vea, se lea y se sienta excelente.
>
> **Qué quiero que hagas, en este orden:**
>
> 1. **Investiga a Galeno de Pérgamo** y su mundo (el §4 tiene un punto de partida verificado; amplíalo con lo que encuentres: el Asclepeion, la biblioteca de Pérgamo y el pergamino, los códices y las ediciones impresas de sus obras, la iconografía médica antigua, el grabado científico de los siglos XVI–XIX). Resume en una página qué imágenes, materiales y gestos te sirven **y cuáles son un cliché que hay que evitar**. Marca lo que supongas.
> 2. **Evoluciona el sistema de diseño** (§5, §9-A): paleta, tipografía, escala, tamaños de botones y controles, iconografía, un **sistema de ilustración**, movimiento y modo oscuro. Dime explícitamente **qué reglas actuales mantienes y cuáles reabres**, con tu razón.
> 3. **Diseña 3 propuestas completas y realmente distintas del asistente** (§9-B): las 10 pantallas, sus estados importantes y las dos ventanas web de Slack. Las tres comparten el producto y el copy base, pero **difieren en dirección visual** (nivel de ornamento, pareja tipográfica, técnica de ilustración, composición de la pantalla, forma de los botones).
> 4. **Reescribe el copy** de cada pantalla en español e inglés (§8): guía al usuario con precisión en cada paso (qué va a pasar, cuánto tarda, qué necesito de él, por qué). Los textos nativos en cada idioma, no traducciones literales.
> 5. **Compara las tres y recomienda una** (§9-C), con costo de implementación honesto en SwiftUI.
>
> **Gusto de partida (mío, Rafa):** un aire **más clásico**; **botones más grandes**; tipografías **legibles pero caligráficas**; **ilustraciones** e **iconos** acordes al mundo de Galeno de Pérgamo; un asistente que **guía y es muy específico** con el usuario en cada paso. No es una lista cerrada: si ves algo mejor, propónlo y defiéndelo.
>
> **Reglas del juego.**
> - Es una app **nativa de Mac (SwiftUI)**: la implementabilidad cuenta. Para cada propuesta di qué es nativo, qué es un control propio, qué fuentes hay que embeber (con su **licencia**) y qué assets hay que producir (§6).
> - El producto es **serio** (toca el Slack, el correo y el WhatsApp de una persona): lo clásico debe transmitir **confianza y calma**, no disfraz. Lo que sale hacia otras personas siempre pide aprobación, y la interfaz debe hacerlo evidente (§8).
> - Entrega **prototipos navegables** (no solo imágenes): las 10 pantallas encadenadas, en el tamaño real de la ventana (**720×560 pt**), claro y oscuro, en **español** y con una muestra en **inglés**.
> - Si algo del brief bloquea tu trabajo, pregunta **antes** de empezar, una sola vez y de forma agrupada. Si no, decide y deja anotada la suposición.
>
> **Formato de entrega.** Un lienzo con secciones: (0) investigación; (A) sistema de diseño v2; (B1, B2, B3) las tres propuestas; (C) comparación y recomendación; (D) notas de implementación para SwiftUI (tokens, componentes, assets, fuentes).

---

## 2. Contexto de producto

**Qué es.** Galeno es una **app de escritorio para Mac**. El usuario la abre, sigue un asistente de 10 pasos y termina con **su propio agente** de Claude Code, ya configurado con guardrails, subagentes, skills y conexiones a sus herramientas. **Galeno es la app; el agente es del usuario** (él le pone nombre). Frase de venta: *«Tu propio agente en 15 minutos, sin saber configurar nada.»* Narrativa: *Galeno te crea tu agente.*

**Para quién (v0.0.1).** **Product Managers** de Latinoamérica, no técnicos. Su mundo: Slack, Notion, Jira, Google Drive/Docs/Sheets, Gmail, reuniones transcritas (Fireflies, Granola, Fathom, Google Meet) y, muy importante en la región, **WhatsApp**.

**Qué hace por debajo** (para entender qué espera y qué teme el usuario):
1. Detecta Claude Code (si no está, guía a instalarlo; Galeno **no** lo instala).
2. Le pide un nombre para su agente y **una línea** sobre el proyecto.
3. **Conecta sus herramientas una por una** (OAuth; QR en WhatsApp; en Slack, Galeno crea una app propia en su workspace).
4. Le deja elegir **qué leer** (canales, grupos, carpetas, proyectos), **qué skills** instalar y **qué reglas** de envío.
5. **Escribe la carpeta del agente** (`~/Galeno/<nombre>/`) y la deja lista para abrirla en la app de Claude o en Terminal.

**Lo que más vale (y lo que da miedo).** El agente **lee** Slack, WhatsApp y correo, y puede **escribir** en Notion o Jira. Por eso el producto promete poco y verifica mucho: WhatsApp es de **solo lectura** (no existe código de envío), y **todo envío externo pide aprobación humana siempre**. La confianza es parte del producto: la interfaz tiene que ser tranquila, clara y honesta.

**Líneas rojas que la interfaz no puede romper** (ya decididas):
- Nunca decir que WhatsApp es «seguro» u «oficial», ni prometer cumplimiento garantizado. La advertencia de la pantalla de WhatsApp (pantalla 5) **no se reescribe** sin mi aprobación: puedes rediseñar su presentación, no su sentido. Propón mejoras de redacción **aparte**, marcadas como propuesta.
- Ninguna interfaz que sugiera que el agente puede enviar algo externo sin pedir permiso.
- Galeno no habla con servidores propios: nada de «sincronizar con la nube», «tu cuenta Galeno», etc. Todo es local; las credenciales las guarda Claude Code.

---

## 3. El usuario y su momento

- **Perfil:** profesional de producto, listo y ocupado, cómodo con Slack y Notion, **incómodo con la terminal**. Probablemente ya pagó (USD 200, pago único) y llega con una mezcla de curiosidad y recelo: *«¿esto va a tocar mis chats? ¿y si hace algo mal?»*.
- **Duración:** ~10–15 minutos, el más largo (paso 5) lo ocupan las conexiones. Ya hay pantallas de «dopamina» para romper la espera; los textos de esas pantallas los escribo yo después, pero **propón** versiones.
- **Emoción objetivo:** **calma y competencia** al inicio («esto está pensado»), **progreso visible** en el medio, **orgullo y claridad** al final («tengo un asistente mío y sé exactamente qué hará y qué no»).
- **Dónde se atora hoy** (dolores reales de las pruebas): no sabe qué va a pasar en la ventana que se abre (Slack pide iniciar sesión dos veces en el flujo antiguo; ahora una); no entiende por qué le piden elegir «qué leer» si el agente lo lee todo; no sabe si lo que ve en pantalla (un número de canales, una lista) es real; los errores de OAuth dicen qué falló pero no qué hacer.
- **Idiomas:** español (principal) e inglés; el idioma se elige en el paso 1 y cambia **toda la app en caliente**. Español latinoamericano neutro, trato de **tú**.

---

## 4. Galeno de Pérgamo — punto de partida de la investigación

> Verificado en fuentes generales (Wikipedia, biografías de UCL y EBSCO, guías de Pérgamo). **Amplía y contrasta**; donde dudes, márcalo.

**La persona**
- Nació en **129 d. C. en Pérgamo** (hoy Bergama, Turquía) y murió hacia el 200–216 d. C. (las fuentes discrepan: unas dicen ~199, otras ~216). Médico, cirujano y filósofo griego bajo el Imperio romano.
- Estudió medicina en el **Asclepeion** de Pérgamo, el templo-hospital de **Asclepio**, el dios de la curación. Según su propio relato, su padre lo encaminó a la medicina tras un sueño con Asclepio.
- A los 28 años (157 d. C.) fue **médico y cirujano de los gladiadores** del sumo sacerdote de Asia: de ahí su experiencia en heridas y anatomía práctica, cuando la disección humana estaba prohibida.
- Después ejerció en **Roma**, entre médicos y emperadores. Escribió un corpus enorme, y su autoridad dominó la medicina durante siglos (más de mil años).
- Su método —observar, **sistematizar**, probar— es el «método» que Galeno (el producto) toma como metáfora: un criterio que ordena el caos para que otro trabaje con calma.

**La ciudad**
- La **biblioteca de Pérgamo** rivalizaba con la de Alejandría. Según la tradición, cuando los Ptolomeos vetaron el papiro para frenarla, los artesanos de Pérgamo perfeccionaron la piel tratada que se llamó *charta pergamena*: de ahí **pergamino** (y «Pérgamo» en la palabra). **Nuestro color de fondo ya es el pergamino**; esta conexión es un regalo para la marca y se puede contar.
- Hitos visuales: el **Asclepeion** (columnata, galería, templo), la **acrópolis** con su teatro, el friso del **Altar de Pérgamo** (relieve helenístico, dramático).

**Lo que el proyecto ya usa como fuente estética** (de `docs/04`)
- La litografía *Claude Galien* de **Vigneron** (siglo XIX, dominio público): el retrato del logo.
- La portada de ***Galeni Pergameni opera omnia*** (Basilea, 1538, **ΓΑΛΗΝΟΥ ΑΠΑΝΤΑ**): capitales romanas, composición de portada impresa, sello rojo de biblioteca.

**Motivos auténticos que podrían servir** (a validar tú): el **bastón de Asclepio** (una sola serpiente, no el caduceo de Hermes: es un error común), el mortero y las **plantas medicinales** (láminas botánicas), la **columnata** del Asclepeion, el **códice y el rollo**, la pluma de caña, el **grabado en cobre / xilografía** de tratados médicos del XVI, los **diagramas anatómicos** y las tablas de los humores (con cuidado: es historia, no un consejo médico), el **sello de biblioteca**. Fuentes libres para grabados históricos: Wellcome Collection y Biodiversity Heritage Library (dominio público); revisa siempre la licencia de cada imagen.

**Clichés a evitar** (es el riesgo número uno): togas y coronas de laurel de «fiesta romana», tipografía «medieval» gótica o de taberna, pergaminos enrollados con bordes quemados, sellos de lacre dibujados con chorreo, serpientes decorativas sin criterio, columnas griegas de stock, sepia saturado, filigranas sin función. Lo clásico que buscamos es **el de un impresor sobrio y un grabador científico**: orden, proporción, silencio, y un detalle bien hecho en el lugar justo.

---

## 5. El sistema de diseño actual y qué se reabre

Fuente completa: `docs/04-design-system.md` (adjunto). Resumen:

**Idea:** «un libro antiguo bien impreso»: papel envejecido, tinta gris cálida, capitales romanas espaciadas, **un solo acento de lacre rojo**, mucho silencio. *No* es vintage decorativo.

**Paleta** (medida de los originales; claro / oscuro «libro de noche»)
`parchment-50 #F3EEE2` (fondo) · `parchment-100 #EEE7D8` · `parchment-200 #E7E0D1` · `parchment-300 #D8D1C1` (bordes) · `parchment-400 #D0CBBC` · `vellum-100 #E2C9B7` — `ink-900 #2E2D2A` (texto) · `ink-700 #63655E` · `ink-500 #8C877C` · `ink-300 #B5B0A5` — `binding-900 #314041` (encuadernación; base del modo oscuro `#262E30`) — acento único `seal-700 #8B3A3A` (+ `seal-100 #F0E3E0`) — estados `moss-700 #4F6F5B` (éxito), `ochre-700 #9A7B2F` (aviso).

**Tipografía actual:** web/guía: **Cinzel** (capitales inscripcionales, solo títulos cortos), **EB Garamond** (texto, 18 px), **JetBrains Mono** (código). **En la app:** *New York* (serif del sistema) con `.smallCaps()` y tracking en los títulos de paso; **sin fuentes embebidas**.

**Forma:** espacio 4·8·12·16·24·32·48·64·96; radios 4/8/12; **bordes de 1 px como forma de separar, sin sombras**; separador `·  ·  ·`; punto final tras títulos en capitales (**GALENO.**).

**Controles hoy (app):** nativos de macOS —botón primario `borderedProminent` con tinte `ink-900`, campos nativos, casillas y selectores nativos— sobre un fondo de pergamino. Botones de tamaño estándar (≈28 pt de alto en la barra, `controlSize(.large)` en algunos).

### Reglas actuales: qué mantienes, qué reabres

| Regla actual | Estado | Nota |
|---|---|---|
| Papel pergamino + tinta cálida + **un solo acento** lacre | **Mantener como base** | Se puede ampliar con **un segundo tono muy contenido** si lo justificas |
| Capitales romanas solo en títulos cortos; nunca párrafos | **Mantener** | |
| Sin sombras decorativas; bordes finos para separar | **Reabrir con criterio** | Una sombra suave en botones grandes puede ayudar a la «pulsabilidad» |
| **Sin ilustraciones ni ornamento** (prohibidos: florituras, marcos, viñetas, plumas, pergaminos) | **REABRIR** (lo pido yo) | Define un **sistema de ilustración sobrio** con reglas claras de dónde sí y dónde no |
| **Sin texturas** | **Reabrir con prudencia** | Una viñeta o grano casi imperceptible podría sumar; justifica y mide su costo |
| **Sin fuentes embebidas** (solo New York) | **REABRIR** (lo pido yo) | Quiero tipografías **legibles pero caligráficas**. Propón pares concretos con **licencia verificada** (OFL / uso comercial en app) |
| **Controles 100 % nativos** | **Reabrir** | Quiero **botones más grandes** y con carácter. Dime qué se logra con estilos nativos y qué exige un control propio, y su costo |
| Iconos: SF Symbols monocromos | **Reabrir** | Propón un set de iconos de línea fina coherente con el mundo clásico, o una mezcla justificada |
| Logos de terceros solo monocromos `ink-700` | **Mantener** | Es una decisión de respeto a las marcas y de coherencia |
| Modo claro y oscuro | **Mantener** | El oscuro es gris-verdoso, no negro |
| Movimiento discreto 150–300 ms, trazo y opacidad, sin rebotes ni confeti de colores | **Mantener el espíritu** | Puedes proponer gestos propios (p. ej. una línea que se «escribe») |
| El retrato solo en logo/ícono/splash/hero | **Reabrir levemente** | ¿Un retrato pequeño como compañero en algunas pantallas? Argumenta |

> **Importante:** cualquier regla que reabras significa que luego hay que actualizar `docs/04-design-system.md` y `AGENTS.md` (hoy prohíben fuentes embebidas, texturas y controles que imiten «lo antiguo»). Por eso te pido que **cada cambio venga justificado y con su costo**.

---

## 6. Restricciones técnicas (para que lo diseñado se pueda construir)

- **Plataforma:** macOS 14+, **SwiftUI**. Ventana **fija de 720×560 pt** (no redimensionable). El contenido de cada paso hace scroll si no cabe, pero **se diseña para caber**.
- **Navegación:** barra de progreso arriba («PASO 3 DE 10»); Atrás/Siguiente abajo, **salvo** el paso 5 (lleva sus propios botones) y el 9 (sin botones mientras escribe).
- **Idiomas:** ES/EN cambian en caliente; las cadenas más largas (ES) tienen que caber. Diseña con **textos largos reales** (apéndice A).
- **Modo claro y oscuro** del sistema, ambos de primera clase.
- **Accesibilidad:** contraste AA (ver reglas de `docs/04` §2), áreas de clic cómodas (≥ 40 pt para lo primario), foco visible con teclado, **reduce motion** respetado (ya existe), lector de pantalla (cada ilustración decorativa debe poder marcarse como decorativa).
- **Fuentes:** si propones fuentes que no son del sistema, indica **licencia**, pesos necesarios y **peso en MB**. Debe haber un **fallback** (New York) coherente.
- **Ilustraciones:** se entregan como **vectores** (SVG/PDF) o como PNG @2x/@3x; idealmente **monocromas «template»** para que tomen el color de tinta del modo claro/oscuro. Di cuántas ilustraciones son necesarias y de qué tamaños.
- **Imágenes de terceros:** solo dominio público o licencia verificada; anota la procedencia de cada una (el retrato de Vigneron ya es de dominio público).
- **Dos ventanas web** (WebKit) que Galeno abre para Slack: la de **iniciar sesión** y la de **«Permitir»**. Su *contenido* es de Slack (no se diseña), pero su **barra superior** sí es de Galeno: lleva el dominio a la vista (seguridad), un indicador de paso («Paso 2 de 4») con barra animada, el texto de lo que está haciendo Galeno o de cuándo es el turno del usuario, y «Cancelar». Diséñala.
- **Nada de red propia:** no pueden aparecer elementos que supongan servidores de Galeno (cuentas, sincronización, telemetría).

---

## 7. Inventario del asistente (qué hay que diseñar)

Para cada pantalla: **objetivo**, **qué decide el usuario**, **estados** y **oportunidad de guía**. El copy actual de cada una está en el apéndice A.

### 1 · Idioma y bienvenida
Elige español o inglés (preseleccionado según el Mac). Explica qué es Galeno, qué va a configurar y cuánto tarda (~10–15 min).
- *Oportunidad:* es el único momento de «portada». Ideal para el retrato, la frase *«Galeno te crea tu agente»* y una promesa honesta de calma y control: qué va a pasar, qué **no** va a pasar (no envía nada sin permiso).

### 2 · Detección de Claude Code
Busca `claude`. Estados: **buscando**, **encontrado** (versión, ruta, sesión iniciada o no), **no encontrado** (comando oficial de instalación con «Copiar», enlace a la guía, «Comprobar de nuevo»), **sin sesión** (aviso **no bloqueante**).
- *Oportunidad:* explicar *por qué* (Claude Code es el motor del agente) y qué hacer exactamente si falta, con un paso a paso visual.

### 3 · Tu agente
Nombre del agente (obligatorio, ≤ 60), rol (fijo: «Product Manager» en v0.0.1), una línea del proyecto (opcional, ≤ 140).
- *Oportunidad:* es la pantalla más **personal**. Que dé ganas de ponerle nombre; ejemplos de nombres y de descripciones; mostrar que el nombre acompañará al usuario («tu agente *Hera*…»).

### 4 · Elige tus herramientas
Grilla de 10 herramientas (WhatsApp, Slack, Notion, Google Drive/Docs/Sheets, Gmail, Jira, Fireflies, Granola, Fathom, Google Meet). Marca **solo las que usa**. Meet exige Drive (queda marcado). Pie: «Vas a conectar N herramientas · ~X min».
- *Oportunidad:* que cada tarjeta diga **qué hará el agente con ella** en una línea concreta; agrupar por tipo (mensajería, documentos, trabajo, reuniones); ilustración/icono propio por herramienta dentro de la regla de logos monocromos.

### 5 · Conecta una por una (sub-wizard — la pantalla más compleja y más larga)
Una conexión por pantalla. Barra de progreso propia con los logos («2 de 5 conectadas»). **Estados** (cada uno necesita diseño):
- **Listo para conectar:** logo grande, qué hará el agente, «Conectar», «Conectar después».
- **Trabajando:** *Revisando…*, *Registrando…*, *Esperando el navegador…* (con ayuda: «Autoriza en el navegador»).
- **Éxito:** check que se dibuja, «¡X conectado!» y un **dato real** («Encontré 12 canales»).
- **Falla:** mensaje claro, **Reintentar**, **Saltar por ahora**; con detalle técnico discreto.
- **Ya había un servidor con ese nombre:** pregunta con dos caminos («Usar otro nombre» recomendado / «Borrar el existente…» con confirmación que dice qué se borra).
- **Slack:** «Iniciar sesión en Slack» abre la ventana web (ver §6) y luego la de «Permitir»; si la app se borró en Slack, ofrece «Crear la app de nuevo».
- **WhatsApp:** **advertencia previa obligatoria** con «Entiendo, continuar»; luego el **QR** (rota cada ~60 s; marco, instrucciones de cómo escanearlo desde el teléfono), **sincronizando** (chats que aparecen, barra indeterminada, «Seguir mientras sincroniza»).
- **Pantallas de dopamina** (a pantalla completa, sin botones de OAuth): tras las 2 primeras, a la mitad y antes de la última.
- **Celebración final:** qué ve el agente (totales) + lo que quedó para después; en Slack, una ficha **«ponle cara a tu app»** (icono 512–2000 px y descripción, con enlace a su configuración).
- *Oportunidad:* que **cada conexión explique qué va a pasar en la ventana siguiente antes de que ocurra**, con una mini-ilustración de «lo que verás» (p. ej. un esquema del paso «Permitir»).

### 6 · Elige qué leer
Por herramienta conectada, una lista (canales, chats/grupos, páginas/bases, carpetas, etiquetas, proyectos) obtenida del servicio; con buscador si hay muchas. **Lo elegido no es una barrera, es el foco** del agente (queda en su `AGENTS.md`); la pantalla debe decirlo con claridad. Estados por herramienta: **buscando** (puede tardar), **lista**, **falló** (reintentar / «Que lea todo»), **vacía**, **parcial** («solo los primeros resultados»); las de transcripción **no tienen nada que elegir**.
- *Oportunidad:* el punto más fácil de malentender. Una ilustración simple de «foco vs. alcance» (el agente ve todo, pero mira aquí) puede hacer mucho.

### 7 · Elige tus skills
Dos niveles: **las nuestras** (17, en 4 grupos, todas marcadas; cada una con nombre, comando `/slug`, una línea, y aviso si necesita una herramienta que no conectó) y **curadas de la comunidad** (8, con **crédito al autor, licencia y enlace a su GitHub**; hoy «Próximamente»).
- *Oportunidad:* que las skills se entiendan como **oficios** del agente, no como una lista técnica; agrupación visual; el crédito a los autores como gesto de cortesía (como el colofón de un libro).

### 8 · Reglas
Arriba, **fijo y no editable**: todo envío externo (Slack, correo) siempre pide aprobación; WhatsApp es de solo lectura. Debajo, lo elegible: escrituras internas en Notion/Jira/Google Docs/Sheets (**Preguntarme / Sin preguntar**). Nota: solo escribe sin preguntar en su carpeta `memoria/`.
- *Oportunidad:* es la pantalla de **confianza**. Diseñarla para que se sienta como un «pacto» claro: lo que **nunca** hará, lo que **siempre** pregunta, lo que tú decides.

### 9 · Generando
Cuatro pasos visibles (reglas, herramientas, skills, guardado); el motor trabaja de verdad y es lo que decide. **Estados:** en curso, éxito (pasa solo a «Listo»), **falla** (qué falló, «Reintentar», «Volver a las reglas»; nada queda a medias).
- *Oportunidad:* la espera más corta (~3 s) pero la más simbólica: «se escribe tu agente». Un gesto de **escritura** (una línea que se traza, un folio que se llena) encaja con el mundo del libro.

### 10 · Listo
Dónde quedó la carpeta (ruta, «Mostrar en Finder», «Copiar ruta»), **primer comando sugerido** según lo que conectó («Resume lo que pasó esta semana en Slack»), y **dónde abrir** el agente: **App de Claude** o **Terminal** (con nota de que la app pedirá confirmar la carpeta). Avisos si hubo algo que revisar.
- *Oportunidad:* el cierre emocional y el puente al uso. Que el primer comando sea irresistible de probar, y que quede claro qué sigue.

### Fuera del asistente (considéralo en el sistema, sin diseñarlo completo)
- **El home** (lista de agentes, crear otro, gestionar, salud) llegará después; el sistema de diseño debe poder crecer hacia ahí.
- **Wizard corto** del segundo agente (nombre, proyecto, qué leer, skills).

---

## 8. Guía, tono y copy

**Lo que quiero del asistente: que guíe con precisión.** En cada pantalla, el usuario debe saber, sin pensar:
1. **Dónde está** y cuánto falta.
2. **Qué va a pasar ahora** (antes de pulsar): «Se abrirá una ventana de Slack. Inicia sesión; Galeno hace el resto.»
3. **Qué necesito de él** (una acción concreta) y **qué hace Galeno por él**.
4. **Por qué** se lo piden, en una frase.
5. **Qué pasa si se equivoca** (siempre se puede reintentar o saltar; nada se envía sin permiso).

**Principios de redacción**
- **Español latinoamericano neutro, trato de tú.** Frases cortas. Verbos concretos («Conecta», «Elige», «Abre»), no sustantivos abstractos.
- **Específico, no genérico:** «Encontré 12 canales» > «Conexión exitosa». Usa el nombre del agente y de la herramienta cuando sepas cuál es.
- **Honesto y calmado:** sin signos de exclamación en exceso, sin hype, sin «¡Increíble!». Promete poco y cumple. Nunca «seguro», «oficial», «garantizado» (WhatsApp).
- **Los errores dicen qué hacer**, no solo qué pasó: causa en palabras humanas + siguiente paso + detalle técnico discreto.
- **Los textos de dopamina y celebración son nativos en cada idioma**, no traducidos literalmente. Propón versiones para las tres pantallas de dopamina y para las celebraciones (hoy son marcadores `TODO(dopamina)`).
- **Botones con verbo y tamaño de acción:** el primario siempre dice lo que hace («Conectar Slack», no «Siguiente»); el secundario discreto no compite.
- **Micro-copy de progreso:** cuánto tarda («~1 min»), qué se está haciendo («Mirando tus canales…»).
- **Vocabulario fijo:** *agente* (no «bot»), *herramientas* (no «integraciones»), *conectar* (no «vincular», salvo WhatsApp, que es «vincular un dispositivo»), *skills* (se queda en inglés, con una línea que lo explica), *foco* (para «qué leer»).

**Para cada propuesta entrega el copy de las 10 pantallas y de los estados clave**, en ES y EN, con el mismo criterio. Dime dónde cambias el copy actual y por qué.

---

## 9. Entregables

### A · Sistema de diseño v2
- **Dirección y principios** (una página): qué es el estilo, qué no es.
- **Color:** tokens claro/oscuro; si añades tonos, justifícalos; reglas de contraste verificadas; uso del acento.
- **Tipografía:** pares concretos (con licencia y peso en MB), escala completa (títulos caligráficos/capitales, texto legible, etiquetas, datos), reglas de uso, fallback.
- **Espacio, forma, bordes y elevación.**
- **Controles con todos sus estados** (normal, hover, pulsado, foco, deshabilitado, cargando, error): botón primario/secundario/terciario **más grandes** (propón alturas y radios), campo de texto, casilla, selector segmentado, lista seleccionable, tarjeta de herramienta, aviso/nota, barra de progreso y de pasos, chip/etiqueta.
- **Iconografía:** estilo, grosor de trazo, cuadrícula, **set de iconos** para las ~25 acciones y estados del asistente.
- **Sistema de ilustración:** técnica (grabado en línea, xilografía, lámina botánica…), reglas de composición, **cuándo sí y cuándo no**, escala, cómo se comportan en modo oscuro; y la **lista de ilustraciones** para el asistente (una por pantalla/estado importante, con su motivo y tamaño).
- **Movimiento:** 6–8 gestos con duración y curva (escribir, pasar página, encender, tachar…), y su versión «reducir movimiento».
- **Modo oscuro** completo.
- **Qué mantienes, qué reabres y a qué costo** (tabla del §5, completada).

### B · Tres propuestas del asistente completo
Las tres deben ser **opciones reales**, no variantes de color. Te sugiero estos **ejes de variación** (elige los tuyos si ves mejores):

| Eje | Rango a explorar |
|---|---|
| Ornamento | sobrio de impresor ↔ rico de manuscrito |
| Tipografía | capitales + serif de lectura ↔ caligrafía humanista ↔ itálica de cancillería |
| Ilustración | grabado de línea ↔ lámina botánica/anatómica ↔ xilografía/tinta plana |
| Composición | una columna tipo página ↔ panel de ilustración a un lado ↔ portada de libro por paso |
| Botones | grandes con borde fino ↔ llenos de tinta ↔ con «sello» como detalle |

Para **cada propuesta** entrega:
1. **Nombre, idea en una frase y moodboard** (descrito o referenciado: qué imágenes/épocas/materiales).
2. **Sistema aplicado:** paleta, fuentes, botones, iconos e ilustraciones.
3. **Las 10 pantallas** en 720×560 pt, **claro y oscuro** (al menos la propuesta que recomiendes en ambos modos; las otras, en claro y una muestra en oscuro), con el copy ES (y EN en una muestra).
4. **Los estados clave:** pantalla 2 (encontrado / no encontrado), pantalla 5 (listo, trabajando, éxito, falla, advertencia de WhatsApp + QR, nombre repetido, Slack), pantalla 6 (buscando / lista / falló), pantalla 9 (en curso / falla), pantalla 10.
5. **Las dos ventanas web de Slack** con su barra superior.
6. **Prototipo navegable** del recorrido.
7. **Rationale:** por qué esta dirección sirve a este usuario en este momento; **riesgos** (cliché, legibilidad, accesibilidad, mantenimiento).
8. **Costo de implementación en SwiftUI:** qué es nativo, qué control propio hay que escribir, fuentes a embeber (licencia + MB), número y tipo de assets, y una estimación relativa (bajo / medio / alto).

### C · Comparación y recomendación
Tabla de las tres (legibilidad, carácter, confianza, costo de construir, riesgo de cliché, escalabilidad al home) y **tu recomendación razonada**, con qué tomarías de las otras dos.

### D · Notas de implementación
Tokens listos para SwiftUI (`Color`, `Font`, escala, espacios, radios), inventario de componentes a construir, assets a producir (con formato y tamaños), fuentes (con licencia), y un **orden de migración** que permita adoptar el rediseño por partes sin romper la app.

---

## 10. Qué no hacer

- **Disfraz:** nada que parezca una fiesta temática. Sin togas, laureles, tipografía gótica, pergaminos quemados, lacres con chorreo, serpientes decorativas sin sentido.
- **No rehacer el retrato** ni colorearlo (reglas del logo en `docs/04` §4).
- **No ilustraciones genéricas de stock ni «estilo IA».** Cada ilustración tiene un motivo y un lugar.
- **No emoji** en la interfaz.
- **No más color** del necesario: la identidad es tinta sobre papel con un acento.
- **No sacrificar legibilidad por carácter:** el texto de cuerpo tiene que leerse sin esfuerzo a 14–16 pt en pantalla; lo caligráfico es para títulos y momentos.
- **No inventar funciones** (cuentas, nube, sincronización) ni cambiar el flujo de 10 pasos: se rediseña **cómo se ve, se lee y se guía**, no qué hace.
- **No reescribir la advertencia de WhatsApp** (solo su presentación).

---

## 11. Decisiones que quedan para mí (pregúntame o marca tu suposición)

1. ¿**Embeber fuentes** en la app? (Hoy no.) Si tu propuesta lo necesita, di cuáles y su licencia.
2. ¿**Controles propios** para los botones grandes, o alcanza con estilos nativos?
3. ¿Un **retrato pequeño** acompañando en más pantallas?
4. ¿Se permite una **textura casi imperceptible**?
5. Si recomiendas ilustraciones por pantalla: ¿las produce un ilustrador o se generan? (Evalúa el costo de cada camino y su consistencia.)

---

# Apéndice A — Copy actual (ES / EN)

> Las cadenas con `%@`, `%lld` o `%1$@` llevan un dato: nombre del agente, de la herramienta, un número. Los textos `TODO(dopamina)` son marcadores: **propón los definitivos**. Las claves se agrupan por pantalla.

### Navegación general

| Clave | Español | English |
|---|---|---|
| `step.agent.summary` | Le pones nombre a tu agente y una línea sobre el proyecto en el que va a trabajar. | You name your agent and add one line about the project it will work on. |
| `step.agent.title` | Tu agente | Your agent |
| `step.connect.summary` | Conectamos cada herramienta en su propia pantalla, con un dato real de lo que encontramos. | We connect each tool on its own screen, with a real figure of what we found. |
| `step.connect.title` | Conecta una por una | Connect them one by one |
| `step.detection.summary` | Comprobamos que Claude Code esté instalado; si no, te guiamos para instalarlo. | We check that Claude Code is installed; if it is not, we guide you through installing it. |
| `step.detection.title` | Detectar Claude Code | Detect Claude Code |
| `step.done.summary` | Cómo usar tu agente, primeros comandos y dónde quedó su carpeta. | How to use your agent, first commands and where its folder is. |
| `step.done.title` | Listo | Done |
| `step.generating.summary` | Escribimos la configuración de tu agente, paso a paso. | We write your agent's configuration, step by step. |
| `step.generating.title` | Generando | Building |
| `step.rules.summary` | Defines qué puede hacer tu agente sin preguntar y qué siempre pide aprobación. | You decide what your agent may do without asking and what always needs approval. |
| `step.rules.title` | Reglas | Rules |
| `step.skills.summary` | Las nuestras, marcadas por defecto, y las curadas de la comunidad, con crédito a su autor. | Ours, ticked by default, and the community's curated ones, credited to their authors. |
| `step.skills.title` | Elige tus skills | Choose your skills |
| `step.sources.summary` | Eliges los grupos, canales, carpetas y proyectos en los que tu agente se enfoca. | You choose the groups, channels, folders and projects your agent focuses on. |
| `step.sources.title` | Elige qué leer | Choose what to read |
| `step.tools.summary` | Marca solo las herramientas que usas. | Tick only the tools you use. |
| `step.tools.title` | Elige tus herramientas | Choose your tools |
| `step.welcome.summary` | Eliges el idioma y te cuento qué vamos a configurar y cuánto tarda. | You choose the language, and I tell you what we will set up and how long it takes. |
| `step.welcome.title` | Idioma y bienvenida | Language and welcome |
| `wizard.back` | Atrás | Back |
| `wizard.finish` | Terminar | Finish |
| `wizard.next` | Siguiente | Next |
| `wizard.placeholder` | Esta pantalla está en construcción. | This screen is under construction. |
| `wizard.progress.label` | Progreso del asistente | Wizard progress |
| `wizard.progress.step %lld %lld` | Paso %1$lld de %2$lld | Step %1$lld of %2$lld |

### 1 · Idioma y bienvenida

| Clave | Español | English |
|---|---|---|
| `welcome.language.label` | Idioma | Language |
| `welcome.setup.body` | Tus herramientas (Slack, Notion, Gmail…), lo que tu agente lee y lo que puede hacer sin preguntarte. | Your tools (Slack, Notion, Gmail…), what your agent reads, and what it can do without asking you. |
| `welcome.setup.title` | Qué vamos a configurar | What we will set up |
| `welcome.time.body` | Entre 10 y 15 minutos, según cuántas herramientas conectes. | Between 10 and 15 minutes, depending on how many tools you connect. |
| `welcome.time.title` | Cuánto tarda | How long it takes |
| `welcome.what.body` | Crea y configura tu agente en Claude Code, pensado para Product Managers. | It creates and configures your agent in Claude Code, built for Product Managers. |
| `welcome.what.title` | Qué es Galeno | What Galeno is |

### 2 · Detección de Claude Code

| Clave | Español | English |
|---|---|---|
| `detection.checking` | Buscando Claude Code… | Looking for Claude Code… |
| `detection.copied` | Copiado | Copied |
| `detection.copy` | Copiar | Copy |
| `detection.found.title` | Claude Code está instalado | Claude Code is installed |
| `detection.found.version %@` | Versión %@ | Version %@ |
| `detection.guide` | Guía de instalación | Installation guide |
| `detection.loggedOut.body` | Abre una terminal, escribe claude y sigue los pasos en el navegador. Puedes continuar ahora; la necesitarás para usar tu agente. | Open a terminal, type claude and follow the steps in your browser. You can continue now; you will need it to use your agent. |
| `detection.loggedOut.title` | No veo una sesión iniciada | I don't see a signed-in session |
| `detection.notFound.afterInstall` | Cuando termine, escribe claude en la terminal una vez para iniciar sesión y pulsa Comprobar de nuevo. | When it finishes, type claude in the terminal once to sign in, then press Check again. |
| `detection.notFound.body` | Cópialo y pégalo en tu Terminal. Galeno no instala nada por su cuenta. | Copy it and paste it into your Terminal. Galeno doesn't install anything on its own. |
| `detection.notFound.title` | No encontré Claude Code en este Mac | I couldn't find Claude Code on this Mac |
| `detection.recheck` | Comprobar de nuevo | Check again |

### 3 · Tu agente

| Clave | Español | English |
|---|---|---|
| `agent.name.error.empty` | Ponle un nombre para continuar. | Give it a name to continue. |
| `agent.name.error.tooLong` | El nombre es demasiado largo. | That name is too long. |
| `agent.name.label` | ¿Cómo quieres llamarlo? | What do you want to call it? |
| `agent.name.placeholder` | Aurora | Aurora |
| `agent.project.hint` | Una línea basta: tu agente completa el resto en su primera sesión. | One line is enough: your agent fills in the rest in its first session. |
| `agent.project.label` | ¿En qué proyecto va a trabajar? | What project will it work on? |
| `agent.project.placeholder` | App de citas para la clínica X, lanzamos en noviembre | Appointments app for clinic X, launching in November |
| `agent.role.label` | Rol | Role |
| `agent.role.productManager` | Product Manager | Product Manager |

### 4 · Herramientas

| Clave | Español | English |
|---|---|---|
| `tools.meetNote` | Google Meet se lee con Google Drive, así que lo marcamos por ti. | Google Meet is read through Google Drive, so we ticked it for you. |
| `tools.summary.none` | Elige al menos una herramienta para continuar. | Pick at least one tool to continue. |
| `tools.summary.one %lld` | Vas a conectar 1 herramienta · ~%lld min | You'll connect 1 tool · ~%lld min |
| `tools.summary.other %lld %lld` | Vas a conectar %1$lld herramientas · ~%2$lld min | You'll connect %1$lld tools · ~%2$lld min |

### 5 · Conexión (sub-wizard, Slack y WhatsApp incluidos)

| Clave | Español | English |
|---|---|---|
| `connect.backToTools` | Volver a elegir herramientas | Back to choosing tools |
| `connect.celebration.nothing` | Todavía no conectaste nada. Puedes hacerlo después desde la app. | You haven't connected anything yet. You can do it later from the app. |
| `connect.celebration.skipped %@` | Para después: %@ | For later: %@ |
| `connect.celebration.title` | Esto es lo que tu agente ya ve | Here is what your agent can already see |
| `connect.connect` | Conectar | Connect |
| `connect.continue` | Continuar | Continue |
| `connect.counting` | Mirando qué encontré… | Seeing what I found… |
| `connect.failure.bridgeFailed` | WhatsApp no pudo vincularse. | WhatsApp couldn't be linked. |
| `connect.failure.bridgeMissing` | No encuentro el componente de WhatsApp que viene con Galeno. | I can't find the WhatsApp component that ships with Galeno. |
| `connect.failure.couldNotRegister` | No pude registrar la conexión en Claude Code. | I couldn't register the connection in Claude Code. |
| `connect.failure.detail %@` | Detalle: %@ | Detail: %@ |
| `connect.failure.loginFailed` | La autorización no se completó. | The authorization didn't complete. |
| `connect.failure.nameInUse` | Tampoco puedo usar el nombre alternativo: ya hay otro servidor con ese nombre en Claude Code. Renómbralo o bórralo desde Claude Code y reintenta. | I can't use the alternate name either: another server with that name already exists in Claude Code. Rename or delete it from Claude Code and try again. |
| `connect.failure.notAuthorizedInTime` | La autorización no llegó a tiempo. | The authorization didn't arrive in time. |
| `connect.failure.qrExpired` | El código QR venció antes de que lo escanearas. | The QR code expired before you scanned it. |
| `connect.failure.slackManifest` | Slack rechazó la configuración de la app. | Slack rejected the app's configuration. |
| `connect.failure.slackNotAllowed` | Slack no te dejó crear la app. Casi seguro hace falta la aprobación de un administrador de tu workspace. | Slack didn't let you create the app. You most likely need a workspace admin's approval. |
| `connect.failure.slackUnreachable` | No pude hablar con Slack. Revisa tu conexión a internet. | I couldn't reach Slack. Check your internet connection. |
| `connect.failure.stillNotConnected` | Se autorizó, pero el servicio todavía no responde. | Access was granted, but the service still doesn't respond. |
| `connect.failure.tokenRejected` | Slack no aceptó ese token. Puede haber vencido (duran 12 horas) o no ser el correcto. | Slack didn't accept that token. It may have expired (they last 12 hours) or be the wrong one. |
| `connect.found.channels %lld` | (one) Encontré %lld canal / (other) Encontré %lld canales | (one) I found %lld channel / (other) I found %lld channels |
| `connect.found.groups %lld` | (one) Encontré %lld grupo / (other) Encontré %lld grupos | (one) I found %lld group / (other) I found %lld groups |
| `connect.found.labels %lld` | (one) Encontré %lld etiqueta / (other) Encontré %lld etiquetas | (one) I found %lld label / (other) I found %lld labels |
| `connect.found.meetings %lld` | (one) Encontré %lld reunión / (other) Encontré %lld reuniones | (one) I found %lld meeting / (other) I found %lld meetings |
| `connect.found.projects %lld` | (one) Encontré %lld proyecto / (other) Encontré %lld proyectos | (one) I found %lld project / (other) I found %lld projects |
| `connect.foundAtLeast.channels %lld` | (one) Encontré al menos %lld canal / (other) Encontré al menos %lld canales | (one) I found at least %lld channel / (other) I found at least %lld channels |
| `connect.foundAtLeast.groups %lld` | (one) Encontré al menos %lld grupo / (other) Encontré al menos %lld grupos | (one) I found at least %lld group / (other) I found at least %lld groups |
| `connect.foundAtLeast.labels %lld` | (one) Encontré al menos %lld etiqueta / (other) Encontré al menos %lld etiquetas | (one) I found at least %lld label / (other) I found at least %lld labels |
| `connect.foundAtLeast.meetings %lld` | (one) Encontré al menos %lld reunión / (other) Encontré al menos %lld reuniones | (one) I found at least %lld meeting / (other) I found at least %lld meetings |
| `connect.foundAtLeast.projects %lld` | (one) Encontré al menos %lld proyecto / (other) Encontré al menos %lld proyectos | (one) I found at least %lld project / (other) I found at least %lld projects |
| `connect.later` | Conectar después | Connect later |
| `connect.ownApp.body` | Slack y Google piden que la conexión pase por una app creada en tu propia cuenta, para que nada pase por servidores nuestros. Galeno la creará por ti en una próxima actualización; por ahora queda para después. | Slack and Google require the connection to go through an app created in your own account, so nothing goes through our servers. Galeno will create it for you in an upcoming update; for now it stays for later. |
| `connect.ownApp.title %@` | %@ necesita una app propia | %@ needs its own app |
| `connect.progress %lld %lld` | %1$lld de %2$lld conectadas | %1$lld of %2$lld connected |
| `connect.retry` | Reintentar | Try again |
| `connect.skip` | Saltar por ahora | Skip for now |
| `connect.slack.adminMessage %@` | Hola, uso Galeno para conectar mi Slack con mi asistente de IA. Necesito que apruebes la app «%@» en nuestro workspace (Administrar → Aplicaciones) y que permitas el cliente MCP de Slack. El asistente solo envía mensajes con mi aprobación explícita. | Hi, I use Galeno to connect my Slack to my AI assistant. I need you to approve the app “%@” in our workspace (Manage → Apps) and to allow Slack's MCP client. The assistant only sends messages with my explicit approval. |
| `connect.slack.copyAdminMessage` | Copiar mensaje para mi administrador | Copy a message for my admin |
| `connect.slack.signin.body` | Slack pide que la conexión pase por una app creada en tu propia cuenta. Inicia sesión en Slack y Galeno la crea por ti. | Slack requires the connection to go through an app created in your own account. Sign in to Slack and Galeno creates it for you. |
| `connect.slack.signin.button` | Iniciar sesión en Slack | Sign in to Slack |
| `connect.slack.signin.privacy` | Se abre una ventana de Galeno con la página de Slack. Galeno no lee ni guarda tu contraseña, y la sesión se borra al cerrar la ventana. Si entras con Google, elige «Sign in with email»: Google no permite iniciar sesión en ventanas de otras apps. | A Galeno window opens with Slack's page. Galeno doesn't read or store your password, and the session is erased when the window closes. If you sign in with Google, choose “Sign in with email”: Google doesn't allow signing in inside other apps' windows. |
| `connect.slack.window.cancel` | Cancelar | Cancel |
| `connect.slack.window.captured` | Listo. Creando tu app de Slack… | Done. Creating your Slack app… |
| `connect.slack.window.chooseWorkspace` | Elige tu workspace en la página y pulsa «Generate». | Pick your workspace on the page and press “Generate”. |
| `connect.slack.window.google` | Google no permite iniciar sesión en ventanas de otras apps, así que no se abre aquí. Elige «Sign in with email»: Slack te envía un código por correo. | Google doesn't allow signing in inside other apps' windows, so it doesn't open here. Choose “Sign in with email”: Slack emails you a code. |
| `connect.slack.window.loadFailed %@` | No se pudo abrir Slack: %@ | Couldn't open Slack: %@ |
| `connect.slack.window.loading` | Abriendo Slack… | Opening Slack… |
| `connect.slack.window.needsClick` | Si no avanza solo, pulsa «Generate Token» en la página y elige tu workspace. Galeno recoge el resultado. | If it doesn't move on by itself, press “Generate Token” on the page and pick your workspace. Galeno picks up the result. |
| `connect.slack.window.signIn` | Inicia sesión en Slack. Galeno sigue solo en cuanto entres. | Sign in to Slack. Galeno continues on its own once you're in. |
| `connect.slack.window.tokensPage` | Ir a la página de tokens | Go to the tokens page |
| `connect.slack.window.working` | Preparando la página de tokens… | Preparing the tokens page… |
| `connect.step.checking` | Revisando… | Checking… |
| `connect.step.checkingLink` | Comprobando si ya está vinculado… | Checking whether it is already linked… |
| `connect.step.creatingSlackApp` | Creando tu app de Slack… | Creating your Slack app… |
| `connect.step.installingSync` | Dejando la sincronización lista… | Getting syncing ready… |
| `connect.step.preparingBridge` | Preparando el componente de WhatsApp… | Preparing the WhatsApp component… |
| `connect.step.registering` | Registrando la conexión en Claude Code… | Registering the connection in Claude Code… |
| `connect.step.validatingToken` | Comprobando el token… | Checking the token… |
| `connect.step.waitingForBrowser` | Esperando tu autorización en el navegador… | Waiting for your authorization in the browser… |
| `connect.step.waitingForBrowser.hint` | Se abrió una pestaña del navegador. Autoriza el acceso y vuelve aquí. | A browser tab opened. Grant access and come back here. |
| `connect.success.already %@` | ¡%@ ya estaba conectado! | %@ was already connected! |
| `connect.success.title %@` | ¡%@ conectado! | %@ connected! |
| `connect.value.fathom` | Leerá tus reuniones y sus resúmenes para recordar lo que se acordó. | It will read your meetings and summaries to remember what was agreed. |
| `connect.value.fireflies` | Leerá tus reuniones y sus transcripciones para recordar lo que se acordó. | It will read your meetings and transcripts to remember what was agreed. |
| `connect.value.gmail` | Leerá tu correo para encontrar lo que importa. | It will read your email to find what matters. |
| `connect.value.google-workspace` | Leerá tus documentos y hojas de cálculo de Drive. | It will read your Drive documents and spreadsheets. |
| `connect.value.granola` | Leerá tus reuniones y sus notas para recordar lo que se acordó. | It will read your meetings and notes to remember what was agreed. |
| `connect.value.jira` | Leerá tus proyectos y tickets para seguir el avance. | It will read your projects and tickets to follow progress. |
| `connect.value.notion` | Leerá tus páginas y bases de datos para tener contexto. | It will read your pages and databases to have context. |
| `connect.value.slack` | Leerá tus canales de Slack para hacerte seguimiento. | It will read your Slack channels to keep you on top of things. |
| `connect.value.whatsapp` | Leerá tus grupos y chats para hacerte seguimiento. | It will read your groups and chats to keep you on top of things. |
| `connect.whatsapp.continue` | Entiendo, continuar | I understand, continue |
| `connect.whatsapp.continueInBackground` | Seguir mientras sincroniza | Continue while it syncs |
| `connect.whatsapp.qr.generating` | Generando el código… | Generating the code… |
| `connect.whatsapp.qr.rotates` | El código cambia cada minuto. | The code changes every minute. |
| `connect.whatsapp.qr.steps` | En tu teléfono: Ajustes → Dispositivos vinculados → Vincular un dispositivo. | On your phone: Settings → Linked devices → Link a device. |
| `connect.whatsapp.qr.title` | Escanea este código con WhatsApp | Scan this code with WhatsApp |
| `connect.whatsapp.syncing %lld` | Chats encontrados: %lld | Chats found: %lld |
| `connect.whatsapp.syncing.hint` | La primera vez puede tardar unos minutos. Puedes seguir sin esperar: la sincronización continúa en segundo plano. | The first time can take a few minutes. You can carry on without waiting: syncing continues in the background. |
| `connect.whatsapp.warning.body` | Esto se conecta como un dispositivo vinculado usando el protocolo de WhatsApp Web, de forma no oficial. Es de solo lectura. Existe un riesgo bajo pero real de que WhatsApp lo detecte y restrinja tu cuenta. Todo corre en tu computador; nada sale a servidores nuestros. Tú decides si continuar. | This connects as a linked device using the WhatsApp Web protocol, in an unofficial way. It is read-only. There is a low but real risk that WhatsApp detects it and restricts your account. Everything runs on your computer; nothing goes to our servers. You decide whether to continue. |
| `connect.whatsapp.warning.title` | Antes de vincular | Before you link |
| `connect.nameConflict.title %@` | Ya tienes en Claude Code otro servidor llamado «%@». | You already have a different server called “%@” in Claude Code. |
| `connect.nameConflict.body` | No lo toco. Lo normal es que Galeno use su propio nombre (con «galeno-» delante) y el tuyo siga como está. O, si prefieres, puedo borrar el tuyo. | I won't touch it. The usual choice is for Galeno to use its own name (starting with “galeno-”) and leave yours as it is. Or, if you prefer, I can delete yours. |
| `connect.nameConflict.useOther` | Usar otro nombre | Use another name |
| `connect.nameConflict.remove` | Borrar el existente… | Delete the existing one… |
| `connect.removal.title %@` | ¿Borrar el servidor «%@» de Claude Code? | Delete the “%@” server from Claude Code? |
| `connect.removal.body` | Se borra su configuración en Claude Code, y deja de estar disponible en todos tus proyectos. Si lo necesitas más adelante, tendrás que volver a añadirlo. No se borra nada de la herramienta en sí. | Its configuration is removed from Claude Code, and it stops being available in all your projects. If you need it later, you'll have to add it again. Nothing in the tool itself is deleted. |
| `connect.removal.cancel` | Mejor no | Never mind |
| `connect.removal.confirm %@` | Sí, borrar «%@» | Yes, delete “%@” |
| `connect.step.removingServer` | Borrando el servidor… | Deleting the server… |
| `connect.failure.couldNotRemove` | No pude borrar el servidor. Puedes borrarlo tú desde Claude Code, o volver y elegir otro nombre. | I couldn't delete the server. You can delete it yourself from Claude Code, or go back and pick another name. |
| `connect.celebration.connected` | Conexiones listas | Connections ready |
| `connect.failure.slackMCPNotEnabled` | Slack aceptó la autorización, pero la app no tiene activado el servidor MCP. Actívalo en la página de la app («Agents & AI Apps» → Slack Model Context Protocol (MCP) Server) y reintenta. | Slack accepted the authorization, but the app doesn't have the MCP server turned on. Turn it on in the app's page (“Agents & AI Apps” → Slack Model Context Protocol (MCP) Server) and try again. |
| `connect.slack.openAppPage` | Abrir la página de la app | Open the app's page |
| `connect.slack.window.openingDialog` | Abriendo el diálogo del token… | Opening the token dialog… |
| `connect.slack.window.pickingWorkspace` | Eligiendo tu workspace por ti… | Choosing your workspace for you… |
| `connect.slack.window.generating` | Generando el token… | Generating the token… |
| `connect.slack.window.step %lld %lld` | Paso %lld de %lld | Step %lld of %lld |
| `connect.slack.authorize.loading` | Abriendo la autorización de Slack… | Opening Slack's authorization… |
| `connect.slack.authorize.userTurn` | Si te lo pide, inicia sesión; luego pulsa «Permitir» para que Galeno pueda leer tu Slack. Esta ventana se cierra sola al terminar. | Sign in if asked, then press “Allow” so Galeno can read your Slack. This window closes by itself when done. |
| `connect.slack.authorize.done` | Listo, autorizado. | Done, authorized. |
| `connect.slackDetails.title` | Un último detalle: ponle cara a tu app de Slack | One last thing: give your Slack app a face |
| `connect.slackDetails.icon` | Sube un icono: una imagen de entre 512 × 512 y 2000 × 2000 píxeles, mejor cuadrada. Slack no la acepta si es más pequeña. | Upload an icon: an image between 512 × 512 and 2000 × 2000 pixels, ideally square. Slack rejects it if it's smaller. |
| `connect.slackDetails.description` | Revisa la descripción: la corta admite hasta 140 caracteres y la larga, entre 174 y 4000. Es lo que ve tu administrador al aprobar la app. | Check the description: the short one takes up to 140 characters, the long one 174 to 4000. It's what your admin sees when approving the app. |
| `connect.slackDetails.where` | Está en «Basic Information» → «Display Information» de la app. | It's under “Basic Information” → “Display Information” in the app. |
| `connect.slackDetails.open` | Abrir la configuración de la app | Open the app's settings |
| `connect.slack.authorize.appNotFound` | Slack no reconoce la app de Galeno: parece que se borró. | Slack doesn't recognize Galeno's app: it looks like it was deleted. |
| `connect.failure.slackAppMissing` | Slack ya no reconoce la app que Galeno creó para tu workspace (¿la borraste?). Galeno puede crearla de nuevo: quitará de Claude Code la conexión «slack» que apuntaba a la app borrada y te pedirá iniciar sesión otra vez. | Slack no longer recognizes the app Galeno created for your workspace (was it deleted?). Galeno can create it again: it will remove the “slack” connection in Claude Code that pointed to the deleted app and ask you to sign in again. |
| `connect.slack.recreate` | Crear la app de nuevo | Create the app again |

### 6 · Qué leer

| Clave | Español | English |
|---|---|---|
| `sources.intro` | Tu agente puede leer todo lo que le hayas conectado. Lo que elijas aquí es en qué se enfoca: queda escrito en su AGENTS.md, no es una barrera. | Your agent can read everything you've connected. What you pick here is what it focuses on: it's written into its AGENTS.md, it's not a barrier. |
| `sources.none` | No conectaste ninguna herramienta, así que no hay nada que elegir. Puedes seguir. | You didn't connect any tool, so there's nothing to choose. You can continue. |
| `sources.everything.transcripts` | Lee todas tus reuniones: aquí no hay nada que elegir. | It reads all your meetings: there's nothing to choose here. |
| `sources.loading.hint` | Puede tardar unos segundos. | This can take a few seconds. |
| `sources.retry` | Reintentar | Try again |
| `sources.readAll` | Que lea todo | Let it read everything |
| `sources.readAll.note` | Tu agente leerá todo lo que vea, sin un foco concreto. | Your agent will read everything it sees, with no particular focus. |
| `sources.selected.one` | 1 elegido | 1 chosen |
| `sources.selected.other %lld` | %lld elegidos | %lld chosen |
| `sources.noneSelected` | Sin elegir: tu agente leerá todo sin un foco concreto. | None chosen: your agent will read everything with no particular focus. |
| `sources.partial` | Se muestran solo los primeros resultados. | Only the first results are shown. |
| `sources.noMatch` | Nada coincide con tu búsqueda. | Nothing matches your search. |
| `sources.kind.group` | Grupo | Group |
| `sources.kind.chat` | Chat | Chat |
| `sources.kind.database` | Base de datos | Database |
| `sources.kind.page` | Página | Page |
| `sources.loading.channels` | Buscando tus canales… | Looking for your channels… |
| `sources.failed.channels` | No pude traer tus canales. Puedes reintentar o dejar que tu agente lo lea todo. | I couldn't fetch your channels. You can try again or let your agent read everything. |
| `sources.empty.channels` | No encontré canales para elegir. | I didn't find any channels to choose from. |
| `sources.search.channels` | Buscar canales | Search channels |
| `sources.loading.chats` | Buscando tus chats… | Looking for your chats… |
| `sources.failed.chats` | No pude traer tus chats. Puedes reintentar o dejar que tu agente lo lea todo. | I couldn't fetch your chats. You can try again or let your agent read everything. |
| `sources.empty.chats` | No encontré chats para elegir. | I didn't find any chats to choose from. |
| `sources.search.chats` | Buscar chats | Search chats |
| `sources.loading.pages` | Buscando tus páginas y bases de datos… | Looking for your pages and databases… |
| `sources.failed.pages` | No pude traer tus páginas y bases de datos. Puedes reintentar o dejar que tu agente lo lea todo. | I couldn't fetch your pages and databases. You can try again or let your agent read everything. |
| `sources.empty.pages` | No encontré páginas y bases de datos para elegir. | I didn't find any pages and databases to choose from. |
| `sources.search.pages` | Buscar páginas y bases de datos | Search pages and databases |
| `sources.loading.folders` | Buscando tus carpetas… | Looking for your folders… |
| `sources.failed.folders` | No pude traer tus carpetas. Puedes reintentar o dejar que tu agente lo lea todo. | I couldn't fetch your folders. You can try again or let your agent read everything. |
| `sources.empty.folders` | No encontré carpetas para elegir. | I didn't find any folders to choose from. |
| `sources.search.folders` | Buscar carpetas | Search folders |
| `sources.loading.labels` | Buscando tus etiquetas… | Looking for your labels… |
| `sources.failed.labels` | No pude traer tus etiquetas. Puedes reintentar o dejar que tu agente lo lea todo. | I couldn't fetch your labels. You can try again or let your agent read everything. |
| `sources.empty.labels` | No encontré etiquetas para elegir. | I didn't find any labels to choose from. |
| `sources.search.labels` | Buscar etiquetas | Search labels |
| `sources.loading.projects` | Buscando tus proyectos… | Looking for your projects… |
| `sources.failed.projects` | No pude traer tus proyectos. Puedes reintentar o dejar que tu agente lo lea todo. | I couldn't fetch your projects. You can try again or let your agent read everything. |
| `sources.empty.projects` | No encontré proyectos para elegir. | I didn't find any projects to choose from. |
| `sources.search.projects` | Buscar proyectos | Search projects |

### 7 · Skills

| Clave | Español | English |
|---|---|---|
| `skills.ours.title` | Las nuestras | Ours |
| `skills.ours.count %lld %lld` | %1$lld de %2$lld marcadas | %1$lld of %2$lld ticked |
| `skills.ours.hint` | Vienen marcadas. Desmarca las que no quieras. | They come ticked. Untick the ones you don't want. |
| `skills.all` | Marcar todas | Tick all |
| `skills.none` | Desmarcar todas | Untick all |
| `skills.needs %@` | Todavía no te sirve: necesita %@ | Not useful yet: it needs %@ |
| `skills.curated.title` | Curadas de la comunidad | Curated from the community |
| `skills.curated.hint` | Skills de otras personas que revisamos nosotros. Cada una lleva el crédito de su autor y un enlace a su GitHub. | Skills by other people that we reviewed. Each one carries its author's credit and a link to their GitHub. |
| `skills.curated.soon` | Próximamente | Coming soon |
| `skills.curated.credit %@ %@` | por %1$@ · licencia %2$@ | by %1$@ · %2$@ license |
| `skills.curated.view` | Ver en GitHub | View on GitHub |
| `skills.failed` | No pude leer el catálogo de skills. | I couldn't read the skills catalog. |
| `skills.retry` | Reintentar | Try again |

### 8 · Reglas

| Clave | Español | English |
|---|---|---|
| `rules.external.title` | Lo que sale hacia otras personas siempre te lo pide | Anything that goes out to other people always asks you first |
| `rules.external.body` | Un mensaje en Slack o un correo nunca se envía sin que tú lo apruebes. Esto no se puede cambiar. | A Slack message or an email is never sent without your approval. This can't be changed. |
| `rules.external.tools %@` | Aplica a: %@ | Applies to: %@ |
| `rules.whatsapp` | WhatsApp es de solo lectura: tu agente no puede enviar nada por ahí. | WhatsApp is read-only: your agent can't send anything through it. |
| `rules.internal.title` | Lo que escribe dentro de tus herramientas | What it writes inside your tools |
| `rules.internal.hint` | Un borrador en tu propio Notion se corrige; un correo enviado, no. Por eso aquí sí puedes elegir. | A draft in your own Notion can be fixed; a sent email can't. That's why you can choose here. |
| `rules.none` | Ninguna de tus herramientas conectadas permite escribir, así que no hay nada que decidir aquí. | None of your connected tools lets your agent write, so there's nothing to decide here. |
| `rules.write.notion` | Crear y editar en Notion | Create and edit in Notion |
| `rules.write.jira` | Crear y editar tickets en Jira | Create and edit tickets in Jira |
| `rules.write.google-docs` | Crear y editar en Google Docs | Create and edit in Google Docs |
| `rules.write.google-sheets` | Crear y editar en Google Sheets | Create and edit in Google Sheets |
| `rules.policy.ask` | Preguntarme | Ask me |
| `rules.policy.allow` | Sin preguntar | Don't ask |
| `rules.memory` | En tu computador solo escribe sin preguntar en su carpeta memoria/, donde guarda sus notas del proyecto. | On your computer it only writes without asking in its memoria/ folder, where it keeps its project notes. |

### 9 · Generando

| Clave | Español | English |
|---|---|---|
| `generating.headline %@` | Construyendo tu agente: %@ | Building your agent: %@ |
| `generating.step.rules` | Escribiendo las reglas de tu agente | Writing your agent's rules |
| `generating.step.tools` | Conectando tus herramientas | Connecting your tools |
| `generating.step.skills` | Creando tus skills | Creating your skills |
| `generating.step.saving` | Guardando tu agente | Saving your agent |
| `generating.failed` | No pude terminar de construir tu agente. No quedó nada a medias. | I couldn't finish building your agent. Nothing was left half-done. |
| `generating.detail %@` | Detalle: %@ | Detail: %@ |
| `generating.retry` | Reintentar | Try again |
| `generating.back` | Volver a las reglas | Back to the rules |

### 10 · Listo

| Clave | Español | English |
|---|---|---|
| `done.headline %@` | Tu agente %@ está listo | Your agent %@ is ready |
| `done.noAgent` | Todavía no hay un agente generado. Vuelve a las reglas y avanza otra vez. | There's no generated agent yet. Go back to the rules and continue again. |
| `done.where.title` | Dónde quedó | Where it lives |
| `done.where.reveal` | Mostrar en Finder | Show in Finder |
| `done.copyPath` | Copiar ruta | Copy path |
| `done.copied` | Copiado | Copied |
| `done.first.title` | Pídele esto primero | Ask it this first |
| `done.first.copy` | Copiar | Copy |
| `done.open.title` | Ábrelo en | Open it in |
| `done.open.app` | App de Claude | Claude app |
| `done.open.terminal` | Terminal | Terminal |
| `done.open.appMissing` | No encontré la app de Claude en este Mac. Puedes abrirlo en Terminal. | I couldn't find the Claude app on this Mac. You can open it in Terminal. |
| `done.open.confirm` | La app de Claude te pedirá confirmar la carpeta; es normal. | The Claude app will ask you to confirm the folder; that's normal. |
| `done.open.failed` | No pude abrirlo. Abre la carpeta a mano y escribe «claude». | I couldn't open it. Open the folder by hand and type “claude”. |
| `done.warning.claudeFile` | Ya había un CLAUDE.md en esa carpeta y no lo toqué. Revísalo: tu agente necesita que importe AGENTS.md. | There was already a CLAUDE.md in that folder and I left it alone. Check it: your agent needs it to import AGENTS.md. |

### Pantallas de dopamina (marcadores)

| Clave | Español | English |
|---|---|---|
| `dopamine.agent` | TODO(dopamina) agente | TODO(dopamina) agent |
| `dopamine.connect.first` | TODO(dopamina) tras las 2 primeras | TODO(dopamina) after the first 2 |
| `dopamine.connect.half` | TODO(dopamina) a la mitad | TODO(dopamina) halfway |
| `dopamine.connect.last` | TODO(dopamina) antes de la última | TODO(dopamina) before the last one |
| `dopamine.detection` | TODO(dopamina) detección | TODO(dopamina) detection |
| `dopamine.tools` | TODO(dopamina) herramientas | TODO(dopamina) tools |
| `dopamine.welcome` | TODO(dopamina) bienvenida | TODO(dopamina) welcome |
| `dopamine.generating` | TODO(dopamina) generando | TODO(dopamina) generating |
| `dopamine.done` | TODO(dopamina) listo | TODO(dopamina) done |

---

# Apéndice B — Datos útiles

**Ventana:** 720 × 560 pt, fija. **Barra de progreso:** «PASO N DE 10». **Pasos:** 1 Idioma y bienvenida · 2 Detección · 3 Tu agente · 4 Herramientas · 5 Conexión (sub-wizard) · 6 Qué leer · 7 Skills · 8 Reglas · 9 Generando · 10 Listo.

**Herramientas (10):** WhatsApp, Slack, Notion, Google Drive/Docs/Sheets, Gmail, Jira, Fireflies, Granola, Fathom, Google Meet. (Meet se lee con Drive. Hoy Gmail y Google Workspace quedan en «conectar después».)

**Cifras para dar realismo a los diseños:** un PM típico conecta 4–6 herramientas; un workspace de Slack puede tener decenas de canales; WhatsApp puede listar cientos de chats (≈ 30 grupos); el nombre de un agente va de 4 a 60 caracteres; el nombre de una skill, de 6 a 25.

**Tokens CSS vigentes** (de `docs/04` §10):

```css
:root{
  --parchment-50:#F3EEE2; --parchment-100:#EEE7D8; --parchment-200:#E7E0D1;
  --parchment-300:#D8D1C1; --parchment-400:#D0CBBC; --vellum-100:#E2C9B7;
  --ink-900:#2E2D2A; --ink-700:#63655E; --ink-500:#8C877C; --ink-300:#B5B0A5;
  --binding-900:#314041;
  --seal-700:#8B3A3A; --seal-100:#F0E3E0;
  --moss-700:#4F6F5B; --moss-100:#E6EEE8; --ochre-700:#9A7B2F;
  --space-1:4px; --space-2:8px; --space-3:12px; --space-4:16px; --space-6:24px;
  --space-8:32px; --space-12:48px; --space-16:64px; --space-24:96px;
  --radius-sm:4px; --radius-md:8px; --radius-lg:12px;
}
```

**Fuentes de la estética:** litografía *Claude Galien* (Vigneron, siglo XIX, dominio público) y portada de *Galeni Pergameni opera omnia* (Basilea, 1538, ΓΑΛΗΝΟΥ ΑΠΑΝΤΑ).
