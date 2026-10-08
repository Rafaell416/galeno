# Entregar Galeno: firma y notarización

Cómo sale el DMG que se le da a un cliente. Lo hace `scripts/build-release.sh`; aquí está lo que hay que tener
antes y qué significa cada paso. Para un DMG de demo, sin firma de Apple, sigue valiendo `scripts/hacer-dmg-demo.sh`.

## Por qué hace falta

Un Mac no abre una app descargada de internet si no puede comprobar dos cosas: **quién la hizo** (la firma, con un
certificado «Developer ID» que Apple le da a un desarrollador identificado) y **que Apple la revisó** en busca de
software malicioso (la notarización). Sin eso, quien la descarga ve «no se puede abrir porque Apple no puede
comprobar que no contiene software malicioso», y hay que enseñarle a saltárselo. Con eso, se abre con un solo aviso.

## Lo que tienes que tener (una sola vez)

1. **Estar en el Apple Developer Program** (de pago, anual). Los certificados «Apple Development» que da una cuenta
   gratuita sirven para correr la app en tu Mac, no para entregarla.
2. **El certificado «Developer ID Application»** en el llavero de este Mac. En Xcode: Settings → Accounts → tu cuenta →
   Manage Certificates → `+` → Developer ID Application. Solo lo puede crear el titular de la cuenta. Comprueba que está:

   ```bash
   security find-identity -v -p codesigning
   ```

   Tiene que salir una línea como `"Developer ID Application: Tu Nombre (ABCDE12345)"`. Los diez caracteres del
   paréntesis son tu **Team ID**.
3. **Una contraseña de app** para notarizar: en account.apple.com → Inicio de sesión y seguridad → Contraseñas de
   apps. No es la contraseña de tu Apple ID.
4. **Guardar esas credenciales en el llavero**, con el nombre de perfil que quieras (aquí, `galeno-notary`). El comando
   te pide la contraseña de app y la guarda él: no va en ningún archivo.

   ```bash
   xcrun notarytool store-credentials "galeno-notary" --apple-id "tu@correo.com" --team-id "ABCDE12345"
   ```
5. **create-dmg**, que maqueta el disco:

   ```bash
   brew install create-dmg
   ```
6. **Tus datos de firma** en `scripts/release.env` (no se commitea): copia `scripts/release.env.example` y pon el
   nombre exacto del certificado, el Team ID y el nombre del perfil. Ninguna contraseña.

## Compilar y entregar

```bash
scripts/build-release.sh
```

Deja `build/release/Galeno-<versión>.dmg`, firmado, notarizado y grapado. Se niega a correr con cambios sin commitear:
lo que se entrega tiene que corresponder a un commit.

Para entender la firma sin esperar a Apple, por partes:

| Comando | Hasta dónde llega |
|---|---|
| `scripts/build-release.sh --ensayo` | Todos los pasos con firma «ad hoc», sin certificado. Para ver que la máquina compila y empaqueta. Lo que sale **no se entrega**. |
| `scripts/build-release.sh --sin-notarizar` | Firma de verdad con tu Developer ID y crea el DMG. No lo manda a Apple. |
| `scripts/build-release.sh` | Todo. |
| `scripts/build-release.sh --solo-appcast` | Solo el último paso, sobre el disco ya notarizado de la corrida anterior: para reintentarlo, o tras escribir las notas, sin volver a compilar. |
| `scripts/build-release.sh --sin-actualizaciones` | Deja entregar una app que **no sabe actualizarse sola** (el appcast sigue en la dirección de relleno). Solo para pruebas. |

## Entregar a mano (hoy, sin sitio)

Mientras el appcast no tenga una dirección pública (ver «Actualizaciones» más abajo), las apps instaladas **no se
actualizan solas**: cada versión se entrega a mano. Es lo que se hace hoy, y funciona.

1. **En `main`, con todo mergeado y el árbol limpio** (`git status` sin cambios: el script se niega si no).
2. **Sube la versión si toca**: `CURRENT_PROJECT_VERSION` en el proyecto de Xcode (siempre, cada entrega) y
   `MARKETING_VERSION` (la visible: hoy **0.0.1**). Si cambió el bridge de WhatsApp, `whatsapp-bridge/version.go`.
3. **Compila, firma y notariza**:

   ```bash
   scripts/build-release.sh --sin-actualizaciones
   ```

   Tarda unos minutos (casi todo es esperar a Apple). Deja `build/release/Galeno-<versión>.dmg`. Hace falta el
   certificado y el perfil de `notarytool` de «Lo que tienes que tener».
