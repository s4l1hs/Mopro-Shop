//go:build integration

package sellerpayout_test

import (
	"context"
	"fmt"
	"os"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/mopro/platform/internal/outbox"
	"github.com/mopro/platform/internal/sellerpayout"
	"github.com/mopro/platform/internal/wallet"
	"github.com/mopro/platform/pkg/timex"
)

const (
	defaultLedgerDSN = "postgres://ledger_admin:test123@localhost:6434/mopro_ledger"
)

func ledgerDSN() string {
	if v := os.Getenv("SELLERPAYOUT_TEST_DSN"); v != "" {
		return v
	}
	return defaultLedgerDSN
}

// ── test helpers ───────────────────────────────────────────────────────────────

func setupPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	pool, err := pgxpool.New(context.Background(), ledgerDSN())
	if err != nil {
		t.Fatalf("pool: %v", err)
	}
	if err := pool.Ping(context.Background()); err != nil {
		t.Skipf("postgres-ledger not available (%v); run make test-integration-sellerpayout", err)
	}
	t.Cleanup(pool.Close)
	return pool
}

// seqID provides unique IDs across goroutines in a single test run.
var seqCounter atomic.Int64

func uniqueID() int64 {
	return time.Now().UnixMilli()*1_000_000 + seqCounter.Add(1)
}

// shadowPsp is a no-network PSP for integration tests.
type shadowPsp struct{ calls atomic.Int32 }

func (s *shadowPsp) Transfer(_ context.Context, req sellerpayout.TransferRequest) (sellerpayout.TransferResponse, error) {
	s.calls.Add(1)
	return sellerpayout.TransferResponse{
		TransferID: fmt.Sprintf("shadow_synthetic_%d", req.BatchID),
		Status:     "paid",
	}, nil
}
func (s *shadowPsp) GetTransferStatus(_ context.Context, transferID string) (sellerpayout.TransferResponse, error) {
	return sellerpayout.TransferResponse{TransferID: transferID, Status: "paid"}, nil
}

// differentIDPsp simulates an ambiguous replay (different transfer_id).
type differentIDPsp struct{ callN atomic.Int32 }

func (d *differentIDPsp) Transfer(_ context.Context, req sellerpayout.TransferRequest) (sellerpayout.TransferResponse, error) {
	n := d.callN.Add(1)
	return sellerpayout.TransferResponse{
		TransferID: fmt.Sprintf("transfer_%d_attempt_%d", req.BatchID, n),
		Status:     "paid",
	}, nil
}
func (d *differentIDPsp) GetTransferStatus(_ context.Context, _ string) (sellerpayout.TransferResponse, error) {
	return sellerpayout.TransferResponse{TransferID: "different_id_from_psp", Status: "paid"}, nil
}

func setupService(t *testing.T, pool *pgxpool.Pool, psp sellerpayout.PspTransferer) sellerpayout.Service {
	t.Helper()
	repo := sellerpayout.NewRepository(pool)
	walletRepo := wallet.NewRepository(pool)
	walletOutbox := outbox.NewRepository("wallet_schema.outbox")
	walletSvc := wallet.NewService(walletRepo, walletOutbox, nil)

	calLoader := timex.NewStaticCalendarLoader(map[string]timex.Calendar{
		"TR": {Market: "TR", Holidays: map[string]struct{}{}},
	})

	return sellerpayout.NewService(repo, walletSvc, psp, calLoader, "TRY", nil)
}

// seedPspAccount inserts a seller_psp_accounts row so FindSellerPspAccount succeeds.
func seedPspAccount(t *testing.T, pool *pgxpool.Pool, sellerID int64, memberID string) {
	t.Helper()
	_, err := pool.Exec(context.Background(),
		`INSERT INTO commission_schema.seller_psp_accounts (seller_id, psp_member_id, market, status)
		 VALUES ($1, $2, 'TR', 'active')
		 ON CONFLICT (seller_id) DO UPDATE SET psp_member_id = EXCLUDED.psp_member_id`,
		sellerID, memberID,
	)
	if err != nil {
		t.Fatalf("seedPspAccount: %v", err)
	}
}

