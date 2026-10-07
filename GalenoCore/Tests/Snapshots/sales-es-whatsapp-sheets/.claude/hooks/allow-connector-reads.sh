#!/bin/bash
# Deja leer sin preguntar por los conectores de tu cuenta de Claude (Gmail,
# Calendar, Drive, Docs, Sheets) en la app de Claude, donde sus herramientas
# llevan otro nombre y las reglas de permiso no coinciden.
#
# El matcher de settings.json lo limita a las herramientas que solo leen.
# Enviar, escribir o compartir nunca pasa por aquí.
#
# Lo genera Galeno.
cat <<'JSON'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": "Galeno: read-only connector tool"
  }
}
JSON
