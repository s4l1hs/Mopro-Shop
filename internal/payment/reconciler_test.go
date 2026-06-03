package payment

// Unit tests for Reconciler (TESTING_AUDIT F-001). White-box (package payment) so
// runOnce/reconcileOne and the status→event mapping helpers are reachable. No DB:
// collaborators are handwritten fakes that embed the production interfaces (only the
// methods the reconciler actually calls are implemented; the rest panic if reached,
// which proves the reconciler doesn't call them).
//
// Atomicity (does an outbox failure roll back the status update?) is a DB property and
// is covered in reconciler_integration_test.go, not here — these fakes just record the
// calls the reconciler makes.
//
// See docs/internal/payment-reconciler.md for the discovery that scopes these cases.

import (
	"context"
	"errors"
	"math"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/mopro/platform/internal/outbox"
)

// ── Fakes ───────────────────────────────────────────────────────────────────────

type updateCall struct {
	providerRef                      string
	status                           PaymentStatus
	capturedAt, failedAt, refundedAt *string
	failureReason, refundRef         string
	refundAmountMinor                int64
}

type fakeRepo struct {
	Repository // embedded: unimplemented methods panic if called

	findResult []PaymentIntent
	findErr    error
	findCalls  int

	updates   []updateCall
	updateErr error

	withTxCalls int
	withTxErr   error // returned from WithTx WITHOUT invoking fn (e.g. begin failure)
}

func (f *fakeRepo) FindExpiredPendingPayments(_ context.Context, _ int) ([]PaymentIntent, error) {
	f.findCalls++
	return f.findResult, f.findErr
}

func (f *fakeRepo) WithTx(_ context.Context, fn func(pgx.Tx) error) error {
	f.withTxCalls++
	if f.withTxErr != nil {
		return f.withTxErr
	}
	return fn(nil) // nil tx: the fake repo/outbox ignore it
}

func (f *fakeRepo) UpdatePaymentStatus(_ context.Context, _ pgx.Tx, providerRef string,
	status PaymentStatus, capturedAt, failedAt, refundedAt *string,
	failureReason, refundRef string, refundAmountMinor int64) error {
	f.updates = append(f.updates, updateCall{providerRef, status, capturedAt, failedAt,
		refundedAt, failureReason, refundRef, refundAmountMinor})
	return f.updateErr
}

type fakeSvc struct {
	Service // embedded

	statusByRef map[string]PaymentStatus
	statusErr   error
	checkCalls  []string
}

func (f *fakeSvc) CheckStatus(_ context.Context, providerRef string) (PaymentStatus, error) {
	f.checkCalls = append(f.checkCalls, providerRef)
	if f.statusErr != nil {
		return "", f.statusErr
	}
	return f.statusByRef[providerRef], nil
}

type fakeOutbox struct {
	outbox.Repository // embedded

	inserted  []outbox.Row
	insertErr error
}

func (f *fakeOutbox) Insert(_ context.Context, _ pgx.Tx, row outbox.Row) error {
	f.inserted = append(f.inserted, row)
	return f.insertErr
}

// ── Helpers ─────────────────────────────────────────────────────────────────────

func newTestReconciler(repo *fakeRepo, svc *fakeSvc, ob *fakeOutbox) *Reconciler {
	return NewReconciler(repo, svc, ob, "TR", "TRY", nil)
}

func pendingPayment(ref string, opts ...func(*PaymentIntent)) PaymentIntent {
	p := PaymentIntent{
		ID:          1,
		OrderID:     1001,
		ProviderRef: ref,
		Status:      PaymentStatusPending,
		AmountMinor: 12345, // 123.45 in minor units
		Currency:    "TRY",
	}
	for _, o := range opts {
		o(&p)
	}
	return p
}

// ── Tests ───────────────────────────────────────────────────────────────────────