4. **Pruébalo como lo vería un cliente**: pásalo por AirDrop a otro Mac (eso lo marca como descargado) y ábrelo. Si no
   tienes otro Mac, al menos: `spctl --assess --type open --context context:primary-signature -v build/release/Galeno-<versión>.dmg`
   debe decir `accepted` y `source=Notarized Developer ID`.
5. **Entrégalo**: AirDrop, o un enlace de tu nube. Quien instala por **primera vez** abre el disco y arrastra Galeno a
   Aplicaciones.
6. **Quien ya tenía Galeno** corre además `scripts/instalar-desde-cero.sh` (ver más abajo): deja el Mac como nuevo y
   guarda aparte la memoria de sus agentes.
7. **Anota** en `HANDOFF.md` qué versión y qué bridge se entregó y a quién.

### Instalar desde cero a quien ya tenía Galeno

`scripts/instalar-desde-cero.sh` es para las personas que tienen una versión anterior. **Se le manda junto con el disco**
y se corre una vez, en Terminal:

```bash
bash ~/Downloads/instalar-desde-cero.sh
```

(Con `bash` por delante no hace falta darle permisos ni saltarse ningún aviso de macOS. Busca el `Galeno-….dmg` más nuevo
en Descargas; si está en otro sitio: `bash instalar-desde-cero.sh /ruta/Galeno-0.0.1.dmg`. Con `--dry` solo enseña lo
que haría.)

- **Antes de tocar nada** abre el disco y comprueba que Galeno está firmado y notarizado. Si no, se detiene.
- Enseña lo que va a quitar y pide escribir «si».
- **Guarda una copia de la memoria de cada agente** en `Documentos/Galeno-respaldo-<fecha>/`.
- **Todo va a la Papelera, nada se borra** (la app vieja, los agentes, sus conversaciones en la app de Claude, el estado de
  Galeno con la sesión de WhatsApp y su historial local). No vacía la Papelera.
- **No toca los servidores MCP de Claude Code** (Notion, Slack…): pueden ser de otros proyectos de esa persona.
- Instala la versión nueva en Aplicaciones y la abre. Al final recuerda lo que solo se puede hacer a mano: cerrar la
  sesión vieja en el teléfono (WhatsApp → Dispositivos vinculados) y reiniciar la app de Claude.
- Solo toca carpetas de `~/Galeno` que tengan `AGENTS.md` (las que generó Galeno): una carpeta suya que no lo sea se queda.

**Probarlo sin riesgo**: el script tiene ganchos para correr en un Mac de mentira (`GALENO_PRUEBA=1`,
`GALENO_APLICACIONES`, `GALENO_PAPELERA`, y `HOME` apuntando a una carpeta temporal). Así se probó el 8 oct 2026. Lo que
ese modo no ejercita es el movimiento a la Papelera con Finder, que es el mismo de `scripts/reset-pruebas.sh`.

## Cuando quieras que se actualicen solas

La app se actualiza sola cuando puede leer el **appcast**: un archivo de texto (XML) **publicado en internet** que dice
«la última versión es la X, se descarga de aquí, y esta es su firma». La app lo mira al abrir. Para eso hacen falta tres
cosas, y hoy falta la primera:

1. **Una dirección pública con `https`** donde viva ese archivo, y otra para los discos (`.dmg`). Tienen que poder abrirse
   sin iniciar sesión: **un repositorio privado de GitHub no sirve**. Opciones: el sitio de venta de Galeno (carpeta `site/`,
   Fase 9) con `/appcast.xml` y `/descargas/`; un repositorio público aparte con GitHub Pages; o un almacenamiento público
   (Cloudflare R2, S3). Da igual cuál: es solo «un sitio donde dejar dos tipos de archivo».
2. **Esa dirección escrita en la app** (`SUFeedURL` en `GalenoApp/Galeno-Info.plist`) **y en `scripts/release.env`**
   (`GALENO_DOWNLOAD_URL_PREFIX`).
3. **La clave de Sparkle** (la tienes, ver «Actualizaciones»).

Hasta que exista, la dirección es de relleno y `build-release.sh` exige `--sin-actualizaciones`. **Ojo:** quien instale una
versión con la dirección de relleno **no se actualiza solo** hasta que le pases a mano una versión que ya traiga la
dirección real; desde esa en adelante sí. Por eso conviene tener la dirección antes de entregar a más gente de la que
puedas alcanzar uno por uno.

## Qué hace, paso a paso

