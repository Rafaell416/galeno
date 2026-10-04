# Galeno — Design System
### "Old school": litografía, pergamino y capitales romanas

**Versión:** 1.1 · 4 de octubre de 2026 (rediseño de la app Mac: ver §12, que manda sobre el resto para la app)
**Fuentes de la estética:** la litografía *Claude Galien* de Vigneron (siglo XIX, dominio público) y la portada de *Galeni Pergameni opera omnia*, Basilea, 1538 (ΓΑΛΗΝΟΥ ΑΠΑΝΤΑ).
**Aplica a:** la guía de construcción, el sitio web y la app Mac.

---

## 1. La idea en una frase

Galeno se ve como **un libro antiguo bien impreso**: papel envejecido, tinta gris cálida, capitales romanas espaciadas, un solo acento de lacre rojo, y mucho silencio alrededor de las cosas. No es "vintage decorativo" — es la sobriedad de un impresor del siglo XVI aplicada a una herramienta moderna.

**Lo que NO es:** texturas de papel arrugado sobre todo, bordes ornamentales, filigranas, sepia saturado, tipografías "medievales" góticas, pergaminos enrollados, lacres dibujados. Eso es disfraz. Lo nuestro es un libro, no un tema de Halloween.

---

## 2. Color — extraído de los originales

Los valores salen de medir las imágenes reales, no de inventar.

### Pergamino (fondos)
| Token | Hex | Origen | Uso |
|---|---|---|---|
| `parchment-50` | `#F3EEE2` | Papel de la litografía, zona más clara | Fondo principal |
| `parchment-100` | `#EEE7D8` | Papel de la litografía | Fondo de paneles, tarjetas |
| `parchment-200` | `#E7E0D1` | Papel, tono medio | Fondo alterno, filas |
| `parchment-300` | `#D8D1C1` | Papel, sombra | Bordes, separadores, fondo de código |
| `parchment-400` | `#D0CBBC` | Papel, zona oscura | Bordes marcados, deshabilitado |
| `vellum-100` | `#E2C9B7` | Vitela de la portada 1538 | Acento cálido en ilustraciones y hover (usar poco) |

### Tinta (texto y trazo)
| Token | Hex | Origen | Uso |
|---|---|---|---|
| `ink-900` | `#2E2D2A` | Negro de la litografía | Texto principal, títulos |
| `ink-700` | `#63655E` | Gris medio del grabado | Texto secundario, iconos |
| `ink-500` | `#8C877C` | Gris claro del grabado | Texto terciario, placeholders, anillos finos |
| `ink-300` | `#B5B0A5` | Trazo suave | Líneas decorativas, divisores |
| `binding-900` | `#314041` | Encuadernación de 1538 | Fondo oscuro (modo oscuro), bloques de código en oscuro |

### Acento (uno solo)
| Token | Hex | Origen | Uso |
|---|---|---|---|
| `seal-700` | `#8B3A3A` | Sello rojo de biblioteca en la portada 1538 | **Solo** acciones primarias, enlaces, el "·" del wordmark, estados activos. Nunca fondos grandes |
| `seal-100` | `#F0E3E0` | Sello diluido | Fondo de avisos importantes |

### Estados funcionales (mínimos, sobrios)
| Token | Hex | Uso |
|---|---|---|
| `moss-700` | `#4F6F5B` | Éxito, "conectado", completado |
| `moss-100` | `#E6EEE8` | Fondo de éxito |
| `ochre-700` | `#9A7B2F` | Advertencia |
| `seal-700` | `#8B3A3A` | Error (comparte el acento, con icono distinto) |

### Modo oscuro ("el libro de noche")
Invierte el papel por la encuadernación, pero con el **negro cálido de Claude Code desktop**: fondo `#141413`, paneles `#1D1D1B`, bordes `#302F2C`, texto `parchment-100`, acento `seal-700` aclarado a `#B85C5C`, éxito `#7FA38C`. Sin tinte azul ni verde (se descartó el gris-verdoso `#262E30` de la primera versión, 4 oct 2026).

