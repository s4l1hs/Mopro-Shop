//go:build integration

package cashback_test

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/mopro/platform/internal/cashback"
	"github.com/mopro/platform/internal/outbox"
	"github.com/mopro/platform/internal/wallet"
)

// ── infrastructure ────────────────────────────────────────────────────────────

const cronTestDSN = "postgres://ledger_admin:test123@localhost:6434/mopro_ledger"

func cronTestDSNFromEnv() string {
	if v := os.Getenv("LEDGER_TEST_DSN"); v != "" {
		return v
	}
	return cronTestDSN
}

func cronTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	pool, err := pgxpool.New(context.Background(), cronTestDSNFromEnv())
	if err != nil {
		t.Fatalf("cronTestPool: %v", err)
	}
	if err := pool.Ping(context.Background()); err != nil {
		t.Fatalf("cronTestPool ping: %v (is pg-test on port 6434 running?)", err)
	}
	t.Cleanup(pool.Close)
	return pool
}

func newCronTestSvc(t *testing.T, pool *pgxpool.Pool) cashback.Service {
	t.Helper()
	repo := cashback.NewRepository(pool)
	outboxRepo := outbox.NewRepository("wallet_schema.outbox")
	walletRepo := wallet.NewRepository(pool)
	walletOutbox := outbox.NewRepository("wallet_schema.outbox")
	walletSvc := wallet.NewService(walletRepo, walletOutbox, slog.Default())
	return cashback.NewService(repo, outboxRepo, nil, "TRY_COIN", walletSvc, slog.Default(), nil)
}

// seedCronPlan inserts a v8 cashback plan directly into the test DB.
// Values satisfy the DB CHECK constraint: (total_months-1)*monthly_amount_minor + monthly_amount_last_minor = price_minor.
// Returns the plan ID.
//
// Chosen seed values (T=31, M=500, M_last=600, price=15600):
//
//	price_minor=15600, commission_bps=5000 → T=31, M=500, M_last=600
//	Invariant: 30*500 + 600 = 15600 ✓
func seedCronPlan(t *testing.T, pool *pgxpool.Pool, userID int64, currency string, startDate time.Time, status string) int64 {
	t.Helper()
	uniqueID := cronUniqueID()
	var id int64
	err := pool.QueryRow(context.Background(), `
		INSERT INTO cashback_schema.plans
		    (order_id, user_id, monthly_amount_minor, currency,
		     reference_interest_rate_bps, start_date, status,
		     delivered_at, market, commission_snapshot, idempotency_key,
		     price_minor, commission_bps, total_months, monthly_amount_last_minor)
		VALUES ($1, $2, 500, $3, 0, $4, $5,
		        now()-interval '5 days', 'TR', '[]'::jsonb, $6,
		        15600, 5000, 31, 600)
		RETURNING id`,
		uniqueID, userID, currency, startDate.Format("2006-01-02"), status,
		fmt.Sprintf("cron:test:plan:%d", uniqueID),
	).Scan(&id)
	if err != nil {
		t.Fatalf("seedCronPlan: %v", err)
	}
	return id
}

// cronUniqueID produces a globally unique int64 per call (epoch-ms base).
var (
	cronIDBase    = time.Now().UnixMilli()
	cronIDCounter int64
)

func cronUniqueID() int64 {
	n := atomic.AddInt64(&cronIDCounter, 1)
	return cronIDBase*1_000_000 + n
}

// planPaymentsMade returns the current payments_made counter for the given plan.
func planPaymentsMade(t *testing.T, pool *pgxpool.Pool, planID int64) int {
	t.Helper()
	var n int
	_ = pool.QueryRow(context.Background(),
		`SELECT payments_made FROM cashback_schema.plans WHERE id=$1`,
		planID).Scan(&n)
	return n
}

func outboxEventType(t *testing.T, pool *pgxpool.Pool, idempotencyKey string) string {
	t.Helper()
	var et string
	_ = pool.QueryRow(context.Background(),
		`SELECT event_type FROM wallet_schema.outbox WHERE idempotency_key=$1`,
		idempotencyKey).Scan(&et)
	return et
}

func testAsOf() time.Time {
	return time.Date(2026, 1, 31, 23, 59, 0, 0, time.UTC)
}

// ── tests ──────────────────────────────────────────────────────────────────────

