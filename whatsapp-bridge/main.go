// El bridge de WhatsApp de Galeno: el puente (whatsmeow) y un servidor MCP de
// solo lectura, en un único binario que Claude Code lanza por stdio.
//
// Todavía no tiene comportamiento. Se implementa en la Fase 3; esto solo existe
// para que el módulo compile y el CI tenga algo que construir.
//
// Regla innegociable: este binario nunca expone herramientas de envío.
package main

import "fmt"

// version del bridge.
const version = "0.0.1"

func main() {
	fmt.Printf("galeno whatsapp-bridge %s (sin implementar)\n", version)
}
