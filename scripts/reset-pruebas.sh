#!/bin/bash
# Deja este Mac como si Galeno nunca se hubiera usado, para repetir la prueba de punta a punta.
#
# SOLO PARA DESARROLLO: no se distribuye. Es destructivo: pide confirmación y lista antes lo que va a quitar.
#
#   scripts/reset-pruebas.sh          lista lo que quitaría y pregunta
#   scripts/reset-pruebas.sh --yes    lo quita sin preguntar
#   scripts/reset-pruebas.sh --dry    solo lista, no toca nada
#   scripts/reset-pruebas.sh --con-genericas   quita también los servidores con nombre genérico (ver OJO)
#
# OJO con los servidores MCP: son de TODO Claude Code, no solo de Galeno. Quitar uno (y cerrar su sesión) lo desconecta también
# en cualquier otro proyecto del Mac que use el mismo nombre y dirección (le pasó a Rafa con mediclub-monorepo, 5 oct 2026). Galeno
# registra los suyos como `galeno-<nombre>`: esos son los únicos que son suyos. Los de nombre genérico (`notion`, `slack`…) pueden ser
# de otro proyecto: mira la lista antes de confirmar.
#
# Qué quita:
#   · los agentes de ~/Galeno (a la Papelera, recuperables) y el registro de Galeno (installation.json, draft.json)
#   · las conversaciones de esos agentes en Claude (a la Papelera): la carpeta de proyecto de Claude Code de cada uno y las
#     sesiones de la app de Claude cuya carpeta es un agente de ~/Galeno. Lo mismo que hace «Eliminar» dentro de la app: sin
#     esto, un agente nuevo con el mismo nombre volvía a la conversación del anterior. Nunca toca ~/.claude.json.
#   · la sesión de WhatsApp y todo el historial local (Application Support/Galeno/whatsapp) y su servicio de fondo
#   · los servidores MCP que Galeno registra en Claude Code, con su nombre propio: galeno-slack, galeno-notion… (los de nombre
#     genérico, solo con --con-genericas)
#   · las preferencias de la app (apariencia, sonidos, pantalla de arranque…)
# Qué NO hace (hay que hacerlo a mano, y al final lo recuerda):
#   · cerrar la sesión de Galeno en el teléfono (WhatsApp → Dispositivos vinculados)
#   · borrar la app de Slack con el nombre del agente en api.slack.com/apps
#   · tocar tu `slack` o `notion` de otra procedencia: solo se quitan si apuntan a los servidores oficiales

set -u
MODE=ask
GENERIC=0
for arg in "$@"; do
  case "$arg" in
    --con-genericas) GENERIC=1 ;;
    --yes) MODE=yes ;;
    --dry) MODE=dry ;;
    -h|--help) sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Opción desconocida: $arg (usa --yes, --dry, --con-genericas o --help)"; exit 2 ;;
  esac
done

SUPPORT="$HOME/Library/Application Support/Galeno"
AGENTS_DIR="$HOME/Galeno"
PLIST="$HOME/Library/LaunchAgents/com.galeno.whatsapp-bridge.plist"
LABEL="com.galeno.whatsapp-bridge"
# Los otros números de WhatsApp (`--account`): un servicio por número.
EXTRA_PLISTS=()
for f in "$HOME"/Library/LaunchAgents/com.galeno.whatsapp-bridge.*.plist; do
  [ -e "$f" ] && EXTRA_PLISTS+=("$f")
done
BUNDLE="com.galeno.Galeno"

# Servidores que Galeno registra, con la URL oficial: así no se toca uno tuyo con el mismo nombre.
declare -a SERVERS=(
  "slack|https://mcp.slack.com/mcp"
  "notion|https://mcp.notion.com/mcp"
  "jira|https://mcp.atlassian.com/v2/mcp"
  "gmail|https://gmailmcp.googleapis.com/mcp/v1"
  "fireflies|https://api.fireflies.ai/mcp"
  "granola|https://mcp.granola.ai/mcp"
  "fathom|https://api.fathom.ai/mcp"
  "claude-design|https://api.anthropic.com/v1/design/mcp"
  "google-drive|https://drivemcp.googleapis.com/mcp/v1"
  "google-docs|https://docsmcp.googleapis.com/mcp/v1"
  "google-sheets|https://sheetsmcp.googleapis.com/mcp/v1"
)