func TestCronIntegration_HappyPath(t *testing.T) {
	pool := cronTestPool(t)
	svc := newCronTestSvc(t, pool)
	ctx := context.Background()

	userID := cronUniqueID()
	planID := seedCronPlan(t, pool, userID, "TRY_COIN", time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC), "active")

	res, err := svc.PayMonthlyInstallments(ctx, testAsOf())
	if err != nil {
		t.Fatalf("PayMonthlyInstallments: %v", err)
	}
	if res.Processed < 1 {
		t.Fatalf("want processed >= 1, got %d (failed=%d skipped=%d)", res.Processed, res.Failed, res.Skipped)
	}
	if planPaymentsMade(t, pool, planID) != 1 {
		t.Errorf("payments_made should be 1 after first run for plan=%d", planID)
	}
	t.Logf("PASS: processed=%d skipped=%d failed=%d retries=%d", res.Processed, res.Skipped, res.Failed, res.Retries)
}

func TestCronIntegration_Idempotent(t *testing.T) {
	pool := cronTestPool(t)
	svc := newCronTestSvc(t, pool)
	ctx := context.Background()

	userID := cronUniqueID()
	planID := seedCronPlan(t, pool, userID, "TRY_COIN", time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC), "active")

	_, err := svc.PayMonthlyInstallments(ctx, testAsOf())
	if err != nil {
		t.Fatalf("PayMonthlyInstallments #1: %v", err)
	}
	if planPaymentsMade(t, pool, planID) != 1 {
		t.Fatalf("plan %d: want payments_made=1 after first run", planID)
	}

	_, err = svc.PayMonthlyInstallments(ctx, testAsOf())
	if err != nil {
		t.Fatalf("PayMonthlyInstallments #2: %v", err)
	}
	// After 2nd run for same runDate, next due = start_date+1month = 2026-02-01 > testAsOf(2026-01-31).
	// Plan must NOT be picked up again.
	if planPaymentsMade(t, pool, planID) != 1 {
		t.Errorf("idempotency violated: want payments_made=1 after second run, got %d", planPaymentsMade(t, pool, planID))
	}
}

func TestCronIntegration_PlanNotYetDue_Excluded(t *testing.T) {
	pool := cronTestPool(t)
	svc := newCronTestSvc(t, pool)
	ctx := context.Background()

	userID := cronUniqueID()
	// start_date is in the future relative to testAsOf()
	futureStart := testAsOf().AddDate(0, 2, 0)
	planID := seedCronPlan(t, pool, userID, "TRY_COIN", futureStart, "active")

	svc.PayMonthlyInstallments(ctx, testAsOf()) //nolint:errcheck
	if planPaymentsMade(t, pool, planID) != 0 {
		t.Errorf("plan %d (future start_date) should NOT be processed", planID)
	}
}

func TestCronIntegration_CancelledPlan_Excluded(t *testing.T) {
	pool := cronTestPool(t)
	svc := newCronTestSvc(t, pool)
	ctx := context.Background()

	userID := cronUniqueID()
	planID := seedCronPlan(t, pool, userID, "TRY_COIN", time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC), "cancelled")

	svc.PayMonthlyInstallments(ctx, testAsOf()) //nolint:errcheck
	if planPaymentsMade(t, pool, planID) != 0 {
		t.Errorf("cancelled plan %d should NOT be processed", planID)
	}
}

func TestCronIntegration_AlreadyPaid_Excluded(t *testing.T) {
	pool := cronTestPool(t)
	svc := newCronTestSvc(t, pool)
	ctx := context.Background()

	userID := cronUniqueID()
	planID := seedCronPlan(t, pool, userID, "TRY_COIN", time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC), "active")

	// Stamp payments_made=1 so next due date (start_date+1month=2026-02-01) > testAsOf(2026-01-31).
	if _, err := pool.Exec(ctx,
		`UPDATE cashback_schema.plans SET payments_made=1 WHERE id=$1`, planID); err != nil {
		t.Fatalf("stamp payments_made: %v", err)
	}

	svc.PayMonthlyInstallments(ctx, testAsOf()) //nolint:errcheck
	if planPaymentsMade(t, pool, planID) != 1 {
		t.Errorf("already-paid plan %d should NOT be incremented again, want 1 got %d",
			planID, planPaymentsMade(t, pool, planID))
	}
}

