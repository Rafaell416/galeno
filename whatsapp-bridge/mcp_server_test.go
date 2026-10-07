package main

import (
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// Un grep de texto sobre los .go (como el guardia de CI) no sirve para "en
// el binario": whatsmeow trae su propio SendMessage/Upload compilados, y el
// runtime de Go y sus dependencias de red traen primitivas de socket que en
// algunas plataformas se llaman sendto/sendmsg. Buscar "send" sin acotar
// encontraría siempre coincidencias ajenas — exactamente lo que le pasó al
// guardia viejo de CI, que buscaba el patrón equivocado y por eso nunca
// atrapó nada.
//
// Lo que sí es preciso: compilar el binario, listar sus símbolos, y mirar
// solo los que empiezan con "main." — nuestro propio código, no el de
// ninguna dependencia.
//
// Desde la 0.4.0 el bridge envía (docs/09), y por un solo camino: la
// herramienta MCP deja el mensaje en la bandeja y "sync" lo saca. Esos tres
// nombres son la lista blanca exacta; cualquier otra función o método nuestro
// con "send" en el nombre es un segundo camino de envío y hace fallar la
// prueba. (Los campos Sender/sender y los tipos no generan símbolo "main.":
// solo las funciones y los métodos.)
var allowedSendSymbols = []string{
	"handleSendMessage",                  // mcp_server.go: valida y encola
	"(*outboxDispatcher).sendOutboxItem", // outbox.go: saca un mensaje de la bandeja
	"(*liveClient).SendText",             // outbox.go: la única llamada a whatsmeow
}

func TestOnlyAllowedSendSymbols(t *testing.T) {
	bin := filepath.Join(t.TempDir(), "galeno-whatsapp")

	build := exec.Command("go", "build", "-o", bin, ".")
	if out, err := build.CombinedOutput(); err != nil {
		t.Fatalf("no compiló: %v\n%s", err, out)
	}

	out, err := exec.Command("go", "tool", "nm", bin).Output()
	if err != nil {
		t.Fatalf("go tool nm falló: %v", err)
	}

	var ownSymbols, flagged []string
	for _, line := range strings.Split(string(out), "\n") {
		fields := strings.Fields(line)
		if len(fields) == 0 {
			continue
		}
		symbol := fields[len(fields)-1]
		if !strings.HasPrefix(symbol, "main.") {
			continue // es de una dependencia, no nuestro
		}
		ownSymbols = append(ownSymbols, symbol)
		// Un cierre o una copia en línea llevan el nombre de su función
		// dentro (main.newMCPServer.handleSendMessage.func1), así que se
		// quitan los nombres permitidos y se mira si queda algún "send".
		rest := symbol
		for _, allowed := range allowedSendSymbols {
			rest = strings.ReplaceAll(rest, allowed, "")
		}
		if strings.Contains(strings.ToLower(rest), "send") {
			flagged = append(flagged, symbol)
		}
	}

	if len(ownSymbols) == 0 {
		// Si esto alguna vez da 0, la prueba no está probando nada: más vale
		// que falle fuerte a que pase en silencio sin haber mirado nada.
		t.Fatal("no se encontró ningún símbolo propio (main.*) en el binario; el filtro está mal")
	}

	if len(flagged) > 0 {
		t.Errorf("símbolo(s) con \"send\" fuera de la lista blanca: %s", strings.Join(flagged, ", "))
	}
}
