package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	_ "github.com/mattn/go-sqlite3"
	"github.com/mdp/qrterminal"
	"github.com/modelcontextprotocol/go-sdk/mcp"
	"rsc.io/qr"

	"go.mau.fi/whatsmeow"
	"go.mau.fi/whatsmeow/store/sqlstore"
	"go.mau.fi/whatsmeow/types/events"
	waLog "go.mau.fi/whatsmeow/util/log"
)

func main() {
	if len(os.Args) < 2 {
		printUsage()
		os.Exit(1)
	}

	// `--account <id>` elige de qué número se habla (account.go). Se quita de los argumentos antes de que cada
	// subcomando lea los suyos, y sin él todo va a la cuenta de siempre.
	rest, account, err := extractAccountFlag(os.Args)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}
	os.Args = rest
	accountID = account

	switch os.Args[1] {
	case "pair":
		runPair()
	case "serve":
		runServe()
	case "sync":
		runSync()
	case "status":
		runStatus(len(os.Args) > 2 && os.Args[2] == "--json")
	case "unlink":
		runUnlink()
	case "install-launchd":
		runInstallLaunchd()
	case "uninstall-launchd":
		runUninstallLaunchd()
	case "chats":
		runChats()
	case "outbox":
		runOutbox()
	case "version", "--version":
		runVersion()
	case "-h", "--help", "help":
		printUsage()
	default:
		fmt.Fprintf(os.Stderr, "Subcomando desconocido: %s\n\n", os.Args[1])
		printUsage()
		os.Exit(1)
	}
}

func printUsage() {
	fmt.Fprintln(os.Stderr, `galeno-whatsapp — puente de WhatsApp: lee, y envía texto a una persona o a un grupo
solo con aprobación (fork de lharries/whatsapp-mcp).

Uso:
  galeno-whatsapp pair             Vincula este Mac con tu WhatsApp (muestra un QR)
  galeno-whatsapp sync             Mantiene la conexión a WhatsApp, guarda mensajes y saca
                                   los de la bandeja de salida; pensado para correr de fondo
                                   (ver install-launchd)
  galeno-whatsapp serve            Corre el servidor MCP (stdio); exige estar ya vinculado.
                                   No conecta a WhatsApp: solo lee lo que sync ya guardó.
                                   Con --with-send ofrece además send_message, que deja el
                                   mensaje en la bandeja de salida para que sync lo saque
  galeno-whatsapp status           Dice si hay una sesión vinculada, sin conectar a WhatsApp
                                   (con --json, además cuándo se vinculó y la versión)
  galeno-whatsapp unlink           Cierra la sesión vinculada (para volver a vincular con pair).
                                   No borra los mensajes que ya se guardaron
  galeno-whatsapp install-launchd  Instala "sync" como LaunchAgent, para que arranque
                                   solo al iniciar sesión
  galeno-whatsapp uninstall-launchd  Quita el servicio de fondo de este número (no toca su sesión
                                   ni su historial)
  galeno-whatsapp chats --json     Lista los chats guardados (la app arma con esto la
                                   pantalla "elige qué leer"); no conecta a WhatsApp
  galeno-whatsapp outbox --json    Estado de la bandeja de salida: enviados hoy, topes y
                                   pausa (lo lee la app); no conecta a WhatsApp
  galeno-whatsapp version          Imprime la versión del bridge

Con --account <id> (en cualquier subcomando salvo version) se habla de **otro número**: su
sesión, su historial, su bandeja de salida y su servicio de fondo son aparte. Sin él, el de
siempre.

El estado (sesión y mensajes) vive en:
  ~/Library/Application Support/Galeno/whatsapp/                  (el de siempre)
  ~/Library/Application Support/Galeno/whatsapp/cuentas/<id>/     (con --account)`)
}

// stateDirectory resuelve y crea ~/Library/Application Support/Galeno/whatsapp/ o, con --account, el de esa cuenta
// (`whatsapp/cuentas/<id>/`).
func stateDirectory() (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("no se pudo resolver el directorio del usuario: %v", err)
	}
	dir := stateDirectoryPath(home, accountID)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", fmt.Errorf("no se pudo crear %s: %v", dir, err)
	}
	return dir, nil
}

