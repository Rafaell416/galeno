# Galeno — estado al cerrar la Fase 3b

**3 de octubre de 2026** · `main` en `c3f545a` · los PRs anteriores están mergeados · CI en verde (`swift`, `go`, `go-universal`)

Este documento es una foto de hoy. Para el detalle de cada fase, la guía de construcción; para las decisiones, `HANDOFF.md` y `docs/03-especificacion-v0.0.1.md`.

---

## 1. Qué hay hecho

### Funcionalidades

**El motor (`GalenoCore`, Swift).** Dado lo que el usuario eligió, escribe toda la configuración de Claude Code de un agente:

- `AGENTS.md` con la identidad, el proyecto, las reglas y cómo usar la memoria, en español o inglés.
- Permisos: nada de terminal; los envíos por Slack y Gmail piden aprobación humana (regla más hook); el agente solo escribe en `memoria/`.
- `.mcp.json` con los diez tipos de herramienta, sin ningún token (solo el `client_id` público de las apps OAuth del cliente).
- Tres subagentes (`scribe`, `tracker`, `reporter`) de solo lectura, sin acceso a Slack ni Gmail.
- La memoria del proyecto (`memoria/proyecto.md`): el agente la mantiene y el motor nunca la sobrescribe.
- **Varios agentes**: la instalación recuerda las conexiones compartidas y la lista de agentes, arma el punto de partida de un agente nuevo y le asigna su carpeta `~/Galeno/<agente>/`.
- **Regenerar**: aplicar el generador sobre una carpeta existente la deja idéntica a una nueva con la misma config. Un error no la deja a medias.
- Crea por API la app de Slack del cliente (manifiesto y llamada a la API).

**El bridge de WhatsApp (`whatsapp-bridge`, Go).** Un binario, de solo lectura por estructura de código (no existe función de envío, y un test lo comprueba):

- Vincula el Mac por QR (en terminal y como imagen para la app), y `sync` guarda todos los mensajes; `serve` los expone por MCP con 9 herramientas de lectura.
- `sync` y `serve` están separados a propósito: solo `sync` se conecta a WhatsApp, para que nunca haya dos conexiones a la vez.
- `install-launchd` hace que `sync` arranque solo tras el login. `chats --json` y `version` son los que la app necesita.
- Binario universal (arm64 + x86_64) compilado en CI.

### Especificaciones técnicas

| | |
|---|---|
| **Lenguajes** | Swift 6 (`swift-tools-version 6.0`, macOS 14+), sin dependencias externas · Go 1.26 (`go.mod`; si tu Go es más viejo, descarga la 1.26 solo) |
| **Dependencias Go** | `whatsmeow` (snapshot del 29 sep 2026), SDK oficial de MCP (`go-sdk` v1.8.0), `go-sqlite3` (cgo), `rsc.io/qr`, `qrterminal` |
| **Persistencia** | `installation.json` (agentes, conexiones, idioma) · `whatsmeow.db` (sesión) · `messages.db` (historial) · `AgentConfig` v2, instalación v1 |
| **Pruebas** | 164 en Swift (incluye snapshots de árbol completo en español e inglés) · 18 en Go (incluye la guarda de símbolos de envío) |
| **CI** | Cada PR y cada push a `main`: `swift` (macOS), `go` (Linux), `go-universal` (macOS, `lipo -archs` + arranque) |
| **Versiones** | Bridge `0.2.0`, independiente de la app · motor `0.0.1` |
| **Seguridad** | Ningún secreto en la config ni en servidores propios · `deny` de `Bash`/`NotebookEdit` · `Edit` solo en `memoria/` · hook de aprobación en envíos externos · lista blanca de herramientas en los subagentes |
| **Qué ve el agente de WhatsApp** | **Todos** los chats sincronizados, incluidos los personales. Se descartó filtrar por chat (obligaba a reconfigurar con cada grupo nuevo). Lo elegido en el wizard es su foco, no una barrera |
| **Dónde vive el código** | `GalenoCore/` motor · `whatsapp-bridge/` bridge · `docs/` spec y diseño · `.github/workflows/ci.yml` CI · `GalenoApp/`, `skills/`, `site/` solo tienen README |

