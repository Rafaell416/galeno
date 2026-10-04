package main

import (
	"database/sql"
	"fmt"
	"strings"
	"time"
)

// Las ocho consultas de solo lectura que, en el servidor Python de upstream
// (whatsapp-mcp-server/whatsapp.py), leían directo de store/messages.db
// desde un proceso aparte. Aquí son métodos de *MessageStore porque ya
// estamos en el mismo proceso que escribe esa base: nada de esto pasa por
// HTTP. El comportamiento (columnas, filtros, orden, paginación, formato de
// salida) es el mismo; lo que cambia es el lenguaje.

// Contact es la fuente para search_contacts.
type Contact struct {
	PhoneNumber string `json:"phone_number"`
	Name        string `json:"name,omitempty"`
	JID         string `json:"jid"`
}

// Chat es la fuente para list_chats, get_chat, get_direct_chat_by_contact y
// get_contact_chats.
type Chat struct {
	JID             string  `json:"jid"`
	Name            string  `json:"name,omitempty"`
	LastMessageTime *string `json:"last_message_time,omitempty"`
	LastMessage     string  `json:"last_message,omitempty"`
	LastSender      string  `json:"last_sender,omitempty"`
	LastIsFromMe    *bool   `json:"last_is_from_me,omitempty"`
	// IsGroup se deriva del propio JID (sufijo @g.us), igual que la
	// propiedad is_group del dataclass Chat en Python.
	IsGroup bool `json:"is_group"`
}

func newChat(jid string, name sql.NullString, lastMessageTime sql.NullTime,
	lastMessage, lastSender sql.NullString, lastIsFromMe sql.NullBool) Chat {
	chat := Chat{JID: jid, IsGroup: strings.HasSuffix(jid, "@g.us")}
	if name.Valid {
		chat.Name = name.String
	}
	if lastMessageTime.Valid {
		formatted := lastMessageTime.Time.Format(time.RFC3339)
		chat.LastMessageTime = &formatted
	}
	if lastMessage.Valid {
		chat.LastMessage = lastMessage.String
	}
	if lastSender.Valid {
		chat.LastSender = lastSender.String
	}
	if lastIsFromMe.Valid {
		v := lastIsFromMe.Bool
		chat.LastIsFromMe = &v
	}
	return chat
}

// DetailedMessage es la fuente para get_message_context: un mensaje con
// todo su contexto de chat. list_messages y get_last_interaction, en
// cambio, devuelven texto ya formateado (ver formatMessage más abajo) —
// así los devuelve upstream, y es lo que espera quien ya esté acostumbrado
// a ese formato.
type DetailedMessage struct {
	Timestamp string `json:"timestamp"`
	Sender    string `json:"sender"`
	ChatName  string `json:"chat_name,omitempty"`
	Content   string `json:"content"`
	IsFromMe  bool   `json:"is_from_me"`
	ChatJID   string `json:"chat_jid"`
	ID        string `json:"id"`
	MediaType string `json:"media_type,omitempty"`
}

// formattableMessage es lo mínimo que formatMessage necesita para componer
// una línea de texto: el mensaje y el contexto de chat que lo acompaña.
type formattableMessage struct {
	msg      Message
	id       string
	chatJID  string
	chatName string
}

func detailedToFormattable(d DetailedMessage) formattableMessage {
	t, _ := time.Parse(time.RFC3339, d.Timestamp)
	return formattableMessage{
		msg: Message{
			Time: t, Sender: d.Sender, Content: d.Content, IsFromMe: d.IsFromMe, MediaType: d.MediaType,
		},
		id: d.ID, chatJID: d.ChatJID, chatName: d.ChatName,
	}
}

