#!/bin/bash
# Compila, firma, empaqueta y notariza Galeno para entregarlo: build/release/Galeno-<versión>.dmg
#
#   scripts/build-release.sh                  todo: compila, firma, DMG, notariza, grapa y verifica
#   scripts/build-release.sh --sin-notarizar  hasta el DMG firmado: para ver la firma sin esperar a Apple
#   scripts/build-release.sh --ensayo         sin certificado: firma «ad hoc» y no notariza. Sirve para ensayar los
#                                             pasos; lo que sale NO se puede entregar
#   scripts/build-release.sh --con-cambios    deja compilar con cambios sin commitear (por defecto se niega)
#
# Qué necesita en ESTE Mac: Xcode, Go, create-dmg (`brew install create-dmg`), el certificado «Developer ID
# Application» en el llavero, y las credenciales de notarización guardadas con `xcrun notarytool store-credentials`.
# Los datos van en scripts/release.env (ver release.env.example) o en variables de entorno. Paso a paso: docs/RELEASE.md.
#
# AQUÍ NO HAY CONTRASEÑAS, ni se piden: la firma usa el certificado del llavero y la notarización, el perfil que
# guardó notarytool. No añadir ninguna a este archivo ni a release.env.
#
# El orden importa. Se firma de dentro hacia fuera: primero el bridge de WhatsApp (un ejecutable de Go que va dentro
# de la app) y cualquier otro ejecutable anidado, después la app, y al final el disco. Firmar la app antes que lo de
# dentro, o usar `--deep`, deja una firma que Apple rechaza al notarizar.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MODE=release
ALLOW_DIRTY=0
for arg in "$@"; do
  case "$arg" in
    --sin-notarizar) MODE=signed ;;
    --ensayo) MODE=rehearsal ;;
    --con-cambios) ALLOW_DIRTY=1 ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Opción desconocida: $arg (usa --sin-notarizar, --ensayo, --con-cambios o --help)"; exit 2 ;;
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

# Todo lo que este script crea o borra vive aquí dentro. Rutas fijas a partir de la raíz del repo: nunca una variable
# que, vacía, apunte a otra parte.
OUT="$ROOT/build/release"
DERIVED="$OUT/derived"
STAGE="$OUT/stage"
APP="$STAGE/Galeno.app"
case "$OUT" in */build/release) ;; *) fail "la carpeta de salida no es la esperada: $OUT" ;; esac

# ---------------------------------------------------------------------------------------------------------------
step "0/9 Antes de empezar"
# Lo que puede fallar se mira ahora, no después de diez minutos compilando.
for tool in xcodebuild go lipo codesign hdiutil; do command -v "$tool" >/dev/null || fail "falta $tool"; done

if [ "$MODE" = rehearsal ]; then
  IDENTITY="-"
  echo "  ENSAYO: firma ad hoc, sin notarizar. Lo que salga no se puede entregar."
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

COMMIT="$(git rev-parse --short HEAD)"
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  [ "$ALLOW_DIRTY" -eq 1 ] || [ "$MODE" = rehearsal ] \
    || fail "hay cambios sin commitear: lo que se entrega tiene que corresponder a un commit. (Para probar: --con-cambios)"
  COMMIT="$COMMIT-con-cambios"
fi
mkdir -p "$OUT"

# ---------------------------------------------------------------------------------------------------------------
step "1/9 El motor (GalenoCore)"
swift build -c release --package-path GalenoCore 2>&1 | tail -1

step "2/9 El bridge de WhatsApp (universal: Apple Silicon e Intel)"
make -C whatsapp-bridge universal >/dev/null
BRIDGE_SRC="$ROOT/whatsapp-bridge/bin/galeno-whatsapp"
echo "  arquitecturas: $(lipo -archs "$BRIDGE_SRC")"
[ "$(lipo -archs "$BRIDGE_SRC" | tr ' ' '\n' | sort | tr '\n' ' ')" = "arm64 x86_64 " ] || fail "el bridge no es universal"

step "3/9 La app (Release, universal)"
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
# `grep -c` lee hasta el final: un `grep -q` cortaría a `strings` y, con `pipefail`, la comprobación no saltaría nunca.
if [ "$(strings -a "$APP/Contents/MacOS/Galeno" | grep -c "galeno-fake-connect" || true)" != "0" ]; then
  fail "la app lleva las opciones de prueba de Debug: no es una compilación Release"
fi

# ---------------------------------------------------------------------------------------------------------------
step "4/9 Firmar lo de dentro: el bridge y cualquier otro ejecutable"
# `--options runtime` es el «hardened runtime», que Apple exige para notarizar. `--timestamp` pide a Apple un sello
# de tiempo: sin él la firma deja de valer cuando caduque el certificado. La firma ad hoc del ensayo no lo admite.
if [ "$MODE" = rehearsal ]; then STAMP="--timestamp=none"; else STAMP="--timestamp"; fi

# Todo ejecutable Mach-O que no sea el principal. Hoy es solo el bridge; cuando entre Sparkle habrá más.
NESTED=()
while IFS= read -r file; do
  [ "$file" = "$APP/Contents/MacOS/Galeno" ] && continue
  case "$(file -b "$file")" in *Mach-O*) NESTED+=("$file") ;; esac
done < <(find "$APP/Contents" -type f \( -perm +111 -o -name "*.dylib" \) ! -path "*/Resources/skills/*")
[ ${#NESTED[@]} -gt 0 ] || fail "no encontré el bridge dentro de la app"
if [ -n "$(find "$APP/Contents" -mindepth 1 \( -name "*.framework" -o -name "*.xpc" -o -name "*.app" \) | head -1)" ]; then
  fail "la app lleva un framework, un servicio XPC o una app anidada: hay que firmarlos como paquete, y este script todavía no lo hace"
fi
for file in "${NESTED[@]}"; do
  if [ "$(basename "$file")" = "galeno-whatsapp" ]; then
    codesign --force --options runtime "$STAMP" --identifier "$BRIDGE_ID" --sign "$IDENTITY" "$file"
  else
    codesign --force --options runtime "$STAMP" --sign "$IDENTITY" "$file"
  fi
  echo "  firmado: ${file#"$APP"/}"
done

step "5/9 Firmar la app"
# Sin `--deep`: lo de dentro ya está firmado, cada cosa con lo suyo. Los entitlements van vacíos a propósito
# (docs/RELEASE.md dice por qué): fuera de la tienda, y sin sandbox, la red y lanzar procesos no piden permiso.
codesign --force --options runtime "$STAMP" --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP"
echo "  firmada: Galeno.app"

step "6/9 Comprobar la firma"
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
step "7/9 El disco (DMG)"
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
step "8/9 Notarizar (Apple lo revisa; suele tardar unos minutos)"
LOG="$OUT/notarizacion.txt"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait 2>&1 | tee "$LOG" | sed 's/^/  /'
SUBMISSION="$(grep -m1 -E "^ *id: " "$LOG" | awk '{print $2}')"
if ! grep -q "status: Accepted" "$LOG"; then
  echo
  echo "Apple no lo aceptó. Por qué:"
  [ -n "$SUBMISSION" ] && xcrun notarytool log "$SUBMISSION" --keychain-profile "$PROFILE" 2>&1 | sed 's/^/  /'
  fail "la notarización no pasó"
fi

step "9/9 Grapar y verificar"
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

echo
echo "Listo para entregar: $DMG ($(du -h "$DMG" | cut -f1))"
echo "Galeno $VERSION ($BUILD_NUMBER), commit $COMMIT, firmado por $IDENTITY"