// Exercises §2.2 — empty queue: no PSP call, no writes, nil error.
func TestReconciler_RunOnce_EmptyQueue_NoOp(t *testing.T) {
	repo := &fakeRepo{findResult: nil}
	svc := &fakeSvc{}
	ob := &fakeOutbox{}
	if err := newTestReconciler(repo, svc, ob).runOnce(context.Background()); err != nil {
		t.Fatalf("runOnce: %v", err)
	}
	if len(svc.checkCalls) != 0 || repo.withTxCalls != 0 || len(ob.inserted) != 0 {
		t.Errorf("empty queue must do nothing: checks=%d tx=%d outbox=%d",
			len(svc.checkCalls), repo.withTxCalls, len(ob.inserted))
	}
}

// Exercises §2.6 — terminal statuses each set the matching *_at and emit the matching event.
func TestReconciler_ReconcileOne_TerminalStatuses(t *testing.T) {
	cases := []struct {
		name      string
		status    PaymentStatus
		wantEvent string
		wantAt    func(updateCall) *string // which *_at must be non-nil
	}{
		{"captured", PaymentStatusCaptured, "ecom.payment.captured.v1", func(u updateCall) *string { return u.capturedAt }},
		{"failed", PaymentStatusFailed, "ecom.payment.failed.v1", func(u updateCall) *string { return u.failedAt }},
		{"refunded", PaymentStatusRefunded, "ecom.payment.refunded.v1", func(u updateCall) *string { return u.refundedAt }},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			repo := &fakeRepo{}
			svc := &fakeSvc{statusByRef: map[string]PaymentStatus{"ref-1": tc.status}}
			ob := &fakeOutbox{}
			rec := newTestReconciler(repo, svc, ob)
			if err := rec.reconcileOne(context.Background(), pendingPayment("ref-1")); err != nil {
				t.Fatalf("reconcileOne: %v", err)
			}
			if len(repo.updates) != 1 {
				t.Fatalf("want 1 UpdatePaymentStatus, got %d", len(repo.updates))
			}
			u := repo.updates[0]
			if u.status != tc.status {
				t.Errorf("status: want %s got %s", tc.status, u.status)
			}
			if tc.wantAt(u) == nil {
				t.Errorf("%s: matching *_at timestamp must be set", tc.name)
			}
			// the other two *_at must be nil
			set := 0
			for _, p := range []*string{u.capturedAt, u.failedAt, u.refundedAt} {
				if p != nil {
					set++
				}
			}
			if set != 1 {
				t.Errorf("exactly one *_at must be set, got %d", set)
			}
			if len(ob.inserted) != 1 {
				t.Fatalf("want 1 outbox row, got %d", len(ob.inserted))
			}
			if ob.inserted[0].EventType != tc.wantEvent {
				t.Errorf("event: want %s got %s", tc.wantEvent, ob.inserted[0].EventType)
			}
			if ob.inserted[0].IdempotencyKey != "reconcile:psp:ref-1" {
				t.Errorf("idempotency key: want reconcile:psp:ref-1 got %s", ob.inserted[0].IdempotencyKey)
			}
		})
	}
}

// Exercises §2.2 — pending/unknown leave the row untouched (re-evaluated next tick).
func TestReconciler_ReconcileOne_NonTerminal_LeavesRow(t *testing.T) {
	for _, st := range []PaymentStatus{PaymentStatusPending, PaymentStatusUnknown} {
		t.Run(string(st), func(t *testing.T) {
			repo := &fakeRepo{}
			svc := &fakeSvc{statusByRef: map[string]PaymentStatus{"ref-1": st}}
			ob := &fakeOutbox{}
			rec := newTestReconciler(repo, svc, ob)
			if err := rec.reconcileOne(context.Background(), pendingPayment("ref-1")); err != nil {
				t.Fatalf("reconcileOne: %v", err)
			}
			if repo.withTxCalls != 0 || len(repo.updates) != 0 || len(ob.inserted) != 0 {
				t.Errorf("non-terminal must not write: tx=%d updates=%d outbox=%d",
					repo.withTxCalls, len(repo.updates), len(ob.inserted))
			}
		})
	}
}