---

## 2. Qué falta hasta el final

| Fase | Qué falta |
|---|---|
| **3** (pendiente tuyo) | Probar que `sync` arranca solo tras reiniciar el Mac con `install-launchd` |
| **4** App: el wizard | Proyecto Xcode, los 10 pasos, ES/EN, conectar cada herramienta, QR en pantalla, **crear la app OAuth de Slack y Google** (automatización de navegador, lo más frágil) |
| **4b** App: el home | Lista de agentes, abrir en la app de Claude o Terminal, wizard corto, gestionar config, salud (re-vincular WhatsApp) |
| **5** Skills | Las 17 skills reales, el catálogo curado y publicarlas como fuente remota **con verificación de integridad** |
| **6** QA | Matriz de pruebas en un Mac limpio, ES y EN |
| **7** Licencia | Claves Ed25519 verificadas sin conexión |
| **8** Distribución | Firma, notarización, DMG, release automático, **Sparkle** |
| **9** Sitio | Dominio y sitio, con el appcast y las skills remotas |
| **10** Cobro | Stripe, webhook y email con la licencia |
| **11** Lanzamiento | Beta con 2 PMs, lanzamiento, soporte |

**Decisiones abiertas que conviene cerrar pronto** (detalle en `HANDOFF.md` §12): cómo se verifica la integridad de las skills remotas · cómo abrir una carpeta en la app de Claude desde Galeno · cuántos agentes cubre una licencia · cómo se renombra y elimina un agente · qué hacer cuando la memoria crezca · esquema de versiones del bridge · y que el wizard avise de que el agente puede leer todos los chats.

---

## 3. Arquitectura

Leyenda: `[HECHO]` está construido · `[PARCIAL]` a medias · `[PENDIENTE]` falta · `[EXTERNO]` no es nuestro.

