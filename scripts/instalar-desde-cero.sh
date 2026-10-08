#!/bin/bash
# Instala Galeno desde cero en un Mac que ya tenía una versión anterior.
#
# PARA QUIEN YA TENÍA GALENO. No es el instalador normal (ese es arrastrar Galeno.app a Aplicaciones). Se usa una vez, con el
# disco de la versión nueva descargado:
#
#   bash instalar-desde-cero.sh                       busca el disco Galeno-*.dmg más nuevo en Descargas
#   bash instalar-desde-cero.sh ~/Descargas/Galeno-0.0.1.dmg
#   bash instalar-desde-cero.sh --dry                 solo enseña lo que haría, no toca nada
#
# Qué hace, en este orden:
#   1. Abre el disco y comprueba que Galeno está firmado y notarizado por Apple. Si no, se detiene SIN tocar nada.
#   2. Enseña lo que va a quitar y pide que escribas «si».
#   3. Guarda una copia de la memoria de cada agente en Documentos/Galeno-respaldo-<fecha>/.
#   4. Cierra Galeno y su servicio de WhatsApp.
#   5. Manda a la Papelera (nunca borra): la app vieja, tus agentes, sus conversaciones en la app de Claude y el estado
#      de Galeno (incluida la sesión de WhatsApp y su historial local).
#   6. Instala la versión nueva en Aplicaciones y la abre.
#
# Qué NO hace:
#   · No vacía la Papelera: si algo salió mal, está ahí.
#   · No toca los servidores MCP de Claude Code (Notion, Slack…): pueden ser de otros proyectos tuyos.
#   · No cierra la sesión de Galeno en tu teléfono: se hace a mano y lo recuerda al final.

set -u

MODE=ask
DMG=""
for arg in "$@"; do
  case "$arg" in
    --dry) MODE=dry ;;
    --yes) MODE=yes ;;
    -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "Opción desconocida: $arg (usa --dry, --yes o --help)"; exit 2 ;;
    *) DMG="$arg" ;;
  esac
done

# Ganchos solo para probar el script sin tocar el Mac de verdad (ver docs/RELEASE.md). Sin ellos, todo es real.
#   GALENO_PRUEBA=1        no comprueba la firma, no toca procesos, servicios ni preferencias, y no abre la app
#   GALENO_APLICACIONES    carpeta de aplicaciones (por defecto /Applications)
#   GALENO_PAPELERA        carpeta a la que mover en vez de la Papelera del Finder
TEST="${GALENO_PRUEBA:-0}"
APPS="${GALENO_APLICACIONES:-/Applications}"
TRASH_DIR="${GALENO_PAPELERA:-}"

SUPPORT="$HOME/Library/Application Support/Galeno"
AGENTS_DIR="$HOME/Galeno"
PLIST="$HOME/Library/LaunchAgents/com.galeno.whatsapp-bridge.plist"
LABEL="com.galeno.whatsapp-bridge"
BUNDLE="com.galeno.Galeno"
APP="$APPS/Galeno.app"
STAMP="$(date +%Y-%m-%d-%H%M)"
BACKUP="$HOME/Documents/Galeno-respaldo-$STAMP"

say() { printf '%s\n' "$*"; }
stop() { say ""; say "✗ $*"; exit 1; }

# --- 1. El disco -----------------------------------------------------------------------------------------------------
if [ -z "$DMG" ]; then
  DMG="$(ls -t "$HOME"/Downloads/Galeno-*.dmg 2>/dev/null | head -n 1)"
  [ -n "$DMG" ] || stop "No encontré ningún disco Galeno-….dmg en Descargas. Descárgalo y vuelve a correr esto, o escribe su ruta: bash instalar-desde-cero.sh /ruta/Galeno-0.0.1.dmg"
fi
[ -f "$DMG" ] || stop "No existe el disco: $DMG"

MOUNT="$(mktemp -d "${TMPDIR:-/tmp}/galeno-disco.XXXXXX")"
cleanup() { hdiutil detach "$MOUNT" -quiet >/dev/null 2>&1; rmdir "$MOUNT" >/dev/null 2>&1; }
trap cleanup EXIT

say "== Disco: $(basename "$DMG") =="
hdiutil attach "$DMG" -nobrowse -readonly -noautoopen -mountpoint "$MOUNT" -quiet >/dev/null 2>&1 \
  || stop "No pude abrir el disco. ¿Se descargó completo? Descárgalo otra vez."
