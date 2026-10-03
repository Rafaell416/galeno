package main

import (
	"context"
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

	switch os.Args[1] {
	case "pair":
		runPair()
	case "serve":
		runServe()
	case "sync":
		runSync()
	case "status":
		runStatus()
	case "install-launchd":
		runInstallLaunchd()
	case "chats":
		runChats()
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
	fmt.Fprintln(os.Stderr, `galeno-whatsapp — puente de WhatsApp de solo lectura (fork de lharries/whatsapp-mcp).

Uso:
  galeno-whatsapp pair             Vincula este Mac con tu WhatsApp (muestra un QR)
  galeno-whatsapp sync             Mantiene la conexión a WhatsApp y guarda mensajes;
                                   pensado para correr de fondo (ver install-launchd)
  galeno-whatsapp serve            Corre el servidor MCP (stdio); exige estar ya vinculado.
                                   No conecta a WhatsApp: solo lee lo que sync ya guardó
  galeno-whatsapp status           Dice si hay una sesión vinculada, sin conectar a WhatsApp
  galeno-whatsapp install-launchd  Instala "sync" como LaunchAgent, para que arranque
                                   solo al iniciar sesión
  galeno-whatsapp chats --json     Lista los chats guardados (la app arma con esto la
                                   pantalla "elige qué leer"); no conecta a WhatsApp
  galeno-whatsapp version          Imprime la versión del bridge

El estado (sesión y mensajes) vive en:
  ~/Library/Application Support/Galeno/whatsapp/`)
}

// stateDirectory resuelve y crea ~/Library/Application Support/Galeno/whatsapp/.
func stateDirectory() (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("no se pudo resolver el directorio del usuario: %v", err)
	}
	dir := filepath.Join(home, "Library", "Application Support", "Galeno", "whatsapp")
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
		}
	})
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

	client, messageStore, _, err := openClient(logger)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	defer messageStore.Close()

	if client.Store.ID == nil {
		fmt.Fprintln(os.Stderr, "No hay ninguna sesión vinculada. Corre primero: galeno-whatsapp pair")
		os.Exit(1)
	}

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

	logger.Infof("Sincronizando. Ctrl+C (o launchd) para detener.")

	exitChan := make(chan os.Signal, 1)
	signal.Notify(exitChan, syscall.SIGINT, syscall.SIGTERM)
	<-exitChan
	logger.Infof("Desconectando...")
}

// runServe — subcomando "serve": exige sesión existente, pero NUNCA conecta
// a WhatsApp por su cuenta — esa conexión la sostiene "sync". Solo abre la
// base local y sirve las 9 herramientas MCP por stdio. Nada de lo que corre
// aquí puede escribir a stdout salvo el propio transporte MCP (ver log.go y
// los comentarios en media.go/events.go).
func runServe() {
	logger := newLogger("Serve", "INFO", true)

	client, messageStore, _, err := openClient(logger)
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

	server := newMCPServer(messageStore)
	if err := server.Run(context.Background(), &mcp.StdioTransport{}); err != nil {
		fmt.Fprintf(os.Stderr, "El servidor MCP terminó con error: %v\n", err)
		os.Exit(1)
	}
}

// runStatus — subcomando "status": nunca conecta a WhatsApp, solo mira si
// hay un dispositivo guardado.
func runStatus() {
	logger := newLogger("Status", "INFO", false)

	client, messageStore, _, err := openClient(logger)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	defer messageStore.Close()

	if client.Store.ID == nil {
		fmt.Println("Sin vincular. Corre: galeno-whatsapp pair")
		return
	}

	fmt.Printf("Vinculado como %s.\n", client.Store.ID.User)
}

// runInstallLaunchd — subcomando "install-launchd": ver launchd.go.
func runInstallLaunchd() {
	if err := installLaunchd(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	fmt.Println("Listo: 'galeno-whatsapp sync' arrancará solo al iniciar sesión.")
}
