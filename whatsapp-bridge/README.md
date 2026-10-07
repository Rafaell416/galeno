# whatsapp-bridge

Un único binario Go: el puente de WhatsApp (`whatsmeow`, QR, SQLite) y un servidor MCP, con nueve subcomandos.
**Lee todo lo que `sync` guardó y, desde la 0.4.0, envía por un solo camino:** `send_message`, texto a una persona o a
un grupo del usuario, siempre con la aprobación del usuario, por una bandeja de salida y con guardas en el código
(decisión de Rafa, 7 oct 2026; diseño en `docs/09-plan-simon-envio-y-prospeccion.md` §4, con sus enmiendas). No hay
adjuntos, audios, listas de difusión, estados, canales, «leído» ni «escribiendo…», y no los habrá.

```bash
galeno-whatsapp pair             # Vincula este Mac con tu WhatsApp (muestra un QR)
galeno-whatsapp sync             # Mantiene la conexión viva de fondo y saca la bandeja de salida; nunca sirve MCP
galeno-whatsapp serve            # Sirve las 9 lecturas MCP por stdio; no conecta a WhatsApp
galeno-whatsapp serve --with-send  # Lo mismo, más send_message (deja el mensaje en la bandeja de salida)
galeno-whatsapp status           # Dice si hay una sesión vinculada, sin conectar a WhatsApp
galeno-whatsapp status --json    # Lo mismo para la app: {linked, number, linked_at, version}
galeno-whatsapp unlink           # Cierra la sesión vinculada (no borra el historial) para volver a vincular
galeno-whatsapp install-launchd  # Instala "sync" como LaunchAgent (arranca solo tras el login)
galeno-whatsapp chats --json     # Lista los chats guardados, para la pantalla "elige qué leer"
galeno-whatsapp outbox --json    # Estado de la bandeja de salida: enviados hoy, topes y pausa (para la app)
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
  guarda en SQLite, saca los de la bandeja de salida, y se queda corriendo para siempre (hasta
  `SIGINT`/`SIGTERM`). Pensado para correr de fondo, vía `install-launchd`.
- **`serve`** solo abre la base local y sirve las herramientas MCP por stdio; nunca
  conecta a WhatsApp. Lo lanza Claude Code, una vez por sesión — puede haber varias
  instancias de `serve` a la vez sin ningún riesgo, porque ninguna sostiene una conexión.
  Por eso tampoco envía: deja el mensaje en la bandeja y lo saca `sync` (ver «Envío»).

Consecuencia directa: si pides `download_media` para un archivo que no está en disco,
`serve` no puede ir a buscarlo en vivo (no tiene conexión), y hoy `sync` tampoco descarga
adjuntos. La herramienta responde `{success: false, message: "..."}` diciendo eso tal cual, en
vez de intentar conectarse por su cuenta o de mandar a reintentar.

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

## Las 9 herramientas MCP de lectura

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

La décima, `send_message`, es la única que envía y tiene su propia sección abajo. **No existen** `send_file` ni
`send_audio_message`, y no se añaden. Ocho de las nueve lecturas leen
directo de la base local (`queries.go`); `download_media` solo mira lo que ya está en disco
(`media.go`): el bridge todavía no descarga adjuntos.

## Envío: `send_message`, la bandeja de salida y las guardas

```
Claude Code ──stdio──▶ serve --with-send: send_message ──INSERT──▶ outbox (SQLite)
                                                                       │
                              sync (launchd, conexión viva) ◀──────────┘ cada 2 s
                              └─ envía ──▶ WhatsApp ──▶ UPDATE outbox (sent | failed)
