#!/bin/bash
# Compila, firma, empaqueta y notariza Galeno para entregarlo: build/release/Galeno-<versión>.dmg
#
#   scripts/build-release.sh                  todo: compila, firma, DMG, notariza, grapa y verifica
#   scripts/build-release.sh --sin-notarizar  hasta el DMG firmado: para ver la firma sin esperar a Apple
#   scripts/build-release.sh --ensayo         sin certificado: firma «ad hoc» y no notariza. Sirve para ensayar los
#                                             pasos; lo que sale NO se puede entregar
#   scripts/build-release.sh --con-cambios    deja compilar con cambios sin commitear (por defecto se niega)
#   scripts/build-release.sh --solo-appcast   solo el último paso, sobre el disco ya notarizado de la corrida anterior:
#                                             para reintentarlo, o tras escribir las notas, sin volver a compilar
#   scripts/build-release.sh --sin-actualizaciones   deja entregar una app que NO sabe actualizarse sola (el appcast
#                                             sigue con la dirección de relleno). Solo para pruebas: ver docs/RELEASE.md
#
# Qué necesita en ESTE Mac: Xcode, Go, create-dmg (`brew install create-dmg`), el certificado «Developer ID
# Application» en el llavero, y las credenciales de notarización guardadas con `xcrun notarytool store-credentials`.
# Los datos van en scripts/release.env (ver release.env.example) o en variables de entorno. Paso a paso: docs/RELEASE.md.
#
# AQUÍ NO HAY CONTRASEÑAS, ni se piden: la firma usa el certificado del llavero y la notarización, el perfil que
# guardó notarytool. No añadir ninguna a este archivo ni a release.env.
#
# El orden importa. Se firma de dentro hacia fuera: primero el bridge de WhatsApp (un ejecutable de Go que va dentro
# de la app) y las piezas de Sparkle, después la app, y al final el disco. Firmar la app antes que lo de dentro, o usar
# `--deep`, deja una firma que Apple rechaza al notarizar.
#
# Al final firma el disco con la clave EdDSA de Sparkle (la del llavero, cuenta «galeno») y actualiza el appcast
# (site/appcast.xml), con las notas de la versión y si el bridge de WhatsApp cambió.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MODE=release
ALLOW_DIRTY=0
ALLOW_NO_UPDATES=0
for arg in "$@"; do
  case "$arg" in
    --sin-notarizar) MODE=signed ;;
    --ensayo) MODE=rehearsal ;;
    --con-cambios) ALLOW_DIRTY=1 ;;
    --solo-appcast) MODE=appcast ;;
    --sin-actualizaciones) ALLOW_NO_UPDATES=1 ;;
    -h|--help) sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Opción desconocida: $arg (usa --sin-notarizar, --ensayo, --solo-appcast, --con-cambios, --sin-actualizaciones o --help)"; exit 2 ;;
  esac
done

step() { echo; echo "== $1 =="; }
fail() { echo "✗ $1" >&2; exit 1; }

# shellcheck disable=SC1091
[ -f scripts/release.env ] && . scripts/release.env
IDENTITY="${GALENO_SIGN_IDENTITY:-}"
TEAM_ID="${GALENO_TEAM_ID:-}"
PROFILE="${GALENO_NOTARY_PROFILE:-}"
ENTITLEMENTS="$ROOT/GalenoApp/Galeno.entitlements"
BRIDGE_ID="com.galeno.whatsapp-bridge"
# Sparkle: la cuenta del llavero donde está la clave privada de las actualizaciones, de dónde se descargarán los discos,
# y el appcast, que vive con el sitio.
SPARKLE_ACCOUNT="${GALENO_SPARKLE_ACCOUNT:-galeno}"
DOWNLOAD_PREFIX="${GALENO_DOWNLOAD_URL_PREFIX:-}"
INFO_PLIST="$ROOT/GalenoApp/Galeno-Info.plist"
APPCAST="$ROOT/site/appcast.xml"

# Todo lo que este script crea o borra vive aquí dentro. Rutas fijas a partir de la raíz del repo: nunca una variable
# que, vacía, apunte a otra parte.
OUT="$ROOT/build/release"
DERIVED="$OUT/derived"
STAGE="$OUT/stage"
UPDATES="$OUT/updates"
APP="$STAGE/Galeno.app"
case "$OUT" in */build/release) ;; *) fail "la carpeta de salida no es la esperada: $OUT" ;; esac

