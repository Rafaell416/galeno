# Galeno — Design System
### "Old school": litografía, pergamino y capitales romanas

**Versión:** 1.0 · 2 de octubre de 2026
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
Invierte el papel por la encuadernación: fondo `binding-900` → `#262E30` elevado, texto `parchment-100`, bordes `#3C4648`, acento `seal-700` aclarado a `#B85C5C`, éxito `#7FA38C`. El modo oscuro es **sobrio y gris-verdoso**, no negro puro.

**Regla de contraste:** texto `ink-900` sobre `parchment-50` = 12.6:1. Texto `ink-700` sobre `parchment-50` = 5.4:1 (AA). `ink-500` solo para texto grande o decorativo.

---

## 3. Tipografía

Tres familias, cada una con un trabajo:

| Rol | Familia | Por qué | Fallback |
|---|---|---|---|
| **Display / títulos** | **Cinzel** (Google Fonts) | Capitales romanas inscripcionales: es exactamente el "CLAUDE GALIEN." de la litografía y el "GALENI PERGAMENI" de 1538 | Trajan, Georgia |
| **Texto** | **EB Garamond** (Google Fonts) | La Garamond digital más fiel a la tipografía de imprenta del XVI; lee bien en cuerpo largo | Georgia, serif |
| **Código / datos** | **JetBrains Mono** | Funcional; no intentamos que el código parezca antiguo | Menlo, monospace |

**En la app Mac:** no se embeben fuentes web. Se usa el serif del sistema, **New York** (`Font.system(design: .serif)` en SwiftUI), que da el mismo carácter sin romper lo nativo. Para los títulos grandes en capitales, New York con `.smallCaps()` y tracking amplio. Opcionalmente Cinzel solo en el wordmark (como imagen); el ícono no lleva texto.

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
`galeno-app-icon-1024-rounded.png`: fondo pergamino con viñeta sutil, retrato circular, doble anillo. Sin texto (en el Dock no se lee). Esquinas con el radio estándar de macOS.

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
- **Textura:** **ninguna** imagen de textura de papel. El "papel" es el color plano más la viñeta sutil del ícono. Si alguien quiere textura, la respuesta es no.

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
- **Ornamento prohibido:** florituras, marcos, viñetas dibujadas, sellos de lacre ilustrados, plumas, pergaminos enrollados.
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
**La regla de oro: nativo primero, estética encima.** Controles nativos de macOS (botones, campos, listas), ventana estándar, SF Symbols. Lo que se "viste":
- Fondo de la ventana en `parchment-50` (y `#262E30` en oscuro), respetando el modo del sistema.
- Tipografía: **New York** (serif del sistema) para todo el texto; títulos de paso en New York `.smallCaps()` con tracking. Sin fuentes embebidas.
- Acento de la app (`.tint`) en `seal-700`: afecta botones por defecto, selección, progreso.
- Botón primario nativo con tinte `ink-900`; secundarios en borde.
- Las pantallas de dopamina: el retrato (pequeño, en círculo) con un trazo que se dibuja alrededor, texto en New York, sin confeti de colores.
- El QR de WhatsApp: en un marco de 1px `ink-900` sobre `parchment-100`, con el texto de advertencia en New York, tono sereno.
- Ícono: `galeno-app-icon-1024-rounded.png`.

Lo que **no** se hace en la app: forzar Cinzel como fuente de UI, fondos con textura, controles custom que imiten "viejo", romper el espaciado estándar de macOS.

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