**Regla de contraste:** texto `ink-900` sobre `parchment-50` = 12.6:1. Texto `ink-700` sobre `parchment-50` = 5.4:1 (AA). `ink-500` solo para texto grande o decorativo.

---

## 3. Tipografía

Tres familias, cada una con un trabajo:

| Rol | Familia | Por qué | Fallback |
|---|---|---|---|
| **Display / títulos** | **Cinzel** (Google Fonts) | Capitales romanas inscripcionales: es exactamente el "CLAUDE GALIEN." de la litografía y el "GALENI PERGAMENI" de 1538 | Trajan, Georgia |
| **Texto** | **EB Garamond** (Google Fonts) | La Garamond digital más fiel a la tipografía de imprenta del XVI; lee bien en cuerpo largo | Georgia, serif |
| **Código / datos** | **JetBrains Mono** | Funcional; no intentamos que el código parezca antiguo | Menlo, monospace |

**En la app Mac** (reabierto por el rediseño B1, §12): se embeben **Cormorant Garamond** (títulos) y **EB Garamond** (texto), ambas OFL, con subconjunto latino. **New York** queda como respaldo si una fuente no carga. Cinzel no se usa en la app; solo en el wordmark, como imagen.

### Escala y reglas
| Nivel | Fuente | Tamaño / interlínea | Tracking | Uso |
|---|---|---|---|---|
| Display | Cinzel 700 | 40 / 1.1 | +0.04em, MAYÚSCULAS | Titular de hero, nombre de fase |
| H1 | Cinzel 600 | 28 / 1.15 | +0.03em, MAYÚSCULAS | Títulos de página |
| H2 | EB Garamond 600 | 22 / 1.25 | 0 | Secciones |
| H3 | EB Garamond 600 | 18 / 1.3 | 0 | Subsecciones |
| Cuerpo | EB Garamond 400 | 18 / 1.6 | 0 | Texto corrido (sí, 18: Garamond se ve pequeña a 16) |
| Pequeño | EB Garamond 400 | 15 / 1.5 | 0 | Notas, metadatos |
| Etiqueta | Cinzel 500 | 11 / 1 | +0.12em, MAYÚSCULAS | Kickers, chips ("FASE 3", "PROMPT") |
| Código | JetBrains Mono 400 | 14 / 1.5 | 0 | Bloques y código inline |

**Reglas:**
- Las capitales romanas (Cinzel) **solo en títulos cortos y etiquetas**. Un párrafo en Cinzel es ilegible.
- Números en estilo antiguo (`font-variant-numeric: oldstyle-nums`) en el texto corrido; tabulares en tablas.
- Ancho de medida: 68–74 caracteres. Garamond pide líneas no muy largas.
- Punto final después de títulos en capitales, como en la litografía: **"GALENO."** — es la firma tipográfica de la marca.

---

## 4. El logo

### Marca principal: retrato + wordmark
- **Retrato:** el busto de la litografía, recortado en círculo, con el blanco del papel del grabado fundido al pergamino (no un recorte duro). Doble anillo fino: tinta `ink-900` interior, `ink-500` exterior. Archivo: `galeno-logo-320.png` / `galeno-retrato-1200.jpg`.
- **Wordmark:** `GALENO.` en Cinzel 700, tracking +0.08em, con el punto final en `seal-700`. El punto rojo es el único color del logo.
- **Lockup horizontal:** retrato a la izquierda (altura = 2.2× la altura de las capitales), wordmark a la derecha, separados por 0.6× la altura del retrato.
- **Lockup vertical** (hero, splash): retrato arriba, wordmark debajo centrado, y opcionalmente el subtítulo griego **ΓΑΛΗΝΟΥ ΑΠΑΝΤΑ** en `ink-500`, Cinzel 400, tamaño etiqueta — como guiño a la portada de 1538.