```text
EL USUARIO  (un PM, no técnico: vive en WhatsApp, Slack, Jira, Notion, Google)
                           │
                           ▼
┌────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ GALENO.APP  (Swift / SwiftUI)  ·  GalenoApp/                                                       [PENDIENTE] │
│                                                                                                                │
│ Hoy solo existe GalenoApp/README.md: no hay proyecto Xcode todavía.                                            │
│                                                                                                                │
│ Wizard de 10 pasos, ES/EN, pantallas de dopamina ............. Fase 4   [PENDIENTE]                            │
│ Conectar herramienta por herramienta + QR de WhatsApp ........ Fase 4   [PENDIENTE]                            │
│ Crear la app OAuth de Slack/Google por el cliente ............ Fase 4   [PENDIENTE]                            │
│ Home: lista de agentes, wizard corto, gestionar, salud ....... Fase 4b  [PENDIENTE]                            │
│ Licencia (Ed25519), firma, notarización, DMG, Sparkle ........ Fases 7-8 [PENDIENTE]                           │
└────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
                           │ la usa como librería                                     │ la lanza y supervisa
                           ▼                                                          ▼
┌──────────────────────────────────────────────────────┐   ┌─────────────────────────────────────────────────────┐
│ GALENOCORE  — el motor                       [HECHO] │   │ WHATSAPP-BRIDGE  (Go)                       [HECHO] │
│                                                      │   │                                                     │
│ GalenoCore/Sources/GalenoCore/                       │   │ whatsapp-bridge/  · un binario, 7 subcomandos       │
│                                                      │   │                                                     │
│ Model/         AgentConfig v2, Tool (10), Sources,   │   │ pair      vincula por QR (terminal + pair-qr.png)   │
│                SendingRules, SelectedSkill, Language │   │ sync      ÚNICA conexión a WhatsApp; guarda todo    │
│ Generator/     ConfigGenerator: calcula todo y luego │   │           (la mantiene launchd)                     │
│                escribe; regenera = igual que nueva   │   │ serve     MCP por stdio, 9 herramientas de          │
│                AgentsFile · Settings · MCP(+Catalog) │   │           lectura, sin conexión propia              │
│                ApprovalHook · Memory · Subagents ·   │   │ status    ¿hay sesión vinculada?                    │
│                SkillsInstaller                       │   │ chats     --json: lista para "elige qué leer"       │
│ Installation/  GalenoInstallation, AgentRecord,      │   │ version   0.2.0 (propia, independiente de la app)   │
│                SharedConnection, InstallationStore,  │   │ install-launchd  arranca sync tras el login         │
│                AgentFolder (~/Galeno/<agente>/)      │   │                                                     │
│ SlackSetup/    Manifest + Provisioner (crea la app   │   │ No existe código de envío (lo verifica un test      │
│                de Slack por API)      [PARCIAL]      │   │ sobre los símbolos del binario) · 18 tests          │
│ galeno-gen     herramienta de desarrollo, no se      │   └─────────────────────────────────────────────────────┘
│                distribuye   · 164 tests              │                                                          
└──────────────────────────────────────────────────────┘                                                          
                           │  escribe
                           ▼
┌────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ LA CARPETA DEL AGENTE  ~/Galeno/<agente>/   (la escribe el motor)                                      [HECHO] │
│                                                                                                                │
│ AGENTS.md · CLAUDE.md ..... identidad, reglas, proyecto y memoria (CLAUDE.md importa los dos)                  │
│ .mcp.json ................. los servidores MCP (WhatsApp local + hospedados), sin tokens                       │
│ .claude/settings.json ..... Bash fuera · envíos por Slack/Gmail piden aprobación · solo escribe en memoria/    │
│ .claude/hooks/ ............ hook que exige aprobación humana en todo envío externo                             │
│ .claude/agents/ ........... scribe · tracker · reporter (solo lectura, sin Slack ni Gmail)                     │
│ .claude/skills/ ........... las skills marcadas        [las 17 skills reales: PENDIENTE, Fase 5]               │
│ memoria/proyecto.md ....... notas del agente; el motor la crea una vez y nunca la sobrescribe                  │
└────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
                           │  Claude Code la abre y la carga
                           ▼
┌──────────────────────────────────────────────────────┐   ┌─────────────────────────────────────────────────────┐
│ CLAUDE CODE  (app de Claude o Terminal)              │   │ MCP HOSPEDADOS  (en servidores del proveedor)       │
│                                                      │   │                                                     │
│ [EXTERNO: lo instala el usuario]                     │   │ Notion · Slack · Jira · Gmail                       │
│                                                      │   │ Drive/Docs/Sheets · Fireflies                       │
│ Abre la carpeta del agente y carga                   │   │ Granola · Fathom                                    │
│ la config. Lanza el bridge con                       │   │                                                     │
│ `serve` y habla con los MCP.                         │   │ Endpoints verificados y escritos en                 │
│                                                      │   │ MCPServerCatalog.swift  [HECHO]                     │
│ Que Galeno lo abra desde el home:                    │   │ Conectar cada uno por OAuth desde                   │
│ [PENDIENTE] Fase 4b                                  │   │ la app: [PENDIENTE] Fase 4                          │
└──────────────────────────────────────────────────────┘   └─────────────────────────────────────────────────────┘
                           │  lanza `galeno-whatsapp serve` (stdio), que lee estos datos
                           ▼
┌────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ DATOS LOCALES   ~/Library/Application Support/Galeno/  ·  los escribe `sync`, los lee `serve`          [HECHO] │
│                                                                                                                │
│ whatsmeow.db ... la sesión vinculada      messages.db ... todos los chats y mensajes que sync guardó           │
│ pair-qr.png .... el QR para la app         sync.log ...... el registro del servicio de fondo                   │
│                                                                                                                │
│ Y la instalación, un nivel arriba:  installation.json  (agentes, conexiones compartidas e idioma)              │
└────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
                           │  `sync` se conecta a WhatsApp; es el único que lo hace
                           ▼
┌────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ WHATSAPP  (servidores de Meta)                                                                                 │
│                                                                                                                │
│ Se conecta como dispositivo vinculado (protocolo de WhatsApp Web, no oficial). Solo lectura.                   │
│ Riesgo bajo pero real de restricción de la cuenta: la app debe decirlo (texto ya definido en la spec).         │
└────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ NEGOCIO Y DISTRIBUCIÓN                                                                             [PENDIENTE] │
│                                                                                                                │
│ skills/ (solo README) + catálogo curado + publicación remota con verificación ......... Fase 5                 │
│ site/ (solo README): sitio, dominio, appcast de Sparkle y skills remotas ............. Fase 9                  │
│ Stripe Checkout + webhook + email con la licencia ..................................... Fase 10                │
│ Beta con 2 PMs, lanzamiento, soporte .................................................. Fase 11                │
│                                                                                                                │
│ Ya hecho: CI en cada PR (.github/workflows/ci.yml): swift · go · go-universal [HECHO]                          │
└────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

### El recorrido de un mensaje de WhatsApp

```text
WhatsApp ──protocolo Web──▶ sync ──guarda──▶ messages.db ◀──lee── serve ──MCP/stdio──▶ Claude Code
(Meta)                      (launchd,                            (lo lanza Claude       │
                             única conexión)                      Code por sesión,      ▼
                                                                  sin conexión)    respuesta al PM