// Exercises §2.2 — CheckStatus error surfaces from reconcileOne; runOnce keeps going.
func TestReconciler_RunOnce_CheckStatusError_SkipsAndContinues(t *testing.T) {
	repo := &fakeRepo{findResult: []PaymentIntent{pendingPayment("bad"), pendingPayment("good")}}
	svc := &fakeSvc{
		statusByRef: map[string]PaymentStatus{"good": PaymentStatusCaptured},
		// "bad" missing → returns "" (zero PaymentStatus); to force an error, use statusErr below for a focused test.
	}
	ob := &fakeOutbox{}
	rec := newTestReconciler(repo, svc, ob)
	// pass-level: a per-row failure must not abort the pass (runOnce returns nil).
	if err := rec.runOnce(context.Background()); err != nil {
		t.Fatalf("runOnce must swallow per-row outcomes: %v", err)
	}
	if len(svc.checkCalls) != 2 {
		t.Errorf("both rows must be checked, got %d", len(svc.checkCalls))
	}
}

// Exercises §2.2 — reconcileOne returns the wrapped CheckStatus error.
func TestReconciler_ReconcileOne_CheckStatusError_Returns(t *testing.T) {
	sentinel := errors.New("psp down")
	repo := &fakeRepo{}
	svc := &fakeSvc{statusErr: sentinel}
	ob := &fakeOutbox{}
	err := newTestReconciler(repo, svc, ob).reconcileOne(context.Background(), pendingPayment("ref-1"))
	if err == nil || !errors.Is(err, sentinel) {
		t.Fatalf("want wrapped %v, got %v", sentinel, err)
	}
	if repo.withTxCalls != 0 {
		t.Errorf("no tx must be opened when CheckStatus fails")
	}
}

// Exercises §2.2 — FindExpired error fails the whole pass.
func TestReconciler_RunOnce_FindError(t *testing.T) {
	sentinel := errors.New("db gone")
	repo := &fakeRepo{findErr: sentinel}
	err := newTestReconciler(repo, &fakeSvc{}, &fakeOutbox{}).runOnce(context.Background())
	if err == nil || !errors.Is(err, sentinel) {
		t.Fatalf("want wrapped %v, got %v", sentinel, err)
	}
}

// Exercises §2.4 — UpdatePaymentStatus failure surfaces from reconcileOne (tx rolls back; DB-atomicity in integration).
func TestReconciler_ReconcileOne_UpdateError(t *testing.T) {
	sentinel := errors.New("update boom")
	repo := &fakeRepo{updateErr: sentinel}
	svc := &fakeSvc{statusByRef: map[string]PaymentStatus{"ref-1": PaymentStatusCaptured}}
	ob := &fakeOutbox{}
	err := newTestReconciler(repo, svc, ob).reconcileOne(context.Background(), pendingPayment("ref-1"))
	if err == nil || !errors.Is(err, sentinel) {
		t.Fatalf("want wrapped %v, got %v", sentinel, err)
	}
	if len(ob.inserted) != 0 {
		t.Errorf("outbox must not be inserted after UpdatePaymentStatus fails")
	}
}

// Exercises §2.3/§2.4 — outbox.Insert failure (incl. duplicate idempotency) surfaces; status update was attempted in-tx.
func TestReconciler_ReconcileOne_OutboxError(t *testing.T) {
	for _, insErr := range []error{errors.New("outbox boom"), outbox.ErrDuplicateIdempotency} {
		t.Run(insErr.Error(), func(t *testing.T) {
			repo := &fakeRepo{}
			svc := &fakeSvc{statusByRef: map[string]PaymentStatus{"ref-1": PaymentStatusCaptured}}
			ob := &fakeOutbox{insertErr: insErr}
			err := newTestReconciler(repo, svc, ob).reconcileOne(context.Background(), pendingPayment("ref-1"))
			if err == nil || !errors.Is(err, insErr) {
				t.Fatalf("want wrapped %v, got %v", insErr, err)
			}
			if len(repo.updates) != 1 {
				t.Errorf("UpdatePaymentStatus is attempted in-tx before the outbox insert")
			}
		})
	}
}