# ---------------------------------------------------------------------------------------------------------------
step "0/10 Antes de empezar"
# Lo que puede fallar se mira ahora, no después de diez minutos compilando.
for tool in xcodebuild go lipo codesign hdiutil; do command -v "$tool" >/dev/null || fail "falta $tool"; done

if [ "$MODE" = rehearsal ]; then
  IDENTITY="-"
  echo "  ENSAYO: firma ad hoc, sin notarizar. Lo que salga no se puede entregar."
elif [ "$MODE" = appcast ]; then
  echo "  SOLO EL APPCAST: se usa el disco ya notarizado de build/release."
else
  [ -n "$IDENTITY" ] || fail "falta GALENO_SIGN_IDENTITY (copia scripts/release.env.example a scripts/release.env)"
  case "$IDENTITY" in
    "Developer ID Application:"*) ;;
    *) fail "«$IDENTITY» no es un certificado «Developer ID Application». Los «Apple Development» sirven para correr la app en tu Mac, no para entregarla." ;;
  esac
  # Se guarda la lista antes de buscar en ella: con `pipefail`, un `grep -q` que encuentra pronto corta al comando de
  # la izquierda y la tubería entera cuenta como fallo.
  IDENTITIES="$(security find-identity -v -p codesigning)"
  case "$IDENTITIES" in
    *"\"$IDENTITY\""*) ;;
    *) fail "no encuentro «$IDENTITY» en el llavero. Mira los que hay con: security find-identity -v -p codesigning" ;;
  esac
  [ -n "$TEAM_ID" ] || fail "falta GALENO_TEAM_ID"
  case "$IDENTITY" in *"($TEAM_ID)") ;; *) fail "el Team ID $TEAM_ID no es el del certificado «$IDENTITY»" ;; esac
  command -v create-dmg >/dev/null || fail "falta create-dmg. Instálalo con: brew install create-dmg"
  echo "  certificado: $IDENTITY"
fi
if [ "$MODE" = release ]; then
  [ -n "$PROFILE" ] || fail "falta GALENO_NOTARY_PROFILE"
  # Una consulta barata que solo sale bien si las credenciales guardadas valen.
  xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 \
    || fail "notarytool no acepta el perfil «$PROFILE». Guárdalo con: xcrun notarytool store-credentials \"$PROFILE\" (docs/RELEASE.md)"
  echo "  perfil de notarización: $PROFILE"
fi
[ -f "$ENTITLEMENTS" ] || fail "falta $ENTITLEMENTS"

# ¿La app que sale sabrá actualizarse? Si el appcast sigue en la dirección de relleno (`.invalid`), no: y una app
# entregada así obliga después a avisar a cada cliente a mano (docs/03 §4f). Por eso no se entrega sin decirlo.
FEED="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$INFO_PLIST")"
PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$INFO_PLIST")"
UPDATES_ON=1
case "$FEED" in
  https://*.invalid/*) UPDATES_ON=0 ;;
  https://*) ;;
  *) fail "la dirección del appcast ($FEED) tiene que ser https" ;;
esac
if [ "$UPDATES_ON" -eq 0 ]; then
  [ "$MODE" != appcast ] || fail "el appcast sigue en la dirección de relleno ($FEED): no hay appcast que actualizar"
  if [ "$MODE" = release ] && [ "$ALLOW_NO_UPDATES" -ne 1 ]; then
    fail "el appcast sigue en la dirección de relleno ($FEED): la app que saldría no sabe actualizarse. Pon la del sitio en GalenoApp/Galeno-Info.plist, o pasa --sin-actualizaciones si es solo una prueba."
  fi
  echo "  ¡OJO! El appcast es de relleno: esta app NO se actualizará sola."
elif [ "$MODE" = release ] || [ "$MODE" = appcast ]; then
  case "$DOWNLOAD_PREFIX" in
    https://*/) ;;
    *) fail "falta GALENO_DOWNLOAD_URL_PREFIX (https://…/, acabada en /): de dónde descargarán los clientes cada disco" ;;
  esac
fi

