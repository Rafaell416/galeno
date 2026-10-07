package main

import (
	"encoding/json"
	"errors"
	"io/fs"
	"math/rand/v2"
	"os"
	"path/filepath"
	"strings"
	"time"
	"unicode/utf8"

	"go.mau.fi/whatsmeow/types"
)

// Las guardas del envío (docs/09 §4.4). Viven aquí, en el código del bridge, y
// no en el prompt del agente: ni una instrucción ni una página que el agente
// lea pueden saltarlas. Todo en este archivo es puro (sin red y sin base de
// datos), para probarlo sin nada delante.

const (
	// Topes por defecto y su techo. La app puede bajarlos con send-limits.json;
	// por encima del techo no los sube nadie: está en el código.
	defaultDailyTotal    = 40
	defaultDailyNewChats = 15
	maxDailyTotal        = 80
	maxDailyNewChats     = 25
	// Un mensaje a un grupo lo lee mucha gente a la vez: tiene su propio tope,
	// además de contar para el total.
	defaultDailyGroups = 10
	maxDailyGroups     = 20

	// Entre un mensaje y el siguiente pasa un rato al azar dentro de este rango.
	minSpacing = 45 * time.Second
	maxSpacing = 120 * time.Second

	// Un mensaje aprobado que no pudo salir (el Mac apagado, sin conexión) espera
	// este tiempo y no más: pasado, caduca en vez de salir días después, cuando el
	// usuario quizá ya escribió a mano (decisión de Rafa, 7 oct 2026).
	pendingExpiry = 24 * time.Hour

	maxBodyChars = 1000
	// El mismo texto puede salir a este número de chats en un día; al siguiente
	// se rechaza. Es lo que distingue un mensaje escrito para alguien de una
	// difusión.
	maxChatsPerText = 3

	// Los dos archivos viven en el directorio de estado, donde el agente no
	// puede escribir (solo escribe en memoria/ de su carpeta). Los pone la app.
	pauseFilename  = "send-paused"
	limitsFilename = "send-limits.json"
)

// outboxLimits son los topes del día.
type outboxLimits struct {
	DailyTotal    int `json:"daily_total"`
	DailyNewChats int `json:"daily_new_chats"`
	DailyGroups   int `json:"daily_groups"`
}

// loadOutboxLimits lee send-limits.json. Si no existe o no se entiende, valen
// los topes por defecto; un valor por encima del techo se queda en el techo.
func loadOutboxLimits(stateDir string) outboxLimits {
	limits := outboxLimits{
		DailyTotal: defaultDailyTotal, DailyNewChats: defaultDailyNewChats, DailyGroups: defaultDailyGroups,
	}

	data, err := os.ReadFile(filepath.Join(stateDir, limitsFilename))
	if err != nil {
		return limits
	}
	var file struct {
		DailyTotal    *int `json:"daily_total"`
		DailyNewChats *int `json:"daily_new_chats"`
		DailyGroups   *int `json:"daily_groups"`
	}
	if err := json.Unmarshal(data, &file); err != nil {
		return limits
	}
	limits.DailyTotal = clampLimit(file.DailyTotal, defaultDailyTotal, maxDailyTotal)
	limits.DailyNewChats = clampLimit(file.DailyNewChats, defaultDailyNewChats, maxDailyNewChats)
	limits.DailyGroups = clampLimit(file.DailyGroups, defaultDailyGroups, maxDailyGroups)
	return limits
}

func clampLimit(value *int, fallback, ceiling int) int {
	switch {
	case value == nil || *value < 0:
		return fallback
	case *value > ceiling:
		return ceiling
	default:
		return *value
	}
}

// outboxPaused dice si el usuario pausó los envíos. Si no se puede saber
// (el archivo existe pero no se deja mirar), se toma como pausado.
func outboxPaused(stateDir string) bool {
	_, err := os.Stat(filepath.Join(stateDir, pauseFilename))
	return !errors.Is(err, fs.ErrNotExist)
}

// randomSpacing es el rato al azar entre dos mensajes.
func randomSpacing() time.Duration {
	return minSpacing + rand.N(maxSpacing-minSpacing+1)
}

// clampSpacing garantiza el mínimo pase lo que pase con quien calcule el rato.
func clampSpacing(spacing time.Duration) time.Duration {
	if spacing < minSpacing {
		return minSpacing
	}
	return spacing
}

// No hay guarda de horario ni de festivos (decisión de Rafa, 7 oct 2026): el
// bridge no decide a qué hora ni qué día se puede escribir. Lo decide el
// usuario, que aprueba cada mensaje; a él se le avisa (la descripción de
// send_message, el AGENTS.md generado y la advertencia de la app).

func startOfDay(t time.Time) time.Time {
	return time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, t.Location())
}

// dayBounds es el día local de t, de medianoche a medianoche.
func dayBounds(t time.Time) (start, end time.Time) {
	start = startOfDay(t)
	return start, start.AddDate(0, 0, 1)
}

// MARK: - A quién y qué