### Ícono de la app Mac
Fondo pergamino con viñeta sutil, retrato circular, doble anillo. Sin texto (en el Dock no se lee). **En macOS Xcode no aplica las esquinas** (eso es de iOS): el icono lleva su propia forma, de 824 px con esquinas del 22,37 % centrada en un lienzo de 1024 con margen transparente y una sombra suave, como pide la retícula de Apple. Así está en `AppIcon.appiconset` (`icon_16.png` … `icon_1024.png`), generado desde el cuadrado `galeno-app-icon-1024.png`.

### Usos prohibidos
- No colorear el retrato. Siempre grises de tinta sobre pergamino.
- No poner el retrato sobre fondos oscuros sin su círculo de pergamino.
- No rotar, inclinar ni añadir sombras.
- No sustituir Cinzel por otra fuente en el wordmark.
- No usar el ΓΑΛΗΝΟΥ como logo solo; es ornamento, no marca.

### Crédito
La litografía es de dominio público (Vigneron, lit. de G. Engelmann). En el sitio, página *About* o pie: "Retrato: litografía de Vigneron, dominio público."

---

## 5. Espacio, forma y superficie

- **Escala de espacio:** 4 · 8 · 12 · 16 · 24 · 32 · 48 · 64 · 96. Generosa: un libro tiene márgenes anchos.
- **Radios:** 4 (chips, código), 8 (botones, tarjetas), 12 (paneles). Nunca 20+ ni píldoras: lo redondo es moderno-genérico.
- **Bordes:** 1px `parchment-300` por defecto; 1.5px `ink-900` para énfasis. **Los bordes son la forma de separar, no las sombras.**
- **Sombras:** ninguna decorativa. Solo en elementos flotantes reales (menús, modales): `0 8px 24px rgba(46,45,42,0.12)`.
- **Divisores:** una línea fina `ink-300`, o un ornamento tipográfico centrado `·  ·  ·` en `ink-500` para separar secciones grandes (como un impresor).
- **Textura:** en el sitio y la guía, **ninguna** imagen de textura de papel. En la app Mac hay una sola excepción, decidida en el rediseño: el **grano** de §12 (ruido tenue, 5 % en claro y 7 % en oscuro, que se apaga con una bandera). Ninguna otra textura.

---

## 6. Componentes

| Componente | Especificación |
|---|---|
| **Botón primario** | Fondo `ink-900`, texto `parchment-50`, Cinzel 500 11–12px MAYÚSCULAS tracking +0.1em, padding 12×20, radio 8. Hover: `binding-900`. Nunca el rojo como fondo de botón |
| **Botón secundario** | Borde 1.5px `ink-900`, texto `ink-900`, fondo transparente |
| **Enlace** | `seal-700`, subrayado fino con `text-underline-offset: 3px` |
| **Chip / etiqueta** | Cinzel 500 10–11px MAYÚSCULAS, borde 1px, radio 4. "FASE 3", "PROMPT", "GRATIS" |
| **Tarjeta** | Fondo `parchment-100`, borde 1px `parchment-300`, radio 8–12, padding 24. Sin sombra |
| **Código** | Fondo `parchment-300`, texto `ink-900`, JetBrains Mono, radio 8, borde 1px `parchment-400` |
| **Aviso / nota** | Borde izquierdo 3px `seal-700`, fondo `seal-100`. Para éxito: `moss-700` / `moss-100` |
| **Progreso** | Barra de 6px `parchment-300` con relleno `ink-900` (no de color). Pasos completados: círculo `moss-700` con ✓ |
| **Campo de texto** | Borde inferior 1.5px `ink-500`, sin caja (como una línea en papel); foco: `ink-900` |
| **Separador de sección** | `·  ·  ·` centrado en `ink-500` |

---

## 7. Imagen y motivo

