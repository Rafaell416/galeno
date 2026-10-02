# whatsapp-bridge

Un único binario Go: el puente de WhatsApp (`whatsmeow`, QR, SQLite) y un servidor MCP de
**solo lectura**, que Claude Code lanza por stdio.

> ⚠️ **Estado de este commit: todavía NO es de solo lectura.** `main.go` es el puente de
> lharries tal cual, sin podar — `sendWhatsAppMessage`, el handler `/api/send` y las
> funciones de preparar audio para enviar **siguen presentes**. Se eliminan en el commit
> siguiente, antes de que esto llegue a GitHub (ver `AGENTS.md`, líneas rojas). **No
> compiles y corras esto contra una cuenta real todavía.**

- Base: fork de [`lharries/whatsapp-mcp`](https://github.com/lharries/whatsapp-mcp) (MIT).
  Se conservan sus avisos de licencia (`LICENSE`) y el crédito (`NOTICE`).
- Se eliminan las herramientas de envío (`sendWhatsAppMessage`, el handler `/api/send`, y
  todo lo que solo existía para prepararlas) y el servidor MCP se escribe desde cero en Go,
  dentro del mismo binario — nunca se empaqueta el servidor Python original.
- **Nunca se añaden herramientas de envío**, ni detrás de un flag ni para pruebas.
  El CI lo verifica en cada PR: un guardia sobre los identificadores reales del puente
  (`client.SendMessage`, `client.Upload`, `/api/send`) hace fallar el build si aparecen.
- Los datos de sesión (`store/`, bases SQLite) no se commitean.

Lo que todavía falta: podar el envío (siguiente paso), portar el servidor MCP de Python a
Go, pruebas de verdad, `launchd`.

```bash
cd whatsapp-bridge
go build ./...
go vet ./...
go test ./...
```

Reglas de producto: `docs/03-especificacion-v0.0.1.md` §4.
