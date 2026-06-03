//go:build integration

package payment

// Integration tests for Reconciler (TESTING_AUDIT F-001) against a real Postgres.
// Uses the REAL payment.Repository + REAL outbox.Repository; only the PSP boundary is
// faked (fakeSvc, defined in reconciler_test.go — both files compile under -tags=integration).
//
// These cover what unit tests can't: DB-level atomicity (a failed outbox insert rolls back
// the status update) and concurrency safety (two passes over the same row → exactly one
// event, via the outbox idempotency_key UNIQUE constraint — see docs/internal/payment-reconciler.md §2.3).
//
// Harness mirrors internal/order/integration_test.go: ORDER_TEST_DSN (default the
// e2e-test-up pg-ecom-e2e on :6435), self-contained DROP+CREATE schema in TestMain.

import (
	"context"
	"fmt"
	"os"
	"sync"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/mopro/platform/internal/outbox"
)

const defaultPaymentTestDSN = "postgres://ecom_admin:test123@localhost:6435/mopro_ecom"

var integPaymentPool *pgxpool.Pool

func TestMain(m *testing.M) {
	dsn := os.Getenv("ORDER_TEST_DSN")
	if dsn == "" {
		dsn = defaultPaymentTestDSN
	}
	ctx := context.Background()
	var err error
	integPaymentPool, err = pgxpool.New(ctx, dsn)
	if err != nil {
		fmt.Fprintf(os.Stderr, "payment integration: cannot create pool: %v\n", err)
		os.Exit(1)
	}
	if err := integPaymentPool.Ping(ctx); err != nil {
		fmt.Fprintf(os.Stderr, "payment integration: postgres not reachable at %s: %v\n", dsn, err)
		os.Exit(1)
	}
	if err := setupPaymentSchema(ctx, integPaymentPool); err != nil {
		fmt.Fprintf(os.Stderr, "payment integration: schema setup failed: %v\n", err)
		os.Exit(1)
	}
	code := m.Run()
	integPaymentPool.Close()
	os.Exit(code)
}

// setupPaymentSchema creates a self-contained minimal order_schema.payments + outbox.
// Columns match deploy/postgres-ecom/init/{70-payments,60-outbox}.sql + migration 0062's
// expires_at. The orders FK is dropped (reconciler never touches orders) to keep the
// harness focused.
func setupPaymentSchema(ctx context.Context, pool *pgxpool.Pool) error {
	_, err := pool.Exec(ctx, `
CREATE SCHEMA IF NOT EXISTS order_schema;
DROP TABLE IF EXISTS order_schema.payments CASCADE;
DROP TABLE IF EXISTS order_schema.outbox CASCADE;

CREATE TABLE order_schema.payments (
    id                  BIGSERIAL PRIMARY KEY,
    order_id            BIGINT      NOT NULL,
    idempotency_key     TEXT        NOT NULL,
    provider            TEXT        NOT NULL DEFAULT 'sipay',
    provider_ref        TEXT        NOT NULL DEFAULT '',
    provider_order_no   TEXT        NOT NULL DEFAULT '',
    status              TEXT        NOT NULL DEFAULT 'pending',
    amount_minor        BIGINT      NOT NULL,
    currency            TEXT        NOT NULL,
    captured_at         TIMESTAMPTZ,
    failed_at           TIMESTAMPTZ,
    failure_reason      TEXT        NOT NULL DEFAULT '',
    refunded_at         TIMESTAMPTZ,
    refund_ref          TEXT        NOT NULL DEFAULT '',
    refund_amount_minor BIGINT      NOT NULL DEFAULT 0,
    raw_response        JSONB,
    expires_at          TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT payments_idempotency_key_uq UNIQUE (idempotency_key)
);

CREATE TABLE order_schema.outbox (
    id              BIGSERIAL PRIMARY KEY,
    aggregate       TEXT NOT NULL,
    event_type      TEXT NOT NULL,
    payload         JSONB NOT NULL,
    idempotency_key TEXT NOT NULL UNIQUE,
    trace_id        TEXT,
    span_id         TEXT,
    market          TEXT NOT NULL,
    currency        TEXT NOT NULL,
    published_at    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);`)
	return err
}

func truncatePaymentTables(t *testing.T) {
	t.Helper()
	if _, err := integPaymentPool.Exec(context.Background(),
		`TRUNCATE order_schema.payments, order_schema.outbox RESTART IDENTITY`); err != nil {
		t.Fatalf("truncate: %v", err)
	}
}

// seedExpiredPending inserts a pending payment whose expires_at is well past the
// reconciler's 2-minute buffer, so FindExpiredPendingPayments will return it.
func seedExpiredPending(t *testing.T, ref string) {
	t.Helper()
	_, err := integPaymentPool.Exec(context.Background(),
		`INSERT INTO order_schema.payments
		   (order_id, idempotency_key, provider, provider_ref, status, amount_minor, currency, expires_at)
		 VALUES ($1,$2,'sipay',$3,'pending',$4,'TRY', NOW() - INTERVAL '10 minutes')`,
		1001, ref, ref, 12345)
	if err != nil {
		t.Fatalf("seed %s: %v", ref, err)
	}
}

func paymentStatus(t *testing.T, ref string) (status string, capturedAt *time.Time) {
	t.Helper()
	err := integPaymentPool.QueryRow(context.Background(),
		`SELECT status, captured_at FROM order_schema.payments WHERE provider_ref=$1`, ref).
		Scan(&status, &capturedAt)
	if err != nil {
		t.Fatalf("read status %s: %v", ref, err)
	}
	return status, capturedAt
}

