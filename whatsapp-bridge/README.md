# whatsapp-bridge

Un único binario Go: el puente de WhatsApp (`whatsmeow`, QR, SQLite) y un servidor MCP de
**solo lectura**, con siete subcomandos.

```bash
galeno-whatsapp pair             # Vincula este Mac con tu WhatsApp (muestra un QR)
galeno-whatsapp sync             # Mantiene la conexión viva de fondo; nunca sirve MCP
galeno-whatsapp serve            # Sirve las 9 herramientas MCP por stdio; no conecta a WhatsApp
galeno-whatsapp status           # Dice si hay una sesión vinculada, sin conectar a WhatsApp
galeno-whatsapp install-launchd  # Instala "sync" como LaunchAgent (arranca solo tras el login)
galeno-whatsapp chats --json     # Lista los chats guardados, para la pantalla "elige qué leer"
galeno-whatsapp version          # Imprime la versión del bridge (solo el número)
```

El estado (sesión y mensajes) vive en `~/Library/Application Support/Galeno/whatsapp/`, no
en una carpeta relativa al directorio desde donde se invoque el binario.

## Por qué `serve` no conecta a WhatsApp

El transporte MCP por stdio lanza **un proceso nuevo por cada sesión** de Claude Code —no se
adjunta a uno que ya esté corriendo—. Si ese proceso sostuviera su propia conexión de
whatsmeow *y además* hubiera un proceso de fondo haciendo lo mismo (por ejemplo, vía
`launchd`), habría dos conexiones simultáneas autenticadas como el mismo dispositivo
vinculado — justo el tipo de cosa que WhatsApp puede marcar como anómala.

Por eso la conexión y el servicio MCP son responsabilidades separadas, igual que en el
diseño original de upstream (Python ↔ Go por HTTP, con el Go como único que conectaba):

- **`sync`** es el único subcomando que llama a `client.Connect()`. Recibe mensajes y los
  guarda en SQLite, y se queda corriendo para siempre (hasta `SIGINT`/`SIGTERM`). Pensado
  para correr de fondo, vía `install-launchd`.
- **`serve`** solo abre la base local y sirve las 9 herramientas MCP por stdio; nunca
  conecta a WhatsApp. Lo lanza Claude Code, una vez por sesión — puede haber varias
  instancias de `serve` a la vez sin ningún riesgo, porque ninguna sostiene una conexión.

Consecuencia directa: si pides `download_media` para un archivo que `sync` todavía no
descargó, `serve` no puede ir a buscarlo en vivo (no tiene conexión). La herramienta responde
`{success: false, message: "..."}` pidiendo confirmar que `sync` esté corriendo, en vez de
intentar conectarse por su cuenta.

## El QR: en terminal y como PNG

`pair` imprime el QR en la terminal (como siempre) y además lo escribe como PNG en
`<stateDir>/pair-qr.png`, para que una interfaz gráfica (GalenoApp) lo pueda mostrar sin
tener que parsear la salida de una terminal. whatsmeow rota el código cada ~60 s mientras no
se escanea; cada rotación reescribe el mismo archivo. Al terminar `pair` (éxito, error o
timeout) el PNG se borra — un QR viejo en disco no sirve para nada y podría confundir a quien
lo esté mostrando.

## `install-launchd`: mantener `sync` corriendo tras el login

```bash
galeno-whatsapp install-launchd
```

Escribe un `LaunchAgent` en `~/Library/LaunchAgents/com.galeno.whatsapp-bridge.plist` (la
plantilla vive en `launchd.go`, función `renderLaunchdPlist`) y lo activa con
`launchctl bootstrap gui/<uid>`. El `ProgramArguments` apunta **siempre a `sync`, nunca a
`serve`** — ver la sección anterior sobre por qué. Es idempotente: si ya había un LaunchAgent
instalado (por ejemplo apuntando a un binario de una versión anterior), lo desactiva primero
(`launchctl bootout`) y lo vuelve a activar con el plist nuevo.

`stdout`/`stderr` de `sync` quedan en `<stateDir>/sync.log`.

El `Label` (`com.galeno.whatsapp-bridge`) es **provisional**: cuando exista el bundle ID
definitivo de `GalenoApp`, debería alinearse con ese en vez de quedarse con este valor
genérico.

No instales esto contra una cuenta real salvo que quieras que `sync` arranque una conexión
de verdad al vincular: pensado para que lo dispare GalenoApp después de un `pair` exitoso.

## Las 9 herramientas MCP (todas de lectura)

