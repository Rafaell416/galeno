package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/modelcontextprotocol/go-sdk/mcp"
	"go.mau.fi/whatsmeow/types"
)

// Las pruebas del envío. Ninguna toca la red: "sync" despacha con un cliente
// simulado (fakeWhatsApp) detrás de la interfaz messageSender, y el reloj es
// el que cada prueba pone.

var bogota = time.FixedZone("COT", -5*60*60)

// Miércoles 7 de octubre de 2026, 10:00, hora de Colombia: en horario.
var wednesdayMorning = time.Date(2026, 10, 7, 10, 0, 0, 0, bogota)

type delivery struct {
	to   string
	id   string
	body string
}

type fakeWhatsApp struct {
	offline       bool
	notOnWhatsApp map[string]bool
	lookupErr     error
	deliveryErr   error
	lookups       int
	delivered     []delivery
	ids           int
}

func (f *fakeWhatsApp) Ready() bool     { return !f.offline }
func (f *fakeWhatsApp) OwnUser() string { return "573009998877" }

func (f *fakeWhatsApp) NewMessageID() string {
	f.ids++
	return fmt.Sprintf("WAID%d", f.ids)
}

func (f *fakeWhatsApp) IsOnWhatsApp(_ context.Context, phone string) (types.JID, bool, error) {
	f.lookups++
	if f.lookupErr != nil {
		return types.JID{}, false, f.lookupErr
	}
	if f.notOnWhatsApp[phone] {
		return types.JID{}, false, nil
	}
	return types.NewJID(phone, types.DefaultUserServer), true, nil
}

func (f *fakeWhatsApp) SendText(_ context.Context, to types.JID, id, body string) (time.Time, error) {
	if f.deliveryErr != nil {
		return time.Time{}, f.deliveryErr
	}
	f.delivered = append(f.delivered, delivery{to: to.String(), id: id, body: body})
	return time.Time{}, nil
}

// testOutbox es una bandeja en una carpeta temporal, con un reloj que la
// prueba mueve a mano.
type testOutbox struct {
	env      outboxEnv
	clock    *time.Time
	whatsapp *fakeWhatsApp
	sync     *outboxDispatcher
}

func newTestOutbox(t *testing.T, now time.Time) *testOutbox {
	t.Helper()
	dir := t.TempDir()
	store, err := NewMessageStore(filepath.Join(dir, "messages.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { store.Close() })

	clock := now
	env := newOutboxEnv(store, dir, nil, nil)
	env.now = func() time.Time { return clock }
	env.spacing = func() time.Duration { return time.Minute }
	env.wait = 150 * time.Millisecond
	env.poll = 5 * time.Millisecond

	whatsapp := &fakeWhatsApp{}
	return &testOutbox{
		env:      env,
		clock:    &clock,
		whatsapp: whatsapp,
		sync:     &outboxDispatcher{env: env, sender: whatsapp, logger: newLogger("Test", "ERROR", false)},
	}
}

func (o *testOutbox) advance(d time.Duration) { *o.clock = o.clock.Add(d) }

// knownChat deja un mensaje previo con esa persona: ya no es un chat nuevo.
func (o *testOutbox) knownChat(t *testing.T, jid string) {
	t.Helper()
	db := o.env.store.db
	if _, err := db.Exec(`INSERT OR IGNORE INTO chats (jid, name, last_message_time) VALUES (?, ?, ?)`,
		jid, "Conocido", wednesdayMorning.Add(-24*time.Hour)); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(
		`INSERT INTO messages (id, chat_jid, sender, content, timestamp, is_from_me) VALUES (?, ?, ?, ?, ?, ?)`,
		"prev-"+jid, jid, "alguien", "hola", wednesdayMorning.Add(-24*time.Hour), false); err != nil {
		t.Fatal(err)
	}
}

func (o *testOutbox) mustEnqueue(t *testing.T, recipient, body string) enqueueResult {
	t.Helper()
	result, err := o.env.enqueue(recipient, body)
	if err != nil {
		t.Fatalf("enqueue(%q): %v", recipient, err)
	}
	return result
}

func (o *testOutbox) rows(t *testing.T) int {
	t.Helper()
	var n int
	if err := o.env.store.db.QueryRow(`SELECT COUNT(*) FROM outbox`).Scan(&n); err != nil {
		t.Fatal(err)
	}
	return n
}

func (o *testOutbox) status(t *testing.T, id int64) outboxOutcome {
	t.Helper()
	out, err := o.env.outcome(id)
	if err != nil {
		t.Fatal(err)
	}
	return out
}

func (o *testOutbox) writeLimits(t *testing.T, content string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(o.env.stateDir, limitsFilename), []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
}

func (o *testOutbox) pause(t *testing.T) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(o.env.stateDir, pauseFilename), nil, 0o600); err != nil {
		t.Fatal(err)
	}
}

func phone(i int) string { return fmt.Sprintf("5730011122%02d", i) }

// MARK: - A quién

