package orderledger

import (
	"context"
	"encoding/json"
	"errors"
	"testing"
	"time"

	"github.com/mopro/platform/internal/eventbus"
)

// ── mock service ───────────────────────────────────────────────────────────────

type mockService struct {
	capturedEvent *OrderPaidEvent
	err           error
	callCount     int
}

func (m *mockService) PostCapture(_ context.Context, ev OrderPaidEvent) error {
	m.capturedEvent = &ev
	m.callCount++
	return m.err
}

// ── helpers ────────────────────────────────────────────────────────────────────

func newPaidEvent(orderID int64, sellerID int64, gross int64) eventbus.Event {
	p := orderPaidPayload{
		OrderID:     orderID,
		UserID:      1,
		SellerID:    sellerID,
		PaidAt:      time.Now(),
		AmountMinor: gross,
		Currency:    "TRY",
		Market:      "TR",
		Items: []orderPaidItem{
			{
				VariantID:             1,
				SellerID:              sellerID,
				Qty:                   1,
				UnitPriceMinor:        gross,
				CommissionPctBps:      1500,
				KdvPctBps:             2000,
				CommissionAmountMinor: gross * 15 / 100,
				KdvAmountMinor:        gross * 15 / 100 * 20 / 100,
				SellerNetMinor:        gross - gross*15/100 - gross*15/100*20/100,
			},
		},
	}
	payload, _ := json.Marshal(p)
	return eventbus.Event{
		EventID:        "test-event-1",
		EventType:      TopicOrderPaid,
		Payload:        payload,
		Currency:       "TRY",
		Market:         "TR",
		IdempotencyKey: "order:paid:order_1",
	}
}

// ── tests ──────────────────────────────────────────────────────────────────────

func TestHandlePaid_HappyPath(t *testing.T) {
	svc := &mockService{}
	ev := newPaidEvent(101, 10, 10000)

	if err := handlePaid(context.Background(), svc, ev); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if svc.callCount != 1 {
		t.Fatalf("PostCapture called %d times, want 1", svc.callCount)
	}
	if svc.capturedEvent.OrderID != 101 {
		t.Fatalf("OrderID=%d, want 101", svc.capturedEvent.OrderID)
	}
	if svc.capturedEvent.SellerID != 10 {
		t.Fatalf("SellerID=%d, want 10", svc.capturedEvent.SellerID)
	}
	if svc.capturedEvent.GrossMinor != 10000 {
		t.Fatalf("GrossMinor=%d, want 10000", svc.capturedEvent.GrossMinor)
	}
}

func TestHandlePaid_InvalidJSON_ReturnsError(t *testing.T) {
	svc := &mockService{}
	ev := eventbus.Event{
		EventID:  "bad",
		Payload:  []byte("not-json"),
		Currency: "TRY",
		Market:   "TR",
	}

	err := handlePaid(context.Background(), svc, ev)
	if err == nil {
		t.Fatal("expected error for invalid JSON")
	}
	if svc.callCount != 0 {
		t.Fatal("PostCapture must not be called for invalid payload")
	}
}

func TestHandlePaid_ServiceError_PropagatesError(t *testing.T) {
	svc := &mockService{err: errors.New("ledger write failed")}
	ev := newPaidEvent(202, 20, 5000)

	err := handlePaid(context.Background(), svc, ev)
	if err == nil {
		t.Fatal("expected error to propagate from PostCapture")
	}
}

func TestHandlePaid_CurrencyAndMarket_FromEventBusEnvelope(t *testing.T) {
	// Currency and Market come from the eventbus envelope, not the JSON payload.
	svc := &mockService{}
	ev := newPaidEvent(303, 30, 8000)
	ev.Currency = "EUR" // override envelope currency
	ev.Market = "DE"

	if err := handlePaid(context.Background(), svc, ev); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if svc.capturedEvent.Currency != "EUR" {
		t.Fatalf("Currency=%q, want EUR", svc.capturedEvent.Currency)
	}
	if svc.capturedEvent.Market != "DE" {
		t.Fatalf("Market=%q, want DE", svc.capturedEvent.Market)
	}
}
