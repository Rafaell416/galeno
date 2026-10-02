# whatsapp-bridge

Un único binario Go: el puente de WhatsApp (`whatsmeow`, QR, SQLite) y un servidor MCP de
**solo lectura**, que Claude Code lanza por stdio.

- Base: fork de [`lharries/whatsapp-mcp`](https://github.com/lharries/whatsapp-mcp) (MIT).
  Se conservan sus avisos de licencia (`LICENSE`) y el crédito (`NOTICE`).
- **Solo lectura por estructura de código, ya podado.** Se eliminaron —no se comentaron—
  `sendWhatsAppMessage`, el handler `/api/send`, los structs que solo usaba, y las funciones
  que solo existían para preparar audio a enviar (`analyzeOggOpus`, `placeholderWaveform`).
  También `requestHistorySync`, código sin usar que de paso llamaba a enviar. Detalle en
  `NOTICE`.
- **Nunca se añaden herramientas de envío**, ni detrás de un flag ni para pruebas.
  El CI lo verifica en cada PR: un guardia sobre los identificadores reales del puente
  (`client.SendMessage`, `client.Upload`, `/api/send`, `MarkRead`, `SendPresence`) hace
  fallar el build si reaparecen.
- Los datos de sesión (`store/`, bases SQLite) no se commitean.

Lo que todavía falta: portar el servidor MCP de Python a Go dentro de este mismo binario,
pruebas de verdad, `launchd`.

```bash
cd whatsapp-bridge
go build ./...
go vet ./...
go test ./...
```

Reglas de producto: `docs/03-especificacion-v0.0.1.md` §4.
