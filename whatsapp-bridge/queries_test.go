package main

import (
	"path/filepath"
	"testing"
	"time"
)

// storeWithOneChat abre una base nueva en una carpeta temporal con un chat y un mensaje.
func storeWithOneChat(t *testing.T) *MessageStore {
	t.Helper()
	store, err := NewMessageStore(filepath.Join(t.TempDir(), "messages.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { store.db.Close() })
	when := time.Date(2026, 10, 1, 12, 0, 0, 0, time.UTC)
	if _, err := store.db.Exec(`INSERT INTO chats (jid, name, last_message_time) VALUES (?, ?, ?)`,
		"123@g.us", "Equipo", when); err != nil {
		t.Fatal(err)
	}
	if _, err := store.db.Exec(
		`INSERT INTO messages (id, chat_jid, sender, content, timestamp, is_from_me) VALUES (?, ?, ?, ?, ?, ?)`,
		"m1", "123@g.us", "ana", "hola", when, false); err != nil {
		t.Fatal(err)
	}
	return store
}

// Pedir los chats sin su último mensaje fallaba con "no such column: messages.content": la
// consulta nombraba columnas de una tabla que, sin el JOIN, no estaba.
func TestListChatsWorksWithAndWithoutTheLastMessage(t *testing.T) {
	store := storeWithOneChat(t)

	without, err := store.ListChats(ListChatsOptions{Limit: 20, IncludeLastMessage: false, SortBy: "last_active"})
	if err != nil {
		t.Fatalf("sin último mensaje: %v", err)
	}
	if len(without) != 1 || without[0].JID != "123@g.us" || without[0].LastMessage != "" {
		t.Errorf("sin último mensaje = %+v", without)
	}

	with, err := store.ListChats(ListChatsOptions{Limit: 20, IncludeLastMessage: true, SortBy: "last_active"})
	if err != nil {
		t.Fatalf("con último mensaje: %v", err)
	}
	if len(with) != 1 || with[0].LastMessage != "hola" {
		t.Errorf("con último mensaje = %+v", with)
	}
}

func TestGetChatByJIDWorksWithAndWithoutTheLastMessage(t *testing.T) {
	store := storeWithOneChat(t)

	without, err := store.GetChatByJID("123@g.us", false)
	if err != nil || without == nil {
		t.Fatalf("sin último mensaje: %v, %v", without, err)
	}
	if without.LastMessage != "" {
		t.Errorf("no debería traer el último mensaje: %+v", without)
	}

	with, err := store.GetChatByJID("123@g.us", true)
	if err != nil || with == nil || with.LastMessage != "hola" {
		t.Fatalf("con último mensaje: %+v, %v", with, err)
	}
}