func TestOnlyOnePersonCanBeARecipient(t *testing.T) {
	aliases := newFakeAliases(map[string]string{"98765432101234": "573001112233"})

	cases := []struct {
		name      string
		recipient string
		wantJID   string
		wantWhy   string
	}{
		{"número", "573001112233", "573001112233@s.whatsapp.net", ""},
		{"número con + y espacios", "+57 300 111-2233", "573001112233@s.whatsapp.net", ""},
		{"JID de persona", "573001112233@s.whatsapp.net", "573001112233@s.whatsapp.net", ""},
		{"@lid conocido pasa a su número", "98765432101234@lid", "573001112233@s.whatsapp.net", ""},
		{"@lid desconocido", "11111111111111@lid", "", reasonUnknownLID},
		{"grupo", "120363021234567890@g.us", "", reasonGroup},
		{"lista de difusión", "1234567890@broadcast", "", reasonBroadcast},
		{"estados", "status@broadcast", "", reasonBroadcast},
		{"canal", "120363999999999999@newsletter", "", reasonNewsletter},
		{"otro servidor", "573001112233@c.us", "", reasonNotAPerson},
		{"muy corto", "1234567", "", reasonBadNumber},
		{"muy largo", "1234567890123456", "", reasonBadNumber},
		{"con letras", "57300abc2233", "", reasonBadNumber},
		{"vacío", "  ", "", reasonBadNumber},
		{"JID sin número", "ana@s.whatsapp.net", "", reasonBadNumber},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			jid, why := resolveRecipient(c.recipient, aliases)
			if why != c.wantWhy {
				t.Fatalf("razón = %q, se esperaba %q", why, c.wantWhy)
			}
			if c.wantWhy == "" && jid.String() != c.wantJID {
				t.Errorf("jid = %q, se esperaba %q", jid, c.wantJID)
			}
		})
	}
}

func TestGroupsBroadcastsAndChannelsAreRejectedAndNothingIsWritten(t *testing.T) {
	o := newTestOutbox(t, wednesdayMorning)
	for _, recipient := range []string{
		"120363021234567890@g.us", "1234567890@broadcast", "status@broadcast", "120363999999999999@newsletter",
	} {
		result := o.mustEnqueue(t, recipient, "Hola")
		if !result.Rejected || result.Reason == "" {
			t.Errorf("%s: se esperaba un rechazo con razón, salió %+v", recipient, result)
		}
	}
	if n := o.rows(t); n != 0 {
		t.Errorf("un rechazo no escribe nada; hay %d filas", n)
	}
}

// MARK: - Qué

func TestEmptyAndTooLongMessagesAreRejected(t *testing.T) {
	o := newTestOutbox(t, wednesdayMorning)

	if result := o.mustEnqueue(t, phone(1), " \n "); result.Reason != reasonEmptyText {
		t.Errorf("vacío: %+v", result)
	}
	if result := o.mustEnqueue(t, phone(1), strings.Repeat("ñ", maxBodyChars+1)); result.Reason != reasonTooLong {
		t.Errorf("largo: %+v", result)
	}
	// Mil caracteres justos sí pasan, y se cuentan caracteres, no bytes.
	if result := o.mustEnqueue(t, phone(1), strings.Repeat("ñ", maxBodyChars)); result.Rejected {
		t.Errorf("mil caracteres: %+v", result)
	}
	if n := o.rows(t); n != 1 {
		t.Errorf("filas = %d, se esperaba 1", n)
	}
}

func TestTheSameTextToMoreThanThreeChatsIsRejected(t *testing.T) {
	o := newTestOutbox(t, wednesdayMorning)

	// El mismo texto, con mayúsculas y espacios cambiados, es el mismo texto.
	variants := []string{"Hola, ¿cómo vas?", "hola,  ¿cómo vas?", "HOLA, ¿CÓMO VAS?\n"}
	for i, body := range variants {
		if result := o.mustEnqueue(t, phone(i), body); result.Rejected {
			t.Fatalf("chat %d: %+v", i, result)
		}
	}
	if result := o.mustEnqueue(t, phone(9), "Hola, ¿cómo vas?"); result.Reason != reasonRepeated {
		t.Errorf("el cuarto chat debía rechazarse: %+v", result)
	}
	// A alguien que ya lo recibió, y con otro texto, sí.
	if result := o.mustEnqueue(t, phone(0), "Hola, ¿cómo vas?"); result.Rejected {
		t.Errorf("repetir a la misma persona: %+v", result)
	}
	if result := o.mustEnqueue(t, phone(9), "Hola Ana, vi tu tienda y quería contarte algo."); result.Rejected {
		t.Errorf("otro texto: %+v", result)
	}
}

// MARK: - Topes

func TestTheDailyLimitRejectsTheNextMessage(t *testing.T) {
	o := newTestOutbox(t, wednesdayMorning)
	o.writeLimits(t, `{"daily_total": 2, "daily_new_chats": 25}`)

	for i := 0; i < 2; i++ {
		if result := o.mustEnqueue(t, phone(i), fmt.Sprintf("Mensaje %d", i)); result.Rejected {
			t.Fatalf("mensaje %d: %+v", i, result)
		}
	}
	result := o.mustEnqueue(t, phone(2), "Mensaje 2")
	if !result.Rejected || !strings.Contains(result.Reason, "2 of 2") {
		t.Errorf("el tercero debía rechazarse por tope: %+v", result)
	}
	if n := o.rows(t); n != 2 {
		t.Errorf("filas = %d, se esperaba 2", n)
	}
}

