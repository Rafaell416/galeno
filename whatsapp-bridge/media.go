package main

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"go.mau.fi/whatsmeow"
	waProto "go.mau.fi/whatsmeow/binary/proto"
)

// Nada en este archivo escribe a stdout: durante "serve", stdout es el
// transporte MCP y cualquier línea suelta corrompería el JSON-RPC. Ver log.go.

// Extract text content from a message
func extractTextContent(msg *waProto.Message) string {
	if msg == nil {
		return ""
	}

	// Try to get text content
	if text := msg.GetConversation(); text != "" {
		return text
	} else if extendedText := msg.GetExtendedTextMessage(); extendedText != nil {
		return extendedText.GetText()
	}

	// For now, we're ignoring non-text messages
	return ""
}

// Extract media info from a message
func extractMediaInfo(msg *waProto.Message) (mediaType string, filename string, url string, mediaKey []byte, fileSHA256 []byte, fileEncSHA256 []byte, fileLength uint64) {
	if msg == nil {
		return "", "", "", nil, nil, nil, 0
	}

	// Check for image message
	if img := msg.GetImageMessage(); img != nil {
		return "image", "image_" + time.Now().Format("20060102_150405") + ".jpg",
			img.GetURL(), img.GetMediaKey(), img.GetFileSHA256(), img.GetFileEncSHA256(), img.GetFileLength()
	}

	// Check for video message
	if vid := msg.GetVideoMessage(); vid != nil {
		return "video", "video_" + time.Now().Format("20060102_150405") + ".mp4",
			vid.GetURL(), vid.GetMediaKey(), vid.GetFileSHA256(), vid.GetFileEncSHA256(), vid.GetFileLength()
	}

	// Check for audio message
	if aud := msg.GetAudioMessage(); aud != nil {
		return "audio", "audio_" + time.Now().Format("20060102_150405") + ".ogg",
			aud.GetURL(), aud.GetMediaKey(), aud.GetFileSHA256(), aud.GetFileEncSHA256(), aud.GetFileLength()
	}

	// Check for document message
	if doc := msg.GetDocumentMessage(); doc != nil {
		filename := doc.GetFileName()
		if filename == "" {
			filename = "document_" + time.Now().Format("20060102_150405")
		}
		return "document", filename,
			doc.GetURL(), doc.GetMediaKey(), doc.GetFileSHA256(), doc.GetFileEncSHA256(), doc.GetFileLength()
	}

	return "", "", "", nil, nil, nil, 0
}

// MediaDownloader implements the whatsmeow.DownloadableMessage interface
type MediaDownloader struct {
	URL           string
	DirectPath    string
	MediaKey      []byte
	FileLength    uint64
	FileSHA256    []byte
	FileEncSHA256 []byte
	MediaType     whatsmeow.MediaType
}

// GetDirectPath implements the DownloadableMessage interface
func (d *MediaDownloader) GetDirectPath() string {
	return d.DirectPath
}

// GetURL implements the DownloadableMessage interface
func (d *MediaDownloader) GetURL() string {
	return d.URL
}

// GetMediaKey implements the DownloadableMessage interface
func (d *MediaDownloader) GetMediaKey() []byte {
	return d.MediaKey
}

// GetFileLength implements the DownloadableMessage interface
func (d *MediaDownloader) GetFileLength() uint64 {
	return d.FileLength
}

// GetFileSHA256 implements the DownloadableMessage interface
func (d *MediaDownloader) GetFileSHA256() []byte {
	return d.FileSHA256
}

// GetFileEncSHA256 implements the DownloadableMessage interface
func (d *MediaDownloader) GetFileEncSHA256() []byte {
	return d.FileEncSHA256
}

// GetMediaType implements the DownloadableMessage interface
func (d *MediaDownloader) GetMediaType() whatsmeow.MediaType {
	return d.MediaType
}

// mediaRecord es lo que la base sabe de un mensaje con media, se haya
// descargado ya o no.
type mediaRecord struct {
	mediaType, filename, url            string
	mediaKey, fileSHA256, fileEncSHA256 []byte
	fileLength                          uint64
}

func lookupMediaRecord(messageStore *MessageStore, messageID, chatJID string) (mediaRecord, error) {
	var rec mediaRecord
	var err error
	rec.mediaType, rec.filename, rec.url, rec.mediaKey, rec.fileSHA256, rec.fileEncSHA256, rec.fileLength, err =
		messageStore.GetMediaInfo(messageID, chatJID)

	if err != nil {
		// Try to get basic info if extended info isn't available
		err = messageStore.db.QueryRow(
			"SELECT media_type, filename FROM messages WHERE id = ? AND chat_jid = ?",
			messageID, chatJID,
		).Scan(&rec.mediaType, &rec.filename)

		if err != nil {
			return mediaRecord{}, fmt.Errorf("failed to find message: %v", err)
		}
	}

	if rec.mediaType == "" {
		return mediaRecord{}, fmt.Errorf("not a media message")
	}
	return rec, nil
}

// mediaNotCachedError señala que el archivo todavía no se descargó a disco
// y hace falta una conexión viva a WhatsApp para traerlo. "serve" (el
// proceso que sirve el MCP por sesión) nunca sostiene esa conexión —la
// sostiene "sync", de fondo— así que nunca intenta este camino: solo mira
// si cachedMediaPath ya lo tiene, y si no, lo dice con honestidad en vez de
// conectarse por su cuenta (ver mcp_server.go:handleDownloadMedia).
type mediaNotCachedError struct {
	messageID, chatJID string
}

func (e *mediaNotCachedError) Error() string {
	return fmt.Sprintf("media for message %s in chat %s is not cached locally", e.messageID, e.chatJID)
}

