package main

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"testing"
	"time"

	"go.mau.fi/whatsmeow/types"
)

// fakeAliases es un aliasLookup en memoria: lid → número y número → lid, por
// la parte de usuario del JID.
type fakeAliases struct {
	pnForLID map[string]string
	lidForPN map[string]string
}

func newFakeAliases(pairs map[string]string) fakeAliases {
	f := fakeAliases{pnForLID: map[string]string{}, lidForPN: map[string]string{}}
	for lid, pn := range pairs {
		f.pnForLID[lid] = pn
		f.lidForPN[pn] = lid
	}
	return f
}

func (f fakeAliases) GetPNForLID(_ context.Context, lid types.JID) (types.JID, error) {
	if pn, ok := f.pnForLID[lid.User]; ok {
		return types.NewJID(pn, types.DefaultUserServer), nil
	}
	return types.JID{}, errors.New("sin mapeo")
}

func (f fakeAliases) GetLIDForPN(_ context.Context, pn types.JID) (types.JID, error) {
	if lid, ok := f.lidForPN[pn.User]; ok {
		return types.NewJID(lid, types.HiddenUserServer), nil
	}
	return types.JID{}, errors.New("sin mapeo")
}

var t0 = time.Date(2026, 10, 1, 12, 0, 0, 0, time.UTC)

func row(jid, name string, minutes int) chatRow {
	return chatRow{jid: jid, name: name, last: t0.Add(time.Duration(minutes) * time.Minute), hasLast: true}
}

func TestMergesTheNumberAndLIDRowsOfTheSamePerson(t *testing.T) {
	rows := []chatRow{
		row("120363000000000001@g.us", "Equipo Aurora", 30),
		row("573001110001@s.whatsapp.net", "Beatriz Mora", 10),
		row("98765432101234@lid", "98765432101234", 20), // la fila @lid es más reciente y sin nombre
		row("573009990003@s.whatsapp.net", "Carlos Díaz", 5),
	}
	lookup := newFakeAliases(map[string]string{"98765432101234": "573001110001"})

	chats := buildChatList(rows, lookup, nil)

	if len(chats) != 3 {
		t.Fatalf("se esperaban 3 entradas (el contacto repetido se une), hay %d: %+v", len(chats), chats)
	}
	merged := chats[1]
	if merged.JID != "98765432101234@lid" {
		t.Errorf("el JID debe ser el de la fila más reciente, es %s", merged.JID)
	}
	if merged.Name != "Beatriz Mora" {
		t.Errorf("el nombre debe ser el de la fila que sí lo tiene, es %q", merged.Name)
	}
	if len(merged.Aliases) != 1 || merged.Aliases[0] != "573001110001@s.whatsapp.net" {
		t.Errorf("aliases = %v", merged.Aliases)
	}
}

func TestChatsAreSortedNewestFirstAndUndatedLast(t *testing.T) {
	rows := []chatRow{
		row("1@s.whatsapp.net", "Viejo", 1),
		{jid: "2@s.whatsapp.net", name: "Sin fecha"},
		row("3@s.whatsapp.net", "Nuevo", 99),
	}

	var names []string
	for _, c := range buildChatList(rows, nil, nil) {
		names = append(names, c.Name)
	}

	if got := strings.Join(names, ","); got != "Nuevo,Viejo,Sin fecha" {
		t.Errorf("orden = %s", got)
	}
}

func TestRowsAreNotMergedWithoutAKnownMapping(t *testing.T) {
	rows := []chatRow{
		row("573001110001@s.whatsapp.net", "Beatriz", 10),
		row("98765432101234@lid", "98765432101234", 20),
	}

	if n := len(buildChatList(rows, nil, nil)); n != 2 {
		t.Errorf("sin almacén de alias se unieron filas: %d", n)
	}
	if n := len(buildChatList(rows, newFakeAliases(nil), nil)); n != 2 {
		t.Errorf("con un almacén vacío se unieron filas: %d", n)
	}
}

// Que un contacto tenga alias conocido no inventa una fila que no existe.
func TestAKnownAliasWithoutARowAddsNothing(t *testing.T) {
	rows := []chatRow{row("573001110001@s.whatsapp.net", "Beatriz", 10)}
	lookup := newFakeAliases(map[string]string{"98765432101234": "573001110001"})

	chats := buildChatList(rows, lookup, nil)

	if len(chats) != 1 || len(chats[0].Aliases) != 0 {
		t.Errorf("chats = %+v", chats)
	}
}

