package main

import (
	"context"
	"errors"
	"time"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

// Las 9 herramientas de lectura, puerto de whatsapp-mcp-server/main.py, y una
// sola de envío, send_message (docs/09 §4.3). send_file y send_audio_message
// de upstream no existen aquí y no se añaden (líneas rojas, AGENTS.md).
//
// Nada en este archivo habla con WhatsApp: send_message deja el mensaje en la
// bandeja de salida y lo saca "sync" (outbox.go).

// Valores por defecto de Python que Go no tiene (ver nota en el plan): se
// aplican cuando el campo llega en su valor cero.
const (
	defaultLimit         = 20
	defaultContextBefore = 1
	defaultContextAfter  = 1
	defaultMessageBefore = 5
	defaultMessageAfter  = 5
	defaultSortBy        = "last_active"
)

// newMCPServer arma el servidor. Con outbox en nil solo hay lecturas; con una
// bandeja se añade send_message (ver runServe: --with-send).
func newMCPServer(store *MessageStore, outbox *outboxEnv) *mcp.Server {
	server := mcp.NewServer(&mcp.Implementation{Name: "galeno-whatsapp", Version: bridgeVersion}, nil)

	if outbox != nil {
		openWorld := true
		mcp.AddTool(server, &mcp.Tool{
			Name: "send_message",
			Description: "Send ONE WhatsApp text message to ONE person. The user approves every message before it goes out. " +
				"Text only: no files, images, audio or stickers, and never to groups, broadcast lists or channels. " +
				"Daily limits, office hours and a pause between messages are enforced by Galeno to protect the user's number: " +
				"when the result is \"rejected\", tell the user the reason and do not try to work around it " +
				"(do not reword, split, or resend to get past a limit). " +
				"\"queued\" means it will go out at scheduled_for; \"pending\" means Galeno is not connected to WhatsApp right now " +
				"and the message will go out when it is. Do not send the same message again in either case.",
			Annotations: &mcp.ToolAnnotations{Title: "Send a WhatsApp message", OpenWorldHint: &openWorld},
		}, handleSendMessage(*outbox))
	}

	mcp.AddTool(server, &mcp.Tool{
		Name:        "search_contacts",
		Description: "Search WhatsApp contacts by name or phone number.",
	}, handleSearchContacts(store))

	mcp.AddTool(server, &mcp.Tool{
		Name: "list_messages",
		Description: "Get WhatsApp messages matching specified criteria, formatted as text. " +
			"Includes surrounding context by default.",
	}, handleListMessages(store))

	mcp.AddTool(server, &mcp.Tool{
		Name:        "list_chats",
		Description: "Get WhatsApp chats matching specified criteria.",
	}, handleListChats(store))

	mcp.AddTool(server, &mcp.Tool{
		Name:        "get_chat",
		Description: "Get WhatsApp chat metadata by JID.",
	}, handleGetChat(store))

	mcp.AddTool(server, &mcp.Tool{
		Name:        "get_direct_chat_by_contact",
		Description: "Get WhatsApp chat metadata by sender phone number.",
	}, handleGetDirectChatByContact(store))

	mcp.AddTool(server, &mcp.Tool{
		Name:        "get_contact_chats",
		Description: "Get all WhatsApp chats involving the contact.",
	}, handleGetContactChats(store))

	mcp.AddTool(server, &mcp.Tool{
		Name:        "get_last_interaction",
		Description: "Get most recent WhatsApp message involving the contact, formatted as text.",
	}, handleGetLastInteraction(store))

	mcp.AddTool(server, &mcp.Tool{
		Name:        "get_message_context",
		Description: "Get context around a specific WhatsApp message.",
	}, handleGetMessageContext(store))

	mcp.AddTool(server, &mcp.Tool{
		Name:        "download_media",
		Description: "Get the local file path of a WhatsApp attachment that is already on this computer. This bridge does not fetch attachments from WhatsApp yet, so most return success=false: the text of the chat is still readable, and the user can open the file in WhatsApp.",
	}, handleDownloadMedia(store))

	return server
}

// MARK: - search_contacts

type SearchContactsInput struct {
	Query string `json:"query" jsonschema:"search term to match against contact names or phone numbers"`
}

type SearchContactsOutput struct {
	Contacts []Contact `json:"contacts"`
}

func handleSearchContacts(store *MessageStore) func(context.Context, *mcp.CallToolRequest, SearchContactsInput) (*mcp.CallToolResult, SearchContactsOutput, error) {
	return func(ctx context.Context, req *mcp.CallToolRequest, in SearchContactsInput) (*mcp.CallToolResult, SearchContactsOutput, error) {
		contacts, err := store.SearchContacts(in.Query)
		if err != nil {
			return nil, SearchContactsOutput{}, err
		}
		return nil, SearchContactsOutput{Contacts: contacts}, nil
	}
}

// MARK: - list_messages

type ListMessagesInput struct {
	After             string `json:"after,omitempty" jsonschema:"ISO-8601 date; only return messages after this"`
	Before            string `json:"before,omitempty" jsonschema:"ISO-8601 date; only return messages before this"`
	SenderPhoneNumber string `json:"sender_phone_number,omitempty"`
	ChatJID           string `json:"chat_jid,omitempty"`
	Query             string `json:"query,omitempty"`
	Limit             int    `json:"limit,omitempty" jsonschema:"default 20"`
	Page              int    `json:"page,omitempty"`
	IncludeContext    *bool  `json:"include_context,omitempty" jsonschema:"default true"`
	ContextBefore     int    `json:"context_before,omitempty" jsonschema:"default 1"`
	ContextAfter      int    `json:"context_after,omitempty" jsonschema:"default 1"`
}

type ListMessagesOutput struct {
	Text string `json:"text"`
}

func handleListMessages(store *MessageStore) func(context.Context, *mcp.CallToolRequest, ListMessagesInput) (*mcp.CallToolResult, ListMessagesOutput, error) {
	return func(ctx context.Context, req *mcp.CallToolRequest, in ListMessagesInput) (*mcp.CallToolResult, ListMessagesOutput, error) {
		opts := ListMessagesOptions{
			SenderPhoneNumber: in.SenderPhoneNumber,
			ChatJID:           in.ChatJID,
			Query:             in.Query,
			Limit:             orDefault(in.Limit, defaultLimit),
			Page:              in.Page,
			IncludeContext:    in.IncludeContext == nil || *in.IncludeContext,
			ContextBefore:     orDefault(in.ContextBefore, defaultContextBefore),
			ContextAfter:      orDefault(in.ContextAfter, defaultContextAfter),
		}
		if in.After != "" {
			t, err := time.Parse(time.RFC3339, in.After)
			if err != nil {
				return nil, ListMessagesOutput{}, invalidISO8601Error("after", in.After)
			}
			opts.After = &t
		}
		if in.Before != "" {
			t, err := time.Parse(time.RFC3339, in.Before)
			if err != nil {
				return nil, ListMessagesOutput{}, invalidISO8601Error("before", in.Before)
			}
			opts.Before = &t
		}

		text, err := store.ListMessages(opts)
		if err != nil {
			return nil, ListMessagesOutput{}, err
		}
		return nil, ListMessagesOutput{Text: text}, nil
	}
}

// MARK: - list_chats

type ListChatsInput struct {
	Query              string `json:"query,omitempty"`
	Limit              int    `json:"limit,omitempty" jsonschema:"default 20"`
	Page               int    `json:"page,omitempty"`
	IncludeLastMessage *bool  `json:"include_last_message,omitempty" jsonschema:"default true"`
	SortBy             string `json:"sort_by,omitempty" jsonschema:"'last_active' or 'name', default last_active"`
}

type ListChatsOutput struct {
	Chats []Chat `json:"chats"`
}

func handleListChats(store *MessageStore) func(context.Context, *mcp.CallToolRequest, ListChatsInput) (*mcp.CallToolResult, ListChatsOutput, error) {
	return func(ctx context.Context, req *mcp.CallToolRequest, in ListChatsInput) (*mcp.CallToolResult, ListChatsOutput, error) {
		chats, err := store.ListChats(ListChatsOptions{
			Query:              in.Query,
			Limit:              orDefault(in.Limit, defaultLimit),
			Page:               in.Page,
			IncludeLastMessage: in.IncludeLastMessage == nil || *in.IncludeLastMessage,
			SortBy:             orDefaultString(in.SortBy, defaultSortBy),
		})
		if err != nil {
			return nil, ListChatsOutput{}, err
		}
		return nil, ListChatsOutput{Chats: chats}, nil
	}
}

// MARK: - get_chat

type GetChatInput struct {
	ChatJID            string `json:"chat_jid"`
	IncludeLastMessage *bool  `json:"include_last_message,omitempty" jsonschema:"default true"`
}

type GetChatOutput struct {
	// nil cuando no existe el chat — no encontrado no es un error.
	Chat *Chat `json:"chat"`
}

func handleGetChat(store *MessageStore) func(context.Context, *mcp.CallToolRequest, GetChatInput) (*mcp.CallToolResult, GetChatOutput, error) {
	return func(ctx context.Context, req *mcp.CallToolRequest, in GetChatInput) (*mcp.CallToolResult, GetChatOutput, error) {
		chat, err := store.GetChatByJID(in.ChatJID, in.IncludeLastMessage == nil || *in.IncludeLastMessage)
		if err != nil {
			return nil, GetChatOutput{}, err
		}
		return nil, GetChatOutput{Chat: chat}, nil
	}
}

// MARK: - get_direct_chat_by_contact

type GetDirectChatByContactInput struct {
	SenderPhoneNumber string `json:"sender_phone_number"`
}

type GetDirectChatByContactOutput struct {
	Chat *Chat `json:"chat"`
}

func handleGetDirectChatByContact(store *MessageStore) func(context.Context, *mcp.CallToolRequest, GetDirectChatByContactInput) (*mcp.CallToolResult, GetDirectChatByContactOutput, error) {
	return func(ctx context.Context, req *mcp.CallToolRequest, in GetDirectChatByContactInput) (*mcp.CallToolResult, GetDirectChatByContactOutput, error) {
		chat, err := store.GetDirectChatByContact(in.SenderPhoneNumber)
		if err != nil {
			return nil, GetDirectChatByContactOutput{}, err
		}
		return nil, GetDirectChatByContactOutput{Chat: chat}, nil
	}
}

// MARK: - get_contact_chats

type GetContactChatsInput struct {
	JID   string `json:"jid"`
	Limit int    `json:"limit,omitempty" jsonschema:"default 20"`
	Page  int    `json:"page,omitempty"`
}

type GetContactChatsOutput struct {
	Chats []Chat `json:"chats"`
}

func handleGetContactChats(store *MessageStore) func(context.Context, *mcp.CallToolRequest, GetContactChatsInput) (*mcp.CallToolResult, GetContactChatsOutput, error) {
	return func(ctx context.Context, req *mcp.CallToolRequest, in GetContactChatsInput) (*mcp.CallToolResult, GetContactChatsOutput, error) {
		chats, err := store.GetContactChats(in.JID, orDefault(in.Limit, defaultLimit), in.Page)
		if err != nil {
			return nil, GetContactChatsOutput{}, err
		}
		return nil, GetContactChatsOutput{Chats: chats}, nil
	}
}

// MARK: - get_last_interaction

type GetLastInteractionInput struct {
	JID string `json:"jid"`
}

type GetLastInteractionOutput struct {
	Text string `json:"text"`
}

func handleGetLastInteraction(store *MessageStore) func(context.Context, *mcp.CallToolRequest, GetLastInteractionInput) (*mcp.CallToolResult, GetLastInteractionOutput, error) {
	return func(ctx context.Context, req *mcp.CallToolRequest, in GetLastInteractionInput) (*mcp.CallToolResult, GetLastInteractionOutput, error) {
		text, err := store.GetLastInteraction(in.JID)
		if err != nil {
			return nil, GetLastInteractionOutput{}, err
		}
		return nil, GetLastInteractionOutput{Text: text}, nil
	}
}

// MARK: - get_message_context

func handleGetMessageContext(store *MessageStore) func(context.Context, *mcp.CallToolRequest, GetMessageContextInput) (*mcp.CallToolResult, MessageContext, error) {
	return func(ctx context.Context, req *mcp.CallToolRequest, in GetMessageContextInput) (*mcp.CallToolResult, MessageContext, error) {
		result, err := store.GetMessageContext(
			in.MessageID,
			orDefault(in.Before, defaultMessageBefore),
			orDefault(in.After, defaultMessageAfter),
		)
		if err != nil {
			// Igual que upstream (que lanza ValueError si el id no existe):
			// esto sí es un error de la llamada, no un "no encontrado" normal.
			return nil, MessageContext{}, err
		}
		return nil, *result, nil
	}
}

type GetMessageContextInput struct {
	MessageID string `json:"message_id"`
	Before    int    `json:"before,omitempty" jsonschema:"default 5"`
	After     int    `json:"after,omitempty" jsonschema:"default 5"`
}

// MARK: - download_media

type DownloadMediaInput struct {
	MessageID string `json:"message_id"`
	ChatJID   string `json:"chat_jid"`
}

type DownloadMediaOutput struct {
	Success  bool   `json:"success"`
	Message  string `json:"message"`
	FilePath string `json:"file_path,omitempty"`
}

// mediaNotAvailableMessage es lo que se le dice al agente cuando el adjunto
// no está en disco. Hoy nadie lo descarga ("sync" recibe y guarda, pero no
// baja archivos: ver downloadMedia en media.go), así que reintentar no sirve.
// El mensaje anterior ("make sure the sync service is running, then try
// again") hacía que el agente le aconsejara al usuario algo que no funciona
// (primer demo con un usuario externo, 4 oct 2026). Tiene que decir la verdad
// y qué sí se puede hacer.
const mediaNotAvailableMessage = "This attachment is not available: Galeno cannot open WhatsApp attachments (documents, images, audio) yet. Retrying will not help. Tell the user plainly that you can read the text of the chat but not this file, and that they can open it themselves in WhatsApp."

// handleDownloadMedia solo mira la caché local (cachedMediaPath, en
// media.go): "serve" no sostiene su propia conexión a WhatsApp —la sostiene
// "sync", de fondo—, así que nunca intenta descargar en vivo. Si el archivo
// no está en disco, lo dice con honestidad en vez de conectarse por su
// cuenta, que reabriría el riesgo de dos conexiones simultáneas con el
// mismo dispositivo vinculado.
func handleDownloadMedia(store *MessageStore) func(context.Context, *mcp.CallToolRequest, DownloadMediaInput) (*mcp.CallToolResult, DownloadMediaOutput, error) {
	return func(ctx context.Context, req *mcp.CallToolRequest, in DownloadMediaInput) (*mcp.CallToolResult, DownloadMediaOutput, error) {
		_, _, absPath, err := cachedMediaPath(store, in.MessageID, in.ChatJID)
		if err != nil {
			var notCached *mediaNotCachedError
			if errors.As(err, &notCached) {
				return nil, DownloadMediaOutput{
					Success: false,
					Message: mediaNotAvailableMessage,
				}, nil
			}
			// Como en whatsapp.py: un fallo de descarga es un resultado
			// normal (success: false), no un error de protocolo MCP.
			return nil, DownloadMediaOutput{Success: false, Message: err.Error()}, nil
		}
		return nil, DownloadMediaOutput{Success: true, Message: "Media downloaded successfully", FilePath: absPath}, nil
	}
}

// MARK: - send_message

type SendMessageInput struct {
	Recipient string `json:"recipient" jsonschema:"the person's phone number in international format, digits only, no + (for example 573001112233), or a JID ending in @s.whatsapp.net"`
	Message   string `json:"message" jsonschema:"the text to send, up to 1000 characters"`
}

type SendMessageOutput struct {
	// sent | queued | pending | failed | rejected
	Status       string `json:"status"`
	ChatJID      string `json:"chat_jid,omitempty"`
	SentAt       string `json:"sent_at,omitempty"`
	ScheduledFor string `json:"scheduled_for,omitempty"`
	OutboxID     int64  `json:"outbox_id,omitempty"`
	// Error es lo que respondió WhatsApp cuando el envío falló; Reason, por
	// qué Galeno no lo envió o cuándo lo hará.
	Error  string `json:"error,omitempty"`
	Reason string `json:"reason,omitempty"`
}

const (
	reasonQueued      = "Scheduled, not sent yet: Galeno spaces messages out and only sends in office hours. It will go out at scheduled_for if this computer is on. Do not send it again."
	reasonNotPickedUp = "Not sent yet: Galeno is not connected to WhatsApp right now (the computer may have just woken up, or the sync is not running). It will go out when the connection is back, in office hours. Tell the user; do not send it again."
)

// handleSendMessage valida y deja el mensaje en la bandeja de salida. Un
// rechazo es un resultado normal (status "rejected" con su razón), no un error
// de protocolo: el agente tiene que poder leer por qué y contárselo al usuario.
func handleSendMessage(outbox outboxEnv) func(context.Context, *mcp.CallToolRequest, SendMessageInput) (*mcp.CallToolResult, SendMessageOutput, error) {
	return func(ctx context.Context, req *mcp.CallToolRequest, in SendMessageInput) (*mcp.CallToolResult, SendMessageOutput, error) {
		queued, err := outbox.enqueue(in.Recipient, in.Message)
		if err != nil {
			return nil, SendMessageOutput{}, err
		}
		if queued.Rejected {
			return nil, SendMessageOutput{Status: statusRejected, Reason: queued.Reason}, nil
		}

		out := SendMessageOutput{Status: statusQueued, ChatJID: queued.ChatJID, OutboxID: queued.ID}
		if !queued.DueNow {
			out.ScheduledFor = queued.NotBefore.Format(time.RFC3339)
			out.Reason = reasonQueued
			return nil, out, nil
		}

		outcome, err := outbox.awaitOutcome(ctx, queued.ID)
		if err != nil {
			return nil, SendMessageOutput{}, err
		}
		out.Status = outcome.Status
		switch outcome.Status {
		case statusSent:
			out.SentAt = outcome.SentAt.In(queued.NotBefore.Location()).Format(time.RFC3339)
		case statusPending:
			out.Reason = reasonNotPickedUp
		case statusRejected:
			out.Reason = outcome.Error
		default:
			out.Error = outcome.Error
		}
		return nil, out, nil
	}
}

// MARK: - ayudas compartidas

func orDefault(value, fallback int) int {
	if value == 0 {
		return fallback
	}
	return value
}

func orDefaultString(value, fallback string) string {
	if value == "" {
		return fallback
	}
	return value
}

func invalidISO8601Error(field, value string) error {
	return &invalidDateError{field: field, value: value}
}

type invalidDateError struct {
	field, value string
}

func (e *invalidDateError) Error() string {
	return "invalid date format for '" + e.field + "': " + e.value + ". Please use ISO-8601 format."
}