- **Única imagen de marca:** el retrato. Se usa con moderación: ícono, logo, hero del sitio, splash de la app. No en cada pantalla.
- **Capturas del producto:** siempre reales, con la app en su paleta. Enmarcadas con borde 1px `ink-300`, sin mockups de MacBook.
- **Ornamento permitido:** el subtítulo griego ΓΑΛΗΝΟΥ ΑΠΑΝΤΑ como guiño, el `·  ·  ·` como separador, y numerales romanos para las fases en la guía (I, II, III…) si se quiere acentuar.
- **Ornamento prohibido:** florituras, marcos, viñetas dibujadas, sellos de lacre ilustrados, plumas, pergaminos enrollados. *(En la app Mac rige §12: ahí se admiten láminas de grabado de línea y unos pocos glifos propios.)*
- **Iconografía:** SF Symbols en la app (monocromos `ink-700`); en la web, íconos de línea fina monocromos. Nunca íconos de color ni ilustraciones de stock. Los logos de las herramientas de terceros (grilla del paso 4) se permiten **solo en monocromo `ink-700`**, para identificar la herramienta y nada más; sin logo disponible, un SF Symbol del mismo color.

---

## 8. Movimiento

Discreto, como pasar una página. Duraciones 150–300 ms, curva `ease-out`. Las animaciones de dopamina del wizard (check que se dibuja, logo que "se enciende") usan **trazo y opacidad**, no rebotes ni confeti de colores — si hay confeti, es de puntos `ink-500` y `seal-700`, pocos, que caen como polvo de tinta.

---

## 9. Cómo se aplica a cada superficie

### La guía de construcción (HTML)
Fondo `parchment-50`, texto EB Garamond 18, títulos de fase en Cinzel, el retrato en el temario, numerales romanos opcionales. Prompts marcados con chip `PROMPT` en `seal-700`. Pruebas en `moss`. Modo oscuro "libro de noche".

### El sitio web
Estructura tipo SourceNote (hero → video → capturas+texto → about → testimonios → precio → footer), vestida con este sistema. Hero: retrato centrado grande, `GALENO.` debajo, subtítulo en EB Garamond, un solo botón `COMPRAR · USD 200`. Secciones separadas por `·  ·  ·`. Capturas reales con borde fino. Cero gradientes, cero tarjetas con íconos. Tipografías vía Google Fonts.

### La app Mac (wizard)
> **Reabierto (oct 2026):** el rediseño B1 «El impresor» sustituye lo de esta sección sobre fuentes, controles, ilustración y dopamina. Manda **§12**. Lo que sigue se conserva como historia y para lo que §12 no cambia (ventana estándar, SF Symbols, respeto al modo del sistema).

**La regla de oro (versión original): nativo primero, estética encima.** Controles nativos de macOS (botones, campos, listas), ventana estándar, SF Symbols. Lo que se "viste":
- Fondo de la ventana en `parchment-50` (y `#141413` en oscuro), respetando el modo del sistema.
- Tipografía: **New York** (serif del sistema) para todo el texto; títulos de paso en New York `.smallCaps()` con tracking. Sin fuentes embebidas.
- Acento de la app (`.tint`) en `seal-700`: afecta botones por defecto, selección, progreso.
- Botón primario nativo con tinte `ink-900`; secundarios en borde.
- Las pantallas de dopamina: el retrato (pequeño, en círculo) con un trazo que se dibuja alrededor, texto en New York, sin confeti de colores.
- El QR de WhatsApp: en un marco de 1px `ink-900` sobre `parchment-100`, con el texto de advertencia en New York, tono sereno.
- Ícono: `galeno-app-icon-1024-rounded.png`.

Lo que **no** se hace en la app: forzar Cinzel como fuente de UI, romper el espaciado estándar de macOS. *(Fondos con textura y controles propios dejaron de estar prohibidos: ver §12.)*

---

## 10. Tokens listos para copiar

```css
:root{
  --parchment-50:#F3EEE2; --parchment-100:#EEE7D8; --parchment-200:#E7E0D1;
  --parchment-300:#D8D1C1; --parchment-400:#D0CBBC; --vellum-100:#E2C9B7;
  --ink-900:#2E2D2A; --ink-700:#63655E; --ink-500:#8C877C; --ink-300:#B5B0A5;
  --binding-900:#314041;
  --seal-700:#8B3A3A; --seal-100:#F0E3E0;
  --moss-700:#4F6F5B; --moss-100:#E6EEE8; --ochre-700:#9A7B2F;
  --font-display:"Cinzel",Trajan,Georgia,serif;
  --font-text:"EB Garamond",Georgia,serif;
  --font-mono:"JetBrains Mono",Menlo,monospace;
  --space-1:4px; --space-2:8px; --space-3:12px; --space-4:16px; --space-6:24px;
  --space-8:32px; --space-12:48px; --space-16:64px; --space-24:96px;
  --radius-sm:4px; --radius-md:8px; --radius-lg:12px;
}
```