1. **Compila el motor** (`GalenoCore`).
2. **Compila el bridge de WhatsApp** universal: un solo ejecutable de Go que corre en Apple Silicon y en Intel.
3. **Compila la app** en Release, universal, y la copia a una carpeta de trabajo con el bridge recién compilado dentro
   (`Galeno.app/Contents/Resources/galeno-whatsapp`).
4. **Firma lo de dentro: el bridge y Sparkle.** Van primero porque están dentro de la app: se firma de dentro hacia
   fuera. Sparkle es un framework con cuatro ayudantes (dos servicios XPC, el instalador y una app pequeña), que se
   firman cada uno por separado y en su orden. `--options runtime`
   activa el *hardened runtime* (protecciones que Apple exige para notarizar) y `--timestamp` pide un sello de tiempo,
   para que la firma siga valiendo cuando caduque el certificado.
5. **Firma la app**, con sus entitlements. Sin `--deep`: firmar «todo de golpe» pisa las firmas de dentro y es una de
   las causas típicas de que Apple rechace la notarización.
6. **Comprueba la firma**: que está íntegra, que la app y el bridge llevan el hardened runtime, tu equipo y el sello de
   tiempo, y que la app no lleva `get-task-allow` (el permiso de depuración, que Apple no notariza).
7. **Crea el DMG** con `create-dmg` y lo firma también: es lo que el usuario descarga.
8. **Notariza**: sube el DMG a Apple y espera el veredicto (unos minutos). Si lo rechaza, el script enseña el informe
   de Apple con el motivo de cada archivo.
9. **Grapa y verifica.** Grapar pega al DMG el comprobante de Apple, para que abra sin internet. Después le pregunta a
   Gatekeeper (`spctl`) qué haría con el disco y con la app tal como va dentro, que es lo que vería un cliente.
10. **Actualiza el appcast** (`site/appcast.xml`): firma el disco con la clave de Sparkle y añade su entrada, con las
    notas de la versión. Es lo que miran las apps ya instaladas para saber que hay una versión nueva.

## Actualizaciones (Sparkle)

Las apps ya instaladas se actualizan solas: al abrir, y desde «Buscar actualizaciones…» (menú Galeno, o Ajustes), miran
el **appcast**, un archivo público con la lista de versiones y de dónde se descarga cada una. Si hay una más nueva la
descargan, comprueban su firma y se reemplazan.

**Dos firmas distintas.** La de Apple (Developer ID y notarización) dice quién hizo la app. La de Sparkle (EdDSA) dice
que *esta actualización* la publicó Galeno: la app solo instala lo que venga firmado con la clave cuya mitad pública
lleva dentro (`SUPublicEDKey` en `GalenoApp/Galeno-Info.plist`). Sin esa segunda firma, quien tomara el servidor
podría empujar una app falsa a todos los clientes.

**La clave privada de Sparkle** se generó una vez y vive en el **llavero de inicio de sesión** de este Mac, en el
elemento «Private key for signing Sparkle updates», cuenta `galeno`. No está en el repo ni en ningún archivo.

- **Sin ella no se puede publicar ninguna actualización que las apps instaladas acepten.** Guarda una copia: expórtala
  a un archivo, métela en tu gestor de contraseñas y manda el archivo a la Papelera.

  ```bash
  build/release/derived/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account galeno -x ~/Desktop/sparkle-galeno.key
  ```
- **Como secreto de GitHub**, para cuando el release corra en GitHub Actions (hoy corre en este Mac y no hace falta):

  ```bash
  gh secret set SPARKLE_ED_PRIVATE_KEY < ~/Desktop/sparkle-galeno.key
  ```
- Para ver la pública otra vez: `generate_keys --account galeno -p`. Volver a correr `generate_keys` no la cambia.

**Lo que no viaja.** La petición al appcast no lleva perfil del sistema ni ningún dato del usuario
(`SUEnableSystemProfiling` en falso, y otra vez en `UpdatesModel`). Va lo que cualquier petición web, y el nombre y la
versión de la app en la cabecera. La dirección del appcast no lleva parámetros.

**Mientras el sitio no exista**, `SUFeedURL` es una dirección de relleno (`https://galeno.invalid/appcast.xml`; `.invalid`
es un dominio reservado que nunca existe). Con ella la app no arranca Sparkle, «Buscar actualizaciones…» sale apagado, y
`build-release.sh` **se niega a entregar** salvo con `--sin-actualizaciones`: una app que sale sin saber actualizarse
obliga después a avisar a cada cliente a mano.

