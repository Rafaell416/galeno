package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"sort"
	"strings"
	"time"

	"go.mau.fi/whatsmeow/types"
)

// Subcomando "chats --json": la lista de chats que la app muestra en "elige
// qué leer" y de donde saca el "Encontré N grupos". Lo corre la app, no el
// agente (que no tiene terminal), y lee todo lo que "sync" guardó: elegir un
// chat aquí le dice al agente en qué enfocarse, no le quita acceso a los demás.
//
// No abre ninguna conexión a WhatsApp.

// ChatEntry es un chat tal como lo ve la app.
type ChatEntry struct {
	JID             string  `json:"jid"`
	Name            string  `json:"name"`
	IsGroup         bool    `json:"is_group"`
	LastMessageTime *string `json:"last_message_time,omitempty"`
	// Aliases son los otros JID del mismo contacto: WhatsApp puede identificar
	// a una persona por su número (@s.whatsapp.net) o por un identificador
	// oculto (@lid), y la base puede tener una fila de cada uno.
	Aliases []string `json:"aliases,omitempty"`
}

type chatRow struct {
	jid     string
	name    string
	last    time.Time
	hasLast bool
}

// aliasLookup es lo único que se necesita del almacén de whatsmeow para
// saber si dos JID son la misma persona. Lo cumple client.Store.LIDs, y
// consultarlo es local: no toca la red.
type aliasLookup interface {
	GetPNForLID(ctx context.Context, lid types.JID) (types.JID, error)
	GetLIDForPN(ctx context.Context, pn types.JID) (types.JID, error)
}

func (store *MessageStore) listChatRows() ([]chatRow, error) {
	rows, err := store.db.Query("SELECT jid, name, last_message_time FROM chats")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []chatRow
	for rows.Next() {
		var jid string
		var name sql.NullString
		var last sql.NullTime
		if err := rows.Scan(&jid, &name, &last); err != nil {
			return nil, err
		}
		result = append(result, chatRow{jid: jid, name: name.String, last: last.Time, hasLast: last.Valid})
	}
	return result, rows.Err()
}

// counterpartJID devuelve el otro JID de la misma persona, si se conoce.
func counterpartJID(jid string, lookup aliasLookup) (string, bool) {
	if lookup == nil {
		return "", false
	}
	parsed, err := types.ParseJID(jid)
	if err != nil {
		return "", false
	}
	var other types.JID
	switch parsed.Server {
	case types.HiddenUserServer:
		other, err = lookup.GetPNForLID(context.Background(), parsed)
	case types.DefaultUserServer:
		other, err = lookup.GetLIDForPN(context.Background(), parsed)
	default:
		return "", false
	}
	if err != nil || other.IsEmpty() {
		return "", false
	}
	return other.ToNonAD().String(), true
}

// contactNames es lo único que se necesita de los contactos de whatsmeow para
// ponerle nombre a un chat que la base guardó sin él. Lo cumple
// client.Store.Contacts, y consultarlo es local.
type contactNames interface {
	GetContact(ctx context.Context, user types.JID) (types.ContactInfo, error)
}

// resolvedName busca el nombre de una persona en los contactos de whatsmeow,
// que guardan los números, no los @lid: un JID @lid se pasa antes a su número.
// Primero el nombre de la agenda, y si no hay, el que la persona se puso.
func resolvedName(jid string, lookup aliasLookup, contacts contactNames) string {
	if contacts == nil {
		return ""
	}
	candidates := []string{jid}
	if other, ok := counterpartJID(jid, lookup); ok {
		candidates = append(candidates, other)
	}
	for _, candidate := range candidates {
		parsed, err := types.ParseJID(candidate)
		if err != nil || parsed.Server != types.DefaultUserServer {
			continue
		}
		info, err := contacts.GetContact(context.Background(), parsed)
		if err != nil {
			continue
		}
		for _, name := range []string{info.FullName, info.PushName, info.BusinessName} {
			if name != "" {
				return name
			}
		}
	}
	return ""
}

// looksUnnamed dice si un nombre es solo el número o el identificador: lo que
// el almacén guarda cuando no encontró el nombre de la persona.
func looksUnnamed(name string) bool {
	if name == "" {
		return true
	}
	for _, r := range name {
		if r < '0' || r > '9' {
			return false
		}
	}
	return true
}