// openClient abre (o crea) el dispositivo de whatsmeow y nuestro propio
// MessageStore, los dos en el directorio de estado compartido, y devuelve
// ese directorio para quien lo necesite (pair, para el QR en PNG). No
// conecta: eso lo decide cada subcomando. Construir un *whatsmeow.Client no
// toca la red por sí solo —solo client.Connect() lo hace—, así que "serve"
// puede llamar a esta misma función para ver si hay sesión vinculada
// (client.Store.ID) sin arriesgarse a sostener una conexión que no le
// corresponde (esa es responsabilidad exclusiva de "sync"; ver su propio
// comentario).
func openClient(logger waLog.Logger) (client *whatsmeow.Client, messageStore *MessageStore, stateDir string, err error) {
	dir, err := stateDirectory()
	if err != nil {
		return nil, nil, "", err
	}

	ctx := context.Background()
	dbLog := logger.Sub("Database")
	whatsmeowDBPath := filepath.Join(dir, "whatsmeow.db")
	container, err := sqlstore.New(ctx, "sqlite3", fmt.Sprintf("file:%s?_foreign_keys=on", whatsmeowDBPath), dbLog)
	if err != nil {
		return nil, nil, "", fmt.Errorf("no se pudo abrir la base de sesión: %v", err)
	}

	// GetFirstDevice ya crea un dispositivo nuevo internamente si no había
	// ninguno (no devuelve sql.ErrNoRows en ese caso); no hace falta
	// distinguir el caso "sin dispositivo" nosotros mismos.
	deviceStore, err := container.GetFirstDevice(ctx)
	if err != nil {
		return nil, nil, "", fmt.Errorf("no se pudo leer el dispositivo: %v", err)
	}

	client = whatsmeow.NewClient(deviceStore, logger.Sub("Client"))
	if client == nil {
		return nil, nil, "", fmt.Errorf("no se pudo crear el cliente de WhatsApp")
	}

	messageStore, err = NewMessageStore(filepath.Join(dir, "messages.db"))
	if err != nil {
		return nil, nil, "", fmt.Errorf("no se pudo abrir el historial de mensajes: %v", err)
	}

	return client, messageStore, dir, nil
}

// pairQRFilename es el nombre fijo del PNG del QR dentro del directorio de
// estado, para que la app Swift (Fase 4) sepa de antemano dónde mirar sin
// tener que leer stdout.
const pairQRFilename = "pair-qr.png"

// connectAndPair conecta un cliente sin sesión previa, muestra el QR (en la
// terminal y como PNG en stateDir, por si una app gráfica lo está mirando),
// y espera hasta 3 minutos a que el usuario lo escanee. No hace nada (ni
// falla) si el cliente ya tenía sesión: solo se llama cuando se confirmó que
// no la hay.
func connectAndPair(client *whatsmeow.Client, stateDir string, logger waLog.Logger) error {
	qrPath := filepath.Join(stateDir, pairQRFilename)
	// Por si quedó uno de un intento anterior que no se limpió solo
	// (por ejemplo, el proceso murió a la fuerza): un QR viejo en disco
	// podría confundir a quien lo esté mirando.
	os.Remove(qrPath)
	defer os.Remove(qrPath)

	qrChan, _ := client.GetQRChannel(context.Background())
	if err := client.Connect(); err != nil {
		return fmt.Errorf("no se pudo conectar: %v", err)
	}

	connected := make(chan bool, 1)
	fmt.Println("Escanea este código QR con tu WhatsApp (Ajustes → Dispositivos vinculados):")
	for evt := range qrChan {
		if evt.Event == "code" {
			qrterminal.GenerateHalfBlock(evt.Code, qrterminal.L, os.Stdout)

			// El mismo código, como PNG. qr.L es el mismo nivel de
			// corrección de errores que usa qrterminal.L por debajo
			// (qrterminal lo reexporta tal cual), así que el PNG y el
			// dibujo en terminal son visualmente equivalentes.
			if code, err := qr.Encode(evt.Code, qr.L); err == nil {
				if err := os.WriteFile(qrPath, code.PNG(), 0o600); err != nil {
					logger.Warnf("No se pudo escribir el QR como PNG: %v", err)
				}
			} else {
				logger.Warnf("No se pudo generar el QR como PNG: %v", err)
			}
		} else if evt.Event == "success" {
			connected <- true
			break
		}
	}

	select {
	case <-connected:
		return nil
	case <-time.After(3 * time.Minute):
		return fmt.Errorf("se agotó el tiempo esperando que escanearas el QR")
	}
}