// displayNameForJID resuelve un JID al nombre guardado para ese
// chat, igual que whatsapp.py:get_sender_name — primero por JID exacto,
// luego por coincidencia parcial del número. Si no encuentra nada, devuelve
// el propio JID (no es un error: upstream hace lo mismo).
func displayNameForJID(store *MessageStore, jid string) string {
	var name sql.NullString
	if err := store.db.QueryRow("SELECT name FROM chats WHERE jid = ? LIMIT 1", jid).Scan(&name); err == nil {
		if name.Valid && name.String != "" {
			return name.String
		}
	}

	phonePart := jid
	if idx := strings.Index(jid, "@"); idx >= 0 {
		phonePart = jid[:idx]
	}
	if err := store.db.QueryRow("SELECT name FROM chats WHERE jid LIKE ? LIMIT 1", "%"+phonePart+"%").Scan(&name); err == nil {
		if name.Valid && name.String != "" {
			return name.String
		}
	}
	return jid
}

// formatMessage compone una línea de texto para un mensaje, igual que
// whatsapp.py:format_message. Siempre antepone el chat cuando se conoce su
// nombre: en upstream show_chat_info nunca se llama con False en ningún
// punto del código, así que no hace falta el parámetro.
func formatMessage(store *MessageStore, m formattableMessage) string {
	var b strings.Builder
	if m.chatName != "" {
		fmt.Fprintf(&b, "[%s] Chat: %s ", m.msg.Time.Format("2006-01-02 15:04:05"), m.chatName)
	} else {
		fmt.Fprintf(&b, "[%s] ", m.msg.Time.Format("2006-01-02 15:04:05"))
	}

	contentPrefix := ""
	if m.msg.MediaType != "" {
		contentPrefix = fmt.Sprintf("[%s - Message ID: %s - Chat JID: %s] ", m.msg.MediaType, m.id, m.chatJID)
	}

	senderName := "Me"
	if !m.msg.IsFromMe {
		senderName = displayNameForJID(store, m.msg.Sender)
	}
	fmt.Fprintf(&b, "From: %s: %s%s\n", senderName, contentPrefix, m.msg.Content)
	return b.String()
}

func formatMessagesList(store *MessageStore, messages []formattableMessage) string {
	if len(messages) == 0 {
		return "No messages to display."
	}
	var b strings.Builder
	for _, m := range messages {
		b.WriteString(formatMessage(store, m))
	}
	return b.String()
}

// SearchContacts busca en chats individuales (nunca grupos) por nombre o
// número, igual que whatsapp.py:search_contacts.
func (store *MessageStore) SearchContacts(query string) ([]Contact, error) {
	pattern := "%" + query + "%"
	rows, err := store.db.Query(`
		SELECT DISTINCT jid, name
		FROM chats
		WHERE (LOWER(name) LIKE LOWER(?) OR LOWER(jid) LIKE LOWER(?))
		  AND jid NOT LIKE '%@g.us'
		ORDER BY name, jid
		LIMIT 50`, pattern, pattern)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	contacts := []Contact{}
	for rows.Next() {
		var jid string
		var name sql.NullString
		if err := rows.Scan(&jid, &name); err != nil {
			return nil, err
		}
		phone, _, _ := strings.Cut(jid, "@")
		contacts = append(contacts, Contact{PhoneNumber: phone, Name: name.String, JID: jid})
	}
	return contacts, rows.Err()
}

// ListChatsOptions son los parámetros de list_chats, con sus defaults de
// Python ya resueltos por quien construye el valor (ver mcp_server.go).
type ListChatsOptions struct {
	Query              string
	Limit              int
	Page               int
	IncludeLastMessage bool
	SortBy             string // "last_active" o "name"
}