func TestTheNewChatLimitOnlyCountsPeopleWithNoPreviousChat(t *testing.T) {
	o := newTestOutbox(t, wednesdayMorning)
	o.writeLimits(t, `{"daily_total": 40, "daily_new_chats": 2}`)
	known := phone(50) + "@s.whatsapp.net"
	o.knownChat(t, known)

	for i := 0; i < 2; i++ {
		if result := o.mustEnqueue(t, phone(i), fmt.Sprintf("Primer contacto %d", i)); result.Rejected {
			t.Fatalf("nuevo %d: %+v", i, result)
		}
	}
	result := o.mustEnqueue(t, phone(2), "Primer contacto 2")
	if !result.Rejected || !strings.Contains(result.Reason, "new contacts") {
		t.Errorf("el tercer chat nuevo debía rechazarse: %+v", result)
	}
	// Con quien ya hay conversación se sigue pudiendo, y un segundo mensaje a
	// alguien nuevo de hoy no vuelve a contar como nuevo.
	if result := o.mustEnqueue(t, known, "Seguimiento"); result.Rejected {
		t.Errorf("chat conocido: %+v", result)
	}
	if result := o.mustEnqueue(t, phone(0), "Se me olvidó decirte algo"); result.Rejected {
		t.Errorf("segundo mensaje al mismo chat nuevo: %+v", result)
	}
}

func TestLimitsCannotBeRaisedAboveTheCeiling(t *testing.T) {
	dir := t.TempDir()
	write := func(content string) outboxLimits {
		if err := os.WriteFile(filepath.Join(dir, limitsFilename), []byte(content), 0o600); err != nil {
			t.Fatal(err)
		}
		return loadOutboxLimits(dir)
	}

	if got := loadOutboxLimits(dir); got != (outboxLimits{defaultDailyTotal, defaultDailyNewChats}) {
		t.Errorf("sin archivo = %+v", got)
	}
	if got := write(`{"daily_total": 5000, "daily_new_chats": 5000}`); got != (outboxLimits{maxDailyTotal, maxDailyNewChats}) {
		t.Errorf("por encima del techo = %+v", got)
	}
	if got := write(`{"daily_total": 10, "daily_new_chats": 3}`); got != (outboxLimits{10, 3}) {
		t.Errorf("bajados = %+v", got)
	}
	if got := write(`{"daily_total": -1}`); got != (outboxLimits{defaultDailyTotal, defaultDailyNewChats}) {
		t.Errorf("negativo o ausente = %+v", got)
	}
	if got := write(`esto no es json`); got != (outboxLimits{defaultDailyTotal, defaultDailyNewChats}) {
		t.Errorf("ilegible = %+v", got)
	}
}

// Con el archivo pidiendo miles, el chat nuevo número 26 del día se rechaza.
func TestTheCeilingHoldsWhenTheFileAsksForMore(t *testing.T) {
	o := newTestOutbox(t, wednesdayMorning)
	o.writeLimits(t, `{"daily_total": 5000, "daily_new_chats": 5000}`)

	for i := 0; i < maxDailyNewChats; i++ {
		if result := o.mustEnqueue(t, phone(i), fmt.Sprintf("Primer contacto %d", i)); result.Rejected {
			t.Fatalf("nuevo %d: %+v", i, result)
		}
	}
	if result := o.mustEnqueue(t, phone(90), "Uno más"); !result.Rejected {
		t.Errorf("el %d debía rechazarse: %+v", maxDailyNewChats+1, result)
	}
}

// MARK: - Horario y espaciado

func TestOfficeHours(t *testing.T) {
	at := func(day, hour, minute int) time.Time { return time.Date(2026, 10, day, hour, minute, 0, 0, bogota) }
	// Octubre de 2026: el 5 es lunes, el 9 viernes, el 10 sábado, el 11 domingo.
	cases := []struct {
		name string
		when time.Time
		want time.Time
	}{
		{"miércoles en horario", at(7, 10, 0), at(7, 10, 0)},
		{"miércoles antes de abrir", at(7, 7, 59), at(7, 8, 0)},
		{"miércoles justo al abrir", at(7, 8, 0), at(7, 8, 0)},
		{"miércoles al cerrar", at(7, 19, 0), at(8, 8, 0)},
		{"viernes de noche", at(9, 21, 30), at(10, 8, 0)},
		{"sábado por la mañana", at(10, 12, 59), at(10, 12, 59)},
		{"sábado por la tarde", at(10, 13, 0), at(12, 8, 0)},
		{"domingo", at(11, 11, 0), at(12, 8, 0)},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := nextOpening(c.when); !got.Equal(c.want) {
				t.Errorf("nextOpening = %s, se esperaba %s", got, c.want)
			}
			if inOfficeHours(c.when) != c.when.Equal(c.want) {
				t.Errorf("inOfficeHours(%s) no cuadra con nextOpening", c.when)
			}
		})
	}
}

func TestOutsideOfficeHoursTheMessageWaitsForTheNextOpening(t *testing.T) {
	saturdayAfternoon := time.Date(2026, 10, 10, 14, 0, 0, 0, bogota)
	o := newTestOutbox(t, saturdayAfternoon)

	result := o.mustEnqueue(t, phone(1), "Hola")
	monday := time.Date(2026, 10, 12, 8, 0, 0, 0, bogota)
	if result.Rejected || result.DueNow || !result.NotBefore.Equal(monday) {
		t.Fatalf("se esperaba en cola para el lunes a las 8: %+v", result)
	}

	// "sync" tampoco lo saca antes de tiempo.
	o.sync.dispatchOutbox(context.Background())
	if len(o.whatsapp.delivered) != 0 || o.status(t, result.ID).Status != statusPending {
		t.Errorf("no debía salir fuera de horario")
	}
}