NEW_APP="$MOUNT/Galeno.app"
[ -d "$NEW_APP" ] || stop "El disco no trae Galeno.app. No toqué nada."

NEW_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$NEW_APP/Contents/Info.plist" 2>/dev/null || echo "?")"
if [ "$TEST" != 1 ]; then
  codesign --verify --deep --strict "$NEW_APP" >/dev/null 2>&1 \
    || stop "La firma de Galeno no es válida. No lo instalo y no toqué nada. Pide el disco otra vez."
  SPCTL="$(spctl --assess --type execute -vv "$NEW_APP" 2>&1)"
  case "$SPCTL" in
    *"accepted"*) ;;
    *) stop "macOS no reconoce esta versión de Galeno como notarizada. No la instalo y no toqué nada." ;;
  esac
  say "✓ Firmada y notarizada. Versión $NEW_VERSION."
else
  say "(modo prueba: no se comprueba la firma) Versión $NEW_VERSION."
fi

# --- 2. Lo que se va a quitar ----------------------------------------------------------------------------------------
say ""
say "== Lo que se va a quitar (todo a la Papelera, nada se borra) =="

OLD_VERSION=""
[ -d "$APP" ] && OLD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo "?")"
if [ -d "$APP" ]; then say "· La app vieja: $APP (versión $OLD_VERSION)"; else say "· La app vieja: (no estaba instalada)"; fi

