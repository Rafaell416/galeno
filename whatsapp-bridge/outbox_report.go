package main

import (
	"database/sql"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"time"
)

// Subcomando "outbox --json": lo que la app enseña en su vista de salud
// («Enviados hoy: N de 40»). Lo corre la app, no el agente. Solo lee, y no
// abre ninguna conexión a WhatsApp. No incluye el texto de los mensajes: la
// app no lo necesita.

type outboxReport struct {
	Paused bool               `json:"paused"`
	Limits outboxReportLimits `json:"limits"`
	Today  outboxReportToday  `json:"today"`
	// PendingTotal cuenta todo lo que espera en la bandeja, sea para hoy o
	// para otro día.
	PendingTotal int                `json:"pending_total"`
	Recent       []outboxReportItem `json:"recent"`
}

type outboxReportLimits struct {
	DailyTotal       int `json:"daily_total"`
	DailyNewChats    int `json:"daily_new_chats"`
	MaxDailyTotal    int `json:"max_daily_total"`
	MaxDailyNewChats int `json:"max_daily_new_chats"`
}

// outboxReportToday es lo que cuenta para los topes de hoy: lo que ya salió
// y lo que está en cola para hoy.
type outboxReportToday struct {
	Sent     int `json:"sent"`
	Pending  int `json:"pending"`
	NewChats int `json:"new_chats"`
}

type outboxReportItem struct {
	ID        int64   `json:"id"`
	ChatJID   string  `json:"chat_jid"`
	Status    string  `json:"status"`
	IsNewChat bool    `json:"is_new_chat"`
	CreatedAt string  `json:"created_at"`
	NotBefore string  `json:"not_before"`
	SentAt    *string `json:"sent_at,omitempty"`
	Error     string  `json:"error,omitempty"`
}

// recentOutboxItems es cuántos mensajes recientes lista el informe.
const recentOutboxItems = 50

func buildOutboxReport(store *MessageStore, stateDir string, now time.Time) (outboxReport, error) {
	limits := loadOutboxLimits(stateDir)
	report := outboxReport{
		Paused: outboxPaused(stateDir),
		Limits: outboxReportLimits{
			DailyTotal:       limits.DailyTotal,
			DailyNewChats:    limits.DailyNewChats,
			MaxDailyTotal:    maxDailyTotal,
			MaxDailyNewChats: maxDailyNewChats,
		},
		Recent: []outboxReportItem{},
	}

	dayStart, dayEnd := dayBounds(now)
	rows, err := store.db.Query(
		`SELECT status, is_new_chat FROM outbox
		 WHERE status IN (?, ?) AND COALESCE(sent_at, not_before) >= ? AND COALESCE(sent_at, not_before) < ?`,
		statusPending, statusSent, stamp(dayStart), stamp(dayEnd))
	if err != nil {
		return outboxReport{}, err
	}
	for rows.Next() {
		var status string
		var isNewChat bool
		if err := rows.Scan(&status, &isNewChat); err != nil {
			rows.Close()
			return outboxReport{}, err
		}
		if status == statusSent {
			report.Today.Sent++
		} else {
			report.Today.Pending++
		}
		if isNewChat {
			report.Today.NewChats++
		}
	}
	if err := rows.Close(); err != nil {
		return outboxReport{}, err
	}

	if err := store.db.QueryRow(`SELECT COUNT(*) FROM outbox WHERE status = ?`, statusPending).
		Scan(&report.PendingTotal); err != nil {
		return outboxReport{}, err
	}

	recent, err := store.db.Query(
		`SELECT id, chat_jid, status, is_new_chat, created_at, not_before, sent_at, error
		 FROM outbox ORDER BY id DESC LIMIT ?`, recentOutboxItems)
	if err != nil {
		return outboxReport{}, err
	}
	defer recent.Close()

	local := func(t time.Time) string { return t.In(now.Location()).Format(time.RFC3339) }
	for recent.Next() {
		var item outboxReportItem
		var createdAt, notBefore time.Time
		var sentAt sql.NullTime
		var failure sql.NullString
		if err := recent.Scan(&item.ID, &item.ChatJID, &item.Status, &item.IsNewChat,
			&createdAt, &notBefore, &sentAt, &failure); err != nil {
			return outboxReport{}, err
		}
		item.CreatedAt, item.NotBefore, item.Error = local(createdAt), local(notBefore), failure.String
		if sentAt.Valid {
			when := local(sentAt.Time)
			item.SentAt = &when
		}
		report.Recent = append(report.Recent, item)
	}
	return report, recent.Err()
}

// runOutbox — subcomando "outbox". Solo imprime JSON en stdout.
func runOutbox() {
	flags := flag.NewFlagSet("outbox", flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	asJSON := flags.Bool("json", false, "imprime el estado de la bandeja de salida como JSON")
	if err := flags.Parse(os.Args[2:]); err != nil {
		os.Exit(2)
	}
	if !*asJSON {
		fmt.Fprintln(os.Stderr, "Uso: galeno-whatsapp outbox --json")
		os.Exit(2)
	}

	// No hace falta el cliente de whatsmeow: basta con el historial.
	dir, err := stateDirectory()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	store, err := NewMessageStore(filepath.Join(dir, "messages.db"))
	if err != nil {
		fmt.Fprintf(os.Stderr, "No se pudo abrir el historial de mensajes: %v\n", err)
		os.Exit(1)
	}
	defer store.Close()

	report, err := buildOutboxReport(store, dir, time.Now())
	if err != nil {
		fmt.Fprintf(os.Stderr, "No se pudo leer la bandeja de salida: %v\n", err)
		os.Exit(1)
	}
	data, err := json.MarshalIndent(report, "", "  ")
	if err != nil {
		fmt.Fprintf(os.Stderr, "No se pudo armar el JSON: %v\n", err)
		os.Exit(1)
	}
	os.Stdout.Write(append(data, '\n'))
}