// Razones de rechazo. Las lee el agente, así que le dicen qué pasó y qué
// contarle al usuario; ninguna le sugiere cómo rodear la guarda.
const (
	reasonPaused            = "Sending is paused: the user turned on \"Pausar envíos\" in Galeno. Nothing was sent. Tell the user; do not retry until they turn it off."
	reasonBroadcast         = "This is a broadcast list or a status. Galeno only sends WhatsApp messages to one person or to one group the user is in. Nothing was sent."
	reasonNewsletter        = "This is a channel. Galeno only sends WhatsApp messages to one person or to one group the user is in. Nothing was sent."
	reasonNotAPerson        = "This recipient is not a person's WhatsApp number or a group. Nothing was sent."
	reasonBadNumber         = "The recipient must be a phone number in international format, digits only (8 to 15 digits, country code included, no +), a JID ending in @s.whatsapp.net, or the JID of a group (@g.us) taken from list_chats. Nothing was sent."
	reasonUnknownLID        = "This chat is identified by a hidden id (@lid) and its phone number is not known on this computer. Ask the user for the person's phone number. Nothing was sent."
	reasonUnknownGroup      = "This group is not among the user's WhatsApp chats on this computer. Galeno only writes to groups the user is already in. Nothing was sent."
	reasonUnnamedGroup      = "Galeno does not know this group's name yet, so the user could not see which group they are approving. Nothing was sent."
	reasonGroupNameMissing  = "To write to a group, also pass its name in group_name: the user has to see which group it is before approving. This group is called %q. Nothing was sent."
	reasonGroupNameMismatch = "group_name does not match: the group with this id is called %q. Make sure it is the group the user means. Nothing was sent."
	reasonNameOnPerson      = "group_name is only for groups, and this recipient is a person. Leave it empty. Nothing was sent."
	reasonEmptyText         = "The message is empty. Nothing was sent."
	reasonTooLong           = "The message is longer than 1000 characters. Shorten it; do not split it into several messages. Nothing was sent."
	reasonRepeated          = "The same text already went to 3 other chats today. Galeno does not send one text to many chats: write each message for whoever gets it. Nothing was sent."
	reasonDailyTotal        = "Daily limit reached: %d of %d WhatsApp messages for %s. Nothing was sent. The limit protects the user's number from being blocked; do not try to work around it. Tell the user what is left to send."
	reasonDailyNew          = "Daily limit for new contacts reached: %d of %d first messages to people with no previous chat, for %s. Nothing was sent. You can still write to people the user already talks to. The limit protects the user's number from being blocked; do not try to work around it."
	reasonDailyGroups       = "Daily limit for groups reached: %d of %d messages to groups for %s. Nothing was sent. You can still write to one person at a time. The limit protects the user's number from being blocked; do not try to work around it."
	failureInterrupt        = "The bridge stopped while this message was going out, so it is not known whether it arrived. Check the chat before writing again."
	failureNotOnWA          = "This number is not on WhatsApp."
	failureNotAPerson       = "WhatsApp did not return a personal number for this recipient."
	failureGroup            = "Could not reach this group on WhatsApp (the user may no longer be in it): "
	failureExpired          = "Not sent: this message waited more than 24 hours for Galeno to be connected to WhatsApp, so it expired. Tell the user; do not send it again without asking them."
	failureDailyLimit       = "Not sent: the daily limit of %d WhatsApp messages had already been reached when this message's turn came. Tell the user; do not send it again without asking them."
)

// resolveRecipient convierte lo que pasó el agente (un número o un JID) en el
// JID de una persona o de un grupo (decisión de Rafa, 7 oct 2026). Si no es
// ninguna de las dos cosas (una lista de difusión, los estados, un canal),
// devuelve por qué. Un chat @lid se pasa a su número con lo que whatsmeow ya
// tiene guardado: consultarlo es local. Que el grupo sea uno del usuario y que
// su nombre sea el que el usuario va a ver al aprobar lo comprueba groupGuard
// (outbox_enqueue.go).
func resolveRecipient(raw string, lookup aliasLookup) (types.JID, string) {
	raw = strings.TrimSpace(raw)
	user := raw

	if strings.Contains(raw, "@") {
		jid, err := types.ParseJID(raw)
		if err != nil {
			return types.JID{}, reasonBadNumber
		}
		switch jid.Server {
		case types.DefaultUserServer:
			user = jid.User
		case types.HiddenUserServer:
			other, ok := counterpartJID(jid.ToNonAD().String(), lookup)
			if !ok {
				return types.JID{}, reasonUnknownLID
			}
			parsed, err := types.ParseJID(other)
			if err != nil || parsed.Server != types.DefaultUserServer {
				return types.JID{}, reasonUnknownLID
			}
			user = parsed.User
		case types.GroupServer:
			if jid.User == "" || strings.Trim(jid.User, "0123456789-") != "" {
				return types.JID{}, reasonBadNumber
			}
			return jid.ToNonAD(), ""
		case types.BroadcastServer:
			return types.JID{}, reasonBroadcast
		case types.NewsletterServer:
			return types.JID{}, reasonNewsletter
		default:
			return types.JID{}, reasonNotAPerson
		}
	} else {
		user = strings.NewReplacer("+", "", " ", "", "-", "", "(", "", ")", "", ".", "").Replace(raw)
	}

	if len(user) < 8 || len(user) > 15 || strings.Trim(user, "0123456789") != "" {
		return types.JID{}, reasonBadNumber
	}
	jid := types.NewJID(user, types.DefaultUserServer)
	if jid.IsBot() {
		return types.JID{}, reasonNotAPerson
	}
	return jid, ""
}

// checkBody devuelve el texto listo para salir, o por qué no puede salir.
func checkBody(body string) (string, string) {
	text := strings.TrimSpace(body)
	if text == "" {
		return "", reasonEmptyText
	}
	if utf8.RuneCountInString(text) > maxBodyChars {
		return "", reasonTooLong
	}
	return text, ""
}

// normalizedBody es el texto tal como se compara para saber si es "el mismo":
// sin mayúsculas y con los espacios y saltos de línea reducidos a uno.
func normalizedBody(body string) string {
	return strings.Join(strings.Fields(strings.ToLower(body)), " ")
}