// Lo que se pide un viernes por la noche cuenta para el tope del sábado.
func TestLimitsCountForTheDayTheMessageGoesOut(t *testing.T) {
	fridayNight := time.Date(2026, 10, 9, 20, 0, 0, 0, bogota)
	o := newTestOutbox(t, fridayNight)
	o.writeLimits(t, `{"daily_total": 2, "daily_new_chats": 25}`)

	for i := 0; i < 2; i++ {
		if result := o.mustEnqueue(t, phone(i), fmt.Sprintf("Mensaje %d", i)); result.Rejected {
			t.Fatalf("mensaje %d: %+v", i, result)
		}
	}
	result := o.mustEnqueue(t, phone(2), "Mensaje 2")
	if !result.Rejected || !strings.Contains(result.Reason, "2026-10-10") {
		t.Errorf("el tercero debía rechazarse por el tope del sábado: %+v", result)
	}
}

func TestSpacingBetweenMessagesNeverGoesBelowTheMinimum(t *testing.T) {
	o := newTestOutbox(t, wednesdayMorning)
	// Aunque quien calcula el rato devuelva cero.
	o.env.spacing = func() time.Duration { return 0 }

	first := o.mustEnqueue(t, phone(1), "Uno")
	second := o.mustEnqueue(t, phone(2), "Dos")
	third := o.mustEnqueue(t, phone(3), "Tres")

	if !first.DueNow {
		t.Errorf("el primero del día sale ya: %+v", first)
	}
	if second.DueNow || second.NotBefore.Sub(first.NotBefore) < minSpacing {
		t.Errorf("segundo: %s después del primero", second.NotBefore.Sub(first.NotBefore))
	}
	if third.NotBefore.Sub(second.NotBefore) < minSpacing {
		t.Errorf("tercero: %s después del segundo", third.NotBefore.Sub(second.NotBefore))
	}

	for i := 0; i < 2000; i++ {
		if d := randomSpacing(); d < minSpacing || d > maxSpacing {
			t.Fatalf("randomSpacing() = %s, fuera de %s–%s", d, minSpacing, maxSpacing)
		}
	}
}

// Varios mensajes atrasados (el Mac estuvo dormido) no salen de golpe.
func TestOverdueMessagesStillGoOutOneAtATime(t *testing.T) {
	o := newTestOutbox(t, wednesdayMorning)
	first := o.mustEnqueue(t, phone(1), "Uno")
	second := o.mustEnqueue(t, phone(2), "Dos")

	o.advance(2 * time.Hour)
	ctx := context.Background()
	o.sync.dispatchOutbox(ctx)
	o.advance(10 * time.Second)
	o.sync.dispatchOutbox(ctx)
	if len(o.whatsapp.delivered) != 1 || o.status(t, second.ID).Status != statusPending {
		t.Fatalf("a los 10 s solo debía haber salido uno: %+v", o.whatsapp.delivered)
	}
	if o.status(t, first.ID).Status != statusSent {
		t.Errorf("el primero debía estar enviado")
	}

	o.advance(time.Minute)
	o.sync.dispatchOutbox(ctx)
	if len(o.whatsapp.delivered) != 2 || o.status(t, second.ID).Status != statusSent {
		t.Errorf("pasado el rato debía salir el segundo: %+v", o.whatsapp.delivered)
	}
}

// Aunque el despacho se reinicie y olvide su propio reloj, el mínimo se
// respeta contra lo que dice la base.
func TestSpacingHoldsAcrossARestartOfSync(t *testing.T) {
	o := newTestOutbox(t, wednesdayMorning)
	o.mustEnqueue(t, phone(1), "Uno")
	second := o.mustEnqueue(t, phone(2), "Dos")
	if _, err := o.env.store.db.Exec(`UPDATE outbox SET not_before = ?`, stamp(wednesdayMorning)); err != nil {
		t.Fatal(err)
	}

	ctx := context.Background()
	o.sync.dispatchOutbox(ctx)
	restarted := &outboxDispatcher{env: o.env, sender: o.whatsapp, logger: o.sync.logger}
	o.advance(minSpacing - time.Second)
	restarted.dispatchOutbox(ctx)
	if len(o.whatsapp.delivered) != 1 {
		t.Fatalf("antes del mínimo no debía salir el segundo: %+v", o.whatsapp.delivered)
	}
	o.advance(2 * time.Second)
	restarted.dispatchOutbox(ctx)
	if o.status(t, second.ID).Status != statusSent {
		t.Errorf("pasado el mínimo debía salir")
	}
}

