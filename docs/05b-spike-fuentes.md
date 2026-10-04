# Spike de tipografía (rediseño B1) — resultado

Fecha: 4 oct 2026. Fuente: `google/fonts` (`ofl/ebgaramond`, `ofl/cormorantgaramond`), licencia OFL.

## Hallazgos

- Las cuatro fuentes son **TTF variables** con un solo eje `wght` (EB Garamond 400–800,
  Cormorant Garamond 300–700) y **instancias con nombre** que traen nombre PostScript:
  `CormorantGaramond-SemiBold`, `CormorantGaramond-SemiBoldItalic`, `EBGaramond-Regular`,
  `EBGaramond-Medium`, `EBGaramond-Italic`, etc.
- Registradas con `CTFontManagerRegisterFontsForURL`, **`NSFont(name:)` resuelve esos nombres**
  con el peso correcto (SemiBold = 0,3; Medium = 0,2). Los nombres que usa el diseño sirven tal cual.
- **Versalitas reales:** EB Garamond y Cormorant (romana) traen `smcp`/`c2sc`; activando el
  selector de minúsculas→versalitas el ancho cambia (22,9 → 27,3 pt), o sea que sí se aplican.
  **Cormorant Garamond cursiva no trae `smcp`**: las etiquetas en versalitas van en EB Garamond.
- **Tamaño:** sin tocar ≈ 3,5 MB. Subconjunto latino (ASCII, Latin-1, comillas, guiones, `·`, `→`,
  `…`) conservando el eje y las características `kern liga smcp c2sc onum lnum pnum tnum case
  ccmp locl calt mark mkmk frac`: **≈ 0,5 MB en total** (EBGaramond 129 KB, Italic 127 KB,
  Cormorant 142 KB, Italic 110 KB), por debajo de la estimación del diseño (≈ 1,2 MB).
  Instancias estáticas de los 6 pesos usados salen a ≈ 0,45 MB: no compensan, se queda la variable.
- El subconjunto con `--name-IDs='*' --name-legacy` conserva las instancias con nombre
  (sin eso se pierden los nombres PostScript).

## Decisión

Embeber las **4 variables subconjuntadas** (≈ 0,5 MB), accesibles por nombre PostScript, con
fallback a `Font.system(design: .serif)` si `NSFont(name:)` devuelve `nil`.

## Receta (reproducible)

```bash
U="U+0020-007E,U+00A0-00FF,U+0131,U+0152-0153,U+02C6,U+02DA,U+02DC,U+2010-2015,U+2018-201E,U+2020-2022,U+2026,U+2030,U+2039-203A,U+20AC,U+2122,U+2190-2193,U+2212,U+00B7"
F="kern,liga,smcp,c2sc,onum,lnum,pnum,tnum,case,ccmp,locl,calt,mark,mkmk,frac"
pyftsubset EBGaramond[wght].ttf --unicodes="$U" --layout-features="$F" \
  --no-hinting --desubroutinize --name-IDs='*' --name-legacy --output-file=EBGaramond.ttf
```

## Pendiente para la Parte 1

Copiar los 4 archivos a `GalenoApp/Galeno/Fonts/`, `ATSApplicationFontsPath = "Fonts"` (en un
`Info.plist` parcial o `INFOPLIST_KEY`), licencias OFL en `GalenoApp/THIRD_PARTY.md`, y un test
que compruebe que los nombres PostScript cargan. Con la fuente en el paquete hay que confirmar
que `.smallCaps()` de SwiftUI actúa sobre estas fuentes (a nivel `NSFont` ya está verificado).
