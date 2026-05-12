package mng_test

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"testing"

	"github.com/mopro/platform/internal/shipping"
	"github.com/mopro/platform/internal/shipping/mng"
)

func TestAdapter_HandleWebhook_Valid(t *testing.T) {
	const secret = "mng-secret"
	body := []byte(`{"tracking_number":"MNG-001","status_code":"TESLIM","description":"ok","event_at":"2026-01-01T10:00:00Z"}`)

	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write(body)
	sig := hex.EncodeToString(mac.Sum(nil))

	a := mng.New(shipping.MNGConfig{WebhookSecret: secret})
	ev, err := a.HandleWebhook(context.Background(), body, map[string]string{"X-MNG-Signature": sig})
	if err != nil {
		t.Fatalf("HandleWebhook: %v", err)
	}
	if ev.State != shipping.ShipmentStateDelivered {
		t.Errorf("state: want delivered, got %s", ev.State)
	}
}

func TestAdapter_HandleWebhook_InvalidSig(t *testing.T) {
	a := mng.New(shipping.MNGConfig{WebhookSecret: "secret"})
	_, err := a.HandleWebhook(context.Background(), []byte(`{}`), map[string]string{"X-MNG-Signature": "bad"})
	if err != shipping.ErrInvalidSignature {
		t.Errorf("want ErrInvalidSignature, got %v", err)
	}
}
