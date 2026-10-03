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
// ninguna dependencia. Ninguno de los nombres que elegimos contiene "send";
// el único identificador que sí la contiene como subcadena es el campo
// Sender/sender (quién mandó un mensaje), y los campos de struct no generan
// símbolo en absoluto — solo funciones y métodos lo hacen — así que esta
// prueba pasa limpia por construcción, no porque se haya ajustado para que
// pase.
func TestNoSendSymbolsInOurOwnCode(t *testing.T) {
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
		if strings.Contains(strings.ToLower(symbol), "send") {
			flagged = append(flagged, symbol)
		}
	}

	if len(ownSymbols) == 0 {
		// Si esto alguna vez da 0, la prueba no está probando nada: más vale
		// que falle fuerte a que pase en silencio sin haber mirado nada.
		t.Fatal("no se encontró ningún símbolo propio (main.*) en el binario; el filtro está mal")
	}

	if len(flagged) > 0 {
		t.Errorf("símbolo(s) con \"send\" en nuestro propio código: %s", strings.Join(flagged, ", "))
	}
}
