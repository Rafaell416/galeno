package main

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	"go.mau.fi/whatsmeow"
	"go.mau.fi/whatsmeow/proto/waE2E"
	"go.mau.fi/whatsmeow/types"
	waLog "go.mau.fi/whatsmeow/util/log"
	"google.golang.org/protobuf/proto"
)

// La bandeja de salida, del lado de "sync": la única pieza con una conexión
// viva a WhatsApp, y por eso la única que puede sacar un mensaje.
//
// Este es el ÚNICO archivo del bridge donde puede aparecer client.SendMessage(
// (lo comprueban el guardia de CI y TestSendCallOnlyInOutbox). Solo sale texto,
// a una persona o a un grupo del usuario: no hay adjuntos, ni audios, ni listas
// de difusión, ni estados, ni canales, ni «leído», ni «escribiendo…». Añadir
// cualquiera de esos es una línea roja (AGENTS.md).

// messageSender es lo que el despacho necesita de WhatsApp. En producción lo
// cumple liveClient; las pruebas usan uno simulado, sin red.
type messageSender interface {
	// Ready dice si hay conexión. Sin ella no se intenta nada: el mensaje
	// espera en la bandeja.
	Ready() bool
	// OwnUser es el número de la cuenta vinculada.
	OwnUser() string
	NewMessageID() string
	// IsOnWhatsApp pregunta si un número tiene WhatsApp y devuelve su JID.
	IsOnWhatsApp(ctx context.Context, phone string) (types.JID, bool, error)
	// CheckGroup falla si el grupo ya no existe o el usuario ya no está en él.
	CheckGroup(ctx context.Context, group types.JID) error
	SendText(ctx context.Context, to types.JID, id, body string) (time.Time, error)
}

// liveClient es el messageSender de verdad, sobre la conexión de "sync".
type liveClient struct {
	client *whatsmeow.Client
}

func (c *liveClient) Ready() bool {
	return c.client.IsConnected() && c.client.IsLoggedIn()
}

func (c *liveClient) OwnUser() string {
	if c.client.Store.ID == nil {
		return ""
	}
	return c.client.Store.ID.User
}

func (c *liveClient) NewMessageID() string {
	return string(c.client.GenerateMessageID())
}

func (c *liveClient) IsOnWhatsApp(ctx context.Context, phone string) (types.JID, bool, error) {
	answers, err := c.client.IsOnWhatsApp(ctx, []string{"+" + phone})
	if err != nil {
		return types.JID{}, false, err
	}
	for _, answer := range answers {
		if !answer.IsIn {
			continue
		}
		// WhatsApp puede responder con el identificador oculto (@lid) y dar
		// el número aparte. Se envía siempre al número.
		for _, jid := range []types.JID{answer.PhoneNumber, answer.JID} {
			if jid.Server == types.DefaultUserServer && jid.User != "" {
				return jid.ToNonAD(), true, nil
			}
		}
	}
	return types.JID{}, false, nil
}

func (c *liveClient) CheckGroup(ctx context.Context, group types.JID) error {
	_, err := c.client.GetGroupInfo(ctx, group)
	return err
}

func (c *liveClient) SendText(ctx context.Context, to types.JID, id, body string) (time.Time, error) {
	response, err := c.client.SendMessage(ctx, to,
		&waE2E.Message{Conversation: proto.String(body)},
		whatsmeow.SendRequestExtra{ID: types.MessageID(id)})
	if err != nil {
		return time.Time{}, err
	}
	return response.Timestamp, nil
}

// outboxDispatcher saca los mensajes de la bandeja, de uno en uno.
type outboxDispatcher struct {
	env    outboxEnv
	sender messageSender
	logger waLog.Logger
	// nextAllowed es cuándo puede salir el siguiente: tras cada envío se
	// espera un rato al azar, también cuando hay varios atrasados.
	nextAllowed time.Time
}

// outboxTick es cada cuánto mira "sync" la bandeja.
const outboxTick = 2 * time.Second

// run mira la bandeja hasta que se cancela el contexto.
func (d *outboxDispatcher) run(ctx context.Context) {
	d.recoverInterrupted()

	ticker := time.NewTicker(outboxTick)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			d.dispatchOutbox(ctx)
		}
	}
}

// recoverInterrupted cierra lo que quedó a medias si "sync" se detuvo durante
// un envío: no se sabe si llegó, así que no se repite. Queda como fallido,
// diciendo eso.
func (d *outboxDispatcher) recoverInterrupted() {
	_, err := d.env.store.db.Exec(
		`UPDATE outbox SET status = ?, error = ? WHERE status = ? AND wa_message_id IS NOT NULL`,
		statusFailed, failureInterrupt, statusPending)
	if err != nil {
		d.logger.Warnf("No se pudo revisar la bandeja de salida: %v", err)
	}
}

