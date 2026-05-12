package hepsijet_test

import (
	"context"
	"testing"

	"github.com/mopro/platform/internal/shipping"
	"github.com/mopro/platform/internal/shipping/hepsijet"
)

func TestAdapter_HandleWebhook_ValidToken(t *testing.T) {
	const token = "static-webhook-token"
	body := []byte(`{"trackingNumber":"HJ-001","status":"DELIVERED","description":"ok","eventAt":"2026-01-01T10:00:00Z"}`)

	a := hepsijet.New(shipping.HepsiJetConfig{WebhookToken: token})
	ev, err := a.HandleWebhook(context.Background(), body, map[string]string{"Authorization": "Bearer " + token})
	if err != nil {
		t.Fatalf("HandleWebhook: %v", err)
	}
	if ev.State != shipping.ShipmentStateDelivered {
		t.Errorf("state: want delivered, got %s", ev.State)
	}
	if ev.TrackingNumber != "HJ-001" {
		t.Errorf("tracking: want HJ-001, got %s", ev.TrackingNumber)
	}
}

func TestAdapter_HandleWebhook_WrongToken(t *testing.T) {
	a := hepsijet.New(shipping.HepsiJetConfig{WebhookToken: "correct-token"})
	_, err := a.HandleWebhook(context.Background(), []byte(`{}`), map[string]string{"Authorization": "Bearer wrong-token"})
	if err != shipping.ErrInvalidSignature {
		t.Errorf("want ErrInvalidSignature, got %v", err)
	}
}

func TestAdapter_HandleWebhook_MissingAuth(t *testing.T) {
	a := hepsijet.New(shipping.HepsiJetConfig{WebhookToken: "tok"})
	_, err := a.HandleWebhook(context.Background(), []byte(`{}`), map[string]string{})
	if err != shipping.ErrInvalidSignature {
		t.Errorf("want ErrInvalidSignature, got %v", err)
	}
}