Por qué están separados: si `serve` también se conectara, habría dos conexiones simultáneas con el
mismo dispositivo vinculado, y WhatsApp puede marcarlo como anómalo.
```

### Cómo se genera la carpeta de un agente

```text
 respuestas del wizard                 conexiones compartidas
 (AgentConfig por agente)              (installation.json)
          │                                     │
          └──────────────┬──────────────────────┘
                         ▼
              GalenoInstallation.resolvedConfig      ← estado y client_id salen de las conexiones
                         │
                         ▼
              ConfigGenerator.generate               ← calcula todo; si algo falla, no toca nada
                         │
          ┌──────────────┼────────────────────────────┐
          ▼              ▼                            ▼
    escribe/regenera   quita lo que sobra        no toca nunca
    la config          (skills desmarcadas,      memoria/
                        hook sin uso)
```

---

## 4. Guía para probarlo todo desde cero

Cada paso dice qué esperar. Si algo no coincide, ese paso es donde mirar.

### 0. Requisitos

- macOS 14 o más nuevo, con **Xcode** instalado (trae Swift 6 y `clang`).
- **Go**: cualquier versión 1.2x sirve. El proyecto pide 1.26 y tu Go la descarga solo la primera vez.
- **Claude Code** 2.1.277 o más nuevo (`claude --version`).
- Acceso al repositorio privado (`gh auth status` debe estar iniciado) y, para el bridge, un WhatsApp en el teléfono.

### 1. Clonar

```bash
git clone git@github.com:Rafaell416/galeno.git
cd galeno
REPO="$PWD"
```

### 2. El motor: compilar y probar

```bash
swift build --package-path GalenoCore
swift test  --package-path GalenoCore
```

Esperado: `Executed 164 tests, with 0 failures`.

### 3. Generar un agente y regenerarlo (con `galeno-gen`)

Esto prueba lo más importante del motor: que cambiar la config y regenerar deja la carpeta igual que una nueva.

```bash
mkdir -p /tmp/galeno-prueba && cd /tmp/galeno-prueba
G="$REPO/GalenoCore/.build/debug/galeno-gen"