// dispatchOutbox es una vuelta: saca como mucho un mensaje. Las guardas que
// dependen del momento se vuelven a mirar aquí, porque entre que "serve"
// aceptó el mensaje y ahora pudo pasar cualquier cosa (el Mac dormido, el
// usuario que pausó, varios mensajes atrasados a la vez).
func (d *outboxDispatcher) dispatchOutbox(ctx context.Context) {
	db := d.env.store.db
	now := d.env.now()

	// En pausa no sale nada, y lo que estaba en cola se cancela: al quitar la
	// pausa no sale de golpe lo acumulado.
	if outboxPaused(d.env.stateDir) {
		if _, err := db.Exec(`UPDATE outbox SET status = ?, error = ? WHERE status = ?`,
			statusRejected, reasonPaused, statusPending); err != nil {
			d.logger.Warnf("No se pudo cancelar la bandeja en pausa: %v", err)
		}
		return
	}
	// Lo que lleva más de un día esperando caduca, haya conexión o no: así un
	// mensaje viejo nunca sale en cuanto vuelve "sync".
	if _, err := db.Exec(
		`UPDATE outbox SET status = ?, error = ? WHERE status = ? AND not_before <= ? AND wa_message_id IS NULL`,
		statusFailed, failureExpired, statusPending, stamp(now.Add(-pendingExpiry))); err != nil {
		d.logger.Warnf("No se pudo caducar lo que llevaba esperando: %v", err)
	}
	if !d.sender.Ready() || now.Before(d.nextAllowed) {
		return
	}

	item, found, err := d.nextDue(now)
	if err != nil {
		d.logger.Warnf("No se pudo leer la bandeja de salida: %v", err)
		return
	}
	if !found {
		return
	}

	// El mínimo entre dos mensajes vale también contra lo que diga la base.
	var lastSent sql.NullTime
	err = db.QueryRow(`SELECT sent_at FROM outbox WHERE status = ? ORDER BY sent_at DESC LIMIT 1`, statusSent).
		Scan(&lastSent)
	if err != nil && err != sql.ErrNoRows {
		d.logger.Warnf("No se pudo leer el último envío: %v", err)
		return
	}
	if lastSent.Valid && now.Sub(lastSent.Time) < minSpacing {
		return
	}

	// El tope del día cuenta lo que ya salió hoy. Si se llenó (mensajes
	// atrasados de otro día que se suman a los de hoy), el que sobra no sale:
	// queda como fallido, diciendo por qué, y decide el usuario.
	dayStart, dayEnd := dayBounds(now)
	var sentToday int
	err = db.QueryRow(`SELECT COUNT(*) FROM outbox WHERE status = ? AND sent_at >= ? AND sent_at < ?`,
		statusSent, stamp(dayStart), stamp(dayEnd)).Scan(&sentToday)
	if err != nil {
		d.logger.Warnf("No se pudo contar los envíos de hoy: %v", err)
		return
	}
	if limit := loadOutboxLimits(d.env.stateDir).DailyTotal; sentToday >= limit {
		if _, err := db.Exec(`UPDATE outbox SET status = ?, error = ? WHERE id = ? AND status = ?`,
			statusFailed, fmt.Sprintf(failureDailyLimit, limit), item.id, statusPending); err != nil {
			d.logger.Warnf("No se pudo anotar el mensaje %d que pasó del tope: %v", item.id, err)
		}
		return
	}

	d.sendOutboxItem(ctx, item)
	d.nextAllowed = d.env.now().Add(clampSpacing(d.env.spacing()))
}

type outboxItem struct {
	id      int64
	chatJID string
	body    string
}

// nextDue es el mensaje pendiente más antiguo que ya puede salir. Uno que ya
// tiene id de WhatsApp está saliendo o quedó en el aire: no se vuelve a tomar.
func (d *outboxDispatcher) nextDue(now time.Time) (outboxItem, bool, error) {
	var item outboxItem
	err := d.env.store.db.QueryRow(
		`SELECT id, chat_jid, body FROM outbox
		 WHERE status = ? AND not_before <= ? AND wa_message_id IS NULL ORDER BY not_before, id LIMIT 1`,
		statusPending, stamp(now),
	).Scan(&item.id, &item.chatJID, &item.body)
	if err == sql.ErrNoRows {
		return outboxItem{}, false, nil
	}
	if err != nil {
		return outboxItem{}, false, err
	}
	return item, true, nil
}

