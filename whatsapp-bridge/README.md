# whatsapp-bridge

Un único binario Go: el puente de WhatsApp (`whatsmeow`, QR, SQLite) y un servidor MCP de
**solo lectura**, en el mismo proceso, con tres subcomandos.

```bash
galeno-whatsapp pair      # Vincula este Mac con tu WhatsApp (muestra un QR)
galeno-whatsapp serve     # Corre el servidor MCP (stdio); exige estar ya vinculado
galeno-whatsapp status    # Dice si hay una sesión vinculada, sin conectar a WhatsApp
```

El estado (sesión y mensajes) vive en `~/Library/Application Support/Galeno/whatsapp/`, no
en una carpeta relativa al directorio desde donde se invoque el binario.

## Las 9 herramientas MCP (todas de lectura)

Puerto a Go del servidor Python de upstream (`whatsapp-mcp-server/`, no incluido en este
repo), con el [SDK oficial de MCP para Go](https://github.com/modelcontextprotocol/go-sdk)
(`github.com/modelcontextprotocol/go-sdk`, mantenido con Google — lo preferí sobre el
popular pero no oficial `mark3labs/mcp-go`).

`search_contacts` · `list_messages` · `list_chats` · `get_chat` ·
`get_direct_chat_by_contact` · `get_contact_chats` · `get_last_interaction` ·
`get_message_context` · `download_media`.

**No existen** `send_message`, `send_file` ni `send_audio_message`. Ocho de las nueve leen
directo de la base local (`queries.go`); `download_media` llama a la función Go que ya
descarga medios (`media.go`) — en upstream esto eran dos procesos que se hablaban por HTTP
(Python ↔ Go); aquí es una sola llamada de función, en el mismo proceso.

## Por qué `serve` no puede imprimir nada por su cuenta

Durante `serve`, **stdout es el transporte MCP**: cualquier línea suelta ahí rompe el
JSON-RPC a mitad de sesión. `log.go` reemplaza el logger de whatsmeow (que escribe a stdout
por diseño) por uno que escribe a stderr, y lo mismo vale para los logs propios del puente.
Verificado de verdad, no solo diseñado así: corriendo `status` con los dos flujos separados,
stdout lleva exactamente la salida, stderr lleva exactamente los logs.

## Garantías de solo lectura

- **Ya podado del fork**: se eliminaron —no se comentaron— `sendWhatsAppMessage`, el
  handler `/api/send` (ya no existe ningún servidor HTTP: ver arriba), y las funciones que
  solo existían para preparar audio a enviar. Detalle en `NOTICE`.
- **El CI verifica dos veces**, en capas distintas:
  1. Un grep sobre el código fuente contra los identificadores reales del puente
     (`client.SendMessage`, `client.Upload`, `/api/send`, `MarkRead`, `SendPresence`).
  2. `TestNoSendSymbolsInOurOwnCode` compila el binario y lista sus símbolos con
     `go tool nm`, acotado a los que empiezan con `main.` (nuestro código, no el de
     `whatsmeow` ni del runtime de Go, que sí traen sus propias primitivas de red con
     "send" en el nombre). Si algún día una función nuestra vuelve a tener "send" en el
     nombre, esta prueba falla aunque el grep de texto no la vea venir.
- Los datos de sesión (`~/Library/Application Support/Galeno/whatsapp/`) no se commitean.

## Build universal (arm64 + amd64)

```bash
make universal   # produce bin/galeno-whatsapp, un Mach-O de dos arquitecturas
```

`go-sqlite3` usa cgo; el `Makefile` le pasa `CC="clang -arch ..."` por arquitectura y
combina los dos binarios con `lipo`.

```bash
cd whatsapp-bridge
go build ./...
go vet ./...
go test ./...
```

Reglas de producto: `docs/03-especificacion-v0.0.1.md` §4.
