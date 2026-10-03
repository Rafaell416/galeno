package main

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"path/filepath"
	"time"

	_ "github.com/mattn/go-sqlite3"
	"github.com/mdp/qrterminal"
	"github.com/modelcontextprotocol/go-sdk/mcp"

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
	case "status":
		runStatus()
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
  galeno-whatsapp pair      Vincula este Mac con tu WhatsApp (muestra un QR)
  galeno-whatsapp serve     Corre el servidor MCP (stdio); exige estar ya vinculado
  galeno-whatsapp status    Dice si hay una sesión vinculada, sin conectar a WhatsApp

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
// MessageStore, los dos en el directorio de estado compartido. No conecta:
// eso lo decide cada subcomando (pair siempre conecta para mostrar el QR si
// hace falta; serve exige que ya haya sesión; status nunca conecta).
func openClient(logger waLog.Logger) (*whatsmeow.Client, *MessageStore, error) {
	dir, err := stateDirectory()
	if err != nil {
		return nil, nil, err
	}

	dbLog := logger.Sub("Database")
	whatsmeowDBPath := filepath.Join(dir, "whatsmeow.db")
	container, err := sqlstore.New("sqlite3", fmt.Sprintf("file:%s?_foreign_keys=on", whatsmeowDBPath), dbLog)
	if err != nil {
		return nil, nil, fmt.Errorf("no se pudo abrir la base de sesión: %v", err)
	}

	deviceStore, err := container.GetFirstDevice()
	if err != nil {
		if err == sql.ErrNoRows {
			deviceStore = container.NewDevice()
			logger.Infof("No había ningún dispositivo guardado; se crea uno nuevo")
		} else {
			return nil, nil, fmt.Errorf("no se pudo leer el dispositivo: %v", err)
		}
	}

	client := whatsmeow.NewClient(deviceStore, logger.Sub("Client"))
	if client == nil {
		return nil, nil, fmt.Errorf("no se pudo crear el cliente de WhatsApp")
	}

	messageStore, err := NewMessageStore(filepath.Join(dir, "messages.db"))
	if err != nil {
		return nil, nil, fmt.Errorf("no se pudo abrir el historial de mensajes: %v", err)
	}

	return client, messageStore, nil
}

// connectAndPair conecta un cliente sin sesión previa, muestra el QR, y
// espera hasta 3 minutos a que el usuario lo escanee. No hace nada (ni falla)
// si el cliente ya tenía sesión: solo se llama cuando se confirmó que no la hay.
func connectAndPair(client *whatsmeow.Client, logger waLog.Logger) error {
	qrChan, _ := client.GetQRChannel(context.Background())
	if err := client.Connect(); err != nil {
		return fmt.Errorf("no se pudo conectar: %v", err)
	}

	connected := make(chan bool, 1)
	fmt.Println("Escanea este código QR con tu WhatsApp (Ajustes → Dispositivos vinculados):")
	for evt := range qrChan {
		if evt.Event == "code" {
			qrterminal.GenerateHalfBlock(evt.Code, qrterminal.L, os.Stdout)
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
// inicial) y para serve.
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

	client, messageStore, err := openClient(logger)
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

	if err := connectAndPair(client, logger); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	time.Sleep(2 * time.Second)
	client.Disconnect()
	fmt.Println("Vinculado correctamente.")
}

// runServe — subcomando "serve": exige sesión existente, conecta, y sirve el
// MCP por stdio. Nada de lo que corre aquí puede escribir a stdout salvo el
// propio transporte MCP (ver log.go y los comentarios en media.go/events.go).
func runServe() {
	logger := newLogger("Serve", "INFO", true)

	client, messageStore, err := openClient(logger)
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

	fmt.Fprintln(os.Stderr, "Conectado. Sirviendo MCP por stdio...")

	server := newMCPServer(client, messageStore)
	if err := server.Run(context.Background(), &mcp.StdioTransport{}); err != nil {
		fmt.Fprintf(os.Stderr, "El servidor MCP terminó con error: %v\n", err)
		os.Exit(1)
	}
}

// runStatus — subcomando "status": nunca conecta a WhatsApp, solo mira si
// hay un dispositivo guardado.
func runStatus() {
	logger := newLogger("Status", "INFO", false)

	client, messageStore, err := openClient(logger)
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
