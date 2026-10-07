#!/bin/bash
# Arma el DMG de prueba de Galeno para entregárselo a alguien: build/Galeno-demo-<fecha>-<commit>.dmg
#
#   scripts/hacer-dmg-demo.sh
#
# Qué lleva el disco: Galeno.app, un acceso a Aplicaciones, `instalar-galeno.sh` (limpia lo anterior, instala y
# abre; lo usa quien lo recibe, ver LÉEME) y el LÉEME.
#
# SIN FIRMA DE APPLE: la app y el bridge de WhatsApp van firmados «ad hoc» (sin Developer ID) y sin notarizar. Es una
# versión de demo. Para entregar de verdad: Developer ID + notarización (Fase 8 de la guía).
#
# Necesita Xcode y Go en ESTE Mac (el de desarrollo); quien recibe el DMG no necesita nada.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DATE="$(date +%Y-%m-%d)"
COMMIT="$(git rev-parse --short HEAD)"
DIRTY=""
[ -n "$(git status --porcelain --untracked-files=no)" ] && DIRTY="-con-cambios"
NAME="Galeno-demo-$DATE-$COMMIT$DIRTY"
BUILD="$ROOT/build"
DERIVED="$BUILD/demo"
STAGE="$BUILD/demo-dmg"
DMG="$BUILD/$NAME.dmg"

echo "== 1/5 El bridge de WhatsApp (universal: Apple Silicon e Intel) =="
make -C whatsapp-bridge universal
lipo -archs whatsapp-bridge/bin/galeno-whatsapp

echo "== 2/5 La app (Release, universal, firma ad hoc) =="
xcodebuild -project GalenoApp/Galeno.xcodeproj -scheme Galeno -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$DERIVED" ONLY_ACTIVE_ARCH=NO build \
  | grep -E "error:|warning: .*(deprecated|unused)|BUILD (SUCCEEDED|FAILED)" || true
APP="$DERIVED/Build/Products/Release/Galeno.app"
[ -d "$APP" ] || { echo "No se generó Galeno.app"; exit 1; }

echo "== 3/5 Comprobando la app =="
BIN="$APP/Contents/MacOS/Galeno"
echo "  arquitecturas de la app: $(lipo -archs "$BIN")"
echo "  arquitecturas del bridge: $(lipo -archs "$APP/Contents/Resources/galeno-whatsapp")"
codesign --verify --deep --strict "$APP" && echo "  firma ad hoc: íntegra"
[ -f "$APP/Contents/Resources/skills/catalog.json" ] || { echo "Faltan las skills dentro de la app"; exit 1; }
echo "  skills dentro de la app: $(find "$APP/Contents/Resources/skills" -name SKILL.md | wc -l | tr -d ' ')"
# `grep -c` y no `grep -q`: con `pipefail`, uno que encuentra pronto corta a `strings` y la comprobación no saltaba nunca.
if [ "$(strings -a "$BIN" | grep -c "galeno-fake-connect" || true)" != "0" ]; then
  echo "  ¡La app lleva las opciones de prueba de Debug (-galeno-fake-connect)! No es una compilación Release."
  exit 1
fi

echo "== 4/5 Armando el disco =="
rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Galeno.app"
ln -s /Applications "$STAGE/Applications"
cp scripts/instalar-galeno.sh "$STAGE/instalar-galeno.sh"
chmod +x "$STAGE/instalar-galeno.sh"
MONTHS=(enero febrero marzo abril mayo junio julio agosto septiembre octubre noviembre diciembre)
LONG_DATE="$(date +%-d) de ${MONTHS[$(($(date +%-m) - 1))]} de $(date +%Y)"
sed "s/{{FECHA}}/$LONG_DATE/" scripts/dmg/LEEME.md > "$STAGE/LÉEME.md"

echo "== 5/5 Creando el DMG =="
rm -f "$DMG"
hdiutil create -volname "Galeno" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null && echo "  DMG verificado"

echo
echo "Listo: $DMG ($(du -h "$DMG" | cut -f1))"
echo "Commit: $COMMIT$DIRTY"