func TestCronIntegration_WalletFrozen_Skipped(t *testing.T) {
	pool := cronTestPool(t)
	ctx := context.Background()

	repo := cashback.NewRepository(pool)
	outboxRepo := outbox.NewRepository("wallet_schema.outbox")
	walletRepo := wallet.NewRepository(pool)
	walletOutbox := outbox.NewRepository("wallet_schema.outbox")
	walletSvc := wallet.NewService(walletRepo, walletOutbox, slog.Default())

	userID := cronUniqueID()
	planID := seedCronPlan(t, pool, userID, "TRY_COIN", time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC), "active")

	walletID, err := walletSvc.OpenOrFindUserWallet(ctx, userID, "TRY_COIN")
	if err != nil {
		t.Fatalf("OpenOrFindUserWallet: %v", err)
	}
	if _, err := pool.Exec(ctx,
		`UPDATE wallet_schema.accounts SET status='frozen' WHERE id=$1`, walletID); err != nil {
		t.Fatalf("freeze wallet: %v", err)
	}

	svc := cashback.NewService(repo, outboxRepo, nil, "TRY_COIN", walletSvc, slog.Default(), nil)
	res, err := svc.PayMonthlyInstallments(ctx, testAsOf())
	if err != nil {
		t.Fatalf("PayMonthlyInstallments: %v", err)
	}
	if planPaymentsMade(t, pool, planID) != 0 {
		t.Errorf("frozen wallet plan %d should be skipped, payments_made should stay 0", planID)
	}
	_ = res
}