func TestOverdueMessagesBeyondTheDailyLimitMoveToAnotherDay(t *testing.T) {
	o := newTestOutbox(t, wednesdayMorning)
	o.writeLimits(t, `{"daily_total": 1, "daily_new_chats": 25}`)
	o.mustEnqueue(t, phone(1), "El de hoy")
	// Uno de ayer que no salió porque el Mac estaba apagado.
	if _, err := o.env.store.db.Exec(
		`INSERT INTO outbox (chat_jid, body, created_at, not_before, status, is_new_chat) VALUES (?, ?, ?, ?, ?, ?)`,
		phone(2)+"@s.whatsapp.net", "El de ayer", stamp(wednesdayMorning.Add(-20*time.Hour)),
		stamp(wednesdayMorning.Add(-20*time.Hour)), statusPending, true); err != nil {
		t.Fatal(err)
	}

	ctx := context.Background()
	o.sync.dispatchOutbox(ctx)
	o.advance(5 * time.Minute)
	o.sync.dispatchOutbox(ctx)

	if len(o.whatsapp.delivered) != 1 {
		t.Fatalf("con tope 1 solo debía salir uno hoy: %+v", o.whatsapp.delivered)
	}
	var notBefore time.Time
	if err := o.env.store.db.QueryRow(`SELECT not_before FROM outbox WHERE status = ?`, statusPending).
		Scan(&notBefore); err != nil {
		t.Fatal(err)
	}
	thursday := time.Date(2026, 10, 8, 8, 0, 0, 0, bogota)
	if !notBefore.Equal(thursday) {
		t.Errorf("el que sobra debía pasar al jueves a las 8, quedó en %s", notBefore.In(bogota))
	}
}

// MARK: - Pausa

func TestWhilePausedEverythingIsRejected(t *testing.T) {
	o := newTestOutbox(t, wednesdayMorning)
	queued := o.mustEnqueue(t, phone(1), "Antes de la pausa")
	later := o.mustEnqueue(t, phone(2), "También antes")

	o.pause(t)

	// "serve": no entra nada nuevo.
	if result := o.mustEnqueue(t, phone(3), "Durante la pausa"); result.Reason != reasonPaused {
		t.Errorf("serve en pausa: %+v", result)
	}
	if n := o.rows(t); n != 2 {
		t.Errorf("filas = %d, se esperaba 2", n)
	}

	// "sync": lo que estaba en cola se cancela y no sale nada.
	o.sync.dispatchOutbox(context.Background())
	if len(o.whatsapp.delivered) != 0 {
		t.Errorf("en pausa no sale nada: %+v", o.whatsapp.delivered)
	}
	for _, id := range []int64{queued.ID, later.ID} {
		if out := o.status(t, id); out.Status != statusRejected || out.Error != reasonPaused {
			t.Errorf("mensaje %d = %+v", id, out)
		}
	}

	// Al quitar la pausa no sale de golpe lo que se canceló.
	if err := os.Remove(filepath.Join(o.env.stateDir, pauseFilename)); err != nil {
		t.Fatal(err)
	}
	o.advance(10 * time.Minute)
	o.sync.dispatchOutbox(context.Background())
	if len(o.whatsapp.delivered) != 0 {
		t.Errorf("lo cancelado no vuelve: %+v", o.whatsapp.delivered)
	}
}

// MARK: - Despacho

func TestDispatchMarksTheMessageSentAndWritesItToTheHistory(t *testing.T) {
	o := newTestOutbox(t, wednesdayMorning)
	o.env.contacts = fakeContacts{phone(1): {FullName: "Ana Restrepo"}}
	o.sync.env = o.env
	queued := o.mustEnqueue(t, phone(1), "Hola Ana")

	o.sync.dispatchOutbox(context.Background())

	chatJID := phone(1) + "@s.whatsapp.net"
	if len(o.whatsapp.delivered) != 1 || o.whatsapp.delivered[0].to != chatJID || o.whatsapp.delivered[0].body != "Hola Ana" {
		t.Fatalf("entregas = %+v", o.whatsapp.delivered)
	}
	out := o.status(t, queued.ID)
	if out.Status != statusSent || !out.SentAt.Equal(wednesdayMorning) {
		t.Errorf("estado = %+v", out)
	}

	var content, sender, messageID string
	var isFromMe bool
	err := o.env.store.db.QueryRow(
		`SELECT id, content, sender, is_from_me FROM messages WHERE chat_jid = ?`, chatJID,
	).Scan(&messageID, &content, &sender, &isFromMe)
	if err != nil {
		t.Fatalf("el mensaje enviado no quedó en el historial: %v", err)
	}
	if content != "Hola Ana" || !isFromMe || sender != "573009998877" || messageID != o.whatsapp.delivered[0].id {
		t.Errorf("historial = id %q, %q, de %q, mío %v", messageID, content, sender, isFromMe)
	}
	var name string
	if err := o.env.store.db.QueryRow(`SELECT name FROM chats WHERE jid = ?`, chatJID).Scan(&name); err != nil || name != "Ana Restrepo" {
		t.Errorf("chat = %q, %v", name, err)
	}

	// El agente lo ve con las lecturas de siempre.
	text, err := o.env.store.GetLastInteraction(chatJID)
	if err != nil || !strings.Contains(text, "Hola Ana") {
		t.Errorf("get_last_interaction = %q, %v", text, err)
	}

	// Una segunda vuelta no lo manda otra vez.
	o.advance(10 * time.Minute)
	o.sync.dispatchOutbox(context.Background())
	if len(o.whatsapp.delivered) != 1 {
		t.Errorf("se envió dos veces: %+v", o.whatsapp.delivered)
	}
}

