package main

import (
	"encoding/xml"
	"strings"
	"testing"
)

// plistDict es lo mínimo del formato plist que necesitamos para verificar
// el contenido sin depender de una librería externa de plists.
type plistDict struct {
	XMLName xml.Name `xml:"plist"`
	Dict    struct {
		Keys    []string   `xml:"key"`
		Arrays  [][]string `xml:"array>string"`
		Strings []string   `xml:"string"`
	} `xml:"dict"`
}

func TestRenderLaunchdPlistIsValidXML(t *testing.T) {
	contents := renderLaunchdPlist("/Applications/Galeno.app/Contents/Resources/galeno-whatsapp", "/tmp/sync.log")

	var doc plistDict
	if err := xml.Unmarshal([]byte(contents), &doc); err != nil {
		t.Fatalf("el plist no es XML válido: %v\n%s", err, contents)
	}
}

func TestRenderLaunchdPlistTargetsSyncNotServe(t *testing.T) {
	contents := renderLaunchdPlist("/path/to/galeno-whatsapp", "/tmp/sync.log")

	// ProgramArguments debe ser [binario, "sync"] — nunca "serve": "sync" es
	// el único subcomando pensado para correr de fondo sin servir MCP (ver
	// el comentario en cli.go sobre por qué launchd no puede lanzar "serve").
	if !strings.Contains(contents, "<string>/path/to/galeno-whatsapp</string>") {
		t.Error("falta la ruta del binario en ProgramArguments")
	}
	if !strings.Contains(contents, "<string>sync</string>") {
		t.Error("ProgramArguments debería apuntar a \"sync\"")
	}
	if strings.Contains(contents, "<string>serve</string>") {
		t.Error("ProgramArguments NUNCA debe apuntar a \"serve\": causaría una segunda conexión simultánea")
	}
}

func TestRenderLaunchdPlistHasTheExpectedKeys(t *testing.T) {
	contents := renderLaunchdPlist("/bin/galeno-whatsapp", "/tmp/sync.log")

	for _, key := range []string{"Label", "ProgramArguments", "RunAtLoad", "KeepAlive", "StandardOutPath", "StandardErrorPath"} {
		if !strings.Contains(contents, "<key>"+key+"</key>") {
			t.Errorf("falta la clave %q", key)
		}
	}
	if !strings.Contains(contents, "<string>"+launchAgentLabel+"</string>") {
		t.Error("el Label no coincide con launchAgentLabel")
	}
}

func TestRenderLaunchdPlistPointsBothStreamsToTheLogFile(t *testing.T) {
	contents := renderLaunchdPlist("/bin/galeno-whatsapp", "/custom/path/sync.log")

	count := strings.Count(contents, "<string>/custom/path/sync.log</string>")
	if count != 2 {
		t.Errorf("se esperaba la ruta del log dos veces (stdout y stderr), aparece %d", count)
	}
}

// Una ruta con caracteres que tendrían que escaparse en XML (p.ej. un
// usuario con un "&" en el home, por raro que sea) no debería romper el
// documento ni perder el valor real.
func TestRenderLaunchdPlistEscapesXMLSpecialCharacters(t *testing.T) {
	contents := renderLaunchdPlist(`/Users/a&b/galeno-whatsapp`, "/tmp/sync.log")

	var doc plistDict
	if err := xml.Unmarshal([]byte(contents), &doc); err != nil {
		t.Fatalf("una ruta con \"&\" produjo XML inválido: %v\n%s", err, contents)
	}

	var found bool
	for _, s := range doc.Dict.Arrays[0] {
		if s == "/Users/a&b/galeno-whatsapp" {
			found = true
		}
	}
	if !found {
		t.Error("el valor decodificado no coincide con la ruta original")
	}
}
