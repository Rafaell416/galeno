#!/bin/bash
# Instala Galeno de cero: quita lo que haya de una instalación anterior y copia la app de este disco.
#
# Se entrega dentro del DMG, junto a Galeno.app y al LÉEME. El usuario no lo ejecuta con doble clic: abre
# Terminal, escribe «bash » y arrastra este archivo a la ventana (ver el LÉEME).
#
#   bash instalar-galeno.sh                 limpia lo anterior, instala y abre Galeno
#   bash instalar-galeno.sh --solo-limpiar  solo limpia (no instala)
#   bash instalar-galeno.sh --dry           solo muestra lo que quitaría; no toca nada
#   bash instalar-galeno.sh --yes           no pregunta (para repetirlo sin atender)
#
# Qué hace, en este orden:
#   1. Cierra Galeno si está abierta y para su servicio de fondo de WhatsApp.
#   2. Quita de Claude Code las conexiones que Galeno hizo (Notion, Jira, Slack, Fathom, Claude Design, Google…),
#      solo si apuntan a los servidores oficiales: una conexión tuya con el mismo nombre no se toca.
#   3. Junta en UNA carpeta lo de Galeno: la app, los agentes de ~/Galeno, sus ajustes, la sesión de WhatsApp y
#      las conversaciones de esos agentes en Claude. La manda a la Papelera: NADA se borra para siempre.
#   4. Copia Galeno.app a Aplicaciones, le quita la marca de «descargada de internet» (la versión de prueba no
#      lleva la firma de Apple) y la abre.
#
# Qué NO toca: ~/.claude.json, el llavero, Claude Code (ni su sesión), tus conversaciones de Claude que no sean de
# agentes de Galeno, y lo que está en el teléfono o en las cuentas de Slack, Google, Notion, etc.
#
# Solo usa lo que trae macOS (bash, sed, grep, osascript…): no Python, no Homebrew, nada que haya que instalar.
# Escrito para el bash 3.2 que trae macOS.

SOLO_LIMPIAR=0
DRY=0
YES=0
for arg in "$@"; do
  case "$arg" in
    --solo-limpiar) SOLO_LIMPIAR=1 ;;
    --dry) DRY=1 ;;
    --yes) YES=1 ;;
    -h | --help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "No conozco la opción «$arg». Usa --solo-limpiar, --dry, --yes o --help."; exit 2 ;;
  esac
done

if [ -z "${HOME:-}" ] || [ ! -d "$HOME" ]; then
  echo "No encuentro tu carpeta de usuario. No hago nada."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_SOURCE="$SCRIPT_DIR/Galeno.app"
# Se puede cambiar solo para probar el script sin tocar /Applications.
APPLICATIONS="${GALENO_APPLICATIONS:-/Applications}"
APP_DEST="$APPLICATIONS/Galeno.app"

AGENTS_DIR="$HOME/Galeno"
SUPPORT="$HOME/Library/Application Support/Galeno"
PLIST="$HOME/Library/LaunchAgents/com.galeno.whatsapp-bridge.plist"
LABEL="com.galeno.whatsapp-bridge"
BUNDLE="com.galeno.Galeno"
CLAUDE_SESSIONS="$HOME/Library/Application Support/Claude/claude-code-sessions"

# Conexiones que Galeno registra en Claude Code, con la dirección oficial: así no se toca una tuya con el mismo
# nombre pero otra dirección.
SERVERS="
slack|https://mcp.slack.com/mcp
notion|https://mcp.notion.com/mcp
jira|https://mcp.atlassian.com/v2/mcp
fathom|https://api.fathom.ai/mcp
fireflies|https://api.fireflies.ai/mcp
granola|https://mcp.granola.ai/mcp
claude-design|https://api.anthropic.com/v1/design/mcp
gmail|https://gmailmcp.googleapis.com/mcp/v1
google-drive|https://drivemcp.googleapis.com/mcp/v1
google-docs|https://docsmcp.googleapis.com/mcp/v1
google-sheets|https://sheetsmcp.googleapis.com/mcp/v1
google-calendar|https://calendarmcp.googleapis.com/mcp/v1
"

