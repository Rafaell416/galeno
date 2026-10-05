package main

import (
	"encoding/json"

	"go.mau.fi/whatsmeow/proto/waAdv"
	"google.golang.org/protobuf/proto"
)

// statusReport es lo que imprime "status --json": la app de Galeno lo lee para su vista de salud sin tener que
// entender el texto en español de "status".
type statusReport struct {
	Linked bool   `json:"linked"`
	Number string `json:"number,omitempty"`
	// LinkedAt es cuándo se vinculó este dispositivo (segundos Unix), según el propio WhatsApp. 0 = no se pudo
	// leer; la app no inventa una fecha.
	LinkedAt int64  `json:"linked_at,omitempty"`
	Version  string `json:"version"`
}

// linkedAt saca la fecha en que WhatsApp vinculó el dispositivo del detalle de su identidad (ADV). 0 si no hay
// identidad o el detalle no se puede leer.
func linkedAt(account *waAdv.ADVSignedDeviceIdentity) int64 {
	if account == nil || len(account.Details) == 0 {
		return 0
	}
	var details waAdv.ADVDeviceIdentity
	if err := proto.Unmarshal(account.Details, &details); err != nil {
		return 0
	}
	return int64(details.GetTimestamp())
}

// buildStatusReport arma el informe. Función pura, para probarla sin base de datos.
func buildStatusReport(number string, linked bool, account *waAdv.ADVSignedDeviceIdentity) statusReport {
	report := statusReport{Linked: linked, Version: bridgeVersion}
	if linked {
		report.Number = number
		report.LinkedAt = linkedAt(account)
	}
	return report
}

func (report statusReport) json() string {
	data, _ := json.Marshal(report)
	return string(data)
}
