package main

import (
	"testing"

	"github.com/mopro/platform/internal/order"
)

// RT-02: the return cargo code is a deterministic, zero-padded id-derived code
// (our own "İade Kargo Kodu", stable per return) + the configured carrier.
func TestReturnShipping_CodeFormat(t *testing.T) {
	t.Setenv("RETURN_CARRIER", "Test Kargo")
	s := returnShipping(order.Return{ID: 42})
	if s["code"] != "IADE-0000042" {
		t.Errorf("code: want IADE-0000042 got %v", s["code"])
	}
	if s["carrier"] != "Test Kargo" {
		t.Errorf("carrier: want Test Kargo got %v", s["carrier"])
	}
}

func TestReturnShipping_DefaultCarrier(t *testing.T) {
	t.Setenv("RETURN_CARRIER", "")
	s := returnShipping(order.Return{ID: 1})
	if s["carrier"] != defaultReturnCarrier {
		t.Errorf("default carrier: want %q got %v", defaultReturnCarrier, s["carrier"])
	}
}
