# whatsapp-bridge

Un único binario Go: el puente de WhatsApp (`whatsmeow`, QR, SQLite) y un servidor MCP
de **solo lectura**, que Claude Code lanza por stdio.

**Fase 3.** El módulo ya compila y corre sus pruebas, pero todavía no tiene comportamiento:
`main.go` solo imprime la versión. El puente y el MCP se escriben en esa fase.

```bash
go build ./... && go vet ./... && go test ./...
```

- Base: fork de [`lharries/whatsapp-mcp`](https://github.com/lharries/whatsapp-mcp) (MIT).
  Se conservan sus avisos de licencia.
- Se eliminan las tres herramientas de envío (`send_message`, `send_file`,
  `send_audio_message`) y el servidor MCP se porta de Python a Go.
- **Nunca se añaden herramientas de envío**, ni detrás de un flag ni para pruebas.
  El CI lo verifica en cada PR: un `grep` de `send_message`, `send_file` y `send_audio`
  sobre los `.go` de esta carpeta hace fallar el build si aparecen, aunque sea en un comentario.
- Los datos de sesión (`store/`, bases SQLite) no se commitean.

Reglas de producto: `docs/03-especificacion-v0.0.1.md` §4.
