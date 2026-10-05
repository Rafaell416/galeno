package main

import (
	"context"
	"strings"
	"testing"
	"time"
)

// Un adjunto que no está en disco: el bridge todavía no los descarga, así que
// la respuesta tiene que decirlo y no mandar a reintentar. Con el mensaje
// anterior el agente le aconsejaba al usuario "asegúrate de que el servicio
// corre y vuelve a intentarlo", que no servía de nada.
func TestDownloadMediaSaysAttachmentsAreNotAvailableInsteadOfAskingToRetry(t *testing.T) {
	store := storeWithOneChat(t)
	chat := "123@g.us"
	err := store.StoreMessage(
		"MSG1", chat, "573001112233", "", time.Now(), false,
		"document", "poder.pdf", "https://mmg.whatsapp.net/fake",
		[]byte("llave"), []byte("sha"), []byte("enc"), 1234,
	)
	if err != nil {
		t.Fatalf("StoreMessage: %v", err)
	}

	_, out, err := handleDownloadMedia(store)(context.Background(), nil, DownloadMediaInput{MessageID: "MSG1", ChatJID: chat})
	if err != nil {
		t.Fatalf("no debe ser un error de protocolo: %v", err)
	}
	if out.Success {
		t.Fatalf("no hay archivo en disco: no puede decir que lo descargó")
	}
	if out.Message != mediaNotAvailableMessage {
		t.Fatalf("mensaje inesperado: %q", out.Message)
	}
	lower := strings.ToLower(out.Message)
	for _, misleading := range []string{"try again shortly", "sync service is running", "not downloaded yet"} {
		if strings.Contains(lower, misleading) {
			t.Errorf("el mensaje no debe mandar a reintentar: contiene %q", misleading)
		}
	}
	for _, needed := range []string{"cannot open whatsapp attachments", "retrying will not help", "in whatsapp"} {
		if !strings.Contains(lower, needed) {
			t.Errorf("al mensaje le falta %q", needed)
		}
	}
}
