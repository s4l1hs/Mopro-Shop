//go:build integration

package cashback_test

import (
	"context"
	"encoding/json"
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
	return cashback.NewService(repo, outboxRepo, nil, "TRY_COIN", walletSvc, slog.Default())
}

// seedCronPlan inserts a cashback plan directly into the test DB.
// startDate controls whether the plan is "due" for the given asOf.
// Returns the plan ID.
func seedCronPlan(t *testing.T, pool *pgxpool.Pool, userID int64, currency string, startDate time.Time, status string) int64 {
	t.Helper()
	uniqueID := cronUniqueID()
	var id int64
	err := pool.QueryRow(context.Background(), `
		INSERT INTO cashback_schema.plans
		    (order_id, user_id, monthly_amount_minor, currency,
		     reference_interest_rate_bps, start_date, status,
		     delivered_at, market, commission_snapshot, idempotency_key)
		VALUES ($1, $2, 500, $3, 5000, $4, $5,
		        now()-interval '5 days', 'TR', '[]'::jsonb, $6)
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

func paymentExists(t *testing.T, pool *pgxpool.Pool, planID int64, period int) bool {
	t.Helper()
	var count int
	_ = pool.QueryRow(context.Background(),
		`SELECT COUNT(*) FROM cashback_schema.payments WHERE plan_id=$1 AND period_yyyymm=$2`,
		planID, period).Scan(&count)
	return count > 0
}

func paymentPaid(t *testing.T, pool *pgxpool.Pool, planID int64, period int) bool {
	t.Helper()
	var count int
	_ = pool.QueryRow(context.Background(),
		`SELECT COUNT(*) FROM cashback_schema.payments WHERE plan_id=$1 AND period_yyyymm=$2 AND status='paid'`,
		planID, period).Scan(&count)
	return count > 0
}

func lastDistribPeriod(t *testing.T, pool *pgxpool.Pool, planID int64) *int {
	t.Helper()
	var p *int
	_ = pool.QueryRow(context.Background(),
		`SELECT last_distributed_period FROM cashback_schema.plans WHERE id=$1`,
		planID).Scan(&p)
	return p
}

func outboxEventType(t *testing.T, pool *pgxpool.Pool, idempotencyKey string) string {
	t.Helper()
	var et string
	_ = pool.QueryRow(context.Background(),
		`SELECT event_type FROM wallet_schema.outbox WHERE idempotency_key=$1`,
		idempotencyKey).Scan(&et)
	return et
}

const testPeriod = 202601 // a past period so start_date <= asOf is easy to arrange

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

	res, err := svc.RunMonth(ctx, testPeriod, testAsOf(), "TRY_COIN")
	if err != nil {
		t.Fatalf("RunMonth: %v", err)
	}
	if res.Processed < 1 {
		t.Fatalf("want processed >= 1, got %d (failed=%d skipped=%d)", res.Processed, res.Failed, res.Skipped)
	}
	if !paymentPaid(t, pool, planID, testPeriod) {
		t.Errorf("payment row is not 'paid' for plan=%d period=%d", planID, testPeriod)
	}
	p := lastDistribPeriod(t, pool, planID)
	if p == nil || *p != testPeriod {
		t.Errorf("want last_distributed_period=%d, got %v", testPeriod, p)
	}
	t.Logf("PASS: processed=%d skipped=%d failed=%d retries=%d", res.Processed, res.Skipped, res.Failed, res.TotalRetries)
}

func TestCronIntegration_Idempotent(t *testing.T) {
	pool := cronTestPool(t)
	svc := newCronTestSvc(t, pool)
	ctx := context.Background()

	userID := cronUniqueID()
	planID := seedCronPlan(t, pool, userID, "TRY_COIN", time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC), "active")

	res1, err := svc.RunMonth(ctx, testPeriod, testAsOf(), "TRY_COIN")
	if err != nil {
		t.Fatalf("RunMonth #1: %v", err)
	}
	if !paymentPaid(t, pool, planID, testPeriod) {
		t.Fatalf("plan %d: payment not paid after first run", planID)
	}

	res2, err := svc.RunMonth(ctx, testPeriod, testAsOf(), "TRY_COIN")
	if err != nil {
		t.Fatalf("RunMonth #2: %v", err)
	}
	// The plan should be excluded from the second batch (last_distributed_period = testPeriod).
	_ = res1
	_ = res2

	var count int
	pool.QueryRow(ctx, `SELECT COUNT(*) FROM cashback_schema.payments WHERE plan_id=$1 AND period_yyyymm=$2`,
		planID, testPeriod).Scan(&count)
	if count != 1 {
		t.Errorf("idempotency violated: want 1 payment row, got %d", count)
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

	svc.RunMonth(ctx, testPeriod, testAsOf(), "TRY_COIN")
	if paymentExists(t, pool, planID, testPeriod) {
		t.Errorf("plan %d (future start_date) should NOT be processed", planID)
	}
}

func TestCronIntegration_CancelledPlan_Excluded(t *testing.T) {
	pool := cronTestPool(t)
	svc := newCronTestSvc(t, pool)
	ctx := context.Background()

	userID := cronUniqueID()
	planID := seedCronPlan(t, pool, userID, "TRY_COIN", time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC), "cancelled")

	svc.RunMonth(ctx, testPeriod, testAsOf(), "TRY_COIN")
	if paymentExists(t, pool, planID, testPeriod) {
		t.Errorf("cancelled plan %d should NOT be processed", planID)
	}
}

func TestCronIntegration_PeriodAlreadyDistributed_Excluded(t *testing.T) {
	pool := cronTestPool(t)
	svc := newCronTestSvc(t, pool)
	ctx := context.Background()

	userID := cronUniqueID()
	planID := seedCronPlan(t, pool, userID, "TRY_COIN", time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC), "active")

	// Pre-stamp last_distributed_period = testPeriod so it looks already paid.
	_, err := pool.Exec(ctx,
		`UPDATE cashback_schema.plans SET last_distributed_period=$1 WHERE id=$2`,
		testPeriod, planID)
	if err != nil {
		t.Fatalf("stamp last_distributed_period: %v", err)
	}

	svc.RunMonth(ctx, testPeriod, testAsOf(), "TRY_COIN")
	if paymentExists(t, pool, planID, testPeriod) {
		t.Errorf("already-distributed plan %d should NOT produce a new payment", planID)
	}
}

func TestCronIntegration_WalletFrozen_Skipped(t *testing.T) {
	pool := cronTestPool(t)
	ctx := context.Background()

	// Wire the service
	repo := cashback.NewRepository(pool)
	outboxRepo := outbox.NewRepository("wallet_schema.outbox")
	walletRepo := wallet.NewRepository(pool)
	walletOutbox := outbox.NewRepository("wallet_schema.outbox")
	walletSvc := wallet.NewService(walletRepo, walletOutbox, slog.Default())

	userID := cronUniqueID()
	planID := seedCronPlan(t, pool, userID, "TRY_COIN", time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC), "active")

	// Create the wallet account first (OpenOrFindUserWallet), then freeze it.
	walletID, err := walletSvc.OpenOrFindUserWallet(ctx, userID, "TRY_COIN")
	if err != nil {
		t.Fatalf("OpenOrFindUserWallet: %v", err)
	}
	if _, err := pool.Exec(ctx,
		`UPDATE wallet_schema.accounts SET status='frozen' WHERE id=$1`, walletID); err != nil {
		t.Fatalf("freeze wallet: %v", err)
	}

	svc := cashback.NewService(repo, outboxRepo, nil, "TRY_COIN", walletSvc, slog.Default())
	res, err := svc.RunMonth(ctx, testPeriod, testAsOf(), "TRY_COIN")
	if err != nil {
		t.Fatalf("RunMonth: %v", err)
	}
	if paymentExists(t, pool, planID, testPeriod) {
		t.Errorf("frozen wallet plan %d should be skipped, not paid", planID)
	}
	// Skipped count may include other plans; just ensure no payment was written for this plan.
	_ = res
}

func TestCronIntegration_OutboxSinglePayload(t *testing.T) {
	pool := cronTestPool(t)
	svc := newCronTestSvc(t, pool)
	ctx := context.Background()

	userID := cronUniqueID()
	planID := seedCronPlan(t, pool, userID, "TRY_COIN", time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC), "active")

	_, err := svc.RunMonth(ctx, testPeriod, testAsOf(), "TRY_COIN")
	if err != nil {
		t.Fatalf("RunMonth: %v", err)
	}
	if !paymentPaid(t, pool, planID, testPeriod) {
		t.Fatalf("plan %d: payment not paid", planID)
	}

	// Exactly 1 outbox row for this plan's idempotency key.
	idemKey := "cashback:" + int64Str(planID) + ":" + intStr(testPeriod)
	var obCount int
	pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM wallet_schema.outbox WHERE idempotency_key=$1`, idemKey).Scan(&obCount)
	if obCount != 1 {
		t.Errorf("want exactly 1 outbox row, got %d (key=%s)", obCount, idemKey)
	}

	// Event type must be the cashback-specific one (not the generic 'fin.ledger.posted.v1').
	et := outboxEventType(t, pool, idemKey)
	if et != "fin.cashback.payment.posted.v1" {
		t.Errorf("outbox event_type = %q, want fin.cashback.payment.posted.v1", et)
	}

	// Payload must contain metadata with plan_id.
	var payload struct {
		Metadata map[string]string `json:"metadata"`
	}
	var rawPayload []byte
	pool.QueryRow(ctx,
		`SELECT payload FROM wallet_schema.outbox WHERE idempotency_key=$1`, idemKey).Scan(&rawPayload)
	if err := json.Unmarshal(rawPayload, &payload); err != nil {
		t.Fatalf("unmarshal outbox payload: %v", err)
	}
	if payload.Metadata["plan_id"] != int64Str(planID) {
		t.Errorf("metadata.plan_id = %q, want %q", payload.Metadata["plan_id"], int64Str(planID))
	}
}