cat > a.json <<'EOF'
{
  "schemaVersion": 2, "agentName": "Aurora", "language": "es", "role": "product-manager",
  "projectDescription": "App de citas para la clínica del Cliente A.",
  "connections": [
    { "tool": "slack", "status": "connected", "oauthClientID": "1234567890123.1234567890123",
      "sources": { "readsEverything": true, "selected": [] } },
    { "tool": "notion", "status": "connected", "sources": { "readsEverything": true, "selected": [] } }
  ],
  "skills": [ {"id":"prd","source":"galeno"}, {"id":"acta","source":"galeno"}, {"id":"informe-slack","source":"galeno"} ],
  "sendingRules": { "internalWrites": { "notion": "allow" } }
}
EOF

# La misma config con una sola skill y Slack saltado:
python3 - <<'EOF'
import json
a = json.load(open("a.json")); a["skills"] = [a["skills"][0]]
for c in a["connections"]:
    if c["tool"] == "slack": c["status"] = "skipped"
json.dump(a, open("b.json", "w"), indent=2)
EOF

swift build --package-path "$REPO/GalenoCore" 2>&1 | tail -1     # compila galeno-gen
"$G" a.json carpeta                    # 1) genera: verás 13 archivos
echo "NOTA DEL AGENTE" > carpeta/memoria/proyecto.md
"$G" b.json carpeta                    # 2) regenera: aparece "Quitado" con el hook y 2 skills
ls carpeta/.claude/skills              # debe decir solo: prd
cat carpeta/memoria/proyecto.md        # debe seguir: NOTA DEL AGENTE
"$G" b.json fresca > /dev/null         # 3) la misma config en una carpeta nueva
diff -r -x memoria carpeta fresca && echo "IGUALES"
```

Esperado: `Quitado (ya no lo pide la config)` lista el hook y las skills `acta` e `informe-slack`; `diff` no muestra diferencias.

**Un error no deja la carpeta a medias:**

```bash
python3 -c "
import json; b = json.load(open('b.json')); b['agentName'] = 'Otro'
b['skills'].append({'id': 'no-existe', 'source': 'galeno'}); json.dump(b, open('roto.json', 'w'))"
cp -R carpeta antes
"$G" roto.json carpeta ; echo "salida: $?"      # error, salida 1
diff -r carpeta antes && echo "CARPETA INTACTA"
```

**Que Claude Code la entienda** (en una terminal aparte):

```bash
cd /tmp/galeno-prueba/carpeta && claude
```

Dentro: `/agents` debe mostrar `scribe`, `tracker` y `reporter`. La primera vez te enseña el diálogo de confianza de la carpeta: acéptalo. Pídele "anota en tu memoria que lanzamos el 15 de noviembre" (lo escribe sin preguntar) y luego "edita el AGENTS.md" (queda bloqueado).

### 4. El bridge: compilar y probar

```bash
cd "$REPO/whatsapp-bridge"
go build ./... && go vet ./... && go test ./...
```

Esperado: `ok  github.com/Rafaell416/galeno/whatsapp-bridge`. La primera vez tarda porque compila SQLite y puede descargar Go 1.26.

```bash
go build -o bin/galeno-whatsapp .
./bin/galeno-whatsapp version          # 0.2.0
make universal                          # binario de dos arquitecturas
lipo -archs bin/galeno-whatsapp         # x86_64 arm64
go build -o bin/galeno-whatsapp .       # vuelve al binario de tu Mac para los pasos siguientes
```

**Con un HOME vacío, sin tocar tu estado ni conectar nada:**

```bash
HOME="$(mktemp -d)" ./bin/galeno-whatsapp status         # Sin vincular. Corre: galeno-whatsapp pair
HOME="$(mktemp -d)" ./bin/galeno-whatsapp chats --json   # []
```

### 5. Vincular tu WhatsApp (usa **tu** cuenta; es de solo lectura)

> Esto vincula tu WhatsApp como dispositivo vinculado, de forma no oficial. Hay un riesgo bajo pero real de que WhatsApp restrinja la cuenta.

```bash
./bin/galeno-whatsapp pair
```

Escanea el QR de la terminal desde WhatsApp → Ajustes → Dispositivos vinculados. También se escribe como imagen y se renueva cada ~60 s:

```bash
open "$HOME/Library/Application Support/Galeno/whatsapp/pair-qr.png"
```

Esperado: `Vinculado correctamente.` Unos avisos de `prekeys` justo después son normales. Comprueba:

```bash
./bin/galeno-whatsapp status            # Vinculado como <tu número>.
```

### 6. Sincronizar

```bash
./bin/galeno-whatsapp sync              # déjalo corriendo en esta terminal
```

Esperado: `Conectado a WhatsApp` y luego `Sincronizando`. La primera carga del historial tarda varios minutos. En otra terminal:

```bash
sqlite3 "$HOME/Library/Application Support/Galeno/whatsapp/messages.db" \
  "select count(*) as chats from chats; select count(*) as mensajes from messages;"
