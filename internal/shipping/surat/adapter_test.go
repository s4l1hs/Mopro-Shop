package surat_test

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/mopro/platform/internal/shipping"
	"github.com/mopro/platform/internal/shipping/surat"
)

// buildServer returns a test server that serves minimal Sürat API responses.
func buildServer(t *testing.T) *httptest.Server {
	t.Helper()
	mux := http.NewServeMux()

	// Auth
	mux.HandleFunc("/api/v1/auth/login", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{
			"Status": 200,
			"Data":   map[string]any{"Token": "test-token", "ExpiresIn": 3600},
		})
	})

	// Track
	mux.HandleFunc("/api/v1/shipment/track/SURAT-001", func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(map[string]any{
			"Data": map[string]any{
				"status":      "DELIVERED",
				"description": "Teslim edildi",
				"eventAt":     time.Now().UTC().Format(time.RFC3339),
			},
		})
	})

	return httptest.NewServer(mux)
}

func TestAdapter_HandleWebhook_ValidSignature(t *testing.T) {
	const secret = "webhook-secret-123"
	body := []byte(`{"trackingNumber":"SURAT-001","status":"DELIVERED","description":"ok","eventAt":"2026-01-01T10:00:00Z"}`)

	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write(body)
	sig := hex.EncodeToString(mac.Sum(nil))

	a := surat.New(shipping.SuratConfig{WebhookSecret: secret})
	ev, err := a.HandleWebhook(context.Background(), body, map[string]string{"X-Surat-Sign": sig})
	if err != nil {
		t.Fatalf("HandleWebhook: %v", err)
	}
	if ev.State != shipping.ShipmentStateDelivered {
		t.Errorf("state: want delivered, got %s", ev.State)
	}
	if ev.TrackingNumber != "SURAT-001" {
		t.Errorf("tracking: want SURAT-001, got %s", ev.TrackingNumber)
	}
}

func TestAdapter_HandleWebhook_InvalidSignature(t *testing.T) {
	a := surat.New(shipping.SuratConfig{WebhookSecret: "secret"})
	_, err := a.HandleWebhook(context.Background(), []byte(`{}`), map[string]string{"X-Surat-Sign": "bad"})
	if err != shipping.ErrInvalidSignature {
		t.Errorf("want ErrInvalidSignature, got %v", err)
	}
}

func TestAdapter_TrackShipment(t *testing.T) {
	srv := buildServer(t)
	defer srv.Close()

	a := surat.New(shipping.SuratConfig{BaseURL: srv.URL, Username: "u", Password: "p"})
	res, err := a.TrackShipment(context.Background(), "SURAT-001")
	if err != nil {
		t.Fatalf("TrackShipment: %v", err)
	}
	if res.State != shipping.ShipmentStateDelivered {
		t.Errorf("state: want delivered, got %s", res.State)
	}
}