// Si la conversación ya está guardada bajo el @lid de la persona, el mensaje
// enviado va ahí: el historial no se parte en dos chats.
func TestASentMessageJoinsTheExistingChatOfThatPerson(t *testing.T) {
	o := newTestOutbox(t, wednesdayMorning)
	o.env.lookup = newFakeAliases(map[string]string{"98765432101234": phone(1)})
	o.sync.env = o.env
	o.knownChat(t, "98765432101234@lid")

	result := o.mustEnqueue(t, "98765432101234@lid", "Seguimiento")
	if result.Rejected || result.ChatJID != phone(1)+"@s.whatsapp.net" {
		t.Fatalf("enqueue = %+v", result)
	}
	var isNewChat bool
	if err := o.env.store.db.QueryRow(`SELECT is_new_chat FROM outbox WHERE id = ?`, result.ID).Scan(&isNewChat); err != nil || isNewChat {
		t.Errorf("no es un chat nuevo: %v, %v", isNewChat, err)
	}

	o.sync.dispatchOutbox(context.Background())

	var chats, underLID int
	o.env.store.db.QueryRow(`SELECT COUNT(*) FROM chats`).Scan(&chats)
	o.env.store.db.QueryRow(`SELECT COUNT(*) FROM messages WHERE chat_jid = ? AND is_from_me = 1`, "98765432101234@lid").Scan(&underLID)
	if chats != 1 || underLID != 1 {
		t.Errorf("chats = %d, mensajes míos bajo el @lid = %d", chats, underLID)
	}
	var name string
	o.env.store.db.QueryRow(`SELECT name FROM chats WHERE jid = ?`, "98765432101234@lid").Scan(&name)
	if name != "Conocido" {
		t.Errorf("el chat que ya existía conserva su nombre; quedó %q", name)
	}
}

func TestAFailedDeliveryIsMarkedFailedAndNotRetried(t *testing.T) {
	o := newTestOutbox(t, wednesdayMorning)
	o.whatsapp.deliveryErr = errors.New("server returned error 463")
	queued := o.mustEnqueue(t, phone(1), "Hola")

	ctx := context.Background()
	o.sync.dispatchOutbox(ctx)

	out := o.status(t, queued.ID)
	if out.Status != statusFailed || out.Error != "server returned error 463" {
		t.Fatalf("estado = %+v", out)
	}

	// Aunque WhatsApp vuelva a funcionar, no se reintenta solo.
	o.whatsapp.deliveryErr = nil
	o.advance(10 * time.Minute)
	o.sync.dispatchOutbox(ctx)
	if len(o.whatsapp.delivered) != 0 || o.whatsapp.lookups != 1 {
		t.Errorf("se reintentó: entregas %+v, consultas %d", o.whatsapp.delivered, o.whatsapp.lookups)
	}
	var inHistory int
	o.env.store.db.QueryRow(`SELECT COUNT(*) FROM messages`).Scan(&inHistory)
	if inHistory != 0 {
		t.Errorf("un fallido no va al historial")
	}
}

func TestANumberThatIsNotOnWhatsAppFails(t *testing.T) {
	o := newTestOutbox(t, wednesdayMorning)
	o.whatsapp.notOnWhatsApp = map[string]bool{phone(1): true}
	queued := o.mustEnqueue(t, phone(1), "Hola")

	o.sync.dispatchOutbox(context.Background())

	if out := o.status(t, queued.ID); out.Status != statusFailed || out.Error != failureNotOnWA {
		t.Errorf("estado = %+v", out)
	}
	if len(o.whatsapp.delivered) != 0 {
		t.Errorf("no debía enviarse: %+v", o.whatsapp.delivered)
	}
}

func TestWithoutAConnectionTheMessageWaits(t *testing.T) {
	o := newTestOutbox(t, wednesdayMorning)
	o.whatsapp.offline = true
	queued := o.mustEnqueue(t, phone(1), "Hola")

	ctx := context.Background()
	o.sync.dispatchOutbox(ctx)
	if out := o.status(t, queued.ID); out.Status != statusPending || o.whatsapp.lookups != 0 {
		t.Fatalf("sin conexión no se toca: %+v", out)
	}

	o.whatsapp.offline = false
	o.advance(time.Hour)
	o.sync.dispatchOutbox(ctx)
	if out := o.status(t, queued.ID); out.Status != statusSent {
		t.Errorf("al volver la conexión debía salir: %+v", out)
	}
}

// Si "sync" se detuvo a mitad de un envío no se sabe si llegó: no se repite.
func TestAMessageInterruptedMidDeliveryIsNotRepeated(t *testing.T) {
	o := newTestOutbox(t, wednesdayMorning)
	queued := o.mustEnqueue(t, phone(1), "Hola")
	if _, err := o.env.store.db.Exec(`UPDATE outbox SET wa_message_id = 'WAIDX' WHERE id = ?`, queued.ID); err != nil {
		t.Fatal(err)
	}

	// Ni siquiera sin haber pasado por el arranque se vuelve a tomar.
	o.sync.dispatchOutbox(context.Background())
	if len(o.whatsapp.delivered) != 0 {
		t.Fatalf("un mensaje ya reservado no se envía otra vez: %+v", o.whatsapp.delivered)
	}

	o.sync.recoverInterrupted()
	if out := o.status(t, queued.ID); out.Status != statusFailed || out.Error != failureInterrupt {
		t.Errorf("estado = %+v", out)
	}
}

// MARK: - La herramienta MCP

