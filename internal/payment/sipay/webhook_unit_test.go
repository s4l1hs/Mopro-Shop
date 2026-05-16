package sipay_test

import (
	"bytes"
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/mopro/platform/internal/outbox"
	"github.com/mopro/platform/internal/payment"
	"github.com/mopro/platform/internal/payment/sipay"
)

// panicOnInsertOutbox panics if Insert is called, asserting no outbox emission.
type panicOnInsertOutbox struct{}

func (panicOnInsertOutbox) Insert(_ context.Context, _ pgx.Tx, _ outbox.Row) error {
	panic("outbox.Insert must not be called for unknown event types")
}
func (panicOnInsertOutbox) FetchUnpublished(_ context.Context, _ pgx.Tx, _ int) ([]outbox.Row, error) {
	return nil, nil
}
func (panicOnInsertOutbox) MarkPublished(_ context.Context, _ pgx.Tx, _ int64) error {
	return nil
}

// unitStubRepo is a minimal payment.Repository for unit tests (no pgx pool needed).
type unitStubRepo struct{}

func (unitStubRepo) InsertPaymentIntent(_ context.Context, _ pgx.Tx, p payment.PaymentIntent) (payment.PaymentIntent, error) {
	p.ID = 1
	p.CreatedAt = time.Now()
	p.UpdatedAt = time.Now()
	return p, nil
}
func (unitStubRepo) FindPaymentIntentByIdempotencyKey(_ context.Context, _ string) (payment.PaymentIntent, error) {
	return payment.PaymentIntent{}, payment.ErrPaymentNotFound
}
func (unitStubRepo) UpdatePaymentStatus(_ context.Context, _ pgx.Tx, _ string, _ payment.PaymentStatus, _, _, _ *string, _, _ string, _ int64) error {
	return nil
}
func (unitStubRepo) FindPaymentByOrderID(_ context.Context, _ int64) (payment.PaymentIntent, error) {
	return payment.PaymentIntent{}, payment.ErrPaymentNotFound
}
func (unitStubRepo) WithTx(_ context.Context, fn func(pgx.Tx) error) error {
	return fn(nil)
}

// stubWebhookConfirmer returns a fixed PaymentEvent regardless of input.
type stubWebhookConfirmer struct {
	ev  payment.PaymentEvent
	err error
}

func (s *stubWebhookConfirmer) ConfirmWebhook(_ context.Context, _ []byte, _ string) (payment.PaymentEvent, error) {
	return s.ev, s.err
}

// TestSipayWebhook_UnknownEventTypeReturnsError verifies that when ConfirmWebhook
// returns an event type not in knownPaymentEventTypes, the handler responds 400
// and does NOT call outbox.Insert (i.e., no outbox row is written).
func TestSipayWebhook_UnknownEventTypeReturnsError(t *testing.T) {
	confirmer := &stubWebhookConfirmer{
		ev: payment.PaymentEvent{
			Type:        payment.PaymentEventType("ecom.payment.unknown.v1"),
			ProviderRef: "unknown-ref-001",
			AmountMinor: 1000,
			Currency:    "TRY",
		},
	}

	h := sipay.NewWebhookHandlerWithConfirmer(
		confirmer, unitStubRepo{}, panicOnInsertOutbox{}, nil, "TR", "TRY", nil,
	)

	body := []byte(`{"hash_key":"anything"}`)
	req := httptest.NewRequest(http.MethodPost, "/webhooks/sipay", bytes.NewReader(body))
	rr := httptest.NewRecorder()
	h.ServeHTTP(rr, req)

	if rr.Code != http.StatusBadRequest {
		t.Errorf("want 400 BadRequest for unknown event type, got %d", rr.Code)
	}
}