```swift
// SwiftUI — Galeno
extension Color {
  static let parchment50 = Color(red:0.953, green:0.933, blue:0.886)
  static let parchment100 = Color(red:0.933, green:0.906, blue:0.847)
  static let parchment300 = Color(red:0.847, green:0.820, blue:0.757)
  static let ink900 = Color(red:0.180, green:0.176, blue:0.165)
  static let ink700 = Color(red:0.388, green:0.396, blue:0.369)
  static let ink500 = Color(red:0.549, green:0.529, blue:0.486)
  static let seal700 = Color(red:0.545, green:0.227, blue:0.227)
  static let moss700 = Color(red:0.310, green:0.435, blue:0.357)
}
// Tipografía: New York (serif del sistema), sin fuentes embebidas
let galenoTitle = Font.system(.title, design: .serif).weight(.semibold)
let galenoBody  = Font.system(.body,  design: .serif)
// Títulos de paso en versalitas con tracking:
Text("Conecta tus herramientas").font(galenoTitle.smallCaps()).kerning(1.2)
// Acento global:
ContentView().tint(.seal700)
```

---

## 11. Archivos de marca entregados

| Archivo | Uso |
|---|---|
| `galeno-app-icon-1024.png` | Ícono de la app (cuadrado; Xcode aplica las esquinas) |
| `galeno-app-icon-1024-rounded.png` | Preview del ícono como se verá en el Dock |
| `galeno-logo-320.png` | Logo circular pequeño (web, guía, favicon) |
| `galeno-retrato-1200.jpg` | Retrato grande para el hero del sitio |

---

## 12. La app Mac: rediseño B1 «El impresor» (4 oct 2026)

Decidido por Rafa tras el estudio de Claude Design (proyecto «Decisiones de diseño en formulario»). **Para la app, esta sección manda sobre §3 a §9.** El resto (sitio, guía, ícono) sigue como estaba. La idea no cambia —un libro bien impreso—; cambia cuánto se dibuja: ahora hay tipografía propia, controles propios, láminas y un grano.

**Criterio:** todo lo que aparezca en pantalla debe poder justificarse como algo que haría un impresor de Basilea en 1538 o un grabador anatómico en 1750.

### Tipografía
- **Títulos:** Cormorant Garamond SemiBold (cursiva Medium para frases). **Texto:** EB Garamond. **Datos y rutas:** monoespaciada del sistema.
- Archivos: las 4 TTF variables de Google Fonts, reducidas a latino (~0,5 MB en total), en `GalenoApp/Galeno/Fonts/`, registradas al primer uso (`Typography.swift`). Licencias OFL en `GalenoApp/THIRD_PARTY.md`. Receta y medidas: `docs/05b-spike-fuentes.md`.
- Escala (`Typo`): portada 36 · título de paso 32 · cita 26 cursiva · cuerpo 16 · lista 15 · nota 13,5 · etiqueta en versalitas 13 · rótulo con cifras 12 en mayúsculas. El cuerpo nunca baja de 14.
- **Versalitas** (`SmallCapsText`): como las pinta el diseño, las minúsculas pasan a mayúsculas al 70 % del tamaño y lo demás queda entero. No se usa la característica `smcp` de la fuente: es más ancha que la del diseño y convierte las cifras a estilo antiguo («10» se leería «Io»).
- Títulos de paso en minúscula inicial, con un **punto final en lacre**: es el único acento de la pantalla.