func callSendMessage(t *testing.T, o *testOutbox, recipient, message string) SendMessageOutput {
	t.Helper()
	_, out, err := handleSendMessage(o.env)(context.Background(), nil, SendMessageInput{Recipient: recipient, Message: message})
	if err != nil {
		t.Fatal(err)
	}
	return out
}

func TestSendMessageReportsWhatHappened(t *testing.T) {
	t.Run("rechazado: con razón y sin escribir nada", func(t *testing.T) {
		o := newTestOutbox(t, wednesdayMorning)
		out := callSendMessage(t, o, "120363021234567890@g.us", "Hola")
		if out.Status != statusRejected || out.Reason != reasonGroup || out.OutboxID != 0 || o.rows(t) != 0 {
			t.Errorf("salida = %+v", out)
		}
	})

	t.Run("enviado: espera a que sync lo saque", func(t *testing.T) {
		o := newTestOutbox(t, wednesdayMorning)
		o.env.wait = 5 * time.Second
		done := make(chan struct{})
		go func() {
			defer close(done)
			for i := 0; i < 400 && len(o.whatsapp.delivered) == 0; i++ {
				o.sync.dispatchOutbox(context.Background())
				time.Sleep(5 * time.Millisecond)
			}
		}()
		out := callSendMessage(t, o, phone(1), "Hola")
		<-done
		if out.Status != statusSent || out.ChatJID != phone(1)+"@s.whatsapp.net" || out.SentAt != "2026-10-07T10:00:00-05:00" {
			t.Errorf("salida = %+v", out)
		}
	})

	t.Run("pendiente: sync no está corriendo", func(t *testing.T) {
		o := newTestOutbox(t, wednesdayMorning)
		out := callSendMessage(t, o, phone(1), "Hola")
		if out.Status != statusPending || out.Reason != reasonNotPickedUp || out.OutboxID == 0 {
			t.Errorf("salida = %+v", out)
		}
	})

	t.Run("en cola: fuera de horario, con la hora estimada y sin esperar", func(t *testing.T) {
		o := newTestOutbox(t, time.Date(2026, 10, 11, 11, 0, 0, 0, bogota))
		o.env.wait = time.Hour
		out := callSendMessage(t, o, phone(1), "Hola")
		if out.Status != statusQueued || out.ScheduledFor != "2026-10-12T08:00:00-05:00" || out.Reason != reasonQueued {
			t.Errorf("salida = %+v", out)
		}
	})

	t.Run("fallido: con el error", func(t *testing.T) {
		o := newTestOutbox(t, wednesdayMorning)
		o.env.wait = 5 * time.Second
		o.whatsapp.notOnWhatsApp = map[string]bool{phone(1): true}
		done := make(chan struct{})
		go func() {
			defer close(done)
			for i := 0; i < 400 && o.whatsapp.lookups == 0; i++ {
				o.sync.dispatchOutbox(context.Background())
				time.Sleep(5 * time.Millisecond)
			}
		}()
		out := callSendMessage(t, o, phone(1), "Hola")
		<-done
		if out.Status != statusFailed || out.Error != failureNotOnWA {
			t.Errorf("salida = %+v", out)
		}
	})
}