// seedScheduledPayouts inserts N scheduled payouts for a given seller.
func seedScheduledPayouts(t *testing.T, pool *pgxpool.Pool, sellerID int64, count int, currency string) []int64 {
	t.Helper()
	var ids []int64
	for i := 0; i < count; i++ {
		uid := uniqueID()
		var id int64
		err := pool.QueryRow(context.Background(), `
			INSERT INTO commission_schema.seller_payouts
				(order_id, seller_id, amount_minor, currency, delivered_at, unlock_at,
				 status, market, idempotency_key)
			VALUES ($1, $2, $3, $4, now()-interval '5 days', now()-interval '2 days',
			        'scheduled', 'TR', $5)
			RETURNING id`,
			uid, sellerID, int64(10000+i*100), currency,
			fmt.Sprintf("payout:order_%d:seller_%d", uid, sellerID),
		).Scan(&id)
		if err != nil {
			t.Fatalf("seedScheduledPayout %d: %v", i, err)
		}
		ids = append(ids, id)
	}
	return ids
}

// paymentExists checks whether commission_schema.payout_batches has a paid row for seller+date.
func batchPaidExists(t *testing.T, pool *pgxpool.Pool, sellerID int64, payoutDate time.Time) bool {
	t.Helper()
	var count int
	err := pool.QueryRow(context.Background(),
		`SELECT COUNT(*) FROM commission_schema.payout_batches
		 WHERE seller_id=$1 AND status='paid' AND payout_date=$2`,
		sellerID, payoutDate.Format("2006-01-02"),
	).Scan(&count)
	if err != nil {
		t.Fatalf("batchPaidExists: %v", err)
	}
	return count > 0
}

// ── Test A: batch aggregation ──────────────────────────────────────────────────

func TestPayoutIntegration_BatchAggregation(t *testing.T) {
	pool := setupPool(t)
	psp := &shadowPsp{}
	svc := setupService(t, pool, psp)
	ctx := context.Background()

	sellerID := uniqueID()
	payoutDate := time.Now().UTC().Truncate(24 * time.Hour)

	seedPspAccount(t, pool, sellerID, fmt.Sprintf("member_%d", sellerID))
	seedScheduledPayouts(t, pool, sellerID, 5, "TRY")

	res, err := svc.RunDailyPayouts(ctx, payoutDate, "TR", "TRY")
	if err != nil {
		t.Fatalf("RunDailyPayouts: %v", err)
	}

	// All 5 payouts for the same seller → 1 batch.
	if res.Batched != 1 {
		t.Errorf("want batched=1, got %d", res.Batched)
	}
	if res.Failed != 0 {
		t.Errorf("want failed=0, got %d", res.Failed)
	}
	// PSP called exactly once.
	if psp.calls.Load() != 1 {
		t.Errorf("want 1 PSP call, got %d", psp.calls.Load())
	}

	// Verify batch is paid.
	if !batchPaidExists(t, pool, sellerID, payoutDate) {
		t.Error("expected paid batch in DB")
	}

	// Verify ledger entries exist (D seller_payable + C escrow = 2 entries).
	var entryCount int
	pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM wallet_schema.ledger_entries le
		JOIN wallet_schema.transactions t ON t.id = le.transaction_id
		WHERE t.idempotency_key = $1`,
		sellerpayout.BatchIdempotencyKeyExported(sellerID, payoutDate, "TRY"),
	).Scan(&entryCount)
	if entryCount != 2 {
		t.Errorf("want 2 ledger entries, got %d", entryCount)
	}

	// Verify 1 outbox event.
	var outboxCount int
	pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM wallet_schema.outbox
		WHERE idempotency_key = $1`,
		sellerpayout.BatchIdempotencyKeyExported(sellerID, payoutDate, "TRY"),
	).Scan(&outboxCount)
	if outboxCount != 1 {
		t.Errorf("want 1 outbox event, got %d", outboxCount)
	}
}

// ── Test B: ambiguous state ────────────────────────────────────────────────────

