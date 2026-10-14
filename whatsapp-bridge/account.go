package main

import (
	"database/sql"
	"fmt"
	"os"
	"path/filepath"
	"time"
)

// metaAccountKey guarda de qué número es el historial de messages.db. Sin esto, vincular otro número dejaba los chats
// del anterior mezclados con los nuevos (hallazgo con Simon, 12 oct 2026): el agente listaba conversaciones del número
// personal y enviaba por el de trabajo.
const metaAccountKey = "account"

// failureAccountChanged es lo que lee el agente de un envío que esperaba cuando se cambió de número.
const failureAccountChanged = "Not sent: the linked WhatsApp number was changed while this message was waiting, and the chat belongs to the previous number. Tell the user; do not send it again without asking them."

// accountSwitch describe un cambio de número ya aplicado.
type accountSwitch struct {
	Previous string // el número anterior (la parte de usuario del JID)
	Backup   string // ruta de la copia del historial anterior, junto a messages.db
}

// AdoptAccount deja claro que el historial es del número `user`.
//
//   - Si no había número anotado (instalaciones anteriores a esto, o la primera vez), lo anota y no toca nada: no se
//     puede saber de quién era ese historial, y volver a vincular el mismo número (la sesión caduca a los ~20 días) no
//     debe costarle el contexto al usuario.
//   - Si es el mismo número, no hace nada.
//   - Si es otro, **guarda una copia completa del historial** (VACUUM INTO, nunca se borra) y vacía chats y mensajes, para
//     que el agente no vea ni escriba a conversaciones del número anterior. Lo que está en cola para esos chats se marca
//     como fallido. La bandeja de salida conserva lo ya enviado: los topes del día cuentan por cuenta, no por número, y
//     cambiar de número no los reinicia.
func (store *MessageStore) AdoptAccount(user string, now time.Time) (*accountSwitch, error) {
	if user == "" {
		return nil, fmt.Errorf("número vacío")
	}

	var previous string
	err := store.db.QueryRow(`SELECT value FROM meta WHERE key = ?`, metaAccountKey).Scan(&previous)
	if err != nil && err != sql.ErrNoRows {
		return nil, fmt.Errorf("no se pudo leer el número del historial: %v", err)
	}
	if previous == user {
		return nil, nil
	}
	if previous == "" {
		if _, err := store.db.Exec(`INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)`, metaAccountKey, user); err != nil {
			return nil, fmt.Errorf("no se pudo anotar el número del historial: %v", err)
		}
		return nil, nil
	}

	backup := filepath.Join(store.stateDir, fmt.Sprintf("historial-%s-%s.db", previous, now.UTC().Format("20060102-150405")))
	if _, err := store.db.Exec(`VACUUM INTO ?`, backup); err != nil {
		return nil, fmt.Errorf("no se pudo guardar una copia del historial anterior (no se tocó nada): %v", err)
	}
	if err := os.Chmod(backup, 0o600); err != nil {
		return nil, fmt.Errorf("no se pudo proteger la copia del historial anterior (no se tocó nada): %v", err)
	}

	tx, err := store.db.Begin()
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()
	steps := []struct {
		query string
		args  []interface{}
	}{
		{`UPDATE outbox SET status = ?, error = ? WHERE status = ?`, []interface{}{statusFailed, failureAccountChanged, statusPending}},
		{`DELETE FROM messages`, nil},
		{`DELETE FROM chats`, nil},
		{`INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)`, []interface{}{metaAccountKey, user}},
	}
	for _, step := range steps {
		if _, err := tx.Exec(step.query, step.args...); err != nil {
			return nil, fmt.Errorf("no se pudo empezar el historial del número nuevo: %v", err)
		}
	}
	if err := tx.Commit(); err != nil {
		return nil, err
	}
	return &accountSwitch{Previous: previous, Backup: backup}, nil
}

// accountID es el número del que habla este proceso: `""` es el de siempre, y un identificador es una cuenta extra
// (`--account <id>`). Se fija una vez, al arrancar, y no cambia.
var accountID string

// maxAccountIDLength: el identificador acaba en el nombre del servicio de fondo y en una carpeta.
const maxAccountIDLength = 24

// validAccountID: minúsculas, dígitos y guiones, sin guion al principio ni al final. Es lo mismo que acepta la app
// (`AccountID`): nada con lo que una ruta o un nombre de servicio pudiera salirse de su carpeta.
func validAccountID(id string) bool {
	if id == "" || len(id) > maxAccountIDLength || id[0] == '-' || id[len(id)-1] == '-' {
		return false
	}
	for _, c := range id {
		if !(c >= 'a' && c <= 'z') && !(c >= '0' && c <= '9') && c != '-' {
			return false
		}
	}
	return true
}

// extractAccountFlag saca `--account <id>` (o `--account=<id>`) de los argumentos y devuelve los demás. Sin la
// bandera devuelve la cuenta vacía; con un identificador inválido, un error.
func extractAccountFlag(args []string) (rest []string, account string, err error) {
	rest = make([]string, 0, len(args))
	for i := 0; i < len(args); i++ {
		arg := args[i]
		switch {
		case arg == "--account":
			if i+1 >= len(args) {
				return nil, "", fmt.Errorf("--account necesita un identificador (por ejemplo: --account trabajo)")
			}
			account = args[i+1]
			i++
		case len(arg) > len("--account=") && arg[:len("--account=")] == "--account=":
			account = arg[len("--account="):]
		default:
			rest = append(rest, arg)
		}
	}
	if account != "" && !validAccountID(account) {
		return nil, "", fmt.Errorf("--account %q no es válido: solo minúsculas, números y guiones (máximo %d)", account, maxAccountIDLength)
	}
	return rest, account, nil
}

// stateDirectoryPath es la carpeta de estado de una cuenta bajo `home`. La de siempre no cambia de lugar; las extra
// viven en una subcarpeta aparte, así nada de una puede tocar el estado de la otra.
func stateDirectoryPath(home, account string) string {
	base := filepath.Join(home, "Library", "Application Support", "Galeno", "whatsapp")
	if account == "" {
		return base
	}
	return filepath.Join(base, "cuentas", account)
}