// buildChatList arma la lista que ve la app: un contacto con una fila por
// número y otra por @lid sale como una sola entrada, con el JID de la fila
// más reciente y el otro en aliases. Del más reciente al más antiguo.
func buildChatList(rows []chatRow, lookup aliasLookup, contacts contactNames) []ChatEntry {
	byJID := make(map[string]int, len(rows))
	for i, row := range rows {
		byJID[row.jid] = i
	}

	merged := make([]bool, len(rows))
	type item struct {
		entry ChatEntry
		last  time.Time
		has   bool
	}
	var items []item

	for i, row := range rows {
		if merged[i] {
			continue
		}
		primary, secondary := row, (*chatRow)(nil)

		if other, ok := counterpartJID(row.jid, lookup); ok && other != row.jid {
			if j, exists := byJID[other]; exists && !merged[j] {
				merged[j] = true
				candidate := rows[j]
				secondary = &candidate
				if candidate.hasLast && (!row.hasLast || candidate.last.After(row.last)) {
					primary, secondary = candidate, &row
				}
			}
		}
		merged[i] = true

		name := primary.name
		var aliases []string
		if secondary != nil {
			aliases = []string{secondary.jid}
			if looksUnnamed(name) && !looksUnnamed(secondary.name) {
				name = secondary.name
			}
		}

		// La base guarda el número como nombre cuando no encontró el de la
		// persona. Se completa al leer, sin tocar la base.
		if looksUnnamed(name) && !strings.HasSuffix(primary.jid, "@g.us") {
			if resolved := resolvedName(primary.jid, lookup, contacts); resolved != "" {
				name = resolved
			}
		}

		entry := ChatEntry{
			JID:     primary.jid,
			Name:    name,
			IsGroup: strings.HasSuffix(primary.jid, "@g.us"),
			Aliases: aliases,
		}
		if primary.hasLast {
			formatted := primary.last.Format(time.RFC3339)
			entry.LastMessageTime = &formatted
		}
		items = append(items, item{entry: entry, last: primary.last, has: primary.hasLast})
	}

	sort.SliceStable(items, func(a, b int) bool {
		if items[a].has != items[b].has {
			return items[a].has // los que tienen fecha, primero
		}
		if !items[a].last.Equal(items[b].last) {
			return items[a].last.After(items[b].last)
		}
		return items[a].entry.JID < items[b].entry.JID
	})

	entries := make([]ChatEntry, 0, len(items))
	for _, it := range items {
		entries = append(entries, it.entry)
	}
	return entries
}

// chatsJSON es la salida del subcomando: siempre un arreglo, vacío si no hay
// chats (nunca null).
func chatsJSON(rows []chatRow, lookup aliasLookup, contacts contactNames) ([]byte, error) {
	data, err := json.MarshalIndent(buildChatList(rows, lookup, contacts), "", "  ")
	if err != nil {
		return nil, err
	}
	return append(data, '\n'), nil
}

// runChats — subcomando "chats". Solo imprime JSON en stdout; los logs van a
// stderr.
func runChats() {
	flags := flag.NewFlagSet("chats", flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	asJSON := flags.Bool("json", false, "imprime la lista de chats como JSON")
	if err := flags.Parse(os.Args[2:]); err != nil {
		os.Exit(2)
	}
	if !*asJSON {
		fmt.Fprintln(os.Stderr, "Uso: galeno-whatsapp chats --json")
		os.Exit(2)
	}

	logger := newLogger("Chats", "WARN", false)
	client, messageStore, _, err := openClient(logger)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	defer messageStore.Close()

	rows, err := messageStore.listChatRows()
	if err != nil {
		fmt.Fprintf(os.Stderr, "No se pudo leer la lista de chats: %v\n", err)
		os.Exit(1)
	}

	out, err := chatsJSON(rows, client.Store.LIDs, client.Store.Contacts)
	if err != nil {
		fmt.Fprintf(os.Stderr, "No se pudo armar el JSON: %v\n", err)
		os.Exit(1)
	}
	os.Stdout.Write(out)
}