echo "== Lo que se va a quitar =="

echo "· Agentes en $AGENTS_DIR (a la Papelera):"
if [ -d "$AGENTS_DIR" ] && [ -n "$(ls -A "$AGENTS_DIR" 2>/dev/null)" ]; then
  ls -1 "$AGENTS_DIR" | sed 's/^/    /'
else
  echo "    (ninguno)"
fi

# Las conversaciones de esos agentes en Claude. Rutas exactas, no parecidos: la carpeta de proyecto de Claude Code se calcula
# igual que la nombra Claude (la ruta con cada carácter que no sea letra o cifra cambiado por «-»), solo para los agentes que
# hay ahora; y de la app de Claude, solo las sesiones cuyo `cwd` es una carpeta directamente dentro de ~/Galeno.
PROJECTS="$HOME/.claude/projects"
SESSIONS="$HOME/Library/Application Support/Claude/claude-code-sessions"
nfc() { printf '%s' "$1" | perl -CS -MUnicode::Normalize -pe '$_ = NFC($_)'; }
encoded() { printf '%s' "$1" | perl -CS -MUnicode::Normalize -pe '$_ = NFC($_); s/[^A-Za-z0-9]/-/g'; }
CLAUDE_ITEMS=()
if [ -d "$AGENTS_DIR" ]; then
  for dir in "$AGENTS_DIR"/*/; do
    [ -d "$dir" ] || continue
    project="$PROJECTS/$(encoded "${dir%/}")"
    [ -d "$project" ] && CLAUDE_ITEMS+=("$project")
  done
fi
if [ -d "$SESSIONS" ]; then
  ROOT_NFC="$(nfc "$AGENTS_DIR")"
  while IFS= read -r file; do
    cwd="$(plutil -extract cwd raw -o - "$file" 2>/dev/null)" || continue
    cwd="$(nfc "${cwd%/}")"
    [ "$(dirname "$cwd")" = "$ROOT_NFC" ] && CLAUDE_ITEMS+=("$file")
  done < <(find "$SESSIONS" -mindepth 3 -maxdepth 3 -name 'local_*.json' -type f 2>/dev/null)
fi
echo "· Conversaciones de esos agentes en Claude (a la Papelera):"
if [ ${#CLAUDE_ITEMS[@]} -gt 0 ]; then
  for item in "${CLAUDE_ITEMS[@]}"; do echo "    ${item#"$HOME"/}"; done
else
  echo "    (ninguna)"
fi

echo "· Estado de Galeno en $SUPPORT:"
for item in installation.json draft.json whatsapp bin; do
  [ -e "$SUPPORT/$item" ] && echo "    $item"
done
[ -e "$SUPPORT" ] || echo "    (no existe)"

echo "· Servicio de fondo de WhatsApp:"
if [ -e "$PLIST" ] || launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then echo "    $LABEL"; else echo "    (no instalado)"; fi
for f in ${EXTRA_PLISTS[@]+"${EXTRA_PLISTS[@]}"}; do echo "    $(basename "$f" .plist)"; done

echo "· Servidores MCP en Claude Code:"
FOUND=()
if command -v claude >/dev/null 2>&1; then
  LIST="$(claude mcp list 2>/dev/null)"
  # whatsapp: lo registra Galeno con su binario, no por URL.
  if [ "$GENERIC" -eq 1 ] && echo "$LIST" | grep -qE "^whatsapp:"; then FOUND+=("whatsapp"); fi
  for entry in "${SERVERS[@]}"; do
    name="${entry%%|*}"; url="${entry#*|}"
    # Solo los de nombre propio, salvo --con-genericas: los genéricos pueden ser de otro proyecto.
    candidates=("galeno-$name")
    [ "$GENERIC" -eq 1 ] && candidates+=("$name")
    for candidate in "${candidates[@]}"; do
      if echo "$LIST" | grep -E "^$candidate:" | grep -qF "$url"; then FOUND+=("$candidate"); fi
    done
  done
fi
if [ ${#FOUND[@]} -gt 0 ]; then printf '    %s\n' "${FOUND[@]}"; else echo "    (ninguno)"; fi

echo "· Preferencias de la app ($BUNDLE)"
echo

if [ "$MODE" = dry ]; then echo "(--dry: no se tocó nada)"; exit 0; fi
if [ "$MODE" = ask ]; then
  printf "¿Quitar todo esto? Se pierde la sesión de WhatsApp y su historial local. [escribe 'si'] "
  read -r answer
  [ "$answer" = "si" ] || { echo "Cancelado."; exit 1; }
fi

pkill -x Galeno 2>/dev/null && echo "- Galeno cerrado" && sleep 1

# 1. El servicio de fondo de WhatsApp, antes de borrar su estado.
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null && echo "- servicio de WhatsApp detenido"
rm -f "$PLIST" && echo "- plist de WhatsApp quitado"
for f in ${EXTRA_PLISTS[@]+"${EXTRA_PLISTS[@]}"}; do
  launchctl bootout "gui/$(id -u)/$(basename "$f" .plist)" 2>/dev/null && echo "- servicio de otro número detenido"
  rm -f "$f" && echo "- plist de otro número quitado"
done

# 2. Los servidores MCP.
for name in ${FOUND[@]+"${FOUND[@]}"}; do
  claude mcp remove "$name" -s user >/dev/null 2>&1 && echo "- MCP quitado: $name"
done

# 3. Los agentes, a la Papelera (recuperables).
if [ -d "$AGENTS_DIR" ] && [ -n "$(ls -A "$AGENTS_DIR" 2>/dev/null)" ]; then
  for dir in "$AGENTS_DIR"/*/; do
    [ -d "$dir" ] || continue
    osascript -e "tell application \"Finder\" to delete POSIX file \"${dir%/}\"" >/dev/null 2>&1 \
      && echo "- a la Papelera: $(basename "$dir")" || echo "! no pude mover a la Papelera: $dir"
  done