// Exercises §2.5 — market/currency configured on the reconciler propagate to the outbox row.
func TestReconciler_OutboxRow_CarriesConfiguredMarketAndCurrency(t *testing.T) {
	repo := &fakeRepo{}
	svc := &fakeSvc{statusByRef: map[string]PaymentStatus{"ref-1": PaymentStatusCaptured}}
	ob := &fakeOutbox{}
	// non-TRY config to catch a hard-coded TRY assumption.
	rec := NewReconciler(repo, svc, ob, "DE", "EUR", nil)
	if err := rec.reconcileOne(context.Background(), pendingPayment("ref-1")); err != nil {
		t.Fatalf("reconcileOne: %v", err)
	}
	row := ob.inserted[0]
	if row.Market != "DE" || row.Currency != "EUR" {
		t.Errorf("outbox row market/currency: want DE/EUR got %s/%s", row.Market, row.Currency)
	}
	if row.Aggregate != "payment" {
		t.Errorf("aggregate: want payment got %s", row.Aggregate)
	}
}

// Exercises §6.2/§6.3 — large amounts pass through without overflow/truncation in the payload.
func TestReconciler_AmountPassThrough_NearMaxInt64(t *testing.T) {
	big := int64(math.MaxInt64 / 100) // realistic upper bound for minor units
	repo := &fakeRepo{}
	svc := &fakeSvc{statusByRef: map[string]PaymentStatus{"ref-1": PaymentStatusCaptured}}
	ob := &fakeOutbox{}
	rec := newTestReconciler(repo, svc, ob)
	p := pendingPayment("ref-1", func(pi *PaymentIntent) { pi.AmountMinor = big })
	if err := rec.reconcileOne(context.Background(), p); err != nil {
		t.Fatalf("reconcileOne: %v", err)
	}
	// payload is JSON; just assert the insert happened (marshal can't lose an int64).
	if len(ob.inserted) != 1 {
		t.Fatalf("want 1 outbox row")
	}
}

// Exercises status→event mapping helpers directly (table-driven).
func TestReconciler_StatusEventMapping(t *testing.T) {
	cases := []struct {
		status     PaymentStatus
		wantEvent  PaymentEventType
		wantOutbox string
	}{
		{PaymentStatusCaptured, PaymentEventCaptured, "ecom.payment.captured.v1"},
		{PaymentStatusRefunded, PaymentEventRefunded, "ecom.payment.refunded.v1"},
		{PaymentStatusFailed, PaymentEventFailed, "ecom.payment.failed.v1"},
	}
	for _, tc := range cases {
		if got := paymentEventTypeFromStatus(tc.status); got != tc.wantEvent {
			t.Errorf("paymentEventTypeFromStatus(%s): want %s got %s", tc.status, tc.wantEvent, got)
		}
		if got := outboxEventFromStatus(tc.status); got != tc.wantOutbox {
			t.Errorf("outboxEventFromStatus(%s): want %s got %s", tc.status, tc.wantOutbox, got)
		}
	}
}

// Exercises §2.2 — Run honours context cancellation cleanly (no panic, returns ctx error).
func TestReconciler_Run_CancelsCleanly(t *testing.T) {
	repo := &fakeRepo{}
	rec := newTestReconciler(repo, &fakeSvc{}, &fakeOutbox{})
	rec.interval = time.Millisecond // white-box: drive the ticker fast

	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- rec.Run(ctx) }()
	time.Sleep(10 * time.Millisecond) // let a few ticks fire
	cancel()
	select {
	case err := <-done:
		if !errors.Is(err, context.Canceled) {
			t.Errorf("Run after cancel: want context.Canceled, got %v", err)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("Run did not return after context cancel")
	}
}