AGENTS=()
if [ -d "$AGENTS_DIR" ]; then
  for dir in "$AGENTS_DIR"/*/; do
    # Solo carpetas que Galeno generó: tienen su AGENTS.md. Cualquier otra cosa en ~/Galeno se queda.
    [ -f "${dir}AGENTS.md" ] && AGENTS+=("${dir%/}")
  done
fi
say "· Tus agentes en $AGENTS_DIR:"
if [ ${#AGENTS[@]} -gt 0 ]; then for a in "${AGENTS[@]}"; do say "    $(basename "$a")"; done; else say "    (ninguno)"; fi

# Las conversaciones de esos agentes en Claude. Rutas exactas: la carpeta de proyecto de Claude Code se calcula como la
# nombra Claude (cada carácter que no sea letra o cifra pasa a «-»), y de la app de Claude solo las sesiones cuyo carpeta
# es uno de esos agentes.
PROJECTS="$HOME/.claude/projects"
SESSIONS="$HOME/Library/Application Support/Claude/claude-code-sessions"
nfc() { printf '%s' "$1" | perl -CS -MUnicode::Normalize -pe '$_ = NFC($_)'; }
encoded() { printf '%s' "$1" | perl -CS -MUnicode::Normalize -pe '$_ = NFC($_); s/[^A-Za-z0-9]/-/g'; }
CLAUDE_ITEMS=()
for a in ${AGENTS[@]+"${AGENTS[@]}"}; do
  project="$PROJECTS/$(encoded "$a")"
  [ -d "$project" ] && CLAUDE_ITEMS+=("$project")
done
if [ -d "$SESSIONS" ] && [ ${#AGENTS[@]} -gt 0 ]; then
  while IFS= read -r file; do
    cwd="$(plutil -extract cwd raw -o - "$file" 2>/dev/null)" || continue
    cwd="$(nfc "${cwd%/}")"
    for a in "${AGENTS[@]}"; do
      [ "$cwd" = "$(nfc "$a")" ] && { CLAUDE_ITEMS+=("$file"); break; }
    done
  done < <(find "$SESSIONS" -mindepth 3 -maxdepth 3 -name 'local_*.json' -type f 2>/dev/null)
fi
say "· Sus conversaciones en Claude:"
if [ ${#CLAUDE_ITEMS[@]} -gt 0 ]; then say "    ${#CLAUDE_ITEMS[@]} elemento(s)"; else say "    (ninguna)"; fi

say "· El estado de Galeno en $SUPPORT:"
if [ -e "$SUPPORT" ]; then say "    incluye la sesión de WhatsApp y su historial local (tendrás que volver a vincular)"; else say "    (no existe)"; fi

SERVICE=0
if [ -e "$PLIST" ]; then SERVICE=1; fi
if [ "$TEST" != 1 ] && launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then SERVICE=1; fi
if [ "$SERVICE" = 1 ]; then say "· El servicio de fondo de WhatsApp: se detiene y se quita"; else say "· El servicio de fondo de WhatsApp: (no instalado)"; fi

say ""
say "== Lo que se queda =="
say "· Una copia de la memoria de cada agente, en $BACKUP"
say "· Tus servidores de Claude Code (Notion, Slack…): no se tocan"
say "· La Papelera, sin vaciar"
say ""

if [ "$MODE" = dry ]; then say "(--dry: no se tocó nada)"; exit 0; fi
if [ "$MODE" = ask ]; then
  printf "¿Instalar Galeno %s desde cero con todo lo anterior? [escribe 'si'] " "$NEW_VERSION"
  read -r answer
  [ "$answer" = "si" ] || { say "Cancelado. No se tocó nada."; exit 1; }
fi

# --- 3. La memoria, a salvo ------------------------------------------------------------------------------------------
if [ ${#AGENTS[@]} -gt 0 ]; then
  mkdir -p "$BACKUP" || stop "No pude crear $BACKUP. No toqué nada."
  for a in "${AGENTS[@]}"; do
    if [ -d "$a/memoria" ]; then
      mkdir -p "$BACKUP/$(basename "$a")" && ditto "$a/memoria" "$BACKUP/$(basename "$a")/memoria" \
        || stop "No pude guardar la memoria de $(basename "$a"). No quité nada."
    fi
  done
  say "✓ Memoria guardada en $BACKUP"
fi

# --- 4. Cerrar Galeno y su servicio ----------------------------------------------------------------------------------
if [ "$TEST" != 1 ]; then
  osascript -e 'tell application "Galeno" to quit' >/dev/null 2>&1
  for _ in 1 2 3 4 5 6; do pgrep -x Galeno >/dev/null 2>&1 || break; sleep 1; done
  pgrep -x Galeno >/dev/null 2>&1 && pkill -x Galeno 2>/dev/null
  [ "$SERVICE" = 1 ] && launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 && say "- servicio de WhatsApp detenido"
fi

# --- 5. A la Papelera ------------------------------------------------------------------------------------------------
to_trash() {
  local item="$1"
  [ -e "$item" ] || return 0
  case "$item" in *\"*) say "! no toco una ruta con comillas: $item"; return 1 ;; esac
  if [ -n "$TRASH_DIR" ]; then
    mkdir -p "$TRASH_DIR" && mv "$item" "$TRASH_DIR/$(basename "$item")-$RANDOM" && say "- a la Papelera: ${item#"$HOME"/}"
  else
    osascript -e "tell application \"Finder\" to delete POSIX file \"$item\"" >/dev/null 2>&1 \
      && say "- a la Papelera: ${item#"$HOME"/}" || { say "! no pude mover a la Papelera: $item"; return 1; }
  fi
}

FAILED=0
to_trash "$APP" || FAILED=1
for a in ${AGENTS[@]+"${AGENTS[@]}"}; do to_trash "$a" || FAILED=1; done
for item in ${CLAUDE_ITEMS[@]+"${CLAUDE_ITEMS[@]}"}; do to_trash "$item" || FAILED=1; done
to_trash "$PLIST" || FAILED=1
to_trash "$SUPPORT" || FAILED=1
if [ "$TEST" != 1 ]; then
  defaults delete "$BUNDLE" >/dev/null 2>&1 && say "- preferencias de la app quitadas"
fi
if [ "$FAILED" = 1 ]; then
  stop "Algo no se pudo mover a la Papelera. No instalé la versión nueva para no mezclar. Mira los avisos de arriba y vuelve a correr esto."
fi

# --- 6. Instalar -----------------------------------------------------------------------------------------------------
mkdir -p "$APPS" || stop "No pude usar $APPS."
ditto "$NEW_APP" "$APP" || stop "No pude copiar Galeno a $APPS. Tus cosas anteriores están en la Papelera."
say "✓ Galeno $NEW_VERSION instalado en $APPS"
if [ "$TEST" != 1 ]; then open "$APP"; fi

say ""
say "Listo. Faltan dos cosas a mano:"
say "  1. En el teléfono: WhatsApp → Ajustes → Dispositivos vinculados → cierra la sesión vieja de Galeno."
say "     (Galeno nuevo te pedirá vincular otra vez con un código QR.)"
say "  2. Si la app de Claude está abierta, ciérrala del todo (Cmd+Q) y ábrela: todavía recuerda las conversaciones que se quitaron."
if [ -d "$BACKUP" ]; then
  say ""
  say "Tu memoria anterior está en $BACKUP. Si quieres que el agente nuevo la use,"
  say "copia el contenido de la carpeta «memoria» al agente nuevo (Galeno → tu agente → Contexto)."
fi
