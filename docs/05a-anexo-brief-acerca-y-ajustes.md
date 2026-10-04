# Anexo al brief de rediseño — dos superficies más
### Para pegar como mensaje de seguimiento en Claude Design

> Sigue con lo que estás generando. A lo que ya te pedí **súmale dos superficies pequeñas** que tienen que verse como parte de la misma familia visual en **cada una de las tres propuestas**: **«Acerca de Galeno»** y **«Ajustes»**. Son sencillas, pero son donde la marca se explica y donde el usuario toma el control de su app.

---

## 1. «Acerca de Galeno» — por qué nos llamamos así

**Para qué existe.** Que el usuario sepa **por qué la app se llama Galeno**, con el retrato y la historia, sin que estorbe el asistente. Es el lugar natural de la marca: aquí sí caben el retrato, la tipografía más caligráfica y una ilustración grande. Es también donde van los créditos que debemos mostrar.

**Dónde vive** (diséñalo como una ventana propia, no como un paso del asistente):
- Menú **Galeno ▸ Acerca de Galeno** (siempre disponible).
- En el **paso 1** del asistente, un enlace discreto bajo la bienvenida: **«¿Por qué Galeno?»**, que abre esta misma ventana. Diseña ese enlace y su lugar en la pantalla.
- A futuro, el pie del home.

**Tamaño:** ventana fija, ~**560 × 680 pt**; debe leerse sin desplazar lo esencial (el resto, con scroll).

**Contenido, en este orden:**
1. **Retrato** (litografía de Vigneron, recortado en círculo con doble anillo; reglas del logo en `docs/04` §4) + wordmark **GALENO.**
2. **Título:** «¿Por qué Galeno?»
3. **La historia** (≈ 120 palabras, abajo): una voz serena, sin hype.
4. **Un guiño visual:** una ilustración sobria que cuente el vínculo Pérgamo → pergamino → el color de fondo de la app (propón el motivo).
5. **Créditos:** «Retrato: litografía de Vigneron (siglo XIX), dominio público.»
6. **Pie técnico discreto:** versión de la app y un enlace a «Material de terceros» (licencias de logos, del bridge de WhatsApp, de las skills curadas). Aquí caben, sin competir con la historia.

**Texto base** (propón mejoras de ritmo y de jerarquía; los hechos están verificados y **no se exageran**):

| | Español | English |
|---|---|---|
| **Título** | ¿Por qué Galeno? | Why Galen? |
| **Párrafo 1** | Galeno nació en Pérgamo (hoy Turquía) en el año 129. Estudió medicina en el Asclepeion, el templo-hospital de la ciudad, fue médico de gladiadores a los 28 años y acabó ejerciendo en Roma. Escribió una obra enorme y, durante siglos, su palabra fue la referencia de la medicina. | Galen was born in Pergamon (today in Turkey) in the year 129. He studied medicine at the Asclepieion, the city's temple-hospital, became physician to gladiators at 28 and ended up practicing in Rome. He wrote an enormous body of work, and for centuries his word was medicine's reference. |
| **Párrafo 2** | Se le recuerda por observar con cuidado, ordenar lo que sabía y dejarlo escrito para que otros pudieran trabajar con ello. | He is remembered for observing carefully, putting what he knew in order and writing it down so others could build on it. |
| **Párrafo 3** | Eso quisimos para esta app: que ponga en orden lo necesario para que tu agente trabaje contigo con calma. Y un guiño: según la tradición, en Pérgamo —cuya biblioteca rivalizaba con la de Alejandría— se perfeccionó el pergamino. El fondo que ves es su color. | That is what we wanted for this app: to put in order what your agent needs so it can work with you calmly. And a nod: by tradition, parchment was perfected in Pergamon, whose library rivaled Alexandria's. The background you see is its color. |
| **Crédito** | Retrato: litografía de Vigneron (siglo XIX), dominio público. | Portrait: lithograph by Vigneron (19th century), public domain. |

> Si ves una forma mejor de contarlo, propónla. Lo que **no** cambia: nada de «padre de la medicina» (ese es Hipócrates), nada de consejos médicos, y la historia es historia, no una promesa del producto.

---

## 2. «Ajustes» — apariencia (y el idioma)

**Para qué existe.** Que el usuario elija cómo se ve la app: **Claro**, **Oscuro** o **Sistema** (sigue el modo de su Mac). La app ya trae los dos modos; falta dejar elegir.

**Dónde vive:** la ventana estándar de ajustes de macOS (**Galeno ▸ Ajustes…**, ⌘,). Ventana fija, ~**480 × 260 pt**.

**Contenido:**
1. **Apariencia** — selector de tres opciones: **Sistema · Claro · Oscuro**. Que cada opción muestre una **miniatura** (el pergamino claro, la encuadernación oscura y una mitad-mitad para «Sistema»). Texto de apoyo: «Sistema sigue la apariencia de tu Mac.»
2. **Idioma** — **Español · English** (hoy solo se elige en el paso 1). Cambia al instante, sin reiniciar.
3. Nada más. Sin cuentas, sin sincronización, sin telemetría: no hay nada de eso en Galeno.

**El cambio debe sentirse bien:** al elegir, la ventana de ajustes y el asistente cambian de modo al instante (una transición corta de opacidad, nada de destellos), y respetan «reducir movimiento».

| | Español | English |
|---|---|---|
| **Título de la ventana** | Ajustes | Settings |
| **Sección** | Apariencia | Appearance |
| **Opciones** | Sistema · Claro · Oscuro | System · Light · Dark |
| **Apoyo** | «Sistema» sigue la apariencia de tu Mac. | “System” follows your Mac's appearance. |
| **Sección** | Idioma | Language |

---

## 3. Qué entregar de esto

Para **cada una de las tres propuestas**:
1. **«Acerca de Galeno»** en claro y oscuro, con el texto base (ES) y una muestra (EN), y la ilustración propuesta.
2. **El enlace «¿Por qué Galeno?»** dentro de la pantalla 1.
3. **«Ajustes»** en claro y oscuro, con las tres opciones y sus miniaturas, y el estado de cada opción (normal, seleccionada, foco).
4. Una nota sobre **cómo cambia el diseño al pasar de claro a oscuro** (qué cambia del retrato y de la ilustración).
5. Costo de implementación (SwiftUI): qué es nativo y qué control propio hace falta.

Y en la **comparación final**: cuál propuesta cuenta mejor la historia de Galeno sin parecer un disfraz.
