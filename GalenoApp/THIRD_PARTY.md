# Material de terceros en GalenoApp

## Logos de las herramientas (paso 4 del wizard)

`Galeno/Assets.xcassets/ToolIcons/` contiene cinco logos de [Simple Icons](https://github.com/simple-icons/simple-icons),
versión **16.33.0**, publicados bajo **CC0 1.0 Universal** (dominio público). Son SVG de un solo
`<path>`, sin scripts ni referencias externas, y se muestran siempre en monocromo (`ink-700`,
`docs/04` §7).

| Archivo | Herramienta |
|---|---|
| `tool-whatsapp` | WhatsApp |
| `tool-notion` | Notion |
| `tool-googledrive` | Google Drive, Docs y Sheets |
| `tool-gmail` | Gmail |
| `tool-jira` | Jira |

Fuente de cada archivo: `https://raw.githubusercontent.com/simple-icons/simple-icons/16.33.0/icons/<nombre>.svg`.

**Marcas.** CC0 libera los archivos, no las marcas: WhatsApp, Notion, Google, Gmail y Jira
son marcas de sus dueños. Aquí solo identifican la herramienta con la que Galeno se
conecta; no sugieren que esos proveedores respalden a Galeno.

**Slack.** Su marca (el «hash» de ocho formas) va en `tool-slack`, dibujada en **monocromo**, un solo trazo
tintado como los demás logos. Origen: la identidad oficial de Slack, que Rafa aportó como imagen; la geometría
es la del logo, sin recolorear por piezas. Las [guías de marca de Slack](https://slack.com/terms-of-service/slack-brand)
piden usar la versión monocroma (negra o blanca) sobre fondos que no sean blancos y no permiten recolorear,
cortar ni deformar la marca; aquí se tinta en `ink-700`/`ink-900`, que es monocromo pero no es negro ni
blanco puro. Es un uso nominativo (identifica la herramienta, no sugiere respaldo). **Pendiente de revisar:**
las guías hablan de apps del Slack Marketplace, y Galeno no está en él; si Slack lo objeta, volver al SF Symbol
`number` en `ToolIcon.swift`.

**Fathom.** Su marca (dos barras inclinadas y una pieza corta) va en `tool-fathom`, dibujada en **monocromo**, un solo
trazo tintado como los demás logos. Origen: el logo de Fathom (el grabador de reuniones, fathom.video), que Rafa aportó
como imagen el 4 de octubre de 2026; la geometría es la del logo, sin sus dos tonos de azul. Hasta ese día el archivo era
el «Fathom» de Simple Icons, que resultó ser el logo de **otra empresa** (Fathom Analytics): se reemplazó. Es un uso
nominativo (identifica la herramienta, no sugiere respaldo). **Pendiente de revisar:** no se han leído las guías de marca
de Fathom; si piden otra cosa, volver a un SF Symbol (`waveform`) en `ToolIcon.swift`.

**Sin logo en esa colección:** Fireflies y Granola usan un SF Symbol (`waveform`, `note.text`) en el mismo color. **Sin logo todavía:** Google Calendar (`calendar`) y Claude Design (`paintpalette`) usan también un SF Symbol hasta tener uno monocromo con licencia verificada. Si se sustituyen por los SVG oficiales, anotarlos aquí con su origen
y sus reglas de uso.

## Fuentes del rediseño (`Galeno/Fonts/`)

Dos familias bajo la **SIL Open Font License 1.1** (uso comercial y embebido permitidos; no se
venden por separado). Los textos completos van junto a las fuentes: `OFL-EBGaramond.txt` y
`OFL-CormorantGaramond.txt`. Ninguna declara «Reserved Font Name», así que el subconjunto es lícito.

| Archivo | Familia | Autores | Origen |
|---|---|---|---|
| `EBGaramond.ttf`, `EBGaramond-Italic.ttf` | EB Garamond | The EB Garamond Project Authors (2017) | `google/fonts`, `ofl/ebgaramond` |
| `CormorantGaramond.ttf`, `CormorantGaramond-Italic.ttf` | Cormorant Garamond | The Cormorant Project Authors (2015) | `google/fonts`, `ofl/cormorantgaramond` |

**Modificación.** Son las TTF variables de Google Fonts reducidas a un subconjunto latino
(ASCII, Latin-1, comillas, guiones, `·`, `→`, `…`) con `pyftsubset`, sin hinting, conservando el eje
de peso y las características `kern liga smcp c2sc onum lnum pnum tnum case ccmp locl calt mark mkmk
frac`. Receta y medidas en `docs/05b-spike-fuentes.md`.

## Retrato

`Galeno/Assets.xcassets/retrato-galeno.imageset/retrato-galeno.jpg` es un recorte cuadrado (600 px) de
la litografía *Claude Galien* de **Vigneron** (lit. de G. Engelmann, siglo XIX), **dominio público**.
Se muestra en grises, en círculo, en la bienvenida y en «Listo». Crédito para «Acerca de»:
«Retrato: litografía de Vigneron, dominio público.»

## Icono de la app

`Galeno/Assets.xcassets/AppIcon.appiconset` usa el mismo retrato de Vigneron (dominio público), en su círculo
con doble anillo sobre pergamino. Se compuso con la forma de icono de macOS (824 px, esquinas del 22,37 %,
margen transparente y sombra suave) a partir del cuadrado de 1024 px que aportó Rafa.

## Láminas

Grabados de línea en `Assets.xcassets/plate-*.imageset`, pasados a tinta sobre transparente (el canal alfa es la
oscuridad del grabado; se tiñen con `ink-700` en claro y con el tono de papel en oscuro). Se recortaron, se les
quitó el texto y se ajustó el contraste; no se redibujó nada.

| Asset | Obra | Origen | Licencia |
|---|---|---|---|
| `plate-columnata` | *The entrance to a temple (a portico with an arch) representing access to the Bible*, grabado de John Chantry usado como portada de *The Holy Bible* (Cambridge, John Hayes, 1683): solo las columnas, los capiteles y el arco; se borró el texto del interior del arco. Se usó el escaneo de 2400 px | [Wellcome Collection, 568195i](https://wellcomecollection.org/works/uu839dq2) (IIIF `B15681956`) | Public Domain Mark (verificado en el manifiesto IIIF) |
| `plate-codice` | *Saint Luke, reading an oblong book*, grabado de Philip Galle (Amberes) | [Wellcome Collection, 6345i](https://wellcomecollection.org/works/abuhgkyq) | Public Domain Mark. Se recortó solo el libro y las manos |
| `plate-pluma` | *A seated man sharpening a quill pen*, grabado de línea con aguafuerte de Robert William Wallis según Frans van Mieris el Viejo (publicado en 1880): el hombre, la pluma, el libro y el globo, en viñeta. Se usó el archivo de 890 px que aportó Rafa | [Wellcome Collection, 46345i](https://wellcomecollection.org/works/wpjz9b6n) | Public Domain Mark (según la ficha de Wellcome) |

Si faltara alguna, `Plate` dibuja un marcador solo en Debug (`Plate.swift`).
