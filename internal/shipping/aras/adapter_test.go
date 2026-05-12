package aras_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/mopro/platform/internal/shipping"
	"github.com/mopro/platform/internal/shipping/aras"
)

func buildServer(t *testing.T) *httptest.Server {
	t.Helper()
	mux := http.NewServeMux()
	mux.HandleFunc("/api/v1/shipment/ARAS-001", func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(map[string]any{
			"statusCode":  "4",
			"description": "Teslim edildi",
			"eventAt":     time.Now().UTC().Format(time.RFC3339),
		})
	})
	return httptest.NewServer(mux)
}

func TestAdapter_TrackShipment_Delivered(t *testing.T) {
	srv := buildServer(t)
	defer srv.Close()

	a := aras.New(shipping.ArasConfig{BaseURL: srv.URL, Username: "u", Password: "p"})
	res, err := a.TrackShipment(context.Background(), "ARAS-001")
	if err != nil {
		t.Fatalf("TrackShipment: %v", err)
	}
	if res.State != shipping.ShipmentStateDelivered {
		t.Errorf("state: want delivered, got %s", res.State)
	}
}

func TestAdapter_HandleWebhook_NotSupported(t *testing.T) {
	a := aras.New(shipping.ArasConfig{})
	_, err := a.HandleWebhook(context.Background(), nil, nil)
	if err == nil {
		t.Error("expected error for unsupported webhook")
	}
}