// setupEventHandlers registra los manejadores que guardan en el historial
// local lo que va llegando. Los mismos para pair (captura la sincronización
// inicial) y para sync.
func setupEventHandlers(client *whatsmeow.Client, messageStore *MessageStore, logger waLog.Logger) {
	client.AddEventHandler(func(evt interface{}) {
		switch v := evt.(type) {
		case *events.Message:
			handleMessage(client, messageStore, v, logger)
		case *events.HistorySync:
			handleHistorySync(client, messageStore, v, logger)
		case *events.Connected:
			logger.Infof("Conectado a WhatsApp")
		case *events.LoggedOut:
			logger.Warnf("La sesión se cerró del lado de WhatsApp; hace falta volver a vincular (pair)")
		case *events.PairSuccess:
			// Antes de que llegue la sincronización del historial: si el número es otro, el historial del
			// anterior se aparta aquí y lo que llegue ya es del nuevo.
			adoptAccount(messageStore, v.ID.User, logger)
		}
	})
}

// adoptAccount anota de qué número es el historial y avisa si lo tuvo que apartar porque el número cambió.
// Un fallo aquí no detiene la vinculación ni la sincronización: se registra y el historial queda como estaba.
func adoptAccount(messageStore *MessageStore, user string, logger waLog.Logger) {
	switched, err := messageStore.AdoptAccount(user, time.Now())
	if err != nil {
		logger.Warnf("No se pudo comprobar de qué número es el historial: %v", err)
		return
	}
	if switched != nil {
		logger.Warnf("El número vinculado cambió (%s → %s): el historial anterior se guardó en %s y empieza uno nuevo",
			switched.Previous, user, switched.Backup)
	}
}

// runPair — subcomando "pair".
func runPair() {
	logger := newLogger("Pair", "INFO", true)

	client, messageStore, stateDir, err := openClient(logger)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	defer messageStore.Close()

	if client.Store.ID != nil {
		fmt.Printf("Ya hay una sesión vinculada (%s). Para vincular otra, cierra sesión primero.\n", client.Store.ID.User)
		return
	}

	setupEventHandlers(client, messageStore, logger)

	if err := connectAndPair(client, stateDir, logger); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	if client.Store.ID != nil {
		adoptAccount(messageStore, client.Store.ID.User, logger)
	}

	time.Sleep(2 * time.Second)
	client.Disconnect()
	fmt.Println("Vinculado correctamente.")
}

// runSync — subcomando "sync": la única pieza que sostiene una conexión
// viva a WhatsApp. Pensado para correr de fondo (ver install-launchd):
// conecta, recibe mensajes, los guarda — y nunca sirve MCP. Es justo la
// separación que ya tenía el diseño original (el puente Go de upstream se
// queda corriendo; el servidor MCP en Python solo le pregunta por HTTP, sin
// conectar él mismo). Si "serve" también sostuviera su propia conexión,
// correr los dos a la vez autenticaría al mismo dispositivo dos veces
// — algo que WhatsApp puede detectar como anómalo.
func runSync() {
	logger := newLogger("Sync", "INFO", true)

	client, messageStore, stateDir, err := openClient(logger)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	defer messageStore.Close()

	if client.Store.ID == nil {
		fmt.Fprintln(os.Stderr, "No hay ninguna sesión vinculada. Corre primero: galeno-whatsapp pair")
		os.Exit(1)
	}

	adoptAccount(messageStore, client.Store.ID.User, logger)

	setupEventHandlers(client, messageStore, logger)

	if err := client.Connect(); err != nil {
		fmt.Fprintf(os.Stderr, "No se pudo conectar: %v\n", err)
		os.Exit(1)
	}
	defer client.Disconnect()

	time.Sleep(2 * time.Second)
	if !client.IsConnected() {
		fmt.Fprintln(os.Stderr, "No se logró una conexión estable.")
		os.Exit(1)
	}

	// La bandeja de salida se despacha aquí y solo aquí: es la única conexión
	// viva (ver outbox.go).
	outboxCtx, stopOutbox := context.WithCancel(context.Background())
	defer stopOutbox()
	dispatcher := &outboxDispatcher{
		env:    newOutboxEnv(messageStore, stateDir, client.Store.LIDs, client.Store.Contacts),
		sender: &liveClient{client: client},
		logger: logger.Sub("Outbox"),
	}
	go dispatcher.run(outboxCtx)

	logger.Infof("Sincronizando. Ctrl+C (o launchd) para detener.")

	exitChan := make(chan os.Signal, 1)
	signal.Notify(exitChan, syscall.SIGINT, syscall.SIGTERM)
	<-exitChan
	logger.Infof("Desconectando...")
}

