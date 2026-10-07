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

## Qué hace, paso a paso

1. **Compila el motor** (`GalenoCore`).
2. **Compila el bridge de WhatsApp** universal: un solo ejecutable de Go que corre en Apple Silicon y en Intel.
3. **Compila la app** en Release, universal, y la copia a una carpeta de trabajo con el bridge recién compilado dentro
   (`Galeno.app/Contents/Resources/galeno-whatsapp`).
4. **Firma el bridge.** Va primero porque está dentro de la app: se firma de dentro hacia fuera. `--options runtime`
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
- **Cuando entre Sparkle** (las actualizaciones), la app llevará un framework con ayudantes dentro, que se firman como
  paquete y en su propio orden. El script hoy **se detiene** si encuentra un framework en la app, para no entregar algo
  mal firmado: habrá que enseñarle ese paso.
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
| `la notarización no pasó` | El script enseña el informe de Apple. Lo más común: un ejecutable sin firmar o sin hardened runtime dentro de la app. |
| `create-dmg` se queda esperando | Maqueta la ventana con Finder y macOS pide permiso para controlarlo la primera vez. Acéptalo. |