func (store *MessageStore) ListChats(opts ListChatsOptions) ([]Chat, error) {
	// Sin el último mensaje no hay JOIN, así que sus tres columnas van como NULL: nombrarlas
	// (como hace upstream) revienta con "no such column: messages.content".
	query := `SELECT chats.jid, chats.name, chats.last_message_time, NULL, NULL, NULL FROM chats`
	if opts.IncludeLastMessage {
		query = `SELECT chats.jid, chats.name, chats.last_message_time,
			messages.content, messages.sender, messages.is_from_me
		FROM chats LEFT JOIN messages ON chats.jid = messages.chat_jid
			AND chats.last_message_time = messages.timestamp`
	}

	var where []string
	var args []any
	if opts.Query != "" {
		where = append(where, "(LOWER(chats.name) LIKE LOWER(?) OR chats.jid LIKE ?)")
		pattern := "%" + opts.Query + "%"
		args = append(args, pattern, pattern)
	}
	if len(where) > 0 {
		query += " WHERE " + strings.Join(where, " AND ")
	}

	orderBy := "chats.last_message_time DESC"
	if opts.SortBy == "name" {
		orderBy = "chats.name"
	}
	query += " ORDER BY " + orderBy + " LIMIT ? OFFSET ?"
	args = append(args, opts.Limit, opts.Page*opts.Limit)

	rows, err := store.db.Query(query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	chats := []Chat{}
	for rows.Next() {
		var jid string
		var name, lastMessage, lastSender sql.NullString
		var lastMessageTime sql.NullTime
		var lastIsFromMe sql.NullBool
		if err := rows.Scan(&jid, &name, &lastMessageTime, &lastMessage, &lastSender, &lastIsFromMe); err != nil {
			return nil, err
		}
		chats = append(chats, newChat(jid, name, lastMessageTime, lastMessage, lastSender, lastIsFromMe))
	}
	return chats, rows.Err()
}

func (store *MessageStore) GetChatByJID(chatJID string, includeLastMessage bool) (*Chat, error) {
	// Igual que en ListChats: sin JOIN, las columnas del último mensaje van como NULL.
	query := `SELECT c.jid, c.name, c.last_message_time, NULL, NULL, NULL FROM chats c`
	if includeLastMessage {
		query = `SELECT c.jid, c.name, c.last_message_time, m.content, m.sender, m.is_from_me FROM chats c
			LEFT JOIN messages m ON c.jid = m.chat_jid AND c.last_message_time = m.timestamp`
	}
	query += " WHERE c.jid = ?"

	var jid string
	var name, lastMessage, lastSender sql.NullString
	var lastMessageTime sql.NullTime
	var lastIsFromMe sql.NullBool
	err := store.db.QueryRow(query, chatJID).
		Scan(&jid, &name, &lastMessageTime, &lastMessage, &lastSender, &lastIsFromMe)
	if err == sql.ErrNoRows {
		return nil, nil // no encontrado no es un error, igual que upstream
	}
	if err != nil {
		return nil, err
	}
	chat := newChat(jid, name, lastMessageTime, lastMessage, lastSender, lastIsFromMe)
	return &chat, nil
}

func (store *MessageStore) GetDirectChatByContact(senderPhoneNumber string) (*Chat, error) {
	var jid string
	var name, lastMessage, lastSender sql.NullString
	var lastMessageTime sql.NullTime
	var lastIsFromMe sql.NullBool
	err := store.db.QueryRow(`
		SELECT c.jid, c.name, c.last_message_time, m.content, m.sender, m.is_from_me
		FROM chats c
		LEFT JOIN messages m ON c.jid = m.chat_jid AND c.last_message_time = m.timestamp
		WHERE c.jid LIKE ? AND c.jid NOT LIKE '%@g.us'
		LIMIT 1`, "%"+senderPhoneNumber+"%").
		Scan(&jid, &name, &lastMessageTime, &lastMessage, &lastSender, &lastIsFromMe)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	chat := newChat(jid, name, lastMessageTime, lastMessage, lastSender, lastIsFromMe)
	return &chat, nil
}

func (store *MessageStore) GetContactChats(jid string, limit, page int) ([]Chat, error) {
	rows, err := store.db.Query(`
		SELECT DISTINCT c.jid, c.name, c.last_message_time, m.content, m.sender, m.is_from_me
		FROM chats c
		JOIN messages m ON c.jid = m.chat_jid
		WHERE m.sender = ? OR c.jid = ?
		ORDER BY c.last_message_time DESC
		LIMIT ? OFFSET ?`, jid, jid, limit, page*limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	chats := []Chat{}
	for rows.Next() {
		var chatJID string
		var name, lastMessage, lastSender sql.NullString
		var lastMessageTime sql.NullTime
		var lastIsFromMe sql.NullBool
		if err := rows.Scan(&chatJID, &name, &lastMessageTime, &lastMessage, &lastSender, &lastIsFromMe); err != nil {
			return nil, err
		}
		chats = append(chats, newChat(chatJID, name, lastMessageTime, lastMessage, lastSender, lastIsFromMe))
	}
	return chats, rows.Err()
}

// GetLastInteraction devuelve, ya formateado como texto, el último mensaje
// que involucra al contacto. Cadena vacía si no hay ninguno (upstream
// devuelve None; el handler MCP lo traduce al formato de salida).
func (store *MessageStore) GetLastInteraction(jid string) (string, error) {
	var timestamp time.Time
	var sender, content, chatJID, id string
	var chatName, mediaType sql.NullString
	var isFromMe bool

	err := store.db.QueryRow(`
		SELECT m.timestamp, m.sender, c.name, m.content, m.is_from_me, c.jid, m.id, m.media_type
		FROM messages m
		JOIN chats c ON m.chat_jid = c.jid
		WHERE m.sender = ? OR c.jid = ?
		ORDER BY m.timestamp DESC
		LIMIT 1`, jid, jid).
		Scan(&timestamp, &sender, &chatName, &content, &isFromMe, &chatJID, &id, &mediaType)
	if err == sql.ErrNoRows {
		return "", nil
	}
	if err != nil {
		return "", err
	}

	fm := formattableMessage{
		msg:      Message{Time: timestamp, Sender: sender, Content: content, IsFromMe: isFromMe},
		id:       id,
		chatJID:  chatJID,
		chatName: chatName.String,
	}
	if mediaType.Valid {
		fm.msg.MediaType = mediaType.String
	}
	return formatMessage(store, fm), nil
}

// MessageContext es la salida de get_message_context: el mensaje pedido más
// los que lo rodean.
type MessageContext struct {
	Message DetailedMessage   `json:"message"`
	Before  []DetailedMessage `json:"before"`
	After   []DetailedMessage `json:"after"`
}

func (store *MessageStore) GetMessageContext(messageID string, before, after int) (*MessageContext, error) {
	var target DetailedMessage
	var timestamp time.Time
	var chatName, mediaType sql.NullString
	var chatJID string
	err := store.db.QueryRow(`
		SELECT messages.timestamp, messages.sender, chats.name, messages.content,
			messages.is_from_me, chats.jid, messages.id, messages.chat_jid, messages.media_type
		FROM messages
		JOIN chats ON messages.chat_jid = chats.jid
		WHERE messages.id = ?`, messageID).
		Scan(&timestamp, &target.Sender, &chatName, &target.Content, &target.IsFromMe,
			&target.ChatJID, &target.ID, &chatJID, &mediaType)
	if err == sql.ErrNoRows {
		return nil, fmt.Errorf("no se encontró el mensaje %s", messageID)
	}
	if err != nil {
		return nil, err
	}
	target.Timestamp = timestamp.Format(time.RFC3339)
	if chatName.Valid {
		target.ChatName = chatName.String
	}
	if mediaType.Valid {
		target.MediaType = mediaType.String
	}

	beforeMessages, err := store.queryContextMessages(chatJID, timestamp, before, "<", "DESC")
	if err != nil {
		return nil, err
	}
	afterMessages, err := store.queryContextMessages(chatJID, timestamp, after, ">", "ASC")
	if err != nil {
		return nil, err
	}

	return &MessageContext{Message: target, Before: beforeMessages, After: afterMessages}, nil
}

func (store *MessageStore) queryContextMessages(
	chatJID string, around time.Time, limit int, comparator, order string,
) ([]DetailedMessage, error) {
	rows, err := store.db.Query(fmt.Sprintf(`
		SELECT messages.timestamp, messages.sender, chats.name, messages.content,
			messages.is_from_me, chats.jid, messages.id, messages.media_type
		FROM messages
		JOIN chats ON messages.chat_jid = chats.jid
		WHERE messages.chat_jid = ? AND messages.timestamp %s ?
		ORDER BY messages.timestamp %s
		LIMIT ?`, comparator, order), chatJID, around, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	messages := []DetailedMessage{}
	for rows.Next() {
		var m DetailedMessage
		var timestamp time.Time
		var chatName, mediaType sql.NullString
		if err := rows.Scan(&timestamp, &m.Sender, &chatName, &m.Content, &m.IsFromMe, &m.ChatJID, &m.ID, &mediaType); err != nil {
			return nil, err
		}
		m.Timestamp = timestamp.Format(time.RFC3339)
		if chatName.Valid {
			m.ChatName = chatName.String
		}
		if mediaType.Valid {
			m.MediaType = mediaType.String
		}
		messages = append(messages, m)
	}
	return messages, rows.Err()
}

// ListMessagesOptions son los parámetros de list_messages.
type ListMessagesOptions struct {
	After, Before     *time.Time
	SenderPhoneNumber string
	ChatJID           string
	Query             string
	Limit, Page       int
	IncludeContext    bool
	ContextBefore     int
	ContextAfter      int
}

// ListMessages devuelve el resultado ya formateado como un bloque de texto
// — igual que whatsapp.py:list_messages, que llama a format_messages_list.
// Cuando IncludeContext es true, expande cada resultado con los mensajes
// alrededor (la misma consulta que usa GetMessageContext) antes de formatear.
func (store *MessageStore) ListMessages(opts ListMessagesOptions) (string, error) {
	query := `SELECT messages.timestamp, messages.sender, chats.name, messages.content,
			messages.is_from_me, chats.jid, messages.id, messages.media_type
		FROM messages JOIN chats ON messages.chat_jid = chats.jid`

	var where []string
	var args []any
	if opts.After != nil {
		where = append(where, "messages.timestamp > ?")
		args = append(args, *opts.After)
	}
	if opts.Before != nil {
		where = append(where, "messages.timestamp < ?")
		args = append(args, *opts.Before)
	}
	if opts.SenderPhoneNumber != "" {
		where = append(where, "messages.sender = ?")
		args = append(args, opts.SenderPhoneNumber)
	}
	if opts.ChatJID != "" {
		where = append(where, "messages.chat_jid = ?")
		args = append(args, opts.ChatJID)
	}
	if opts.Query != "" {
		where = append(where, "LOWER(messages.content) LIKE LOWER(?)")
		args = append(args, "%"+opts.Query+"%")
	}
	if len(where) > 0 {
		query += " WHERE " + strings.Join(where, " AND ")
	}
	query += " ORDER BY messages.timestamp DESC LIMIT ? OFFSET ?"
	args = append(args, opts.Limit, opts.Page*opts.Limit)

	rows, err := store.db.Query(query, args...)
	if err != nil {
		return "", err
	}

	var results []formattableMessage
	for rows.Next() {
		var timestamp time.Time
		var chatName, mediaType sql.NullString
		var m Message
		var id, chatJID string
		if err := rows.Scan(&timestamp, &m.Sender, &chatName, &m.Content, &m.IsFromMe, &chatJID, &id, &mediaType); err != nil {
			rows.Close()
			return "", err
		}
		m.Time = timestamp
		if mediaType.Valid {
			m.MediaType = mediaType.String
		}
		results = append(results, formattableMessage{msg: m, id: id, chatJID: chatJID, chatName: chatName.String})
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return "", err
	}

	if !opts.IncludeContext || len(results) == 0 {
		return formatMessagesList(store, results), nil
	}

	// Con contexto: cada resultado se expande a sus vecinos, igual que
	// upstream (que llama a get_message_context por cada mensaje).
	var expanded []formattableMessage
	for _, r := range results {
		ctx, err := store.GetMessageContext(r.id, opts.ContextBefore, opts.ContextAfter)
		if err != nil {
			// Si el contexto falla para un mensaje puntual, no se pierde
			// todo el listado: se usa el mensaje solo.
			expanded = append(expanded, r)
			continue
		}
		for _, before := range ctx.Before {
			expanded = append(expanded, detailedToFormattable(before))
		}
		expanded = append(expanded, detailedToFormattable(ctx.Message))
		for _, after := range ctx.After {
			expanded = append(expanded, detailedToFormattable(after))
		}
	}

	return formatMessagesList(store, expanded), nil
}