func TestCronIntegration_DoubleEntryInvariant(t *testing.T) {
	pool := cronTestPool(t)
	svc := newCronTestSvc(t, pool)
	ctx := context.Background()

	period := 202602

	// Capture net TRY_COIN balance before.
	netBefore := netTryCoinBalance(t, pool)

	userID := cronUniqueID()
	seedCronPlan(t, pool, userID, "TRY_COIN", time.Date(2026, 2, 1, 0, 0, 0, 0, time.UTC), "active")

	asOf := time.Date(2026, 2, 28, 23, 59, 0, 0, time.UTC)
	_, err := svc.RunMonth(ctx, period, asOf, "TRY_COIN")
	if err != nil {
		t.Fatalf("RunMonth: %v", err)
	}

	netAfter := netTryCoinBalance(t, pool)
	if netAfter != netBefore {
		t.Errorf("D=C invariant violated: net TRY_COIN before=%d after=%d", netBefore, netAfter)
	}
}

func TestCronIntegration_ConcurrentRunMonth(t *testing.T) {
	pool := cronTestPool(t)
	ctx := context.Background()

	period := 202603
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
			svc.RunMonth(ctx, period, asOf, "TRY_COIN") //nolint:errcheck
		}()
	}
	wg.Wait()

	// Exactly 1 payment row must exist regardless of concurrency.
	var count int
	pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM cashback_schema.payments WHERE plan_id=$1 AND period_yyyymm=$2`,
		planID, period).Scan(&count)
	if count != 1 {
		t.Errorf("concurrent RunMonth: want 1 payment row, got %d for plan=%d", count, planID)
	}
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

func int64Str(n int64) string {
	return strconv64(n)
}

func intStr(n int) string {
	return strconv64(int64(n))
}

func strconv64(n int64) string {
	if n == 0 {
		return "0"
	}
	buf := make([]byte, 0, 20)
	neg := n < 0
	if neg {
		n = -n
	}
	for n > 0 {
		buf = append([]byte{byte('0' + n%10)}, buf...)
		n /= 10
	}
	if neg {
		buf = append([]byte{'-'}, buf...)
	}
	return string(buf)
}
