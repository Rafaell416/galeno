#!/bin/bash
# Exige confirmación humana antes de cualquier envío externo.
#
# El matcher de settings.json ya limita este hook a las herramientas
# de Slack y Gmail, así que no hace falta leer la entrada: siempre
# pedimos confirmación. Sin dependencias a propósito.
#
# Lo genera Galeno. Si lo editas, el agente podrá enviar sin preguntar.
cat <<'JSON'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": "Esto le envía un mensaje a otras personas. Revisa el destinatario y el contenido antes de aprobar."
  }
}
JSON
