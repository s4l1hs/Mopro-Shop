package orderledger

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/mopro/platform/internal/commission"
	"github.com/mopro/platform/internal/ledger"
)

// ── mocks ──────────────────────────────────────────────────────────────────────

type mockWalletPoster struct {
	findAccountID    int64
	findAccountErr   error
	sellerPayableID  int64
	sellerPayableErr error
	postTxnID        int64
	postErr          error
	postCallCount    int
}

func (m *mockWalletPoster) PostInTx(_ context.Context, _ pgx.Tx, _ ledger.PostInput) (int64, error) {
	m.postCallCount++
	return m.postTxnID, m.postErr
}

func (m *mockWalletPoster) FindAccount(_ context.Context, _, _ string) (int64, error) {
	return m.findAccountID, m.findAccountErr
}

func (m *mockWalletPoster) FindOrOpenSellerPayable(_ context.Context, _ int64, _ string) (int64, error) {
	return m.sellerPayableID, m.sellerPayableErr
}

type mockRepository struct{}

func (r *mockRepository) WithTx(_ context.Context, _ pgx.TxIsoLevel, fn func(pgx.Tx) error) error {
	return fn(nil)
}

// mockCaptureRecorder stands in for commission.CaptureRecorder in unit
// tests. Mirrors the field names of the old mockRepository (existing /
// findErr / insertErr / insertCallCount) so the test cases below read
// the same way they did before the seam was extracted.
type mockCaptureRecorder struct {
	existing        *commission.CapturePosting
	findErr         error
	insertErr       error
	insertCallCount int
}

func (r *mockCaptureRecorder) InsertCapturePosting(_ context.Context, _ pgx.Tx, _ commission.CapturePosting) error {
	r.insertCallCount++
	return r.insertErr
}

func (r *mockCaptureRecorder) FindCapturePostingByOrderID(_ context.Context, _ int64) (*commission.CapturePosting, error) {
	return r.existing, r.findErr
}

// ── helpers ────────────────────────────────────────────────────────────────────

func newTestEvent() OrderPaidEvent {
	return OrderPaidEvent{
		OrderID:       101,
		UserID:        1,
		SellerID:      10,
		PaidAt:        time.Now(),
		GrossMinor:    10000,
		ShippingMinor: 0,
		Currency:      "TRY",
		Market:        "TR",
		Items: []PaidItem{
			{CommissionAmountMinor: 1667, KdvAmountMinor: 333, SellerNetMinor: 8000},
		},
	}
}

// ── tests ──────────────────────────────────────────────────────────────────────

func TestPostCapture_HappyPath(t *testing.T) {
	repo := &mockRepository{}
	recorder := &mockCaptureRecorder{}
	wallet := &mockWalletPoster{findAccountID: 1, sellerPayableID: 2, postTxnID: 99}
	svc := NewService(repo, recorder, wallet, nil, nil)

	if err := svc.PostCapture(context.Background(), newTestEvent()); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if wallet.postCallCount != 1 {
		t.Fatalf("PostInTx called %d times, want 1", wallet.postCallCount)
	}
	if recorder.insertCallCount != 1 {
		t.Fatalf("InsertCapturePosting called %d times, want 1", recorder.insertCallCount)
	}
}

func TestPostCapture_Idempotent_AlreadyPosted(t *testing.T) {
	repo := &mockRepository{}
	recorder := &mockCaptureRecorder{
		existing: &commission.CapturePosting{OrderID: 101, TransactionID: 50},
	}
	wallet := &mockWalletPoster{}
	svc := NewService(repo, recorder, wallet, nil, nil)

	if err := svc.PostCapture(context.Background(), newTestEvent()); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	// FindCapturePostingByOrderID returned a hit — PostInTx must NOT be called.
	if wallet.postCallCount != 0 {
		t.Fatalf("PostInTx called %d times, want 0 for idempotent re-delivery", wallet.postCallCount)
	}
}

func TestPostCapture_InsertPosting_AlreadyPosted_Concurrent(t *testing.T) {
	// InsertCapturePosting returns commission.ErrAlreadyPosted (concurrent
	// retry scenario). The service must treat this as success (nil error).
	repo := &mockRepository{}
	recorder := &mockCaptureRecorder{insertErr: commission.ErrAlreadyPosted}
	wallet := &mockWalletPoster{findAccountID: 1, sellerPayableID: 2, postTxnID: 99}
	svc := NewService(repo, recorder, wallet, nil, nil)

	if err := svc.PostCapture(context.Background(), newTestEvent()); err != nil {
		t.Fatalf("expected nil for concurrent ErrAlreadyPosted, got: %v", err)
	}
}

func TestPostCapture_FindAccountError_ReturnsError(t *testing.T) {
	repo := &mockRepository{}
	recorder := &mockCaptureRecorder{}
	wallet := &mockWalletPoster{findAccountErr: errors.New("account not found")}
	svc := NewService(repo, recorder, wallet, nil, nil)

	err := svc.PostCapture(context.Background(), newTestEvent())
	if err == nil {
		t.Fatal("expected error when FindAccount fails")
	}
}

func TestPostCapture_SellerPayableError_ReturnsError(t *testing.T) {
	repo := &mockRepository{}
	recorder := &mockCaptureRecorder{}
	wallet := &mockWalletPoster{findAccountID: 1, sellerPayableErr: errors.New("seller not found")}
	svc := NewService(repo, recorder, wallet, nil, nil)

	err := svc.PostCapture(context.Background(), newTestEvent())
	if err == nil {
		t.Fatal("expected error when FindOrOpenSellerPayable fails")
	}
}

func TestPostCapture_PostInTxError_ReturnsError(t *testing.T) {
	repo := &mockRepository{}
	recorder := &mockCaptureRecorder{}
	wallet := &mockWalletPoster{findAccountID: 1, sellerPayableID: 2, postErr: errors.New("ledger write failed")}
	svc := NewService(repo, recorder, wallet, nil, nil)

	err := svc.PostCapture(context.Background(), newTestEvent())
	if err == nil {
		t.Fatal("expected error when PostInTx fails")
	}
	if recorder.insertCallCount != 0 {
		t.Fatal("InsertCapturePosting must not be called when PostInTx fails")
	}
}

func TestPostCapture_WithShipping_FiveLines(t *testing.T) {
	ev := newTestEvent()
	ev.ShippingMinor = 500
	ev.GrossMinor = 10500

	repo := &mockRepository{}
	recorder := &mockCaptureRecorder{}
	wallet := &mockWalletPoster{findAccountID: 1, sellerPayableID: 2, postTxnID: 99}
	svc := NewService(repo, recorder, wallet, nil, nil)

	if err := svc.PostCapture(context.Background(), ev); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if wallet.postCallCount != 1 {
		t.Fatal("expected PostInTx to be called once")
	}
}
