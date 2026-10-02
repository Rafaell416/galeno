# whatsapp-bridge

Un único binario Go: el puente de WhatsApp (`whatsmeow`, QR, SQLite) y un servidor MCP
de **solo lectura**, que Claude Code lanza por stdio.

**Fase 3.** El código se añade en esa fase; por ahora la carpeta está vacía.

- Base: fork de [`lharries/whatsapp-mcp`](https://github.com/lharries/whatsapp-mcp) (MIT).
  Se conservan sus avisos de licencia.
- Se eliminan las tres herramientas de envío (`send_message`, `send_file`,
  `send_audio_message`) y el servidor MCP se porta de Python a Go.
- **Nunca se añaden herramientas de envío**, ni detrás de un flag ni para pruebas.
- Los datos de sesión (`store/`, bases SQLite) no se commitean.

Reglas de producto: `docs/03-especificacion-v0.0.1.md` §4.
