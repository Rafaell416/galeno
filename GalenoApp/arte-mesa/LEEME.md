# Arte de la mesa del home

Los originales (Adobe Firefly Image 4, 6 oct 2026; ver `GalenoApp/THIRD_PARTY.md`) y cómo se convierten en las láminas
del catálogo (`Assets.xcassets/figura-*` y `mesa-tablero`). Nada de esta carpeta entra en la app. Todo corre en el
Mac: no se sube nada.

## Las figuras

```bash
# 1. Separar la figura de su fondo (Vision)
swift recorte.swift firefly-galeno.jpg /tmp/recorte-galeno.png

# 2. Recortar, igualar el tono y preparar la lámina para apoyarse en la mesa
#    lamina entrada salida x y ancho alto difIzq difDer franja gamma negros "contornos"
swiftc -O lamina.swift -o /tmp/lamina
/tmp/lamina /tmp/recorte-galeno.png figura-galeno.png 160 106 1280 1534 0 0 0.26 1.25 0.0 \
  "0,588 95,566 105,540 185,530 215,543 264,556 272,640 292,700 300,720 40,720 0,625"
/tmp/lamina /tmp/recorte-wedgwood.png figura-wedgwood.png 174 266 1193 1463 0 0 0.26 1.15 0.0 \
  "212,640 250,618 330,605 345,612 400,600 450,612 470,575 500,565 530,572 538,556 550,558 546,590 572,612 582,660 572,692 500,712 420,716 300,720 215,716"
/tmp/lamina /tmp/recorte-polo.png figura-polo.png 0 133 1556 1827 0.08 0.08 0.24 1.0 0.03 \
  "290,622 318,603 392,598 402,611 442,608 522,588 562,600 548,642 502,702 430,720 288,720 283,682"
```

- `x y ancho alto`: el rectángulo que se conserva, en píxeles del original (fuera el óvalo, la firma y el texto falso).
- `difIzq difDer`: cuánto se difumina cada lado que la imagen cortaba en seco.
- `franja`: la parte de abajo que se apoya en la mesa. Ahí la ropa se oscurece y se disuelve hacia la madera.
- `gamma negros`: para que las tres queden en el mismo tono.
- `contornos`: lo que **no** se disuelve —manos, puños, papel—, en píxeles de la lámina ya reducida (720 de alto). Es
  lo que hace que las manos queden encima de la mesa.

Después, en `Persona.swift`, se ajusta su `FigurePlate`: cuánto mide en la mesa (para que las cabezas queden iguales),
dónde está la mano que escribe y si va reflejada (todas miran hacia la izquierda; Wedgwood y Polo vienen mirando a
la derecha y se reflejan).

`firefly-wedgwood.jpg` es la segunda que se generó: la primera salió de frente y con fondo negro, y no casaba con las
otras dos.

## La mesa

`firefly-mesa.jpg` está vista por el lado corto, con suelo y sombra: así no caben seis personas. `mesa.swift` endereza
su tablero de madera y lo recoloca en la perspectiva diagonal de la app; el canto y las patas se pintan con la misma
madera, oscurecida, y se le añade una sombra suave.

```bash
swiftc -O mesa.swift -o /tmp/hazmesa && /tmp/hazmesa firefly-mesa.jpg mesa-tablero.png
```

Las esquinas del tablero están escritas dos veces: en `mesa.swift` y en `Mesa` (`MesaScene.swift`). Si cambia una,
cambia la otra.
