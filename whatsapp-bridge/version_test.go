package main

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

func TestBridgeVersionIsSemver(t *testing.T) {
	if !regexp.MustCompile(`^\d+\.\d+\.\d+$`).MatchString(bridgeVersion) {
		t.Errorf("bridgeVersion = %q, se esperaba MAJOR.MINOR.PATCH", bridgeVersion)
	}
}

// Prueba de punta a punta de los subcomandos que usa la app: se compila el
// binario de verdad y se corre con un HOME vacío, así que no toca el estado
// de nadie y no abre ninguna conexión.
func TestSubcommandsTheAppUses(t *testing.T) {
	bin := filepath.Join(t.TempDir(), "galeno-whatsapp")
	if out, err := exec.Command("go", "build", "-o", bin, ".").CombinedOutput(); err != nil {
		t.Fatalf("no compiló: %v\n%s", err, out)
	}
	home := t.TempDir()

	run := func(args ...string) (stdout, stderr string, exitCode int) {
		cmd := exec.Command(bin, args...)
		cmd.Env = append(os.Environ(), "HOME="+home)
		var out, errOut strings.Builder
		cmd.Stdout, cmd.Stderr = &out, &errOut
		err := cmd.Run()
		if exitErr, ok := err.(*exec.ExitError); ok {
			return out.String(), errOut.String(), exitErr.ExitCode()
		}
		if err != nil {
			t.Fatalf("%v: %v", args, err)
		}
		return out.String(), errOut.String(), 0
	}

	t.Run("version imprime solo el número", func(t *testing.T) {
		for _, arg := range []string{"version", "--version"} {
			stdout, _, code := run(arg)
			if code != 0 || stdout != bridgeVersion+"\n" {
				t.Errorf("%s → código %d, salida %q", arg, code, stdout)
			}
		}
	})

	t.Run("chats --json con la base vacía es un arreglo vacío", func(t *testing.T) {
		stdout, stderr, code := run("chats", "--json")
		if code != 0 || stdout != "[]\n" {
			t.Errorf("código %d, salida %q, stderr %q", code, stdout, stderr)
		}
	})

	t.Run("chats sin --json es un error de uso y no toca nada", func(t *testing.T) {
		stdout, _, code := run("chats")
		if code != 2 || stdout != "" {
			t.Errorf("código %d, salida %q", code, stdout)
		}
	})

	t.Run("outbox --json con la bandeja vacía trae los topes por defecto", func(t *testing.T) {
		stdout, stderr, code := run("outbox", "--json")
		if code != 0 {
			t.Fatalf("código %d, stderr %q", code, stderr)
		}
		var report outboxReport
		if err := json.Unmarshal([]byte(stdout), &report); err != nil {
			t.Fatalf("no es JSON: %v\n%s", err, stdout)
		}
		wantLimits := outboxReportLimits{defaultDailyTotal, defaultDailyNewChats, maxDailyTotal, maxDailyNewChats}
		if report.Paused || report.Limits != wantLimits || report.Today != (outboxReportToday{}) || report.PendingTotal != 0 {
			t.Errorf("informe = %+v", report)
		}
		// Un arreglo vacío, nunca null: la app lo recorre sin mirar.
		if !strings.Contains(stdout, `"recent": []`) {
			t.Errorf("recent debía ser []:\n%s", stdout)
		}
	})

	t.Run("outbox --json ve la pausa y los topes que puso la app", func(t *testing.T) {
		state := filepath.Join(home, "Library", "Application Support", "Galeno", "whatsapp")
		if err := os.WriteFile(filepath.Join(state, pauseFilename), nil, 0o600); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(state, limitsFilename), []byte(`{"daily_total": 10, "daily_new_chats": 999}`), 0o600); err != nil {
			t.Fatal(err)
		}
		stdout, _, _ := run("outbox", "--json")
		var report outboxReport
		if err := json.Unmarshal([]byte(stdout), &report); err != nil {
			t.Fatalf("no es JSON: %v\n%s", err, stdout)
		}
		if !report.Paused || report.Limits.DailyTotal != 10 || report.Limits.DailyNewChats != maxDailyNewChats {
			t.Errorf("informe = %+v", report)
		}
	})

	t.Run("outbox sin --json es un error de uso", func(t *testing.T) {
		stdout, _, code := run("outbox")
		if code != 2 || stdout != "" {
			t.Errorf("código %d, salida %q", code, stdout)
		}
	})

	t.Run("serve no acepta opciones que no conoce", func(t *testing.T) {
		stdout, _, code := run("serve", "--sin-preguntar")
		if code != 2 || stdout != "" {
			t.Errorf("código %d, salida %q", code, stdout)
		}
	})

	// Sin sesión vinculada, con o sin envío, serve se niega y no escribe nada
	// en stdout (que sería el transporte MCP).
	t.Run("serve exige estar vinculado", func(t *testing.T) {
		for _, args := range [][]string{{"serve"}, {"serve", "--with-send"}} {
			stdout, stderr, code := run(args...)
			if code != 1 || stdout != "" || !strings.Contains(stderr, "galeno-whatsapp pair") {
				t.Errorf("%v → código %d, salida %q, stderr %q", args, code, stdout, stderr)
			}
		}
	})
}