### Color
Se mantienen los tokens de §2. Valores claro/oscuro de los que cambian en oscuro: `parchment-50` F3EEE2/141413, `parchment-100` EEE7D8/1D1D1B, `parchment-200` E7E0D1/252523, `parchment-300` D8D1C1/302F2C, `parchment-400` D0CBBC/42413D, `ink-300` B5B0A5/5E5C56, `seal-100` F0E3E0/2B1F1E, `moss-100` E6EEE8/1F2923, `ochre-700` 9A7B2F/C9A552 y `onInk` F3EEE2/141413 (texto sobre tinta). Los tokens viven en `Theme.swift` como `NSColor` dinámicos. **El lacre aparece como máximo una vez por pantalla.**

### Controles (en `InkButtonStyle.swift`, `InkControls.swift`, `RuleProgress.swift`)
| Control | Medida y forma |
|---|---|
| Primario | 44 pt, relleno `ink-900`, texto `onInk`. Uno por pantalla |
| Secundario | 44 pt, filete 1,5 pt `ink-900`, fondo transparente |
| Terciario | texto subrayado en `ink-700`, para lo discreto |
| En línea | secundario de 36 pt, para acciones dentro del contenido |
| Chip | 28 pt, filete 1,5 pt; marcado = tinta rellena |
| Casilla | 14 pt (área = toda la fila), marcada = tinta rellena con palomita |
| Selector | caja con filete 1,5 pt de 34 pt; la opción elegida, en tinta rellena. La que conviene que se note («Sin preguntar») se rellena en lacre con texto blanco |
| Campo | solo un filete inferior de 1,5 pt (más oscuro con foco), sin caja; el texto de ejemplo, en `ink-500` |
| Progreso | filete de 1 pt con un trazo de 3 pt en tinta que avanza |
**Esquinas rectas** (radio 0), como en el prototipo; solo las tarjetas de «Revisión» y la maqueta «lo que verás» redondean 4 pt. Borde de foco por teclado: 2 pt en lacre, separado del control. Los estados deshabilitados bajan a 40 % de opacidad. Los bordes separan; no hay sombras.

### Pantallas
La fuente de verdad es `Galeno B1 Impresor.dc.html` (Claude Design). Diez pasos: Bienvenida · Claude Code · Tu agente · Tus herramientas · Conectar · Skills · Reglas · Revisión · Escribiendo · Listo. La cabecera lleva «Paso N de 10 · ~M min» (lo que falta, estimado) y el nombre del paso en cursiva. Las dos ventanas de Slack comparten una barra (`SlackWindowBar`): dirección a la vista, paso, de quién es el turno y un filete que avanza.

### Ilustración
- **Láminas** (`Plate`): grabado de línea en un solo tono de tinta, siempre decorativo y oculto a VoiceOver. Van en las pantallas de pausa («dopamina») y en «Listo»; **nunca** junto a formularios, errores ni la advertencia de WhatsApp.
- **Retrato** (`PortraitMark`): la litografía de Vigneron en círculo, con doble anillo fino en la bienvenida y sencillo en «Listo». Crédito: «Retrato: litografía de Vigneron, dominio público».
- Mientras falte el arte, en Debug se ve un recuadro rayado con su leyenda y en Release no se dibuja nada: la pantalla se sostiene con el texto.
- Los grabados salen de material de dominio público (Wellcome; revisar la licencia de cada uno). Cada imagen se anota en `THIRD_PARTY.md`.
- **Glifos de sección** (`Glyphs.swift`): ocho dibujos propios de línea a 1,5 pt sobre cuadrícula de 24 —rollo, códice, pluma, lente, bastón de Asclepio (una sola serpiente), sello, columnata y mortero—, hechos en código (no son SF Symbols ni de terceros). Cuelgan en el margen izquierdo del título, en `ink-500`, sin mover el título: mortero en «Tus herramientas», pluma en «Skills», bastón en «Reglas» y lente en «Revisión». Rollo, códice, sello y columnata quedan en reserva. Nunca van en la misma fila que un SF Symbol.
- Sigue prohibido el ornamento de relleno: florituras, marcos, lacres dibujados.