COMMIT="$(git rev-parse --short HEAD)"
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  [ "$ALLOW_DIRTY" -eq 1 ] || [ "$MODE" = rehearsal ] || [ "$MODE" = appcast ] \
    || fail "hay cambios sin commitear: lo que se entrega tiene que corresponder a un commit. (Para probar: --con-cambios)"
  COMMIT="$COMMIT-con-cambios"
fi
mkdir -p "$OUT"

BRIDGE_SRC="$ROOT/whatsapp-bridge/bin/galeno-whatsapp"
if [ "$MODE" = appcast ]; then
  # Nada se compila ni se firma: se toma lo que dejó la corrida anterior, y se comprueba que es un disco entregable.
  [ -d "$APP" ] && [ -x "$BRIDGE_SRC" ] || fail "no hay una corrida anterior en build/release: corre primero el script entero"
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
  BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
  DMG="$OUT/Galeno-$VERSION.dmg"
  [ -f "$DMG" ] || fail "no encuentro $DMG"
  xcrun stapler validate "$DMG" >/dev/null 2>&1 || fail "$DMG no está notarizado y grapado: no se anuncia en el appcast"
  echo "  Galeno $VERSION ($BUILD_NUMBER), disco: $DMG"
else
# ---------------------------------------------------------------------------------------------------------------
step "1/10 El motor (GalenoCore)"
swift build -c release --package-path GalenoCore 2>&1 | tail -1

step "2/10 El bridge de WhatsApp (universal: Apple Silicon e Intel)"
make -C whatsapp-bridge universal >/dev/null
echo "  arquitecturas: $(lipo -archs "$BRIDGE_SRC")"
[ "$(lipo -archs "$BRIDGE_SRC" | tr ' ' '\n' | sort | tr '\n' ' ')" = "arm64 x86_64 " ] || fail "el bridge no es universal"

step "3/10 La app (Release, universal)"
# Xcode la deja firmada ad hoc; la firma de verdad se pone después, pieza a pieza.
xcodebuild -project GalenoApp/Galeno.xcodeproj -scheme Galeno -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$DERIVED" ONLY_ACTIVE_ARCH=NO build \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true
BUILT="$DERIVED/Build/Products/Release/Galeno.app"
[ -d "$BUILT" ] || fail "no se generó Galeno.app"

# La carpeta de trabajo se rehace de cero. Se quita con su ruta entera, comprobada arriba.
rm -rf "$ROOT/build/release/stage"
mkdir -p "$STAGE"
ditto "$BUILT" "$APP"
# El bridge, dentro de la app. La compilación ya lo copia; aquí se asegura que es exactamente el recién compilado.
cp -f "$BRIDGE_SRC" "$APP/Contents/Resources/galeno-whatsapp"
chmod 755 "$APP/Contents/Resources/galeno-whatsapp"
# Atributos extendidos (cuarentena, etiquetas de Finder): estropean la firma.
xattr -cr "$APP"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
echo "  Galeno $VERSION ($BUILD_NUMBER), commit $COMMIT"
echo "  arquitecturas de la app: $(lipo -archs "$APP/Contents/MacOS/Galeno")"
[ -f "$APP/Contents/Resources/skills/catalog.json" ] || fail "faltan las skills dentro de la app"
# Sparkle decide si algo es «más nuevo» por el número de compilación: uno que ya está en el appcast no se ofrecería.
if [ "$MODE" = release ] && [ "$UPDATES_ON" -eq 1 ] && [ -f "$APPCAST" ]; then
  case "$(cat "$APPCAST")" in
    *"<sparkle:version>$BUILD_NUMBER</sparkle:version>"*)
      fail "el appcast ya tiene la compilación $BUILD_NUMBER: sube CURRENT_PROJECT_VERSION en el proyecto de Xcode" ;;
  esac
fi
# `grep -c` lee hasta el final: un `grep -q` cortaría a `strings` y, con `pipefail`, la comprobación no saltaría nunca.
if [ "$(strings -a "$APP/Contents/MacOS/Galeno" | grep -c "galeno-fake-connect" || true)" != "0" ]; then
  fail "la app lleva las opciones de prueba de Debug: no es una compilación Release"
fi

