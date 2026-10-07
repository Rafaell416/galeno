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

	// Entre un mensaje y el siguiente pasa un rato al azar dentro de este rango.
	minSpacing = 45 * time.Second
	maxSpacing = 120 * time.Second

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
}

// loadOutboxLimits lee send-limits.json. Si no existe o no se entiende, valen
// los topes por defecto; un valor por encima del techo se queda en el techo.
func loadOutboxLimits(stateDir string) outboxLimits {
	limits := outboxLimits{DailyTotal: defaultDailyTotal, DailyNewChats: defaultDailyNewChats}

	data, err := os.ReadFile(filepath.Join(stateDir, limitsFilename))
	if err != nil {
		return limits
	}
	var file struct {
		DailyTotal    *int `json:"daily_total"`
		DailyNewChats *int `json:"daily_new_chats"`
	}
	if err := json.Unmarshal(data, &file); err != nil {
		return limits
	}
	limits.DailyTotal = clampLimit(file.DailyTotal, defaultDailyTotal, maxDailyTotal)
	limits.DailyNewChats = clampLimit(file.DailyNewChats, defaultDailyNewChats, maxDailyNewChats)
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

// MARK: - Horario de oficina

// officeWindow devuelve a qué hora abre y cierra un día, en la hora local de
// quien lo pregunta. Lunes a viernes de 8:00 a 19:00, sábado de 8:00 a 13:00,
// domingo cerrado. Son los valores por defecto de docs/09 §4.4 (se apoyan en
// la Ley 2300 de 2023 de Colombia; los festivos no se miran).
func officeWindow(day time.Time) (open, close time.Time, ok bool) {
	at := func(hour int) time.Time {
		return time.Date(day.Year(), day.Month(), day.Day(), hour, 0, 0, 0, day.Location())
	}
	switch day.Weekday() {
	case time.Sunday:
		return time.Time{}, time.Time{}, false
	case time.Saturday:
		return at(8), at(13), true
	default:
		return at(8), at(19), true
	}
}

func inOfficeHours(t time.Time) bool {
	open, close, ok := officeWindow(t)
	return ok && !t.Before(open) && t.Before(close)
}

// nextOpening devuelve t si cae en horario, y si no, la siguiente apertura.
func nextOpening(t time.Time) time.Time {
	for day := t; ; day = startOfDay(day).AddDate(0, 0, 1) {
		open, close, ok := officeWindow(day)
		if !ok {
			continue
		}
		if day.Before(open) {
			return open
		}
		if day.Before(close) {
			return day
		}
	}
}

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
	reasonPaused      = "Sending is paused: the user turned on \"Pausar envíos\" in Galeno. Nothing was sent. Tell the user; do not retry until they turn it off."
	reasonGroup       = "This is a group. Galeno only sends WhatsApp messages to one person at a time, never to groups. Nothing was sent."
	reasonBroadcast   = "This is a broadcast list or a status. Galeno only sends WhatsApp messages to one person at a time. Nothing was sent."
	reasonNewsletter  = "This is a channel. Galeno only sends WhatsApp messages to one person at a time. Nothing was sent."
	reasonNotAPerson  = "This recipient is not a person's WhatsApp number. Nothing was sent."
	reasonBadNumber   = "The recipient must be a phone number in international format, digits only (8 to 15 digits, country code included, no +), or a JID ending in @s.whatsapp.net. Nothing was sent."
	reasonUnknownLID  = "This chat is identified by a hidden id (@lid) and its phone number is not known on this computer. Ask the user for the person's phone number. Nothing was sent."
	reasonEmptyText   = "The message is empty. Nothing was sent."
	reasonTooLong     = "The message is longer than 1000 characters. Shorten it; do not split it into several messages. Nothing was sent."
	reasonRepeated    = "The same text already went to 3 other people today. Galeno does not send one text to many people: write each message for the person who gets it. Nothing was sent."
	reasonDailyTotal  = "Daily limit reached: %d of %d WhatsApp messages for %s. Nothing was sent. The limit protects the user's number from being blocked; do not try to work around it. Tell the user what is left to send."
	reasonDailyNew    = "Daily limit for new contacts reached: %d of %d first messages to people with no previous chat, for %s. Nothing was sent. You can still write to people the user already talks to. The limit protects the user's number from being blocked; do not try to work around it."
	failureInterrupt  = "The bridge stopped while this message was going out, so it is not known whether it arrived. Check the chat before writing again."
	failureNotOnWA    = "This number is not on WhatsApp."
	failureNotAPerson = "WhatsApp did not return a personal number for this recipient."
)

// resolveRecipient convierte lo que pasó el agente (un número o un JID) en el
// JID de una persona. Si no lo es, devuelve por qué. Un chat @lid se pasa a su
// número con lo que whatsmeow ya tiene guardado: consultarlo es local.
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
			return types.JID{}, reasonGroup
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