func TestGroupsAreMarkedAsGroups(t *testing.T) {
	chats := buildChatList([]chatRow{
		row("120363000000000001@g.us", "Equipo", 1),
		row("573001110001@s.whatsapp.net", "Persona", 2),
	}, nil, nil)

	for _, c := range chats {
		if want := strings.HasSuffix(c.JID, "@g.us"); c.IsGroup != want {
			t.Errorf("%s: is_group = %v", c.JID, c.IsGroup)
		}
	}
}

func TestChatsJSONShape(t *testing.T) {
	rows := []chatRow{
		row("120363000000000001@g.us", "Equipo Aurora", 30),
		row("573001110001@s.whatsapp.net", "Beatriz", 10),
		row("98765432101234@lid", "98765432101234", 20),
		{jid: "573009990003@s.whatsapp.net", name: "Sin fecha"},
	}
	data, err := chatsJSON(rows, newFakeAliases(map[string]string{"98765432101234": "573001110001"}), nil)
	if err != nil {
		t.Fatal(err)
	}

	var decoded []map[string]any
	if err := json.Unmarshal(data, &decoded); err != nil {
		t.Fatalf("no es JSON válido: %v\n%s", err, data)
	}
	if len(decoded) != 3 {
		t.Fatalf("entradas = %d", len(decoded))
	}

	group := decoded[0]
	for _, key := range []string{"jid", "name", "is_group", "last_message_time"} {
		if _, ok := group[key]; !ok {
			t.Errorf("falta la clave %q en %v", key, group)
		}
	}
	if _, ok := group["aliases"]; ok {
		t.Error("un chat sin alias no debe llevar la clave aliases")
	}
	if _, ok := decoded[1]["aliases"]; !ok {
		t.Error("el contacto unido debe llevar aliases")
	}
	if _, ok := decoded[2]["last_message_time"]; ok {
		t.Error("un chat sin fecha no debe llevar last_message_time")
	}
}

func TestNoChatsIsAnEmptyArrayNeverNull(t *testing.T) {
	data, err := chatsJSON(nil, nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	if string(data) != "[]\n" {
		t.Errorf("salida = %q", data)
	}
}

func TestLooksUnnamed(t *testing.T) {
	for name, want := range map[string]bool{
		"": true, "98765432101234": true, "573001110001": true,
		"Beatriz": false, "Equipo 2": false, "+57 300": false,
	} {
		if got := looksUnnamed(name); got != want {
			t.Errorf("looksUnnamed(%q) = %v", name, got)
		}
	}
}

// fakeContacts es un contactNames en memoria, por número.
type fakeContacts map[string]types.ContactInfo

func (f fakeContacts) GetContact(_ context.Context, user types.JID) (types.ContactInfo, error) {
	if info, ok := f[user.User]; ok {
		return info, nil
	}
	return types.ContactInfo{}, errors.New("sin contacto")
}

// Un chat que la base guardó con el número como nombre se completa al leer:
// con el nombre de la agenda, o el que la persona se puso, y pasando antes de
// @lid a número, que es como whatsmeow guarda los contactos.
func TestUnnamedChatsGetTheirNameFromTheContacts(t *testing.T) {
	rows := []chatRow{
		row("98765432101234@lid", "", 30),                      // @lid sin nombre
		row("573001110001@s.whatsapp.net", "573001110001", 20), // número como nombre
		row("573009990003@s.whatsapp.net", "573009990003", 10), // solo con nombre propio
		row("573004440004@s.whatsapp.net", "573004440004", 5),  // sin contacto
	}
	lookup := newFakeAliases(map[string]string{"98765432101234": "573007770007"})
	contacts := fakeContacts{
		"573007770007": {Found: true, FullName: "Ana Restrepo", PushName: "ana"},
		"573001110001": {Found: true, FullName: "Beatriz Mora"},
		"573009990003": {Found: true, PushName: "Carlos"},
	}

	var names []string
	for _, c := range buildChatList(rows, lookup, contacts) {
		names = append(names, c.Name)
	}

	if got := strings.Join(names, "|"); got != "Ana Restrepo|Beatriz Mora|Carlos|573004440004" {
		t.Errorf("nombres = %s", got)
	}
}

// El nombre de un grupo y un nombre que ya existe no se tocan.
func TestExistingNamesAreNeverOverwritten(t *testing.T) {
	rows := []chatRow{
		row("120363000000000001@g.us", "Equipo Aurora", 30),
		row("573001110001@s.whatsapp.net", "Nombre guardado", 20),
		row("120363000000000002@g.us", "", 10),
	}
	contacts := fakeContacts{"573001110001": {Found: true, FullName: "Otro nombre"}}

	var names []string
	for _, c := range buildChatList(rows, nil, contacts) {
		names = append(names, c.Name)
	}

	if got := strings.Join(names, "|"); got != "Equipo Aurora|Nombre guardado|" {
		t.Errorf("nombres = %q", got)
	}
}