cd "$REPO/whatsapp-bridge" && ./bin/galeno-whatsapp chats --json | head -20
```

Los chats nuevos aparecen en la lista; los grupos salen con nombre.

### 7. Conectarlo a Claude Code y probar la lectura

```bash
claude mcp add whatsapp -- "$REPO/whatsapp-bridge/bin/galeno-whatsapp" serve
```

> Usa la **ruta absoluta**. Con una relativa Claude Code no encuentra el binario y falla con `ENOENT`.

Abre una sesión **nueva** de `claude` (el MCP se carga al iniciar) y prueba:

1. "lista mis últimos 5 chats de whatsapp" → debe traer chats reales.
2. "entra al grupo [nombre de uno tuyo] y cuéntame qué está pasando" → debe resumirlo.
3. "manda un mensaje de prueba a [alguien]" → debe decir que **no tiene esa herramienta**. Ese es el candado de solo lectura.

Para deshacer: `claude mcp remove whatsapp`.

### 8. Que arranque solo tras reiniciar (la prueba pendiente de la Fase 3)

Primero **detén el `sync` manual** (Ctrl+C). Dos a la vez serían dos conexiones con el mismo dispositivo.

```bash
./bin/galeno-whatsapp install-launchd
launchctl print gui/$(id -u)/com.galeno.whatsapp-bridge | grep state     # state = running
tail -f "$HOME/Library/Application Support/Galeno/whatsapp/sync.log"      # Ctrl+C para salir
```

Reinicia el Mac. Sin abrir nada más:

```bash
launchctl print gui/$(id -u)/com.galeno.whatsapp-bridge | grep state     # debe seguir en running
```

Y en Claude Code pide los últimos mensajes de un chat: debe incluir los que llegaron mientras reiniciabas (WhatsApp los entrega al reconectar).

> El LaunchAgent apunta a la ruta del binario donde lo instalaste: no lo muevas. Si recompilas, reinicia el servicio con `launchctl kickstart -k gui/$(id -u)/com.galeno.whatsapp-bridge`.

### 9. Ver el CI

```bash
gh run list --limit 3                   # swift, go y go-universal en success
```

### 10. Empezar de cero otra vez

Destructivo: borra la sesión vinculada y todo el historial local.

```bash
launchctl bootout gui/$(id -u) "$HOME/Library/LaunchAgents/com.galeno.whatsapp-bridge.plist"
rm "$HOME/Library/LaunchAgents/com.galeno.whatsapp-bridge.plist"
claude mcp remove whatsapp
rm -rf "$HOME/Library/Application Support/Galeno/whatsapp"
rm -rf /tmp/galeno-prueba
```

Y en el teléfono, en Ajustes → Dispositivos vinculados, cierra la sesión de Galeno.
