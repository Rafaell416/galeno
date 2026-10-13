package main

import (
	"database/sql"
	"path/filepath"
	"testing"
	"time"
)

func newAccountTestStore(t *testing.T) *MessageStore {
	t.Helper()
	store, err := NewMessageStore(filepath.Join(t.TempDir(), "messages.db"))
	if err != nil {
		t.Fatalf("NewMessageStore: %v", err)
	}
	t.Cleanup(func() { store.Close() })
	return store
}

func countRows(t *testing.T, db *sql.DB, query string, args ...interface{}) int {
	t.Helper()
	var n int
	if err := db.QueryRow(query, args...).Scan(&n); err != nil {
		t.Fatalf("%s: %v", query, err)
	}
	return n
}

func seedHistory(t *testing.T, store *MessageStore) {
	t.Helper()
	now := time.Now()
	if err := store.StoreChat("5730000000@s.whatsapp.net", "Cliente", now); err != nil {
		t.Fatal(err)
	}
	if err := store.StoreMessage("m1", "5730000000@s.whatsapp.net", "5730000000", "hola", now, false, "", "", "", nil, nil, nil, 0); err != nil {
		t.Fatal(err)
	}
}

func TestAdoptAccountFirstTimeKeepsHistory(t *testing.T) {
	store := newAccountTestStore(t)
	seedHistory(t, store)

	switched, err := store.AdoptAccount("111", time.Now())
	if err != nil || switched != nil {
		t.Fatalf("la primera vez no debe apartar nada: %v %v", switched, err)
	}
	if n := countRows(t, store.db, `SELECT COUNT(*) FROM messages`); n != 1 {
		t.Fatalf("el historial debe seguir: %d mensajes", n)
	}
}

func TestAdoptAccountSameNumberKeepsHistory(t *testing.T) {
	store := newAccountTestStore(t)
	seedHistory(t, store)
	store.AdoptAccount("111", time.Now())

	switched, err := store.AdoptAccount("111", time.Now())
	if err != nil || switched != nil {
		t.Fatalf("el mismo número no debe apartar nada: %v %v", switched, err)
	}
	if n := countRows(t, store.db, `SELECT COUNT(*) FROM messages`); n != 1 {
		t.Fatalf("el historial debe seguir: %d mensajes", n)
	}
}

func TestAdoptAccountOtherNumberBacksUpAndStartsClean(t *testing.T) {
	store := newAccountTestStore(t)
	seedHistory(t, store)
	store.AdoptAccount("111", time.Now())

	now := time.Now().UTC().Format("2006-01-02 15:04:05")
	// Uno ya enviado hoy (cuenta para los topes) y uno en cola para un chat del número anterior.
	if _, err := store.db.Exec(`INSERT INTO outbox (chat_jid, body, created_at, not_before, status, is_new_chat, sent_at) VALUES (?, ?, ?, ?, ?, 0, ?)`,
		"5730000000@s.whatsapp.net", "ya salió", now, now, statusSent, now); err != nil {
		t.Fatal(err)
	}
	if _, err := store.db.Exec(`INSERT INTO outbox (chat_jid, body, created_at, not_before, status, is_new_chat) VALUES (?, ?, ?, ?, ?, 0)`,
		"5730000000@s.whatsapp.net", "en cola", now, now, statusPending); err != nil {
		t.Fatal(err)
	}

	switched, err := store.AdoptAccount("222", time.Now())
	if err != nil {
		t.Fatalf("AdoptAccount: %v", err)
	}
	if switched == nil || switched.Previous != "111" || switched.Backup == "" {
		t.Fatalf("debía reportar el cambio: %+v", switched)
	}

	if n := countRows(t, store.db, `SELECT COUNT(*) FROM messages`); n != 0 {
		t.Fatalf("el historial nuevo debe empezar vacío: %d mensajes", n)
	}
	if n := countRows(t, store.db, `SELECT COUNT(*) FROM chats`); n != 0 {
		t.Fatalf("los chats nuevos deben empezar vacíos: %d", n)
	}
	if n := countRows(t, store.db, `SELECT COUNT(*) FROM outbox WHERE status = ?`, statusSent); n != 1 {
		t.Fatalf("lo ya enviado debe conservarse para los topes: %d", n)
	}
	if n := countRows(t, store.db, `SELECT COUNT(*) FROM outbox WHERE status = ?`, statusPending); n != 0 {
		t.Fatalf("lo que estaba en cola debe quedar fallido: %d pendientes", n)
	}
	var user string
	if err := store.db.QueryRow(`SELECT value FROM meta WHERE key = ?`, metaAccountKey).Scan(&user); err != nil || user != "222" {
		t.Fatalf("el número anotado debe ser el nuevo: %q %v", user, err)
	}

	// La copia conserva todo.
	backup, err := sql.Open("sqlite3", "file:"+switched.Backup+"?mode=ro")
	if err != nil {
		t.Fatal(err)
	}
	defer backup.Close()
	if n := countRows(t, backup, `SELECT COUNT(*) FROM messages`); n != 1 {
		t.Fatalf("la copia debe tener el historial anterior: %d mensajes", n)
	}
}

func TestAdoptAccountRejectsEmptyNumber(t *testing.T) {
	store := newAccountTestStore(t)
	if _, err := store.AdoptAccount("", time.Now()); err == nil {
		t.Fatal("un número vacío no debe aceptarse")
	}
}
