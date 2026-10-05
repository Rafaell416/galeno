package main

import (
	"encoding/json"
	"testing"

	"go.mau.fi/whatsmeow/proto/waAdv"
	"google.golang.org/protobuf/proto"
)

func accountLinkedAt(t *testing.T, timestamp uint64) *waAdv.ADVSignedDeviceIdentity {
	t.Helper()
	details, err := proto.Marshal(&waAdv.ADVDeviceIdentity{Timestamp: proto.Uint64(timestamp)})
	if err != nil {
		t.Fatal(err)
	}
	return &waAdv.ADVSignedDeviceIdentity{Details: details}
}

// "status --json" le dice a la app desde cuándo está vinculado el dispositivo, para avisar antes de que la
// sesión rote. La fecha sale de lo que WhatsApp mismo guardó al vincular.
func TestStatusReportCarriesTheMomentWhatsAppLinkedTheDevice(t *testing.T) {
	report := buildStatusReport("573001234567", true, accountLinkedAt(t, 1_790_000_000))
	if !report.Linked || report.Number != "573001234567" || report.LinkedAt != 1_790_000_000 {
		t.Fatalf("informe inesperado: %+v", report)
	}
	if report.Version != bridgeVersion {
		t.Errorf("la versión del bridge va en el informe: %q", report.Version)
	}
}

func TestStatusReportWithoutALinkedDeviceHasNoNumberNorDate(t *testing.T) {
	report := buildStatusReport("573001234567", false, accountLinkedAt(t, 1_790_000_000))
	if report.Linked || report.Number != "" || report.LinkedAt != 0 {
		t.Fatalf("sin vincular no debe traer número ni fecha: %+v", report)
	}
}

// Una identidad ilegible no inventa una fecha: la app prefiere decir «no se sabe» que mentir.
func TestLinkedAtIsZeroWhenTheIdentityCannotBeRead(t *testing.T) {
	if linkedAt(nil) != 0 {
		t.Error("sin identidad, 0")
	}
	if linkedAt(&waAdv.ADVSignedDeviceIdentity{}) != 0 {
		t.Error("sin detalle, 0")
	}
	if linkedAt(&waAdv.ADVSignedDeviceIdentity{Details: []byte{0xff, 0xff, 0xff}}) != 0 {
		t.Error("detalle roto, 0")
	}
}

func TestStatusReportJSONHasTheFieldsTheAppReads(t *testing.T) {
	var decoded map[string]any
	if err := json.Unmarshal([]byte(buildStatusReport("57300", true, accountLinkedAt(t, 1_790_000_000)).json()), &decoded); err != nil {
		t.Fatal(err)
	}
	for _, key := range []string{"linked", "number", "linked_at", "version"} {
		if _, ok := decoded[key]; !ok {
			t.Errorf("falta %q en el JSON: %v", key, decoded)
		}
	}
	var unlinked map[string]any
	_ = json.Unmarshal([]byte(buildStatusReport("", false, nil).json()), &unlinked)
	if unlinked["linked"] != false {
		t.Errorf("sin vincular: %v", unlinked)
	}
}
