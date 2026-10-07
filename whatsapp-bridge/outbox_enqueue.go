package main

import (
	"context"
	"database/sql"
	"fmt"
	"time"
)

// Lo que hace "serve" cuando el agente pide un envío: comprobar todas las
// guardas y, solo si pasan, dejar el mensaje en la bandeja de salida. "serve"
// no habla con WhatsApp: quien lo saca es "sync" (outbox.go).

// outboxEnv es lo que la bandeja necesita del mundo. El reloj y el rato al
// azar se pueden cambiar para probarla sin esperar.
type outboxEnv struct {
	store    *MessageStore
	stateDir string
	// lookup y contacts son el almacén local de whatsmeow; consultarlos no
	// toca la red. Pueden ser nil.
	lookup   aliasLookup
	contacts contactNames

	now     func() time.Time
	spacing func() time.Duration
	// Cuánto espera "serve" a que "sync" saque un mensaje que ya puede salir,
	// y cada cuánto mira.
	wait time.Duration
	poll time.Duration
}

func newOutboxEnv(store *MessageStore, stateDir string, lookup aliasLookup, contacts contactNames) outboxEnv {
	return outboxEnv{
		store:    store,
		stateDir: stateDir,
		lookup:   lookup,
		contacts: contacts,
		now:      time.Now,
		spacing:  randomSpacing,
		wait:     30 * time.Second,
		poll:     250 * time.Millisecond,
	}
}

// Estados de un mensaje en la bandeja.
const (
	statusPending  = "pending"
	statusSent     = "sent"
	statusFailed   = "failed"
	statusRejected = "rejected"
	// statusQueued no se guarda: es lo que "serve" responde cuando el mensaje
	// quedó programado para más tarde (por horario o por espaciado).
	statusQueued = "queued"
)

// stamp deja una hora como se guarda en la bandeja: UTC y sin fracción.
func stamp(t time.Time) time.Time {
	return t.UTC().Truncate(time.Second)
}

// enqueueResult es lo que pasó con un pedido de envío.
type enqueueResult struct {
	// Rejected: no entró a la bandeja. Reason dice por qué.
	Rejected bool
	Reason   string

	ID        int64
	ChatJID   string
	NotBefore time.Time
	// DueNow: puede salir ya; si no, quedó programado para NotBefore.
	DueNow bool
}

func rejected(reason string) enqueueResult {
	return enqueueResult{Rejected: true, Reason: reason}
}

// enqueue comprueba las guardas y, si pasan, deja el mensaje en la bandeja.
// Un rechazo no escribe nada.
func (env outboxEnv) enqueue(recipient, body string) (enqueueResult, error) {
	if outboxPaused(env.stateDir) {
		return rejected(reasonPaused), nil
	}
	jid, reason := resolveRecipient(recipient, env.lookup)
	if reason != "" {
		return rejected(reason), nil
	}
	text, reason := checkBody(body)
	if reason != "" {
		return rejected(reason), nil
	}
	chatJID := jid.String()
	limits := loadOutboxLimits(env.stateDir)
	now := env.now()

	// Contar el cupo y escribir van en una sola transacción con el candado
	// de escritura tomado (ver _txlock en store.go).
	tx, err := env.store.db.Begin()
	if err != nil {
		return enqueueResult{}, err
	}
	defer tx.Rollback()

	// Cuándo puede salir: después del último mensaje más un rato al azar, y
	// dentro del horario de oficina.
	notBefore := now
	last, hasLast, err := lastScheduled(tx)
	if err != nil {
		return enqueueResult{}, err
	}
	if hasLast {
		if earliest := last.Add(clampSpacing(env.spacing())); earliest.After(notBefore) {
			notBefore = earliest
		}
	}
	notBefore = nextOpening(notBefore.In(now.Location()))

	// Los topes son del día en que el mensaje sale, no del día en que se pidió:
	// lo que se pide un viernes por la noche cuenta para el lunes.
	dayStart, dayEnd := dayBounds(notBefore)
	scheduled, err := scheduledBetween(tx, dayStart, dayEnd)
	if err != nil {
		return enqueueResult{}, err
	}
	dayLabel := dayStart.Format("2006-01-02")

	if len(scheduled) >= limits.DailyTotal {
		return rejected(fmt.Sprintf(reasonDailyTotal, len(scheduled), limits.DailyTotal, dayLabel)), nil
	}

	isNewChat, err := env.isNewChat(tx, chatJID)
	if err != nil {
		return enqueueResult{}, err
	}
	if isNewChat {
		newChats := 0
		for _, item := range scheduled {
			if item.isNewChat {
				newChats++
			}
		}
		if newChats >= limits.DailyNewChats {
			return rejected(fmt.Sprintf(reasonDailyNew, newChats, limits.DailyNewChats, dayLabel)), nil
		}
	}

	normalized := normalizedBody(text)
	otherChats := map[string]bool{}
	for _, item := range scheduled {
		if item.chatJID != chatJID && normalizedBody(item.body) == normalized {
			otherChats[item.chatJID] = true
		}
	}
	if len(otherChats) >= maxChatsPerText {
		return rejected(reasonRepeated), nil
	}

	inserted, err := tx.Exec(
		`INSERT INTO outbox (chat_jid, body, created_at, not_before, status, is_new_chat) VALUES (?, ?, ?, ?, ?, ?)`,
		chatJID, text, stamp(now), stamp(notBefore), statusPending, isNewChat,
	)
	if err != nil {
		return enqueueResult{}, err
	}
	id, err := inserted.LastInsertId()
	if err != nil {
		return enqueueResult{}, err
	}
	if err := tx.Commit(); err != nil {
		return enqueueResult{}, err
	}

	return enqueueResult{ID: id, ChatJID: chatJID, NotBefore: notBefore, DueNow: !notBefore.After(now)}, nil
}