serve espera hasta 30 s el cambio de estado y se lo devuelve a Claude Code
```

**Entrada:** `recipient` (un número en formato internacional, solo dígitos; un JID `@s.whatsapp.net`; o el JID
`@g.us` de un grupo), `group_name` (solo para un grupo: su nombre exacto) y `message` (texto). **Salida:** `{status, chat_jid, sent_at, scheduled_for, outbox_id, error, reason}`.

| `status` | Qué pasó |
|---|---|
| `sent` | Salió. Queda también en el historial (`messages`, `is_from_me = 1`), así que el agente lo ve con las lecturas de siempre. |
| `queued` | Quedó programado para `scheduled_for`, uno o dos minutos después (por el espaciado). `serve` no espera. |
| `pending` | Podía salir ya, pero `sync` no lo sacó en 30 s (no está corriendo o no tiene conexión). Sale cuando vuelva. |
| `failed` | WhatsApp no lo aceptó, o el número no tiene WhatsApp. `error` dice por qué. **No se reintenta solo.** |
| `rejected` | Una guarda lo frenó. `reason` dice cuál. **No se escribe nada en la bandeja.** |

**La herramienta solo existe si `serve` se lanza con `--with-send`.** Es a propósito: la config que Galeno generaba
antes del envío permite el servidor entero (`mcp__whatsapp__*`), así que una carpeta de agente vieja con un bridge
nuevo enviaría **sin preguntar**. `serve` a secas sigue ofreciendo las 9 lecturas, como la 0.3.0. El motor escribe
`--with-send` en el `.mcp.json` en la misma generación en que escribe la regla `ask` y el hook de aprobación (PR 3
de `docs/09`).

### Las guardas viven en el código

No en el prompt: ni una instrucción ni una página que el agente lea las pueden saltar. `serve` las comprueba todas
antes de escribir en la bandeja, y `sync` vuelve a comprobar las que dependen del momento (`outbox.go`).

| Guarda | Valor | Dónde |
|---|---|---|
| Solo una persona (`@s.whatsapp.net`) o un grupo (`@g.us`). Se rechazan listas de difusión, estados y canales | fijo | `serve`, y otra vez `sync` justo antes de salir |
| Grupo: tiene que estar entre los chats del usuario, y `group_name` tiene que ser su nombre guardado | fijo | `serve` |
| Grupo: que siga existiendo y el usuario siga dentro (`GetGroupInfo`); si no, `failed` | fijo | `sync` |
| Un chat `@lid` se pasa a su número con lo que whatsmeow tiene guardado (local); si no se conoce, se rechaza | fijo | `serve` |
| Número de 8 a 15 dígitos | fijo | `serve` |
| Que el número tenga WhatsApp (`IsOnWhatsApp`); si no, `failed` | fijo | `sync` |
| Tope diario total | **40** (techo **80**) | `serve`; `sync` lo vuelve a mirar |
| Tope diario de chats nuevos (sin mensajes previos con esa persona) | **15** (techo **25**) | `serve` |
| Tope diario de mensajes a grupos (además cuentan para el total) | **10** (techo **20**) | `serve` |
| Espaciado entre envíos: 45–120 s al azar | fijo | `serve` programa; `sync` nunca baja de 45 s |
| El mismo texto (sin mirar mayúsculas ni espacios) a más de 3 chats en un día | fijo | `serve` |
| Largo máximo: 1.000 caracteres | fijo | `serve` |
| Pausa total: archivo `send-paused` | — | `serve` rechaza; `sync` no envía y cancela lo que había en cola |

- **El nombre del grupo es parte de la aprobación.** El usuario aprueba mirando lo que pidió el agente, y de un grupo
  eso es un identificador (`120363…@g.us`) que no le dice nada. Por eso `send_message` exige `group_name`, y el bridge
  rechaza el mensaje si no es el nombre guardado de ese grupo (sin mirar mayúsculas ni espacios), si el grupo no está
  entre los chats, o si se guardó sin nombre. Un `group_name` junto a una persona también se rechaza.
- **No hay guarda de horario ni de festivos** (decisión de Rafa, 7 oct 2026). El bridge no decide a qué hora ni qué
  día se escribe: lo decide el usuario al aprobar. La descripción de la herramienta le pide al agente avisarle antes
  de proponer un mensaje de noche, en domingo o en festivo.
- **Los topes son del día en que el mensaje sale**, no del día en que se pidió: uno que por el espaciado sale pasada
  la medianoche cuenta para mañana. Cuentan lo enviado y lo que está en cola para ese día.
- **`send-limits.json`** (`{"daily_total": 40, "daily_new_chats": 15, "daily_groups": 10}`) y **`send-paused`** viven en el directorio de
  estado. Los escribe la app; el agente no puede escribir ahí. Un valor por encima del techo se queda en el techo, y
  un archivo ausente o ilegible vale por los topes por defecto.
- **En pausa, lo que estaba en cola se cancela** (`rejected`): al quitar la pausa no sale de golpe lo acumulado.
- **Si `sync` se detiene a mitad de un envío**, ese mensaje queda `failed` diciendo que no se sabe si llegó. No se
  repite: antes de tocar la red, el mensaje queda reservado con el id con el que va a salir.
- Sin `sync` corriendo el mensaje se queda `pending` y sale cuando `sync` vuelva, respetando el espaciado y el tope
  del día. Lo que ya no quepa en el tope de ese día queda `failed` diciendo eso, y no se reintenta.

**Prueba manual** (no hay forma de probar el envío real sin una cuenta): enviar a un segundo número propio; comprobar
que llega, que aparece en `list_messages`, y que con `sync` detenido queda `pending` y sale al volver.

## `outbox --json`: la bandeja, para la app

```bash
./galeno-whatsapp outbox --json
```

Solo lee, y no abre ninguna conexión a WhatsApp. No incluye el texto de los mensajes.

```json
{
  "paused": false,
  "limits": { "daily_total": 40, "daily_new_chats": 15, "daily_groups": 10,
              "max_daily_total": 80, "max_daily_new_chats": 25, "max_daily_groups": 20 },
  "today": { "sent": 12, "pending": 3, "new_chats": 7, "groups": 2 },
  "pending_total": 3,
  "recent": [
    { "id": 15, "chat_jid": "573001112233@s.whatsapp.net", "status": "pending", "is_new_chat": true,
      "created_at": "2026-10-07T10:02:11-05:00", "not_before": "2026-10-07T10:03:40-05:00" }
  ]
}
```

`today` es lo que cuenta para los topes de hoy (`sent` + `pending` contra `daily_total`; `new_chats` contra
`daily_new_chats`; `groups` contra `daily_groups`). `recent` son los últimos 50, del más nuevo al más viejo, con `sent_at` y `error` cuando los hay.
Sin `--json` es un error de uso (código 2).

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

Imprime solo el número (`0.4.0`), para que la app lo lea sin separar nada. Es independiente de la
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

## Garantías del envío

- **Un solo camino.** La única llamada a whatsmeow que envía está en `outbox.go` (`liveClient.SendText`), y solo
  manda texto. Lo que se podó del fork sigue sin existir: el handler `/api/send` (no hay ningún servidor HTTP), el
  envío de archivos y el de audios. Detalle en `NOTICE`.
- **Se verifica en tres capas**, y las tres corren con `go test ./...`:
  1. `TestSendCallOnlyInOutbox`: un grep sobre el código fuente. `client.SendMessage(` solo puede aparecer en
     `outbox.go`; `client.Upload(`, `/api/send`, `MarkRead`, `SendPresence` y `SendChatPresence`, en ningún archivo.
     El CI hace la misma comprobación (`.github/workflows/ci.yml`).
  2. `TestOnlyAllowedSendSymbols` compila el binario y lista sus símbolos con `go tool nm`, acotado a los que
     empiezan con `main.` (nuestro código, no el de `whatsmeow` ni del runtime de Go). La lista blanca es exacta:
     `handleSendMessage`, `(*outboxDispatcher).sendOutboxItem` y `(*liveClient).SendText`. Cualquier otra función
     nuestra con "send" en el nombre es un segundo camino de envío y hace fallar la prueba.
  3. `TestSendMessageOnlyExistsWhenServeIsAskedForIt` conecta un cliente MCP de verdad y comprueba que `serve` a
     secas ofrece exactamente las 9 lecturas, y con `--with-send`, esas más `send_message` y ninguna otra.
- Las guardas tienen cada una su prueba en `outbox_test.go`, sin red: `sync` despacha con un cliente simulado detrás
  de la interfaz `messageSender`.
- Los datos de sesión (`~/Library/Application Support/Galeno/whatsapp/`) no se commitean.

## Mantenimiento: es la capa que más se rompe

De las tres capas en que se actualiza Galeno (`docs/03-especificacion-v0.0.1.md` §4f), el
bridge es la que se rompe por causas externas: cuando Meta cambia su protocolo, un
`whatsmeow` viejo deja de conectar. Ya pasó una vez: con la versión de marzo de 2025 el
socket se cerraba (`websocket: close 1006`) justo después de mostrar el QR, y se arregló
con `go get go.mau.fi/whatsmeow@latest`. Si el bridge deja de conectar, empieza por ahí.

Al actualizar `whatsmeow` conviene esperar cambios de firma (la última vez varias llamadas
pasaron a pedir `context.Context`) y un requisito de Go más nuevo, y volver a correr
`go test ./...`: `TestOnlyAllowedSendSymbols` y `TestSendCallOnlyInOutbox` confirman que el
upgrade no abrió un segundo camino de envío.

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
