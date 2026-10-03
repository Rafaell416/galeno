package main

import (
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
}