### Grano
Ruido de 200×200 px, determinista, con opacidad de 5 % (claro) y 7 % (oscuro), sobre toda la ventana (`Grain.swift`). Se apaga con `defaults write com.galeno.Galeno GalenoGrainEnabled -bool NO`.

### Movimiento (`Motion.swift`)
Siete gestos, todos con alternativa en «Reducir movimiento» (el cambio ocurre, sin recorrido): **escribir** (filete de 800 ms bajo el renglón en curso), **trazar** (círculo 700 ms + palomita 500 ms), **pasar página** (300 ms, opacidad y 4 pt), **filete que avanza** (300 ms), **tinta que corre** (1,4 s en bucle, para esperas sin progreso real), **encender** (200 ms, el logo conectado) y **posar el sello** (250 ms).  Sin rebotes ni confeti.

Micro-interacciones del asistente (spec «Micro-interacciones del asistente», salvo las del paso «El foco», que ya no existe): `Motion.swift` reúne las utilidades (`TracedShape`, `AppearAfter`/`.appearing(after:)`, `.staggered`, `CountingNumber`, `WriteUnderline`, `ChasingNumber`, `LoadingRing`, `.settling`, `.revealed`). Reglas: solo opacidad y trazo (nada de rebotes); 120–200 ms para estados, 300 ms para entradas, 500–800 ms para trazos; una sola entrada por pantalla; escalón de 80 ms (30 ms en cascadas, máximo 6); ninguna animación bloquea al usuario; toda cifra que cuenta es un dato real. «Reducir movimiento» (del sistema o de Ajustes → «Menos movimiento», `galenoReduceMotion`) deja todo en fundidos de 150 ms sin desplazamiento ni trazo. Adaptaciones frente a la spec: el chip (G7) no existe; la confirmación de quitar sigue siendo `RemovalConfirmPanel`; las pausas de dopamina usan `plate-columnata`, `plate-codice` (grabados de dominio público recortados y pasados a tinta, con los bordes difuminados) y `plate-pluma` (los tres en viñeta ovalada, 300 pt de ancho; la pluma sale además en «Escribiendo», más pequeña y solo mientras no hay un error; en oscuro la columnata, que es pura línea, se invierte como tiza sobre pizarra, y las dos que llevan figuras —códice y pluma— se muestran como una estampa sobre su papel, `Plate(printOnPaper:)`, porque un rostro en negativo no se lee); el paso 3 deshabilita «Siguiente» con el nombre vacío en vez de mostrar el error al pulsarlo (aprobado por Rafa); en el paso 2 la rueda de búsqueda y la palomita son dos estados distintos, como en el diseño, y no un anillo que se cierra; no hay anuncios de VoiceOver para los cambios de estado (decisión de Rafa); los nombres de chats del sincronizado (5.20) no se muestran porque el puente no los entrega.

### Sonido
Tres, ligados a momentos y no a clics (decisión de Rafa, 4 oct 2026): una **conexión lograda** (`conexion.wav`: dos notas suaves que suben), **algo que falló** —una conexión o la escritura del agente— (`fallo.wav`: dos notas más graves que bajan) y el **sello** al llegar a «Listo» (`sello.wav`). Todos ≤ 450 ms, a −12 dB sobre el volumen del sistema y generados por nosotros (`Sounds/`). **Encendidos de fábrica**, con un solo interruptor en Ajustes. Ningún sonido en casillas, botones, copiar ni cambios de paso, ni música.

### Modo oscuro
«El libro de noche» (§2). El grano sube a 7 % y se dibuja en blanco; el botón primario se invierte (papel sobre fondo oscuro); el acento se aclara a `#B85C5C`.

### Textos
El copy v2 (ES/EN) vive en `Localizable.xcstrings`: botones con verbo («Empezar», «Conectar 5 herramientas»), bloque «Qué va a pasar» antes de cada conexión, errores en tres partes (qué falló, qué hacer, detalle), el nombre del agente desde el paso 3 y sin signos de exclamación. La advertencia de WhatsApp **no se reescribe**; solo cambia su presentación.
