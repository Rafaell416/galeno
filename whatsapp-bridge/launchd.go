package main

import (
	"bytes"
	"encoding/xml"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
)

// launchAgentLabel identifica el LaunchAgent. Provisional: cuando exista el
// bundle id real de GalenoApp, debería alinearse con ese (por ejemplo
// "<bundle-id>.whatsapp-bridge"), no quedarse con este valor genérico.
const launchAgentLabel = "com.galeno.whatsapp-bridge"

// launchAgentLabelFor es el nombre del servicio de un número: el de siempre lleva el nombre de siempre, y cada
// cuenta extra el suyo (`com.galeno.whatsapp-bridge.trabajo`), para que `sync` de uno no pise al del otro.
func launchAgentLabelFor(account string) string {
	if account == "" {
		return launchAgentLabel
	}
	return launchAgentLabel + "." + account
}

// renderLaunchdPlist arma el plist del LaunchAgent. Función pura —sin tocar
// disco— para poder probarla sin instalar nada de verdad. ProgramArguments
// apunta a "sync", nunca a "serve": "sync" es el único subcomando pensado
// para correr de fondo, para siempre, sin servir MCP (ver cli.go).
//
// KeepAlive es el booleano simple, no el diccionario con SuccessfulExit:
// launchd ya throttlea los reinicios con backoff si el proceso termina
// seguido (por ejemplo, mientras no haya sesión vinculada), así que no hace
// falta una política más fina para esto.
func renderLaunchdPlist(binaryPath, logPath, account string) string {
	accountArguments := ""
	if account != "" {
		accountArguments = fmt.Sprintf("\n\t\t<string>--account</string>\n\t\t<string>%s</string>", xmlEscape(account))
	}
	return fmt.Sprintf(`<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>%s</string>
	<key>ProgramArguments</key>
	<array>
		<string>%s</string>
		<string>sync</string>%s
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<true/>
	<key>StandardOutPath</key>
	<string>%s</string>
	<key>StandardErrorPath</key>
	<string>%s</string>
</dict>
</plist>
`, xmlEscape(launchAgentLabelFor(account)), xmlEscape(binaryPath), accountArguments, xmlEscape(logPath), xmlEscape(logPath))
}

// xmlEscape escapa texto para que sea seguro meterlo como contenido de un
// elemento XML. binaryPath y logPath son rutas de archivo: en la práctica
// casi nunca llevan "&", "<" o similares, pero un plist con una ruta sin
// escapar que sí los llevara sería XML inválido — más vale que esto
// funcione siempre, no "en el caso común".
func xmlEscape(s string) string {
	var buf bytes.Buffer
	_ = xml.EscapeText(&buf, []byte(s))
	return buf.String()
}

func launchAgentPlistPath() (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("no se pudo resolver el directorio del usuario: %v", err)
	}
	return filepath.Join(home, "Library", "LaunchAgents", launchAgentLabelFor(accountID)+".plist"), nil
}

// uninstallLaunchd detiene el servicio de fondo de este número y quita su plist (un archivo que Galeno mismo
// escribió, no datos del usuario). **No toca** la sesión ni el historial: eso lo decide quien llama. Idempotente: si
// no estaba instalado, no hace nada.
func uninstallLaunchd() error {
	plistPath, err := launchAgentPlistPath()
	if err != nil {
		return err
	}
	domain := fmt.Sprintf("gui/%d", os.Getuid())
	// Si no estaba cargado, launchctl devuelve error: se ignora a propósito.
	_ = exec.Command("launchctl", "bootout", domain, plistPath).Run()
	if err := os.Remove(plistPath); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("no se pudo quitar %s: %v", plistPath, err)
	}
	return nil
}

// installLaunchd escribe el plist y lo activa. Idempotente: si ya estaba
// instalado (por ejemplo, apuntando a un binario de una versión anterior),
// lo desactiva primero con "bootout" —ignorando el error si no existía— y
// lo vuelve a activar con el plist nuevo.
//
// "bootstrap"/"bootout" con el dominio "gui/<uid>" explícito son la sintaxis
// vigente: "load"/"unload" están obsoletas desde macOS 10.10. Verificado
// contra la documentación, no supuesto de memoria.
func installLaunchd() error {
	binaryPath, err := os.Executable()
	if err != nil {
		return fmt.Errorf("no se pudo resolver la ruta de este binario: %v", err)
	}
	if resolved, err := filepath.EvalSymlinks(binaryPath); err == nil {
		binaryPath = resolved
	}

	stateDir, err := stateDirectory()
	if err != nil {
		return err
	}
	logPath := filepath.Join(stateDir, "sync.log")

	plistPath, err := launchAgentPlistPath()
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(plistPath), 0o755); err != nil {
		return fmt.Errorf("no se pudo crear %s: %v", filepath.Dir(plistPath), err)
	}

	contents := renderLaunchdPlist(binaryPath, logPath, accountID)
	if err := os.WriteFile(plistPath, []byte(contents), 0o644); err != nil {
		return fmt.Errorf("no se pudo escribir %s: %v", plistPath, err)
	}

	domain := fmt.Sprintf("gui/%d", os.Getuid())

	// Por si ya estaba instalado: lo desactivamos primero. Si no existía,
	// launchctl devuelve error — lo ignoramos a propósito.
	_ = exec.Command("launchctl", "bootout", domain, plistPath).Run()

	bootstrap := exec.Command("launchctl", "bootstrap", domain, plistPath)
	if out, err := bootstrap.CombinedOutput(); err != nil {
		return fmt.Errorf("launchctl bootstrap falló: %v\n%s", err, out)
	}

	return nil
}