# ---------------------------------------------------------------------------------------------------------------
step "4/10 Firmar lo de dentro: el bridge y cualquier otro ejecutable"
# `--options runtime` es el «hardened runtime», que Apple exige para notarizar. `--timestamp` pide a Apple un sello
# de tiempo: sin él la firma deja de valer cuando caduque el certificado. La firma ad hoc del ensayo no lo admite.
if [ "$MODE" = rehearsal ]; then STAMP="--timestamp=none"; else STAMP="--timestamp"; fi

# Todo ejecutable Mach-O suelto que no sea el principal: hoy, el bridge. Los frameworks se firman aparte, como paquete.
NESTED=()
while IFS= read -r file; do
  [ "$file" = "$APP/Contents/MacOS/Galeno" ] && continue
  case "$(file -b "$file")" in *Mach-O*) NESTED+=("$file") ;; esac
done < <(find "$APP/Contents" -type f \( -perm +111 -o -name "*.dylib" \) ! -path "*/Resources/skills/*" ! -path "*/Contents/Frameworks/*")
[ ${#NESTED[@]} -gt 0 ] || fail "no encontré el bridge dentro de la app"
for file in "${NESTED[@]}"; do
  if [ "$(basename "$file")" = "galeno-whatsapp" ]; then
    codesign --force --options runtime "$STAMP" --identifier "$BRIDGE_ID" --sign "$IDENTITY" "$file"
  else
    codesign --force --options runtime "$STAMP" --sign "$IDENTITY" "$file"
  fi
  echo "  firmado: ${file#"$APP"/}"
done

# Sparkle: un framework con ayudantes dentro (dos servicios XPC, el instalador y una app pequeña). Cada uno se firma
# por separado y en este orden —lo de más adentro primero—, como pide su documentación. El descargador conserva sus
# propios entitlements. Cualquier otro framework detiene el script: no se entrega nada que no se sepa firmar.
FRAMEWORKS="$APP/Contents/Frameworks"
if [ -d "$FRAMEWORKS" ]; then
  while IFS= read -r bundle; do
    [ "$(basename "$bundle")" = "Sparkle.framework" ] \
      || fail "la app lleva $(basename "$bundle"), que este script no sabe firmar. Enséñale cómo antes de entregar."
  done < <(find "$FRAMEWORKS" -mindepth 1 -maxdepth 1)
  SPARKLE="$FRAMEWORKS/Sparkle.framework"
  SPARKLE_VERSION="$(readlink "$SPARKLE/Versions/Current")"
  INSIDE="$SPARKLE/Versions/$SPARKLE_VERSION"
  codesign --force --options runtime "$STAMP" --sign "$IDENTITY" "$INSIDE/XPCServices/Installer.xpc"
  codesign --force --options runtime "$STAMP" --preserve-metadata=entitlements --sign "$IDENTITY" "$INSIDE/XPCServices/Downloader.xpc"
  codesign --force --options runtime "$STAMP" --sign "$IDENTITY" "$INSIDE/Autoupdate"
  codesign --force --options runtime "$STAMP" --sign "$IDENTITY" "$INSIDE/Updater.app"
  codesign --force --options runtime "$STAMP" --sign "$IDENTITY" "$SPARKLE"
  echo "  firmado: Sparkle.framework y sus cuatro ayudantes"
fi

step "5/10 Firmar la app"
# Sin `--deep`: lo de dentro ya está firmado, cada cosa con lo suyo. Los entitlements van vacíos a propósito
# (docs/RELEASE.md dice por qué): fuera de la tienda, y sin sandbox, la red y lanzar procesos no piden permiso.
codesign --force --options runtime "$STAMP" --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP"
echo "  firmada: Galeno.app"

step "6/10 Comprobar la firma"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | sed 's/^/  /'
for target in "$APP" "$APP/Contents/Resources/galeno-whatsapp"; do
  info="$(codesign -dvv "$target" 2>&1)"
  grep -q "flags=.*runtime" <<<"$info" || fail "$(basename "$target") no lleva el hardened runtime"
  if [ "$MODE" != rehearsal ]; then
    grep -q "^TeamIdentifier=$TEAM_ID$" <<<"$info" || fail "$(basename "$target") no está firmado por el equipo $TEAM_ID"
    grep -q "^Timestamp=" <<<"$info" || fail "$(basename "$target") no lleva sello de tiempo"
  fi
done
# `get-task-allow` deja que un depurador se enganche a la app: Apple no notariza nada que lo lleve.
SIGNED_ENTITLEMENTS="$(codesign -d --entitlements - --xml "$APP" 2>/dev/null || true)"
case "$SIGNED_ENTITLEMENTS" in
  *get-task-allow*) fail "la app lleva get-task-allow (es de las compilaciones de depuración)" ;;
esac
echo "  hardened runtime en la app y en el bridge; sin get-task-allow"

# ---------------------------------------------------------------------------------------------------------------
step "7/10 El disco (DMG)"
if [ "$MODE" = rehearsal ]; then DMG="$OUT/Galeno-$VERSION-ENSAYO.dmg"; else DMG="$OUT/Galeno-$VERSION.dmg"; fi
[ ! -e "$DMG" ] || mv -f "$DMG" "$DMG.anterior"   # el de la corrida anterior se aparta, no se borra
if command -v create-dmg >/dev/null; then
  # create-dmg maqueta la ventana (el icono, y un acceso a Aplicaciones para arrastrar).
  create-dmg --volname "Galeno" --window-size 540 380 --icon-size 96 \
    --icon "Galeno.app" 140 180 --app-drop-link 400 180 --hide-extension "Galeno.app" --no-internet-enable \
    "$DMG" "$STAGE" >/dev/null
else
  # Solo en el ensayo: un disco sin maquetar, para poder seguir sin instalar nada.
  echo "  (sin create-dmg: disco sin maquetar, con hdiutil)"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname "Galeno" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
fi
[ -f "$DMG" ] || fail "no se creó el DMG"
# El disco también se firma: es lo que el usuario descarga y lo primero que mira Gatekeeper.
[ "$MODE" = rehearsal ] || codesign --force --timestamp --sign "$IDENTITY" "$DMG"
echo "  $DMG ($(du -h "$DMG" | cut -f1))"

if [ "$MODE" != release ]; then
  echo
  if [ "$MODE" = rehearsal ]; then
    echo "Ensayo terminado: los pasos funcionan. Este DMG va firmado ad hoc y sin notarizar: NO se entrega."
  else
    echo "Firmado, sin notarizar. Para ver la firma:  codesign -dvv \"$APP\""
    echo "Sin notarizar, Gatekeeper todavía lo bloquea en otro Mac. Corre el script sin --sin-notarizar para terminar."
  fi
  exit 0
fi

# ---------------------------------------------------------------------------------------------------------------
step "8/10 Notarizar (Apple lo revisa; suele tardar unos minutos)"
LOG="$OUT/notarizacion.txt"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait 2>&1 | tee "$LOG" | sed 's/^/  /'
SUBMISSION="$(grep -m1 -E "^ *id: " "$LOG" | awk '{print $2}')"
if ! grep -q "status: Accepted" "$LOG"; then
  echo
  echo "Apple no lo aceptó. Por qué:"
  [ -n "$SUBMISSION" ] && xcrun notarytool log "$SUBMISSION" --keychain-profile "$PROFILE" 2>&1 | sed 's/^/  /'
  fail "la notarización no pasó"
fi

step "9/10 Grapar y verificar"
# Grapar pega al disco el comprobante de Apple: así abre aunque el Mac del usuario no tenga internet.
xcrun stapler staple "$DMG" | sed 's/^/  /'
xcrun stapler validate "$DMG" | sed 's/^/  /'
# Lo que diría Gatekeeper en el Mac de quien lo descarga: del disco, y de la app tal como va dentro.
spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG" 2>&1 | sed 's/^/  /'
MOUNT="$(mktemp -d)"
hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MOUNT" >/dev/null
trap 'hdiutil detach "$MOUNT" >/dev/null 2>&1 || true' EXIT
spctl --assess --type execute --verbose=4 "$MOUNT/Galeno.app" 2>&1 | sed 's/^/  /'
spctl --assess --type execute "$MOUNT/Galeno.app" || fail "Gatekeeper no acepta la app que va en el disco"

fi

# ---------------------------------------------------------------------------------------------------------------
step "10/10 El appcast: lo que las apps ya instaladas miran para saber que hay versión nueva"
BRIDGE_VERSION="$("$BRIDGE_SRC" version)"
if [ "$UPDATES_ON" -eq 0 ]; then
  echo "  saltado: el appcast es de relleno (esta app no busca actualizaciones)"
else
  TOOLS="$DERIVED/SourcePackages/artifacts/sparkle/Sparkle/bin"
  [ -x "$TOOLS/generate_appcast" ] || fail "no encuentro las herramientas de Sparkle en $TOOLS"
  # La clave del llavero tiene que ser la pareja de la pública que lleva la app: si no, la app rechazaría la actualización.
  KEYCHAIN_PUBLIC="$("$TOOLS/generate_keys" --account "$SPARKLE_ACCOUNT" -p 2>/dev/null | tail -1)"
  [ "$KEYCHAIN_PUBLIC" = "$PUBLIC_KEY" ] \
    || fail "la clave de Sparkle del llavero (cuenta «$SPARKLE_ACCOUNT») no es la pareja de SUPublicEDKey. Sin esa clave no se puede publicar una actualización que la app acepte."

  # Qué versión del bridge llevaba la entrega anterior, según el propio appcast.
  PREVIOUS_BRIDGE=""
  if [ -f "$APPCAST" ]; then
    PREVIOUS_BRIDGE="$(sed -n 's/.*id="galeno-bridge" data-version="\([^"]*\)".*/\1/p' "$APPCAST" | head -1)"
  fi
  if [ -z "$PREVIOUS_BRIDGE" ]; then
    BRIDGE_NOTE="Bridge de WhatsApp $BRIDGE_VERSION."
  elif [ "$PREVIOUS_BRIDGE" = "$BRIDGE_VERSION" ]; then
    BRIDGE_NOTE="Bridge de WhatsApp $BRIDGE_VERSION, sin cambios."
  else
    BRIDGE_NOTE="Bridge de WhatsApp actualizado: de la $PREVIOUS_BRIDGE a la $BRIDGE_VERSION."
  fi

  # La carpeta de trabajo del appcast: el de siempre, el disco nuevo y sus notas. Se rehace con su ruta entera.
  rm -rf "$ROOT/build/release/updates"
  mkdir -p "$UPDATES"
  [ ! -f "$APPCAST" ] || cp "$APPCAST" "$UPDATES/appcast.xml"
  cp "$DMG" "$UPDATES/"
  NOTES="$UPDATES/Galeno-$VERSION.html"
  {
    echo "<h2>Galeno $VERSION</h2>"
    # Las notas escritas a mano, si las hay: un renglón por novedad en docs/releases/<versión>.md.
    if [ -f "$ROOT/docs/releases/$VERSION.md" ]; then
      echo "<ul>"
      grep -v '^[[:space:]]*$' "$ROOT/docs/releases/$VERSION.md" | grep -v '^#' \
        | sed -e 's/^[[:space:]]*[-*][[:space:]]*//' -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's|.*|<li>&</li>|'
      echo "</ul>"
    fi
    echo "<p id=\"galeno-bridge\" data-version=\"$BRIDGE_VERSION\">$BRIDGE_NOTE</p>"
  } > "$NOTES"

  # Firma el disco con la clave EdDSA y escribe su entrada. Sin diferenciales por ahora: harían falta los discos viejos.
  "$TOOLS/generate_appcast" --account "$SPARKLE_ACCOUNT" --download-url-prefix "$DOWNLOAD_PREFIX" \
    --embed-release-notes --maximum-versions 0 --maximum-deltas 0 "$UPDATES" 2>&1 | sed 's/^/  /'
  grep -q "sparkle:edSignature=" "$UPDATES/appcast.xml" || fail "el appcast salió sin la firma de Sparkle"
  mkdir -p "$(dirname "$APPCAST")"
  cp "$UPDATES/appcast.xml" "$APPCAST"
  echo "  $BRIDGE_NOTE"
  echo "  appcast actualizado: site/appcast.xml (commitéalo y publícalo con el sitio)"
  echo "  sube el disco a: $DOWNLOAD_PREFIX$(basename "$DMG")"
fi

echo
echo "Listo para entregar: $DMG ($(du -h "$DMG" | cut -f1))"
echo "Galeno $VERSION ($BUILD_NUMBER), bridge $BRIDGE_VERSION, commit $COMMIT, firmado por $IDENTITY"
