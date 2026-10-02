package main

import "testing"

// Pruebas del bridge. Vacías por ahora: se implementa en la Fase 3.
func TestVersion(t *testing.T) {
	if version != "0.0.1" {
		t.Errorf("version = %q, se esperaba %q", version, "0.0.1")
	}
}