**Cuando el sitio exista** (Fase 9):

1. Pon la dirección de verdad en `GalenoApp/Galeno-Info.plist` (`SUFeedURL`, por `https`).
2. Pon en `scripts/release.env` de dónde se descargarán los discos: `GALENO_DOWNLOAD_URL_PREFIX="https://…/descargas/"`.

**Cada versión nueva:**

1. Sube `CURRENT_PROJECT_VERSION` en el proyecto de Xcode (y `MARKETING_VERSION` si toca). Sparkle decide qué es «más
   nuevo» por ese número; el script se niega si el appcast ya lo tiene.
2. Si cambió el bridge de WhatsApp, sube su versión en `whatsapp-bridge/version.go`.
3. Escribe las novedades en `docs/releases/<versión>.md`, una por renglón. Es opcional.
4. Corre `scripts/build-release.sh`.
5. Sube el disco a la dirección que el script enseña al final, y commitea y publica `site/appcast.xml`.

Las notas de cada versión dicen siempre qué versión del bridge lleva y **si cambió** respecto a la anterior
(«sin cambios», o «de la 0.3.0 a la 0.4.0»): el script lo saca comparando con lo que dice el propio appcast.

## Entitlements: por qué van vacíos

`GalenoApp/Galeno.entitlements` no declara nada, y es a propósito.

- **Red y lanzar procesos no piden permiso.** Esos entitlements (`com.apple.security.network.client` y compañía) son
  del *sandbox* de la tienda. Galeno se entrega fuera de la tienda y sin sandbox: puede usar la red y lanzar `claude` y
  el bridge sin declararlo.
- **El hardened runtime no es un entitlement**: se activa al firmar (`--options runtime`). Lo que sí son entitlements
  son sus *excepciones* —cargar código sin firmar, compilar en caliente, variables `DYLD_`, mandar Apple Events a otras
  apps—, y Galeno no necesita ninguna. El bridge de Go tampoco.
- **Añadir uno es abrir una puerta.** Si un día algo lo pide (por ejemplo, controlar otra app con Apple Events), se
  añade solo ese, con el motivo escrito aquí.

## Lo que hay que saber

- **El bridge se usa desde una copia** en `~/Library/Application Support/Galeno/bin/`, no desde dentro de la app. Una
  copia conserva la firma, así que sigue valiendo.
- **Sparkle es el único framework que el script sabe firmar.** Si un día entra otro, el script **se detiene**, para no
  entregar algo mal firmado: habrá que enseñarle ese paso.
- **Cambiar de certificado con usuarios ya instalados** (por ejemplo, pasar del de Aquiles al de Rafa) funciona porque
  las actualizaciones van firmadas con la clave de Sparkle, que no cambia. Lo que no se puede perder es esa clave.
- **La versión del DMG** sale de la app (`MARKETING_VERSION` en el proyecto de Xcode).
- **Probarlo como un cliente**: la verificación del script corre en el Mac que firmó. La prueba de verdad es
  descargar el DMG en otro Mac (o pasarlo por AirDrop, que también lo marca como descargado) y abrirlo: fila «Mac
  limpio» de `docs/QA.md`.

## Si algo falla

| Mensaje | Qué pasa |
|---|---|
| `no encuentro «…» en el llavero` | El nombre de `release.env` no coincide con el del certificado. Cópialo tal cual de `security find-identity -v -p codesigning`. |
| `notarytool no acepta el perfil` | No se guardaron las credenciales, o la contraseña de app se revocó. Repite el paso 4 de arriba. |
| La firma pide la contraseña del llavero | Es macOS preguntando si `codesign` puede usar tu clave privada. «Permitir siempre». |
| `el appcast sigue en la dirección de relleno` | El sitio todavía no tiene dirección para el appcast. Ponla en `Galeno-Info.plist`, o usa `--sin-actualizaciones` si es una prueba. |
| `la clave de Sparkle del llavero … no es la pareja` | La clave del llavero no corresponde a la pública de la app: con ella las apps rechazarían la actualización. Recupera la clave buena de tu copia (`generate_keys --account galeno -f archivo`). |
| El llavero pregunta por «generate_appcast» | Es la herramienta de Sparkle pidiendo la clave para firmar. «Permitir siempre». |
| `la notarización no pasó` | El script enseña el informe de Apple. Lo más común: un ejecutable sin firmar o sin hardened runtime dentro de la app. |
| `create-dmg` se queda esperando | Maqueta la ventana con Finder y macOS pide permiso para controlarlo la primera vez. Acéptalo. |