say() { printf '%s\n' "$*"; }
step() { printf '  ✓ %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*"; }

# ---------------------------------------------------------------------------------------------------------
# 1. Qué hay que quitar
# ---------------------------------------------------------------------------------------------------------

# Rutas que se mandan a la Papelera, una por línea.
MOVE_LIST=""
add_path() { [ -e "$1" ] && MOVE_LIST="${MOVE_LIST}${1}
"; }

# Una línea por cosa, en palabras de persona.
SUMMARY=""
add_summary() { SUMMARY="${SUMMARY}  • ${1}
"; }

if [ -d "$APP_DEST" ]; then
  add_path "$APP_DEST"
  add_summary "La Galeno que ya tienes instalada"
fi
if [ -d "$HOME/Applications/Galeno.app" ]; then
  add_path "$HOME/Applications/Galeno.app"
  add_summary "Otra copia de Galeno en tu carpeta Aplicaciones personal"
fi

if [ -d "$AGENTS_DIR" ]; then
  NAMES=""
  while IFS= read -r name; do
    [ -n "$name" ] && NAMES="${NAMES}${NAMES:+, }${name}"
  done <<EOF
$(ls -1 "$AGENTS_DIR" 2>/dev/null | grep -v '^\.')
EOF
  add_path "$AGENTS_DIR"
  add_summary "Tus agentes de la carpeta «Galeno»${NAMES:+ ($NAMES)}"
fi

if [ -d "$SUPPORT" ]; then
  add_path "$SUPPORT"
  add_summary "Los ajustes de Galeno y, si la vinculaste, la sesión de WhatsApp con sus mensajes guardados"
fi

HAS_SERVICE=0
if [ -e "$PLIST" ] || launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
  HAS_SERVICE=1
  add_path "$PLIST"
  add_summary "El servicio que mantiene WhatsApp sincronizado"
fi

for item in \
  "$HOME/Library/Caches/$BUNDLE" \
  "$HOME/Library/HTTPStorages/$BUNDLE" \
  "$HOME/Library/HTTPStorages/$BUNDLE.binarycookies" \
  "$HOME/Library/WebKit/$BUNDLE" \
  "$HOME/Library/Saved Application State/$BUNDLE.savedState"; do
  add_path "$item"
done

HAS_PREFS=0
if defaults read "$BUNDLE" >/dev/null 2>&1; then
  HAS_PREFS=1
  add_summary "Las preferencias de la app (así vuelves a ver las pantallas de bienvenida)"
fi

# Conversaciones de Claude Code de los agentes: ~/.claude/projects/-Users-nombre-Galeno-<agente>
ENCODED="$(printf '%s' "$AGENTS_DIR/" | sed 's/[^A-Za-z0-9]/-/g')"
CONVERSATIONS=0
for dir in "$HOME/.claude/projects/${ENCODED}"*; do
  if [ -d "$dir" ]; then
    add_path "$dir"
    CONVERSATIONS=$((CONVERSATIONS + 1))
  fi
done
# Conversaciones de la app de Claude que se abrieron en la carpeta de un agente.
SESSION_FILES=""
if [ -d "$CLAUDE_SESSIONS" ]; then
  SESSION_FILES="$(grep -rlE --include='local_*.json' "\"cwd\" *: *\"$HOME/Galeno/" "$CLAUDE_SESSIONS" 2>/dev/null)"
  if [ -n "$SESSION_FILES" ]; then
    while IFS= read -r file; do
      [ -n "$file" ] && MOVE_LIST="${MOVE_LIST}${file}
" && CONVERSATIONS=$((CONVERSATIONS + 1))
    done <<EOF
$SESSION_FILES
EOF
  fi
fi
[ "$CONVERSATIONS" -gt 0 ] && add_summary "Las conversaciones de esos agentes en Claude ($CONVERSATIONS)"

# Dónde está `claude`: una app abierta o una Terminal nueva puede no tenerlo en el PATH.
CLAUDE=""
for candidate in "$(command -v claude 2>/dev/null)" "$HOME/.local/bin/claude" "/opt/homebrew/bin/claude" \
  "/usr/local/bin/claude" "$HOME/.claude/local/claude"; do
  if [ -n "$candidate" ] && [ -x "$candidate" ]; then
    CLAUDE="$candidate"
    break
  fi
done

MCP_FOUND=""
if [ -n "$CLAUDE" ]; then
  say "Mirando las conexiones de Claude Code (tarda unos segundos)…"
  MCP_LIST="$("$CLAUDE" mcp list 2>/dev/null)"
  while IFS='|' read -r name url; do
    [ -z "$name" ] && continue
    for candidate in "$name" "galeno-$name"; do
      if printf '%s\n' "$MCP_LIST" | grep -E "^$candidate:" | grep -qF "$url"; then
        MCP_FOUND="${MCP_FOUND}${MCP_FOUND:+ }${candidate}"
      fi
    done
  done <<EOF
$SERVERS
EOF
  [ -n "$MCP_FOUND" ] && add_summary "Las conexiones a herramientas que Claude Code tiene con Galeno ($(printf '%s' "$MCP_FOUND" | sed 's/ /, /g')); las vuelves a conectar en un momento"
fi

# ---------------------------------------------------------------------------------------------------------
# 2. Lo que se va a hacer, y la pregunta
# ---------------------------------------------------------------------------------------------------------

CAN_INSTALL=0
if [ "$SOLO_LIMPIAR" -eq 0 ]; then
  if [ -d "$APP_SOURCE" ]; then
    CAN_INSTALL=1
  else
    say ""
    warn "No encuentro «Galeno.app» junto a este archivo, así que solo voy a limpiar."
    warn "(Ejecútalo desde la ventana del disco de Galeno si quieres que también la instale.)"
  fi
fi

say ""
say "══ Galeno: empezar de cero ══"
say ""
if [ -n "$SUMMARY" ]; then
  say "Voy a quitar esto:"
  printf '%s' "$SUMMARY"
  say ""
  say "Todo va a la Papelera: no se borra para siempre."
else
  say "No encontré nada de una instalación anterior."
fi
[ "$CAN_INSTALL" -eq 1 ] && say "Después instalaré la Galeno nueva de este disco y la abriré."
say ""

if [ "$DRY" -eq 1 ]; then
  say "(--dry: no toqué nada)"
  exit 0
fi

if [ -z "$SUMMARY" ] && [ "$CAN_INSTALL" -eq 0 ]; then
  exit 0
fi

if [ "$YES" -eq 0 ]; then
  printf "Para seguir escribe  si  y pulsa Intro. Para cancelar, cierra esta ventana: "
  read -r ANSWER
  ANSWER="$(printf '%s' "$ANSWER" | tr '[:upper:]' '[:lower:]' | tr -d ' ')"
  case "$ANSWER" in
    si | sí | s | y | yes) ;;
    *)
      say "No hice nada."
      exit 1
      ;;
  esac