func TestCronIntegration_OutboxSinglePayload(t *testing.T) {
	pool := cronTestPool(t)
	svc := newCronTestSvc(t, pool)
	ctx := context.Background()

	userID := cronUniqueID()
	planID := seedCronPlan(t, pool, userID, "TRY_COIN", time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC), "active")

	_, err := svc.PayMonthlyInstallments(ctx, testAsOf())
	if err != nil {
		t.Fatalf("PayMonthlyInstallments: %v", err)
	}
	if planPaymentsMade(t, pool, planID) != 1 {
		t.Fatalf("plan %d: payments_made should be 1", planID)
	}

	// Exactly 1 outbox row for this plan's installment 1 idempotency key.
	idemKey := fmt.Sprintf("cashback:%d:installment:1", planID)
	var obCount int
	pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM wallet_schema.outbox WHERE idempotency_key=$1`, idemKey).Scan(&obCount)
	if obCount != 1 {
		t.Errorf("want exactly 1 outbox row, got %d (key=%s)", obCount, idemKey)
	}

	et := outboxEventType(t, pool, idemKey)
	if et != "fin.cashback.payment.posted.v1" {
		t.Errorf("outbox event_type = %q, want fin.cashback.payment.posted.v1", et)
	}
}

func TestCronIntegration_DoubleEntryInvariant(t *testing.T) {
	pool := cronTestPool(t)
	svc := newCronTestSvc(t, pool)
	ctx := context.Background()

	netBefore := netTryCoinBalance(t, pool)

	userID := cronUniqueID()
	seedCronPlan(t, pool, userID, "TRY_COIN", time.Date(2026, 2, 1, 0, 0, 0, 0, time.UTC), "active")

	asOf := time.Date(2026, 2, 28, 23, 59, 0, 0, time.UTC)
	_, err := svc.PayMonthlyInstallments(ctx, asOf)
	if err != nil {
		t.Fatalf("PayMonthlyInstallments: %v", err)
	}

	netAfter := netTryCoinBalance(t, pool)
	if netAfter != netBefore {
		t.Errorf("D=C invariant violated: net TRY_COIN before=%d after=%d", netBefore, netAfter)
	}
}

func TestCronIntegration_ConcurrentRunMonth(t *testing.T) {
	pool := cronTestPool(t)
	ctx := context.Background()

	asOf := time.Date(2026, 3, 31, 23, 59, 0, 0, time.UTC)

	userID := cronUniqueID()
	planID := seedCronPlan(t, pool, userID, "TRY_COIN", time.Date(2026, 3, 1, 0, 0, 0, 0, time.UTC), "active")

	const goroutines = 5
	var wg sync.WaitGroup
	for i := 0; i < goroutines; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			svc := newCronTestSvc(t, pool)
			svc.PayMonthlyInstallments(ctx, asOf) //nolint:errcheck
		}()
	}
	wg.Wait()

	// Exactly 1 payment must be made regardless of concurrency.
	if planPaymentsMade(t, pool, planID) != 1 {
		t.Errorf("concurrent PayMonthlyInstallments: want payments_made=1, got %d for plan=%d",
			planPaymentsMade(t, pool, planID), planID)
	}
}

// TestCronIntegration_WalletFrozenAfterCreation_Skipped verifies the Phase 2.2.1
// hotfix: a wallet that was created and then frozen must be classified as Skipped.
func TestCronIntegration_WalletFrozenAfterCreation_Skipped(t *testing.T) {
	pool := cronTestPool(t)
	ctx := context.Background()

	walletRepo := wallet.NewRepository(pool)
	walletOutbox := outbox.NewRepository("wallet_schema.outbox")
	walletSvc := wallet.NewService(walletRepo, walletOutbox, slog.Default())

	userID := cronUniqueID()
	planID := seedCronPlan(t, pool, userID, "TRY_COIN", time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC), "active")

	walletID, err := walletSvc.OpenOrFindUserWallet(ctx, userID, "TRY_COIN")
	if err != nil {
		t.Fatalf("OpenOrFindUserWallet: %v", err)
	}
	if _, err := pool.Exec(ctx,
		`UPDATE wallet_schema.accounts SET status='frozen' WHERE id=$1`, walletID); err != nil {
		t.Fatalf("freeze wallet: %v", err)
	}

	repo := cashback.NewRepository(pool)
	obRepo := outbox.NewRepository("wallet_schema.outbox")
	svc := cashback.NewService(repo, obRepo, nil, "TRY_COIN", walletSvc, slog.Default(), nil)

	res, err := svc.PayMonthlyInstallments(ctx, testAsOf())
	if err != nil {
		t.Fatalf("PayMonthlyInstallments: %v", err)
	}
	if res.Failed != 0 {
		t.Errorf("want Failed=0 for frozen wallet, got %d", res.Failed)
	}
	if res.Skipped < 1 {
		t.Errorf("want Skipped>=1, got %d (plan=%d)", res.Skipped, planID)
	}
	if planPaymentsMade(t, pool, planID) != 0 {
		t.Errorf("no payment must be made for frozen wallet plan=%d", planID)
	}
	t.Logf("PASS: processed=%d skipped=%d failed=%d", res.Processed, res.Skipped, res.Failed)
}

// TestCronIntegration_SerializableRetryOnConflict verifies that two concurrent
// PayMonthlyInstallments goroutines processing plans for the same user both succeed.
func TestCronIntegration_SerializableRetryOnConflict(t *testing.T) {
	pool := cronTestPool(t)
	ctx := context.Background()

	asOf := time.Date(2026, 5, 31, 23, 59, 0, 0, time.UTC)

	userID := cronUniqueID()
	planID1 := seedCronPlan(t, pool, userID, "TRY_COIN", time.Date(2026, 5, 1, 0, 0, 0, 0, time.UTC), "active")
	planID2 := seedCronPlan(t, pool, userID, "TRY_COIN", time.Date(2026, 5, 1, 0, 0, 0, 0, time.UTC), "active")

	barrier := make(chan struct{})
	var wg sync.WaitGroup
	var totalFailed int64
	for i := 0; i < 2; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			<-barrier
			svc := newCronTestSvc(t, pool)
			res, _ := svc.PayMonthlyInstallments(ctx, asOf)
			atomic.AddInt64(&totalFailed, int64(res.Failed))
		}()
	}
	close(barrier)
	wg.Wait()

	if planPaymentsMade(t, pool, planID1) != 1 {
		t.Errorf("plan1=%d: want payments_made=1", planID1)
	}
	if planPaymentsMade(t, pool, planID2) != 1 {
		t.Errorf("plan2=%d: want payments_made=1", planID2)
	}
	if totalFailed > 0 {
		t.Errorf("want totalFailed=0 across goroutines, got %d", totalFailed)
	}

	netAfter := netTryCoinBalance(t, pool)
	_ = netAfter
	t.Logf("PASS: plan1=%d plan2=%d totalFailed=%d", planID1, planID2, totalFailed)
}

// ── helpers ───────────────────────────────────────────────────────────────────

func netTryCoinBalance(t *testing.T, pool *pgxpool.Pool) int64 {
	t.Helper()
	var net int64
	err := pool.QueryRow(context.Background(), `
		SELECT COALESCE(SUM(CASE WHEN le.direction='D' THEN le.amount_minor ELSE -le.amount_minor END), 0)
		FROM wallet_schema.ledger_entries le
		JOIN wallet_schema.accounts a ON a.id = le.account_id
		WHERE a.currency = 'TRY_COIN'`).Scan(&net)
	if err != nil {
		t.Fatalf("netTryCoinBalance: %v", err)
	}
	return net
}