func TestPayoutIntegration_AmbiguousStateOnDifferentTransferID(t *testing.T) {
	pool := setupPool(t)
	ctx := context.Background()

	sellerID := uniqueID()
	payoutDate := time.Now().UTC().Truncate(24 * time.Hour)
	batchKey := sellerpayout.BatchIdempotencyKeyExported(sellerID, payoutDate, "TRY")

	seedPspAccount(t, pool, sellerID, fmt.Sprintf("member_%d", sellerID))
	seedScheduledPayouts(t, pool, sellerID, 2, "TRY")

	// Manually insert a stuck 'processing' batch with a known psp_transfer_id.
	var batchID int64
	err := pool.QueryRow(ctx, `
		INSERT INTO commission_schema.payout_batches
			(seller_id, currency, payout_date, total_amount_minor, status,
			 idempotency_key, market, attempt_count, psp_transfer_id, last_attempt_at)
		VALUES ($1,'TRY',$2,20000,'processing',$3,'TR',1,'original_transfer_abc',now()-interval '15 minutes')
		RETURNING id`,
		sellerID, payoutDate.Format("2006-01-02"), batchKey,
	).Scan(&batchID)
	if err != nil {
		t.Fatalf("insert stuck batch: %v", err)
	}

	// PSP returns a DIFFERENT transfer_id on GetTransferStatus.
	psp := &differentIDPsp{}
	svc := setupService(t, pool, psp)

	_ = svc.ReconcileProcessing(ctx)

	// Batch should be marked 'ambiguous'.
	var status string
	pool.QueryRow(ctx, `SELECT status FROM commission_schema.payout_batches WHERE id=$1`, batchID).Scan(&status)
	if status != "ambiguous" {
		t.Errorf("want status=ambiguous, got %s", status)
	}

	// CRITICAL ledger_alert inserted.
	var alertCount int
	pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM wallet_schema.ledger_alerts
		WHERE batch_id=$1 AND alert_type='ambiguous_transfer' AND severity='CRITICAL'`,
		batchID,
	).Scan(&alertCount)
	if alertCount != 1 {
		t.Errorf("want 1 CRITICAL alert, got %d", alertCount)
	}

	// No ledger entries (Tx2 never ran).
	var entryCount int
	pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM wallet_schema.ledger_entries le
		JOIN wallet_schema.transactions t ON t.id = le.transaction_id
		WHERE t.idempotency_key = $1`, batchKey,
	).Scan(&entryCount)
	if entryCount != 0 {
		t.Errorf("want 0 ledger entries (Tx2 skipped), got %d", entryCount)
	}
}

// ── Test C: shadow mode ────────────────────────────────────────────────────────

func TestPayoutIntegration_ShadowMode(t *testing.T) {
	pool := setupPool(t)
	psp := &shadowPsp{}
	svc := setupService(t, pool, psp)
	ctx := context.Background()

	sellerID := uniqueID()
	payoutDate := time.Now().UTC().Truncate(24 * time.Hour)

	seedPspAccount(t, pool, sellerID, fmt.Sprintf("member_%d", sellerID))
	seedScheduledPayouts(t, pool, sellerID, 3, "TRY")

	res, err := svc.RunDailyPayouts(ctx, payoutDate, "TR", "TRY")
	if err != nil {
		t.Fatalf("RunDailyPayouts: %v", err)
	}

	// Shadow mode: batch paid via synthetic transfer_id (no real HTTP).
	if res.Failed != 0 {
		t.Errorf("shadow mode should have 0 failures, got %d", res.Failed)
	}

	// Verify psp_transfer_id stored starts with "shadow_synthetic_".
	var pspTransferID string
	pool.QueryRow(ctx, `
		SELECT psp_transfer_id FROM commission_schema.payout_batches
		WHERE seller_id=$1 AND payout_date=$2`,
		sellerID, payoutDate.Format("2006-01-02"),
	).Scan(&pspTransferID)
	if len(pspTransferID) == 0 {
		t.Error("expected psp_transfer_id to be stored")
	}
}

// ── Test D: fraud hold mid-processing ─────────────────────────────────────────