// runServe — subcomando "serve": exige sesión existente, pero NUNCA conecta
// a WhatsApp por su cuenta — esa conexión la sostiene "sync". Solo abre la
// base local y sirve las herramientas MCP por stdio. Nada de lo que corre
// aquí puede escribir a stdout salvo el propio transporte MCP (ver log.go y
// los comentarios en media.go/events.go).
//
// Sin argumentos ofrece las 9 lecturas, igual que antes de la 0.4.0. La
// herramienta de envío solo aparece con --with-send, y eso es a propósito:
// la config que Galeno generaba antes del envío permite el servidor entero
// ("mcp__whatsapp__*"), así que una carpeta de agente vieja con un bridge
// nuevo enviaría sin preguntar. El motor escribe --with-send en el .mcp.json
// en la misma generación en la que escribe la regla que pide aprobación.
func runServe() {
	flags := flag.NewFlagSet("serve", flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	withSend := flags.Bool("with-send", false, "ofrece también send_message (siempre con aprobación del usuario)")
	if err := flags.Parse(os.Args[2:]); err != nil {
		os.Exit(2)
	}

	logger := newLogger("Serve", "INFO", true)

	client, messageStore, stateDir, err := openClient(logger)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	defer messageStore.Close()

	if client.Store.ID == nil {
		fmt.Fprintln(os.Stderr, "No hay ninguna sesión vinculada. Corre primero: galeno-whatsapp pair")
		os.Exit(1)
	}

	fmt.Fprintln(os.Stderr, "Sirviendo MCP por stdio (sin conexión propia a WhatsApp; usa lo que 'sync' ya guardó)...")

	var outbox *outboxEnv
	if *withSend {
		env := newOutboxEnv(messageStore, stateDir, client.Store.LIDs, client.Store.Contacts)
		outbox = &env
	}
	server := newMCPServer(messageStore, outbox)
	if err := server.Run(context.Background(), &mcp.StdioTransport{}); err != nil {
		fmt.Fprintf(os.Stderr, "El servidor MCP terminó con error: %v\n", err)
		os.Exit(1)
	}
}

// runStatus — subcomando "status": nunca conecta a WhatsApp, solo mira si
// hay un dispositivo guardado. Con --json imprime un informe para la app.
func runStatus(asJSON bool) {
	logger := newLogger("Status", "INFO", false)

	client, messageStore, _, err := openClient(logger)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	defer messageStore.Close()

	if asJSON {
		linked := client.Store.ID != nil
		number := ""
		if linked {
			number = client.Store.ID.User
		}
		fmt.Println(buildStatusReport(number, linked, client.Store.Account).json())
		return
	}

	if client.Store.ID == nil {
		fmt.Println("Sin vincular. Corre: galeno-whatsapp pair")
		return
	}

	fmt.Printf("Vinculado como %s.\n", client.Store.ID.User)
}

// runUnlink — subcomando "unlink": cierra la sesión vinculada para poder volver a vincular. Se conecta con la sesión
// y le pide a WhatsApp que quite el dispositivo; si no se puede (la sesión ya caducó, o no hay red), borra la sesión
// local de todos modos y avisa de que el teléfono puede seguir mostrándolo en «Dispositivos vinculados».
//
// **No borra el historial** (messages.db): solo la sesión. Tampoco envía nada a nadie.
func runUnlink() {
	logger := newLogger("Unlink", "INFO", false)

	client, messageStore, _, err := openClient(logger)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	defer messageStore.Close()

	if client.Store.ID == nil {
		fmt.Println("Sin vincular. Nada que cerrar.")
		return
	}

	ctx := context.Background()
	connectErr := client.Connect()
	if connectErr == nil {
		connectErr = client.Logout(ctx)
	}
	if connectErr == nil {
		fmt.Println("Sesión cerrada.")
		return
	}

	// WhatsApp no confirmó: se borra la sesión local para poder volver a vincular.
	fmt.Fprintf(os.Stderr, "No pude avisarle a WhatsApp: %v\n", connectErr)
	client.Disconnect()
	if err := client.Store.Delete(ctx); err != nil {
		fmt.Fprintf(os.Stderr, "Tampoco pude borrar la sesión local: %v\n", err)
		os.Exit(1)
	}
	fmt.Println("Sesión local cerrada. Si tu teléfono sigue mostrando este Mac en «Dispositivos vinculados», quítalo desde ahí.")
}

// runUninstallLaunchd — subcomando "uninstall-launchd": ver launchd.go.
func runUninstallLaunchd() {
	if err := uninstallLaunchd(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	fmt.Println("Listo: el servicio de fondo de este número ya no arranca.")
}

// runInstallLaunchd — subcomando "install-launchd": ver launchd.go.
func runInstallLaunchd() {
	if err := installLaunchd(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	fmt.Println("Listo: 'galeno-whatsapp sync' arrancará solo al iniciar sesión.")
}