func outboxCount(t *testing.T, key string) int {
	t.Helper()
	var n int
	if err := integPaymentPool.QueryRow(context.Background(),
		`SELECT count(*) FROM order_schema.outbox WHERE idempotency_key=$1`, key).Scan(&n); err != nil {
		t.Fatalf("outbox count %s: %v", key, err)
	}
	return n
}

func newIntegReconciler(svc Service) *Reconciler {
	return NewReconciler(
		NewRepository(integPaymentPool),
		svc,
		outbox.NewRepository("order_schema.outbox"),
		"TR", "TRY", nil,
	)
}

// Exercises §2.2/§2.6 — an expired pending payment that the PSP reports captured is
// advanced to captured with captured_at set and exactly one outbox event emitted.
func TestIntegration_Reconciler_CapturesExpiredPending(t *testing.T) {
	truncatePaymentTables(t)
	seedExpiredPending(t, "ref-cap")
	rec := newIntegReconciler(&fakeSvc{statusByRef: map[string]PaymentStatus{"ref-cap": PaymentStatusCaptured}})

	if err := rec.runOnce(context.Background()); err != nil {
		t.Fatalf("runOnce: %v", err)
	}
	status, capturedAt := paymentStatus(t, "ref-cap")
	if status != "captured" {
		t.Errorf("status: want captured, got %s", status)
	}
	if capturedAt == nil {
		t.Errorf("captured_at must be set")
	}
	if n := outboxCount(t, "reconcile:psp:ref-cap"); n != 1 {
		t.Errorf("want exactly 1 outbox event, got %d", n)
	}
}

// Exercises §2.2 — a pending payment not yet past expiry is NOT picked up.
func TestIntegration_Reconciler_LeavesNonExpired(t *testing.T) {
	truncatePaymentTables(t)
	_, err := integPaymentPool.Exec(context.Background(),
		`INSERT INTO order_schema.payments
		   (order_id, idempotency_key, provider, provider_ref, status, amount_minor, currency, expires_at)
		 VALUES (1001,'ref-fresh','sipay','ref-fresh','pending',12345,'TRY', NOW() + INTERVAL '30 minutes')`)
	if err != nil {
		t.Fatalf("seed: %v", err)
	}
	rec := newIntegReconciler(&fakeSvc{statusByRef: map[string]PaymentStatus{"ref-fresh": PaymentStatusCaptured}})
	if err := rec.runOnce(context.Background()); err != nil {
		t.Fatalf("runOnce: %v", err)
	}
	if status, _ := paymentStatus(t, "ref-fresh"); status != "pending" {
		t.Errorf("non-expired payment must stay pending, got %s", status)
	}
	if n := outboxCount(t, "reconcile:psp:ref-fresh"); n != 0 {
		t.Errorf("no event expected for non-expired payment, got %d", n)
	}
}

// Exercises §2.3/§2.4 — DB atomicity: if the outbox insert hits the idempotency UNIQUE
// (a duplicate of a prior reconcile), the whole tx rolls back — the status update is
// undone too. Proves the reconciler can't half-apply (status moved but no event, or vice versa).
func TestIntegration_Reconciler_OutboxDuplicate_RollsBackStatus(t *testing.T) {
	truncatePaymentTables(t)
	seedExpiredPending(t, "ref-dup")
	// Pre-insert the outbox row this reconcile would emit (simulates a prior pass / instance).
	if _, err := integPaymentPool.Exec(context.Background(),
		`INSERT INTO order_schema.outbox (aggregate,event_type,payload,idempotency_key,market,currency)
		 VALUES ('payment','ecom.payment.captured.v1','{}','reconcile:psp:ref-dup','TR','TRY')`); err != nil {
		t.Fatalf("pre-seed outbox: %v", err)
	}
	rec := newIntegReconciler(&fakeSvc{statusByRef: map[string]PaymentStatus{"ref-dup": PaymentStatusCaptured}})

	// reconcileOne returns the duplicate error; runOnce swallows it (logged Warn).
	if err := rec.runOnce(context.Background()); err != nil {
		t.Fatalf("runOnce should swallow per-row dup: %v", err)
	}
	// Atomicity: status must STILL be pending (the UpdatePaymentStatus rolled back with the failed insert).
	if status, _ := paymentStatus(t, "ref-dup"); status != "pending" {
		t.Errorf("status must roll back to pending after outbox dup, got %s", status)
	}
	if n := outboxCount(t, "reconcile:psp:ref-dup"); n != 1 {
		t.Errorf("still exactly 1 outbox row (the pre-seeded one), got %d", n)
	}
}

// Exercises §2.3 — concurrency: two passes over the SAME expired row produce exactly one
// event and a captured status. The outbox idempotency_key UNIQUE is the backstop (there is
// no lease). Run under -race via the integration target.
func TestIntegration_Reconciler_ConcurrentPasses_ExactlyOneEvent(t *testing.T) {
	truncatePaymentTables(t)
	seedExpiredPending(t, "ref-conc")
	mk := func() *Reconciler {
		return newIntegReconciler(&fakeSvc{statusByRef: map[string]PaymentStatus{"ref-conc": PaymentStatusCaptured}})
	}
	var wg sync.WaitGroup
	for i := 0; i < 2; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_ = mk().runOnce(context.Background()) // per-row dup error is swallowed by runOnce
		}()
	}
	wg.Wait()

	if status, _ := paymentStatus(t, "ref-conc"); status != "captured" {
		t.Errorf("final status: want captured, got %s", status)
	}
	if n := outboxCount(t, "reconcile:psp:ref-conc"); n != 1 {
		t.Errorf("exactly one event under concurrency, got %d", n)
	}
}