fi
say ""

# ---------------------------------------------------------------------------------------------------------
# 3. Quitar
# ---------------------------------------------------------------------------------------------------------

# Galeno abierta: se le pide cerrar y, si no puede, se cierra.
if pgrep -x Galeno >/dev/null 2>&1; then
  osascript -e 'tell application "Galeno" to quit' >/dev/null 2>&1
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -x Galeno >/dev/null 2>&1 || break
    sleep 1
  done
  pgrep -x Galeno >/dev/null 2>&1 && pkill -x Galeno >/dev/null 2>&1 && sleep 1
  step "Galeno cerrada"
fi

# El servicio de fondo de WhatsApp, antes de mover su estado.
if [ "$HAS_SERVICE" -eq 1 ]; then
  launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1
  pkill -f "Application Support/Galeno/bin/galeno-whatsapp" >/dev/null 2>&1
  step "Servicio de WhatsApp detenido"
fi

# Las conexiones de Claude Code: primero se cierra la autorización y luego se quita el registro.
for name in $MCP_FOUND; do
  "$CLAUDE" mcp logout "$name" >/dev/null 2>&1
  if "$CLAUDE" mcp remove "$name" -s user >/dev/null 2>&1; then
    step "Conexión quitada: $name"
  else
    warn "No pude quitar la conexión «$name». Puedes dejarla: Galeno la reconoce."
  fi