fi

# 3b. Sus conversaciones en Claude, a la Papelera también (recuperables). Solo las rutas que se listaron arriba.
for item in ${CLAUDE_ITEMS[@]+"${CLAUDE_ITEMS[@]}"}; do
  [ -e "$item" ] || continue
  osascript -e "tell application \"Finder\" to delete POSIX file \"$item\"" >/dev/null 2>&1 \
    && echo "- a la Papelera: ${item#"$HOME"/}" || echo "! no pude mover a la Papelera: $item"
done

# 4. El estado de Galeno. Rutas fijas y comprobadas: nunca una variable vacía.
for item in installation.json draft.json whatsapp bin; do
  target="$SUPPORT/$item"
  [ -e "$target" ] && rm -rf -- "$target" && echo "- borrado: $item"
done
rmdir "$SUPPORT" 2>/dev/null

# 5. Preferencias de la app.
defaults delete "$BUNDLE" >/dev/null 2>&1 && echo "- preferencias de la app borradas"
rm -rf -- "$HOME/Library/Saved Application State/$BUNDLE.savedState" 2>/dev/null

echo
echo "Listo. Faltan tres cosas a mano:"
echo "  1. En el teléfono: WhatsApp → Ajustes → Dispositivos vinculados → cierra la sesión de Galeno."
echo "  2. En api.slack.com/apps: borra la app con el nombre de tu agente si quedó alguna."
echo "  3. Si la app de Claude está abierta, ciérrala y ábrela: todavía recuerda los servidores y las conversaciones que se quitaron."