// toolNames lista las herramientas que ve un cliente MCP de verdad.
func toolNames(t *testing.T, server *mcp.Server) []string {
	t.Helper()
	ctx := context.Background()
	serverSide, clientSide := mcp.NewInMemoryTransports()
	if _, err := server.Connect(ctx, serverSide, nil); err != nil {
		t.Fatal(err)
	}
	session, err := mcp.NewClient(&mcp.Implementation{Name: "prueba", Version: "0"}, nil).Connect(ctx, clientSide, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer session.Close()
	listed, err := session.ListTools(ctx, nil)
	if err != nil {
		t.Fatal(err)
	}
	var names []string
	for _, tool := range listed.Tools {
		names = append(names, tool.Name)
	}
	sort.Strings(names)
	return names
}

// La config que Galeno generaba antes del envío permite el servidor entero.
// Por eso "serve" a secas sigue ofreciendo solo las 9 lecturas: una carpeta
// de agente vieja con un bridge nuevo no puede enviar.
func TestSendMessageOnlyExistsWhenServeIsAskedForIt(t *testing.T) {
	o := newTestOutbox(t, wednesdayMorning)
	reads := []string{
		"download_media", "get_chat", "get_contact_chats", "get_direct_chat_by_contact", "get_last_interaction",
		"get_message_context", "list_chats", "list_messages", "search_contacts",
	}

	without := toolNames(t, newMCPServer(o.env.store, nil))
	if strings.Join(without, ",") != strings.Join(reads, ",") {
		t.Errorf("serve a secas = %v", without)
	}

	// Con --with-send hay exactamente una más, y es la única que envía.
	with := toolNames(t, newMCPServer(o.env.store, &o.env))
	want := append(append([]string{}, reads...), "send_message")
	sort.Strings(want)
	if strings.Join(with, ",") != strings.Join(want, ",") {
		t.Errorf("serve --with-send = %v", with)
	}
}

// MARK: - Esquema e informe

func TestTheOutboxIsAddedToAnExistingDatabase(t *testing.T) {
	path := filepath.Join(t.TempDir(), "messages.db")
	old, err := sql.Open("sqlite3", "file:"+path)
	if err != nil {
		t.Fatal(err)
	}
	// La base como la dejaba la 0.3.0: sin bandeja.
	if _, err := old.Exec(`
		CREATE TABLE chats (jid TEXT PRIMARY KEY, name TEXT, last_message_time TIMESTAMP);
		CREATE TABLE messages (id TEXT, chat_jid TEXT, sender TEXT, content TEXT, timestamp TIMESTAMP,
			is_from_me BOOLEAN, media_type TEXT, filename TEXT, url TEXT, media_key BLOB, file_sha256 BLOB,
			file_enc_sha256 BLOB, file_length INTEGER, PRIMARY KEY (id, chat_jid));
		INSERT INTO chats VALUES ('573001112233@s.whatsapp.net', 'Ana', '2026-10-01 12:00:00+00:00');
		INSERT INTO messages (id, chat_jid, sender, content, timestamp, is_from_me)
			VALUES ('m1', '573001112233@s.whatsapp.net', 'ana', 'hola', '2026-10-01 12:00:00+00:00', 0);
	`); err != nil {
		t.Fatal(err)
	}
	old.Close()

	for round := 1; round <= 2; round++ {
		store, err := NewMessageStore(path)
		if err != nil {
			t.Fatalf("vuelta %d: %v", round, err)
		}
		var messages int
		if err := store.db.QueryRow(`SELECT COUNT(*) FROM messages`).Scan(&messages); err != nil || messages != 1 {
			t.Errorf("vuelta %d: mensajes = %d, %v", round, messages, err)
		}
		if _, err := store.db.Exec(
			`INSERT INTO outbox (chat_jid, body, created_at, not_before, is_new_chat) VALUES ('x', 'y', ?, ?, 0)`,
			stamp(wednesdayMorning), stamp(wednesdayMorning)); err != nil {
			t.Errorf("vuelta %d: la bandeja no existe: %v", round, err)
		}
		var rows int
		store.db.QueryRow(`SELECT COUNT(*) FROM outbox`).Scan(&rows)
		if rows != round {
			t.Errorf("vuelta %d: la bandeja tiene %d filas; abrir otra vez no debe vaciarla", round, rows)
		}
		store.Close()
	}
}

func TestOutboxReportCountsTodayAndLeavesTheTextOut(t *testing.T) {
	o := newTestOutbox(t, wednesdayMorning)
	o.writeLimits(t, `{"daily_total": 30, "daily_new_chats": 500}`)
	known := phone(50) + "@s.whatsapp.net"
	o.knownChat(t, known)

	o.mustEnqueue(t, phone(1), "Texto que no debe salir en el informe")
	o.mustEnqueue(t, known, "Seguimiento")
	o.sync.dispatchOutbox(context.Background())
	o.pause(t)

	report, err := buildOutboxReport(o.env.store, o.env.stateDir, *o.clock)
	if err != nil {
		t.Fatal(err)
	}
	if !report.Paused || report.Limits != (outboxReportLimits{30, maxDailyNewChats, maxDailyTotal, maxDailyNewChats}) {
		t.Errorf("pausa y topes = %v, %+v", report.Paused, report.Limits)
	}
	if report.Today != (outboxReportToday{Sent: 1, Pending: 1, NewChats: 1}) || report.PendingTotal != 1 {
		t.Errorf("hoy = %+v, pendientes %d", report.Today, report.PendingTotal)
	}
	if len(report.Recent) != 2 || report.Recent[0].Status != statusPending || report.Recent[1].Status != statusSent ||
		report.Recent[1].SentAt == nil || *report.Recent[1].SentAt != "2026-10-07T10:00:00-05:00" {
		t.Errorf("recientes = %+v", report.Recent)
	}
	data, _ := json.Marshal(report)
	if strings.Contains(string(data), "no debe salir") {
		t.Errorf("el informe lleva el texto de un mensaje: %s", data)
	}
}

// MARK: - Guardia de texto

// Lo mismo que el guardia de CI (.github/workflows/ci.yml), para que también
// salte al correr las pruebas en local: la llamada que envía solo puede estar
// en outbox.go, y lo que nunca se hace (subir archivos, marcar leído, avisar
// «escribiendo…») no puede estar en ningún archivo. Los patrones se arman por
// partes para que este mismo archivo no los contenga.
func TestSendCallOnlyInOutbox(t *testing.T) {
	sendCall := regexp.MustCompile(`client\.` + `SendMessage\(`)
	never := regexp.MustCompile(strings.Join([]string{
		`client\.` + `Upload\(`, `/api/` + `send`, `Mark` + `Read`, `Send` + `Presence`, `SendChat` + `Presence`,
	}, "|"))

	files, err := filepath.Glob("*.go")
	if err != nil || len(files) == 0 {
		t.Fatalf("no se encontraron los .go: %v", err)
	}
	sawOutbox := false
	for _, file := range files {
		data, err := os.ReadFile(file)
		if err != nil {
			t.Fatal(err)
		}
		if found := never.Find(data); found != nil {
			t.Errorf("%s contiene %q: eso no existe en el bridge", file, found)
		}
		if file == "outbox.go" {
			sawOutbox = sendCall.Match(data)
			continue
		}
		if sendCall.Match(data) {
			t.Errorf("%s llama al envío: solo puede hacerlo outbox.go", file)
		}
	}
	if !sawOutbox {
		t.Error("outbox.go ya no tiene la llamada que envía; el guardia no está mirando nada")
	}
}
