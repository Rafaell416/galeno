package main

import "fmt"

// bridgeVersion es la versión del bridge, independiente de la de la app: el
// bridge es la capa que más se rompe por causas externas (Meta cambia su
// protocolo), así que necesita poder parchearse con su propio número
// (docs/03 §4f, capa 2). Es una variable, no una constante, para poder
// fijarla al compilar con -ldflags "-X main.bridgeVersion=…".
//
// Sube el MINOR cuando cambia lo que la app o Claude Code ven (subcomandos,
// herramientas MCP) y el PATCH cuando solo se corrige algo por dentro.
var bridgeVersion = "0.3.0"

// runVersion — subcomando "version": imprime solo el número, para que la app
// lo lea sin tener que separar nada.
func runVersion() {
	fmt.Println(bridgeVersion)
}