// sendOutboxItem saca un mensaje y anota qué pasó. No reintenta: si falla,
// queda como fallido con su error y decide el usuario.
func (d *outboxDispatcher) sendOutboxItem(ctx context.Context, item outboxItem) {
	db := d.env.store.db

	// Antes de tocar la red, el mensaje queda marcado con el id con el que va
	// a salir. Si otro proceso ya lo marcó, no es nuestro; y si "sync" muere
	// a mitad, al volver se sabe que este quedó en el aire (recoverInterrupted).
	messageID := d.sender.NewMessageID()
	claimed, err := db.Exec(`UPDATE outbox SET wa_message_id = ? WHERE id = ? AND status = ? AND wa_message_id IS NULL`,
		messageID, item.id, statusPending)
	if err != nil {
		d.logger.Warnf("No se pudo reservar el mensaje %d: %v", item.id, err)
		return
	}
	if rows, _ := claimed.RowsAffected(); rows != 1 {
		return
	}

	fail := func(reason string) {
		if _, err := db.Exec(`UPDATE outbox SET status = ?, error = ? WHERE id = ?`, statusFailed, reason, item.id); err != nil {
			d.logger.Warnf("No se pudo anotar el fallo del mensaje %d: %v", item.id, err)
		}
		d.logger.Warnf("El mensaje %d de la bandeja no salió: %s", item.id, reason)
	}

	requested, err := types.ParseJID(item.chatJID)
	if err != nil {
		fail(failureNotAPerson)
		return
	}

	// Otra vez, justo antes de salir: solo a una persona o a un grupo.
	var target types.JID
	lookupCtx, cancelLookup := context.WithTimeout(ctx, 20*time.Second)
	defer cancelLookup()
	switch requested.Server {
	case types.GroupServer:
		// Que el grupo siga existiendo y el usuario siga dentro.
		if err := d.sender.CheckGroup(lookupCtx, requested); err != nil {
			fail(failureGroup + err.Error())
			return
		}
		target = requested
	case types.DefaultUserServer:
		found, onWhatsApp, err := d.sender.IsOnWhatsApp(lookupCtx, requested.User)
		if err != nil {
			fail("Could not check the number on WhatsApp: " + err.Error())
			return
		}
		if !onWhatsApp {
			fail(failureNotOnWA)
			return
		}
		if found.Server != types.DefaultUserServer {
			fail(failureNotAPerson)
			return
		}
		target = found
	default:
		fail(failureNotAPerson)
		return
	}

	deliveryCtx, cancelDelivery := context.WithTimeout(ctx, 30*time.Second)
	serverTime, err := d.sender.SendText(deliveryCtx, target, messageID, item.body)
	cancelDelivery()
	if err != nil {
		fail(err.Error())
		return
	}

	sentAt := d.env.now()
	if _, err := db.Exec(`UPDATE outbox SET status = ?, sent_at = ?, error = NULL WHERE id = ?`,
		statusSent, stamp(sentAt), item.id); err != nil {
		d.logger.Warnf("El mensaje %d salió pero no se pudo anotar: %v", item.id, err)
	}
	if serverTime.IsZero() {
		serverTime = sentAt
	}
	d.recordInHistory(target, messageID, item.body, serverTime)
	d.logger.Infof("Salió el mensaje %d de la bandeja", item.id)
}

// recordInHistory guarda el mensaje enviado junto a los demás, para que el
// agente lo vea en el historial. Si la conversación con esa persona ya está
// guardada bajo su identificador oculto (@lid), va ahí y no a un chat aparte.
func (d *outboxDispatcher) recordInHistory(target types.JID, messageID, body string, when time.Time) {
	db := d.env.store.db
	chatJID := target.String()

	exists := func(jid string) bool {
		var found int
		return db.QueryRow(`SELECT 1 FROM chats WHERE jid = ?`, jid).Scan(&found) == nil
	}
	if !exists(chatJID) {
		if other, ok := counterpartJID(chatJID, d.env.lookup); ok && exists(other) {
			chatJID = other
		}
	}

	name := resolvedName(chatJID, d.env.lookup, d.env.contacts)
	if name == "" {
		name = target.User
	}
	// Un chat que ya existía conserva su nombre: solo se le mueve la fecha.
	_, err := db.Exec(
		`INSERT INTO chats (jid, name, last_message_time) VALUES (?, ?, ?)
		 ON CONFLICT(jid) DO UPDATE SET last_message_time = excluded.last_message_time`,
		chatJID, name, when)
	if err != nil {
		d.logger.Warnf("No se pudo guardar el chat del mensaje enviado: %v", err)
		return
	}
	if err := d.env.store.StoreMessage(messageID, chatJID, d.sender.OwnUser(), body, when, true,
		"", "", "", nil, nil, nil, 0); err != nil {
		d.logger.Warnf("No se pudo guardar el mensaje enviado en el historial: %v", err)
	}
}