Puerto a Go del servidor Python de upstream (`whatsapp-mcp-server/`, no incluido en este
repo), con el [SDK oficial de MCP para Go](https://github.com/modelcontextprotocol/go-sdk)
(`github.com/modelcontextprotocol/go-sdk`, mantenido con Google — lo preferí sobre el
popular pero no oficial `mark3labs/mcp-go`).

`search_contacts` · `list_messages` · `list_chats` · `get_chat` ·
`get_direct_chat_by_contact` · `get_contact_chats` · `get_last_interaction` ·
`get_message_context` · `download_media`.

**Qué chats ve el agente: todos los que `sync` guardó.** No hay un filtro por chat, a propósito.
Una lista fija de chats permitidos obligaría a reconfigurar cada vez que aparece un grupo nuevo,
y eso es una mala experiencia. Elegir chats en el wizard le dice al agente en qué enfocarse (va
en su `AGENTS.md`); no le quita acceso a los demás. Si hace falta una barrera algún día, la
opción es una lista de **exclusión** (chats privados que nunca ve), no de inclusión.

**No existen** `send_message`, `send_file` ni `send_audio_message`. Ocho de las nueve leen
directo de la base local (`queries.go`); `download_media` llama a la función Go que ya
descarga medios (`media.go`) — en upstream esto eran dos procesos que se hablaban por HTTP
(Python ↔ Go); aquí es una sola llamada de función, en el mismo proceso.

## `chats --json`: la lista para "elige qué leer"

```bash
./galeno-whatsapp chats --json
```

Escribe en stdout un arreglo JSON, del chat más reciente al más antiguo (los logs van a
stderr). No abre ninguna conexión a WhatsApp y lee todo lo que `sync` guardó:

```json
[
  {
    "jid": "120363021234567890@g.us",
    "name": "Equipo Cliente A",
    "is_group": true,
    "last_message_time": "2026-10-03T09:41:00-05:00"
  },
  {
    "jid": "98765432101234@lid",
    "name": "Ana Restrepo",
    "is_group": false,
    "last_message_time": "2026-10-02T18:05:00-05:00",
    "aliases": ["573001112233@s.whatsapp.net"]
  }
]
```

- **Una persona, una entrada.** WhatsApp puede identificar al mismo contacto por su número
  (`@s.whatsapp.net`) o por un identificador oculto (`@lid`), y la base puede tener una fila de
  cada uno. Si las dos existen salen como una entrada, con el JID de la más reciente y el otro
  en `aliases`.
- **Nombres.** La base guarda el número como nombre cuando no encontró el de la persona. `chats`
  lo completa al leer con los contactos de whatsmeow (nombre de la agenda o el que la persona se
  puso), sin escribir en la base. Quien nunca guardaste ni escribió con nombre sigue saliendo con
  su número.
- Sin `--json` es un error de uso (código 2).

## `version`

Imprime solo el número (`0.2.0`), para que la app lo lea sin separar nada. Es independiente de la
versión de la app: el bridge es la capa que más se rompe por causas externas y tiene que poder
parchearse por su cuenta (`docs/03` §4f). Vive en `version.go` como variable, así que se puede
fijar al compilar con `-ldflags "-X main.bridgeVersion=…"`. Sube el MINOR cuando cambia lo que
la app o Claude Code ven (subcomandos, herramientas MCP) y el PATCH cuando solo se corrige algo
por dentro. El servidor MCP informa esta misma versión.

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

## Mantenimiento: es la capa que más se rompe

De las tres capas en que se actualiza Galeno (`docs/03-especificacion-v0.0.1.md` §4f), el
bridge es la que se rompe por causas externas: cuando Meta cambia su protocolo, un
`whatsmeow` viejo deja de conectar. Ya pasó una vez: con la versión de marzo de 2025 el
socket se cerraba (`websocket: close 1006`) justo después de mostrar el QR, y se arregló
con `go get go.mau.fi/whatsmeow@latest`. Si el bridge deja de conectar, empieza por ahí.

Al actualizar `whatsmeow` conviene esperar cambios de firma (la última vez varias llamadas
pasaron a pedir `context.Context`) y un requisito de Go más nuevo, y volver a correr
`go test ./...`: `TestNoSendSymbolsInOurOwnCode` confirma que el upgrade no reintrodujo
ninguna vía de envío.

**Pendiente:** el esquema de versiones y cómo se parchea el bridge sin re-releasear la app, si
viaja empaquetado dentro de ella (`HANDOFF.md` §12). El número ya existe: ver `version`.

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