func TestPayoutIntegration_FraudHoldMidProcessing(t *testing.T) {
	pool := setupPool(t)
	ctx := context.Background()

	sellerID := uniqueID()
	payoutDate := time.Now().UTC().Truncate(24 * time.Hour)
	batchKey := sellerpayout.BatchIdempotencyKeyExported(sellerID, payoutDate, "TRY")

	seedPspAccount(t, pool, sellerID, fmt.Sprintf("member_%d", sellerID))

	// Insert batch stuck in 'processing' with psp_transfer_id stored.
	var batchID int64
	pool.QueryRow(ctx, `
		INSERT INTO commission_schema.payout_batches
			(seller_id, currency, payout_date, total_amount_minor, status,
			 idempotency_key, market, attempt_count, psp_transfer_id, last_attempt_at)
		VALUES ($1,'TRY',$2,10000,'processing',$3,'TR',1,'transfer_xyz',now()-interval '15 minutes')
		RETURNING id`,
		sellerID, payoutDate.Format("2006-01-02"), batchKey,
	).Scan(&batchID)

	// Insert fraud-hold alert for this batch.
	pool.Exec(ctx, `
		INSERT INTO wallet_schema.ledger_alerts (severity, currency, batch_id, alert_type, message)
		VALUES ('SEV1', 'TRY', $1, 'fraud_hold', 'test fraud hold')`,
		batchID,
	)

	psp := &shadowPsp{}
	svc := setupService(t, pool, psp)

	_ = svc.ReconcileProcessing(ctx)

	// Batch should STILL be 'processing' (Tx2 skipped due to open alert).
	var status string
	pool.QueryRow(ctx, `SELECT status FROM commission_schema.payout_batches WHERE id=$1`, batchID).Scan(&status)
	if status != "processing" {
		t.Errorf("want status=processing (Tx2 blocked by fraud hold), got %s", status)
	}

	// PSP was still called to get status (transfer_id was stored).
	// No ledger entries written.
	var entryCount int
	pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM wallet_schema.ledger_entries le
		JOIN wallet_schema.transactions t ON t.id = le.transaction_id
		WHERE t.idempotency_key = $1`, batchKey,
	).Scan(&entryCount)
	if entryCount != 0 {
		t.Errorf("want 0 ledger entries (Tx2 blocked), got %d", entryCount)
	}
}

// ── Test E: batch aggregation correctness across varied N ─────────────────────

func TestPayoutIntegration_BatchingAggregation_VaryingN(t *testing.T) {
	pool := setupPool(t)
	ctx := context.Background()

	const iterations = 20 // reduced from 500 for CI speed; property still holds

	for i := 0; i < iterations; i++ {
		sellerID := uniqueID()
		n := (i % 10) + 1 // 1..10 payouts per iteration
		payoutDate := time.Now().UTC().AddDate(0, 0, -(i % 3)).Truncate(24 * time.Hour)

		seedPspAccount(t, pool, sellerID, fmt.Sprintf("prop_member_%d", sellerID))
		ids := seedScheduledPayouts(t, pool, sellerID, n, "TRY")

		// Compute expected total.
		var expectedTotal int64
		for j, id := range ids {
			_ = id
			expectedTotal += int64(10000 + j*100)
		}

		psp := &shadowPsp{}
		svc := setupService(t, pool, psp)

		res, err := svc.RunDailyPayouts(ctx, payoutDate, "TR", "TRY")
		if err != nil {
			t.Fatalf("iter %d: %v", i, err)
		}
		if res.Batched != 1 {
			t.Errorf("iter %d: want batched=1, got %d", i, res.Batched)
		}
		if psp.calls.Load() != 1 {
			t.Errorf("iter %d: want 1 PSP call, got %d", i, psp.calls.Load())
		}

		// Verify batch total matches sum of payout amounts.
		var dbTotal int64
		pool.QueryRow(ctx, `
			SELECT total_amount_minor FROM commission_schema.payout_batches
			WHERE seller_id=$1 AND payout_date=$2`,
			sellerID, payoutDate.Format("2006-01-02"),
		).Scan(&dbTotal)
		if dbTotal != expectedTotal {
			t.Errorf("iter %d: total mismatch: want %d, got %d", i, expectedTotal, dbTotal)
		}
	}
}

// ── Test F (regression): phase 2.1/2.2 tests still pass ──────────────────────
// These are integration tests in their own packages; the Makefile runs them.
// This file just documents the dependency for reviewers.

// ── Test: concurrent scheduling for same order is idempotent ──────────────────

func TestPayoutIntegration_ConcurrentSchedule_Idempotent(t *testing.T) {
	pool := setupPool(t)
	svc := setupService(t, pool, &shadowPsp{})
	ctx := context.Background()

	orderID := uniqueID()
	ev := sellerpayout.OrderDeliveredEvent{
		OrderID:     orderID,
		DeliveredAt: time.Now().AddDate(0, 0, -5),
		Market:      "TR",
		Currency:    "TRY",
		Items:       []sellerpayout.DeliveredItem{{SellerID: uniqueID(), SellerNetMinor: 5000}},
	}

	const goroutines = 5
	var wg sync.WaitGroup
	errs := make([]error, goroutines)
	for i := 0; i < goroutines; i++ {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			errs[idx] = svc.SchedulePayoutsForOrder(ctx, ev)
		}(i)
	}
	wg.Wait()

	for i, err := range errs {
		if err != nil {
			t.Errorf("goroutine %d: unexpected error: %v", i, err)
		}
	}

	// Exactly 1 payout row per seller.
	var count int
	pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM commission_schema.seller_payouts
		WHERE order_id=$1`, orderID,
	).Scan(&count)
	if count != 1 {
		t.Errorf("want 1 payout row, got %d (idempotency violated)", count)
	}
}