// mediaLocalPath es dónde vive (o viviría) el archivo de un mensaje:
// <stateDir>/media/<chat>/<filename>. stateDir es el de messageStore
// (~/Library/Application Support/Galeno/whatsapp/), nunca el directorio de
// trabajo del proceso.
func mediaLocalPath(messageStore *MessageStore, chatJID, filename string) string {
	chatDir := filepath.Join(messageStore.stateDir, "media", strings.ReplaceAll(chatJID, ":", "_"))
	return filepath.Join(chatDir, filename)
}

// cachedMediaPath busca si el archivo de un mensaje ya se descargó a disco,
// sin intentar traerlo si no — por eso no necesita un *whatsmeow.Client en
// absoluto.
func cachedMediaPath(messageStore *MessageStore, messageID, chatJID string) (mediaType, filename, absPath string, err error) {
	rec, err := lookupMediaRecord(messageStore, messageID, chatJID)
	if err != nil {
		return "", "", "", err
	}

	localPath := mediaLocalPath(messageStore, chatJID, rec.filename)
	absPath, err = filepath.Abs(localPath)
	if err != nil {
		return "", "", "", fmt.Errorf("failed to get absolute path: %v", err)
	}

	if _, statErr := os.Stat(localPath); statErr == nil {
		return rec.mediaType, rec.filename, absPath, nil
	}

	// No está en disco. Si además nos falta lo necesario para pedirlo, no
	// hay ambigüedad: nadie podría descargarlo igual. Si SÍ tenemos todo lo
	// necesario, lo que falta es la conexión viva — eso lo decide el
	// llamador (ver downloadMedia).
	if rec.url == "" || len(rec.mediaKey) == 0 || len(rec.fileSHA256) == 0 || len(rec.fileEncSHA256) == 0 || rec.fileLength == 0 {
		return "", "", "", fmt.Errorf("incomplete media information for download")
	}
	return "", "", "", &mediaNotCachedError{messageID: messageID, chatJID: chatJID}
}

// downloadMedia descarga media de un mensaje usando una conexión viva,
// probando primero la caché local (cachedMediaPath). Hoy no la llama nada:
// "serve" ya no sostiene su propia conexión, y "sync" por ahora solo recibe
// y guarda, no descarga proactivamente (fuera de alcance de esta serie de
// cambios, ver el plan). Queda lista para cuando algún camino con conexión
// viva la necesite.
func downloadMedia(client *whatsmeow.Client, messageStore *MessageStore, messageID, chatJID string) (bool, string, string, string, error) {
	mediaType, filename, absPath, err := cachedMediaPath(messageStore, messageID, chatJID)
	if err == nil {
		return true, mediaType, filename, absPath, nil
	}
	var notCached *mediaNotCachedError
	if !errors.As(err, &notCached) {
		return false, "", "", "", err
	}

	rec, err := lookupMediaRecord(messageStore, messageID, chatJID)
	if err != nil {
		return false, "", "", "", err
	}

	chatDir := filepath.Dir(mediaLocalPath(messageStore, chatJID, rec.filename))
	if err := os.MkdirAll(chatDir, 0755); err != nil {
		return false, "", "", "", fmt.Errorf("failed to create chat directory: %v", err)
	}
	localPath := mediaLocalPath(messageStore, chatJID, rec.filename)
	absPath, err = filepath.Abs(localPath)
	if err != nil {
		return false, "", "", "", fmt.Errorf("failed to get absolute path: %v", err)
	}

	fmt.Fprintf(os.Stderr, "Attempting to download media for message %s in chat %s...\n", messageID, chatJID)

	// Extract direct path from URL
	directPath := extractDirectPathFromURL(rec.url)

	// Create a downloader that implements DownloadableMessage
	var waMediaType whatsmeow.MediaType
	switch rec.mediaType {
	case "image":
		waMediaType = whatsmeow.MediaImage
	case "video":
		waMediaType = whatsmeow.MediaVideo
	case "audio":
		waMediaType = whatsmeow.MediaAudio
	case "document":
		waMediaType = whatsmeow.MediaDocument
	default:
		return false, "", "", "", fmt.Errorf("unsupported media type: %s", rec.mediaType)
	}

	downloader := &MediaDownloader{
		URL:           rec.url,
		DirectPath:    directPath,
		MediaKey:      rec.mediaKey,
		FileLength:    rec.fileLength,
		FileSHA256:    rec.fileSHA256,
		FileEncSHA256: rec.fileEncSHA256,
		MediaType:     waMediaType,
	}

	// Download the media using whatsmeow client
	mediaData, err := client.Download(downloader)
	if err != nil {
		return false, "", "", "", fmt.Errorf("failed to download media: %v", err)
	}

	// Save the downloaded media to file
	if err := os.WriteFile(localPath, mediaData, 0644); err != nil {
		return false, "", "", "", fmt.Errorf("failed to save media file: %v", err)
	}

	fmt.Fprintf(os.Stderr, "Successfully downloaded %s media to %s (%d bytes)\n", rec.mediaType, absPath, len(mediaData))
	return true, rec.mediaType, rec.filename, absPath, nil
}

// Extract direct path from a WhatsApp media URL
func extractDirectPathFromURL(url string) string {
	// The direct path is typically in the URL, we need to extract it
	// Example URL: https://mmg.whatsapp.net/v/t62.7118-24/13812002_698058036224062_3424455886509161511_n.enc?ccb=11-4&oh=...

	// Find the path part after the domain
	parts := strings.SplitN(url, ".net/", 2)
	if len(parts) < 2 {
		return url // Return original URL if parsing fails
	}

	pathPart := parts[1]

	// Remove query parameters
	pathPart = strings.SplitN(pathPart, "?", 2)[0]

	// Create proper direct path format
	return "/" + pathPart
}