done

# Todo lo demás se junta en una carpeta, con la misma estructura de origen, y la carpeta va a la Papelera.
STAMP="$(date +%Y-%m-%d-%H%M%S)"
STAGE="$HOME/Galeno · limpieza $STAMP"
MOVED=0
FAILED_APP=0
if [ -n "$MOVE_LIST" ]; then
  mkdir -p "$STAGE"
  while IFS= read -r path; do
    [ -z "$path" ] && continue
    case "$path" in
      "$HOME"/*) relative="${path#"$HOME"/}" ;;
      *) relative="fuera-de-tu-carpeta${path}" ;;
    esac
    destination="$STAGE/$relative"
    mkdir -p "$(dirname "$destination")"
    if mv "$path" "$destination" 2>/dev/null; then
      MOVED=$((MOVED + 1))
    else
      warn "No pude mover: $path"
      [ "$path" = "$APP_DEST" ] && FAILED_APP=1
    fi
  done <<EOF
$MOVE_LIST
EOF
  [ "$MOVED" -gt 0 ] && step "Lo de Galeno quedó junto en una carpeta ($MOVED cosas)"
fi

# Las preferencias se quitan por su nombre, no moviendo el archivo: macOS las guarda en memoria.
if [ "$HAS_PREFS" -eq 1 ]; then
  mkdir -p "$STAGE"
  defaults export "$BUNDLE" "$STAGE/preferencias-de-galeno.plist" >/dev/null 2>&1
  defaults delete "$BUNDLE" >/dev/null 2>&1 && step "Preferencias de la app quitadas"
fi

# A la Papelera.
if [ -d "$STAGE" ]; then
  if command -v trash >/dev/null 2>&1 && trash "$STAGE" >/dev/null 2>&1; then
    step "Enviado a la Papelera"
  elif osascript -e "tell application \"Finder\" to delete POSIX file \"$STAGE\"" >/dev/null 2>&1; then
    step "Enviado a la Papelera"
  else
    warn "No pude mandarlo a la Papelera. Arrastra a la Papelera la carpeta «$(basename "$STAGE")» de tu carpeta de usuario."
  fi
fi

# ---------------------------------------------------------------------------------------------------------
# 4. Instalar
# ---------------------------------------------------------------------------------------------------------

if [ "$CAN_INSTALL" -eq 1 ]; then
  say ""
  if [ "$FAILED_APP" -eq 1 ] || [ -d "$APP_DEST" ]; then
    warn "No pude quitar la Galeno anterior de Aplicaciones, así que no instalo encima."
    warn "Arrástrala a la Papelera a mano y vuelve a correr este archivo."
    exit 1
  fi
  if ! mkdir -p "$APPLICATIONS" || ! ditto "$APP_SOURCE" "$APP_DEST"; then
    warn "No pude copiar Galeno a Aplicaciones."
    warn "Arrastra «Galeno» de la ventana del disco a la carpeta Aplicaciones y avísale a Rafa."
    exit 1
  fi
  # La versión de prueba no lleva la firma de Apple: sin esto, macOS dice que «no se puede abrir».
  xattr -dr com.apple.quarantine "$APP_DEST" >/dev/null 2>&1
  step "Galeno instalada en Aplicaciones"
  if open "$APP_DEST" >/dev/null 2>&1; then
    step "Galeno abierta"
  else
    warn "No pude abrirla sola. Ábrela con doble clic desde la carpeta Aplicaciones."
  fi
fi

say ""
say "══ Listo ══"
say ""
if [ -n "$SUMMARY" ]; then
  say "Quedan dos cosas que solo se pueden hacer a mano (por si las conectaste antes):"
  say "  1. En tu teléfono: WhatsApp → Ajustes → Dispositivos vinculados → cierra la sesión del dispositivo de Galeno."
  say "  2. En claude.ai → Ajustes → Conectores: desconecta Gmail, Google Drive o Calendar si quieres volver a conectarlos desde cero."
  say ""
fi
say "Ya puedes cerrar esta ventana."
