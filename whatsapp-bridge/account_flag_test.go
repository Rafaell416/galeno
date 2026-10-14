package main

import (
	"path/filepath"
	"strings"
	"testing"
)

func TestExtractAccountFlagTakesItOutOfTheArguments(t *testing.T) {
	rest, account, err := extractAccountFlag([]string{"galeno-whatsapp", "serve", "--account", "trabajo", "--with-send"})
	if err != nil {
		t.Fatal(err)
	}
	if account != "trabajo" {
		t.Fatalf("la cuenta debía ser trabajo: %q", account)
	}
	want := []string{"galeno-whatsapp", "serve", "--with-send"}
	if strings.Join(rest, " ") != strings.Join(want, " ") {
		t.Fatalf("los demás argumentos no cambian: %v", rest)
	}
}

func TestExtractAccountFlagAcceptsTheEqualsForm(t *testing.T) {
	rest, account, err := extractAccountFlag([]string{"galeno-whatsapp", "status", "--account=trabajo", "--json"})
	if err != nil || account != "trabajo" || strings.Join(rest, " ") != "galeno-whatsapp status --json" {
		t.Fatalf("rest=%v account=%q err=%v", rest, account, err)
	}
}

func TestWithoutTheFlagItIsTheAccountOfAlways(t *testing.T) {
	_, account, err := extractAccountFlag([]string{"galeno-whatsapp", "sync"})
	if err != nil || account != "" {
		t.Fatalf("sin bandera es la de siempre: %q %v", account, err)
	}
}

func TestAnInvalidAccountIsRefusedAndNeverReachesAPath(t *testing.T) {
	for _, bad := range []string{"../etc", "a/b", "A", "a b", "-a", "a-", "a.b", "ñ", strings.Repeat("a", 25)} {
		if _, _, err := extractAccountFlag([]string{"galeno-whatsapp", "sync", "--account", bad}); err == nil {
			t.Fatalf("%q no debería aceptarse", bad)
		}
	}
	if _, _, err := extractAccountFlag([]string{"galeno-whatsapp", "sync", "--account"}); err == nil {
		t.Fatal("--account sin valor debe fallar")
	}
}

func TestEachAccountHasItsOwnStateDirectoryAndTheOneOfAlwaysDoesNotMove(t *testing.T) {
	home := "/Users/x"
	always := stateDirectoryPath(home, "")
	if always != filepath.Join(home, "Library", "Application Support", "Galeno", "whatsapp") {
		t.Fatalf("la de siempre no cambia de sitio: %s", always)
	}
	work := stateDirectoryPath(home, "trabajo")
	other := stateDirectoryPath(home, "personal")
	if work == always || work == other {
		t.Fatalf("cada cuenta tiene su carpeta: %s %s %s", always, work, other)
	}
	if !strings.HasPrefix(work, always+string(filepath.Separator)) {
		t.Fatalf("la de una cuenta vive bajo la de siempre, en una subcarpeta aparte: %s", work)
	}
	// Ninguna cuenta puede caer en un archivo de la carpeta de siempre (messages.db, whatsmeow.db…).
	if filepath.Dir(filepath.Dir(work)) != always {
		t.Fatalf("debe colgar de cuentas/: %s", work)
	}
}

func TestEachAccountHasItsOwnBackgroundService(t *testing.T) {
	if launchAgentLabelFor("") != "com.galeno.whatsapp-bridge" {
		t.Fatal("el de siempre conserva su nombre")
	}
	if launchAgentLabelFor("trabajo") != "com.galeno.whatsapp-bridge.trabajo" {
		t.Fatalf("el de una cuenta lleva el suyo: %s", launchAgentLabelFor("trabajo"))
	}
	plist := renderLaunchdPlist("/bin/galeno-whatsapp", "/tmp/sync.log", "trabajo")
	for _, want := range []string{
		"<string>com.galeno.whatsapp-bridge.trabajo</string>", "<string>sync</string>",
		"<string>--account</string>", "<string>trabajo</string>",
	} {
		if !strings.Contains(plist, want) {
			t.Fatalf("falta %q en el plist:\n%s", want, plist)
		}
	}
	// El de siempre no lleva --account: no cambia lo ya instalado.
	if strings.Contains(renderLaunchdPlist("/bin/galeno-whatsapp", "/tmp/sync.log", ""), "--account") {
		t.Fatal("el servicio de siempre no debe llevar --account")
	}
}

func TestTheAccountIDsTheAppAndTheBridgeAcceptAreTheSame(t *testing.T) {
	for _, good := range []string{"trabajo", "cliente-a", "a1", "x"} {
		if !validAccountID(good) {
			t.Fatalf("%q debería ser válido", good)
		}
	}
}

func TestTheServiceOfAnAccountHasItsOwnPlistPath(t *testing.T) {
	accountID = "trabajo"
	defer func() { accountID = "" }()
	path, err := launchAgentPlistPath()
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasSuffix(path, "com.galeno.whatsapp-bridge.trabajo.plist") {
		t.Fatalf("el plist de una cuenta lleva su nombre: %s", path)
	}
}