// lastScheduled es la hora del último mensaje enviado o por enviar.
func lastScheduled(tx *sql.Tx) (time.Time, bool, error) {
	var sentAt sql.NullTime
	var notBefore time.Time
	err := tx.QueryRow(
		`SELECT sent_at, not_before FROM outbox WHERE status IN (?, ?)
		 ORDER BY COALESCE(sent_at, not_before) DESC LIMIT 1`,
		statusPending, statusSent,
	).Scan(&sentAt, &notBefore)
	if err == sql.ErrNoRows {
		return time.Time{}, false, nil
	}
	if err != nil {
		return time.Time{}, false, err
	}
	if sentAt.Valid {
		return sentAt.Time, true, nil
	}
	return notBefore, true, nil
}

type scheduledItem struct {
	chatJID   string
	body      string
	isNewChat bool
}

// scheduledBetween son los mensajes enviados o por enviar dentro de un día:
// lo que cuenta para los topes.
func scheduledBetween(tx *sql.Tx, start, end time.Time) ([]scheduledItem, error) {
	rows, err := tx.Query(
		`SELECT chat_jid, body, is_new_chat FROM outbox
		 WHERE status IN (?, ?) AND COALESCE(sent_at, not_before) >= ? AND COALESCE(sent_at, not_before) < ?`,
		statusPending, statusSent, stamp(start), stamp(end),
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var items []scheduledItem
	for rows.Next() {
		var item scheduledItem
		if err := rows.Scan(&item.chatJID, &item.body, &item.isNewChat); err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

// isNewChat dice si nunca hubo mensajes con esa persona: ni en el historial
// (bajo su número o bajo su @lid) ni en la bandeja.
func (env outboxEnv) isNewChat(tx *sql.Tx, chatJID string) (bool, error) {
	jids := []any{chatJID}
	query := `SELECT 1 FROM messages WHERE chat_jid = ? LIMIT 1`
	if other, ok := counterpartJID(chatJID, env.lookup); ok {
		jids = append(jids, other)
		query = `SELECT 1 FROM messages WHERE chat_jid IN (?, ?) LIMIT 1`
	}
	var found int
	switch err := tx.QueryRow(query, jids...).Scan(&found); err {
	case nil:
		return false, nil
	case sql.ErrNoRows:
	default:
		return false, err
	}

	switch err := tx.QueryRow(
		`SELECT 1 FROM outbox WHERE chat_jid = ? AND status IN (?, ?) LIMIT 1`,
		chatJID, statusPending, statusSent,
	).Scan(&found); err {
	case nil:
		return false, nil
	case sql.ErrNoRows:
		return true, nil
	default:
		return false, err
	}
}

// outboxOutcome es el estado de un mensaje de la bandeja.
type outboxOutcome struct {
	Status string
	SentAt time.Time
	Error  string
}

func (env outboxEnv) outcome(id int64) (outboxOutcome, error) {
	var out outboxOutcome
	var sentAt sql.NullTime
	var failure sql.NullString
	err := env.store.db.QueryRow(`SELECT status, sent_at, error FROM outbox WHERE id = ?`, id).
		Scan(&out.Status, &sentAt, &failure)
	if err != nil {
		return outboxOutcome{}, err
	}
	out.SentAt = sentAt.Time
	out.Error = failure.String
	return out, nil
}

// awaitOutcome espera a que "sync" saque el mensaje. Si se acaba el tiempo,
// devuelve el estado en que quedó: "pending" quiere decir que "sync" no está
// corriendo (o está sin conexión) y que saldrá cuando vuelva.
func (env outboxEnv) awaitOutcome(ctx context.Context, id int64) (outboxOutcome, error) {
	deadline := time.NewTimer(env.wait)
	defer deadline.Stop()
	ticker := time.NewTicker(env.poll)
	defer ticker.Stop()

	for {
		out, err := env.outcome(id)
		if err != nil || out.Status != statusPending {
			return out, err
		}
		select {
		case <-ctx.Done():
			return out, nil
		case <-deadline.C:
			return out, nil
		case <-ticker.C:
		}
	}
}
