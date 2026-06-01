//go:build integration

package cashback_test

import (
	"context"
	"fmt"
	"log/slog"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/leanovate/gopter"
	"github.com/leanovate/gopter/gen"
	"github.com/leanovate/gopter/prop"

	"github.com/mopro/platform/internal/cashback"
	"github.com/mopro/platform/internal/outbox"
	"github.com/mopro/platform/internal/wallet"
)

// propUniqueID produces a unique int64 for property test isolation.
var (
	propBase    = time.Now().UnixMilli() * 2_000_000
	propCounter int64
)

func propUniqueID() int64 { return propBase + atomic.AddInt64(&propCounter, 1) }

func propCronPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	cfg, err := pgxpool.ParseConfig(cronTestDSNFromEnv())
	if err != nil {
		t.Fatalf("propCronPool parse: %v", err)
	}
	// Pin the pool budget so the concurrent-idempotency deadlock repro is
	// deterministic across runners: pgx defaults to max(4, NumCPU), so a 6-core
	// dev box masked what the 2-vCPU CI runner (4 conns) exposed in PR #41. 4 is
	// the canonical repro. With the fix (GetAccountCurrencies reads on the calling
	// tx), the hot payment path needs only one connection per goroutine, so
	// concurrency no longer saturates the budget.
	cfg.MaxConns = 4
	pool, err := pgxpool.NewWithConfig(context.Background(), cfg)
	if err != nil {
		t.Fatalf("propCronPool: %v", err)
	}
	if err := pool.Ping(context.Background()); err != nil {
		t.Fatalf("propCronPool ping: %v", err)
	}
	t.Cleanup(pool.Close)
	return pool
}

func propCronSvc(pool *pgxpool.Pool) cashback.Service {
	repo := cashback.NewRepository(pool)
	ob := outbox.NewRepository("wallet_schema.outbox")
	walletRepo := wallet.NewRepository(pool)
	walletOutbox := outbox.NewRepository("wallet_schema.outbox")
	walletSvc := wallet.NewService(walletRepo, walletOutbox, slog.Default())
	return cashback.NewService(repo, ob, nil, "TRY_COIN", walletSvc, slog.Default(), nil)
}

// seedPropPlan inserts a v8 cashback plan for property tests.
// Uses the same seed values as seedCronPlan: price=15600, bps=5000, T=31, M=500, M_last=600.
func seedPropPlan(t *testing.T, pool *pgxpool.Pool, userID int64, currency string, startDate time.Time) int64 {
	t.Helper()
	uniqueID := propUniqueID()
	var id int64
	err := pool.QueryRow(context.Background(), `
		INSERT INTO cashback_schema.plans
		    (order_id, user_id, monthly_amount_minor, currency,
		     reference_interest_rate_bps, start_date, status,
		     delivered_at, market, commission_snapshot, idempotency_key,
		     price_minor, commission_bps, total_months, monthly_amount_last_minor)
		VALUES ($1, $2, 500, $3, 5000, $4, 'active',
		        now()-interval '5 days', 'TR', '[]'::jsonb, $5,
		        15600, 5000, 31, 600)
		RETURNING id`,
		uniqueID, userID, currency, startDate.Format("2006-01-02"),
		fmt.Sprintf("prop:cron:plan:%d", uniqueID),
	).Scan(&id)
	if err != nil {
		t.Fatalf("seedPropPlan: %v", err)
	}
	return id
}

// ── Property 1: D=C invariant across N PayMonthlyInstallments calls ───────────

func TestCronProperty_DoubleEntryInvariant(t *testing.T) {
	pool := propCronPool(t)
	svc := propCronSvc(pool)
	ctx := context.Background()

	properties := gopter.NewProperties(func() *gopter.TestParameters {
		p := gopter.DefaultTestParameters()
		p.MinSuccessfulTests = 200
		return p
	}())

	properties.Property("D=C invariant holds after PayMonthlyInstallments", prop.ForAll(
		func(monthOffset uint8) bool {
			year := 2026 + int(monthOffset/12)
			month := time.Month(int(monthOffset%12) + 1)
			asOf := time.Date(year, month, 28, 23, 59, 0, 0, time.UTC)

			userID := propUniqueID()
			startDate := time.Date(year, month, 1, 0, 0, 0, 0, time.UTC)
			seedPropPlan(t, pool, userID, "TRY_COIN", startDate)

			netBefore := cronNetBalance(pool, "TRY_COIN")

			if _, err := svc.PayMonthlyInstallments(ctx, asOf); err != nil {
				t.Logf("PayMonthlyInstallments error: %v", err)
				return false
			}

			netAfter := cronNetBalance(pool, "TRY_COIN")
			if netAfter != netBefore {
				t.Logf("D=C violated: before=%d after=%d", netBefore, netAfter)
				return false
			}
			return true
		},
		gen.UInt8Range(0, 23),
	))

	properties.TestingRun(t, gopter.ConsoleReporter(false))
}

// ── Property 2: idempotency ───────────────────────────────────────────────────
// Running PayMonthlyInstallments N times for the same runDate always produces
// exactly 1 payment per plan (payments_made == 1 after N runs).

func TestCronProperty_Idempotency(t *testing.T) {
	pool := propCronPool(t)
	ctx := context.Background()

	asOf := time.Date(2026, 1, 31, 23, 59, 0, 0, time.UTC)

	properties := gopter.NewProperties(func() *gopter.TestParameters {
		p := gopter.DefaultTestParameters()
		p.MinSuccessfulTests = 200
		return p
	}())

	properties.Property("N PayMonthlyInstallments for same runDate → payments_made == 1", prop.ForAll(
		func(repeats uint8) bool {
			if repeats < 2 {
				repeats = 2
			}
			if repeats > 5 {
				repeats = 5
			}

			userID := propUniqueID()
			planID := seedPropPlan(t, pool, userID, "TRY_COIN",
				time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC))

			for i := 0; i < int(repeats); i++ {
				svc := propCronSvc(pool)
				if _, err := svc.PayMonthlyInstallments(ctx, asOf); err != nil {
					t.Logf("PayMonthlyInstallments %d error: %v", i, err)
					return false
				}
			}

			var made int
			pool.QueryRow(ctx,
				`SELECT payments_made FROM cashback_schema.plans WHERE id=$1`,
				planID).Scan(&made)
			if made != 1 {
				t.Logf("idempotency violated: payments_made=%d for plan=%d", made, planID)
				return false
			}
			return true
		},
		gen.UInt8Range(2, 5),
	))

	properties.TestingRun(t, gopter.ConsoleReporter(false))
}

// ── Property 3: balance monotonically increases with N payments ───────────────
// After N PayMonthlyInstallments calls for N consecutive months, the user's
// balance must equal N × monthly_amount_minor.

func TestCronProperty_MonotonicBalance(t *testing.T) {
	pool := propCronPool(t)
	ctx := context.Background()

	properties := gopter.NewProperties(func() *gopter.TestParameters {
		p := gopter.DefaultTestParameters()
		p.MinSuccessfulTests = 200
		return p
	}())

	properties.Property("N monthly runs → balance == N × monthly_amount_minor", prop.ForAll(
		func(n uint8) bool {
			if n == 0 || n > 6 {
				n = 1
			}

			userID := propUniqueID()
			walletRepo := wallet.NewRepository(pool)
			walletOutbox := outbox.NewRepository("wallet_schema.outbox")
			walletSvc := wallet.NewService(walletRepo, walletOutbox, slog.Default())
			walletAcctID, err := walletSvc.OpenOrFindUserWallet(ctx, userID, "TRY_COIN")
			if err != nil {
				t.Logf("OpenOrFindUserWallet: %v", err)
				return false
			}

			const monthlyAmount = int64(500) // matches seedPropPlan's monthly_amount_minor=500
			startDate := time.Date(2025, 12, 1, 0, 0, 0, 0, time.UTC)
			seedPropPlan(t, pool, userID, "TRY_COIN", startDate)

			for i := 0; i < int(n); i++ {
				year := 2026
				month := time.Month(i + 1) // Jan, Feb, ...
				asOf := time.Date(year, month, 28, 23, 59, 0, 0, time.UTC)
				svc := propCronSvc(pool)
				if _, err := svc.PayMonthlyInstallments(ctx, asOf); err != nil {
					t.Logf("PayMonthlyInstallments month=%d: %v", i+1, err)
					return false
				}
			}

			bal, err := walletSvc.GetBalanceStrict(ctx, walletAcctID)
			if err != nil {
				t.Logf("GetBalanceStrict: %v", err)
				return false
			}
			expected := monthlyAmount * int64(n)
			if bal != expected {
				t.Logf("balance mismatch: got=%d want=%d (n=%d amount=%d)", bal, expected, n, monthlyAmount)
				return false
			}
			return true
		},
		gen.UInt8Range(1, 6),
	))

	properties.TestingRun(t, gopter.ConsoleReporter(false))
}

// ── Property 4: concurrent PayMonthlyInstallments → exactly 1 payment per plan ──

func TestCronProperty_ConcurrentIdempotency(t *testing.T) {
	// Verifies the storage-layer idempotency guard added in this PR:
	// UNIQUE(plan_id, period_yyyymm) on cashback_schema.payments serializes
	// concurrent cron racers, and payments_made (now a COUNT-derived cache
	// refreshed from the payments table) tracks reality precisely — including
	// under N concurrent PayMonthlyInstallments calls for the same plan and
	// run period.
	pool := propCronPool(t)
	ctx := context.Background()

	asOf := time.Date(2026, 4, 30, 23, 59, 0, 0, time.UTC)

	properties := gopter.NewProperties(func() *gopter.TestParameters {
		p := gopter.DefaultTestParameters()
		// 20 iterations over the 2–8 goroutine range amply exercises the
		// idempotency property. 100 (the original) over-samples a 7-value range
		// and, at MaxConns=4 with up-to-8-way SERIALIZABLE contention, blew past
		// the 600s package timeout on the 2-vCPU CI runner (super-linear retry
		// contention on 2 CPUs; ~42s locally on 6 cores). The deterministic
		// single-connection contract is pinned separately by
		// TestProperty_PostInTx_SingleConnectionHotPath.
		p.MinSuccessfulTests = 20
		return p
	}())

	properties.Property("G concurrent PayMonthlyInstallments calls → payments_made == 1", prop.ForAll(
		func(goroutines uint8) bool {
			if goroutines < 2 {
				goroutines = 2
			}
			if goroutines > 8 {
				goroutines = 8
			}

			userID := propUniqueID()
			planID := seedPropPlan(t, pool, userID, "TRY_COIN",
				time.Date(2026, 4, 1, 0, 0, 0, 0, time.UTC))

			barrier := make(chan struct{})
			var wgDone sync.WaitGroup
			for i := 0; i < int(goroutines); i++ {
				wgDone.Add(1)
				go func() {
					defer wgDone.Done()
					<-barrier
					svc := propCronSvc(pool)
					svc.PayMonthlyInstallments(ctx, asOf) //nolint:errcheck
				}()
			}
			close(barrier)
			wgDone.Wait()

			var made int
			pool.QueryRow(ctx,
				`SELECT payments_made FROM cashback_schema.plans WHERE id=$1`,
				planID).Scan(&made)
			if made != 1 {
				t.Logf("concurrent idempotency violated: payments_made=%d for plan=%d", made, planID)
				return false
			}
			return true
		},
		gen.UInt8Range(2, 8),
	))

	properties.TestingRun(t, gopter.ConsoleReporter(false))
}

// TestProperty_PostInTx_SingleConnectionHotPath is the regression guard for the
// PR #41 / fix/cashback-pgxpool-deadlock deadlock. It runs the cashback payment
// hot path against a pool of EXACTLY ONE connection:
//
//	PayMonthlyInstallments → WithTx → PostInTx
//	  (checkReadOnly→GetSystemState, GetAccountCurrencies, inserts)
//
// If any read on that path acquires a SECOND pool connection inside the open
// SERIALIZABLE tx, it blocks forever on the 1-conn pool and the context deadline
// fails the test loudly. Success ⟺ the whole hot path uses a single connection.
// This is a stronger, runner-independent guard than the MaxConns=4 concurrent
// test: it pins the contract directly rather than relying on contention timing.
//
// Scope: the non-duplicate hot path only. The idempotent-replay branch
// (GetTransactionByIdempotencyKey) legitimately reads the POOL to see
// concurrently-committed transactions and is intentionally NOT made tx-aware
// (tx-routing it would return not-found under concurrency) — a fresh plan/period
// never hits ErrDuplicateIdempotency, so it isn't exercised here. See
// tool/audit/cashback_deadlock_baseline.md.
//
// If you add a pool read to a function on the PostInTx hot path, this test will
// hang→fail. Route the read through the calling tx (when correctness allows) or
// reconsider the design — don't widen the pool to silence it.
func TestProperty_PostInTx_SingleConnectionHotPath(t *testing.T) {
	cfg, err := pgxpool.ParseConfig(cronTestDSNFromEnv())
	if err != nil {
		t.Fatalf("parse dsn: %v", err)
	}
	cfg.MaxConns = 1 // exactly one — any second-connection acquire on the hot path deadlocks
	pool, err := pgxpool.NewWithConfig(context.Background(), cfg)
	if err != nil {
		t.Fatalf("pool: %v", err)
	}
	defer pool.Close()

	// Deadline so a regression fails fast instead of hanging the suite.
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	userID := propUniqueID()
	planID := seedPropPlan(t, pool, userID, "TRY_COIN", time.Date(2026, 4, 1, 0, 0, 0, 0, time.UTC))
	asOf := time.Date(2026, 4, 30, 23, 59, 0, 0, time.UTC)

	if _, err := propCronSvc(pool).PayMonthlyInstallments(ctx, asOf); err != nil {
		t.Fatalf("PayMonthlyInstallments on a 1-conn pool: %v "+
			"(a second-connection acquire inside the tx would deadlock here)", err)
	}

	var made int
	if err := pool.QueryRow(context.Background(),
		`SELECT payments_made FROM cashback_schema.plans WHERE id=$1`, planID).Scan(&made); err != nil {
		t.Fatalf("read payments_made: %v", err)
	}
	if made != 1 {
		t.Fatalf("want payments_made=1 after a single hot-path run, got %d", made)
	}
}

// ── Property 5: payments_made cache stays in sync with COUNT(payments WHERE paid) ──
// Verifies the post-fix invariant that plans.payments_made is a faithful
// denormalized cache of the payments table across N consecutive monthly cron
// runs. Catches regressions in RefreshPaymentsMadeCache and in any code that
// might write payments_made without refreshing it from the source of truth.

func TestCronProperty_PaymentsMadeMatchesCount(t *testing.T) {
	pool := propCronPool(t)
	ctx := context.Background()

	properties := gopter.NewProperties(func() *gopter.TestParameters {
		p := gopter.DefaultTestParameters()
		p.MinSuccessfulTests = 50
		return p
	}())

	properties.Property("plans.payments_made == count(payments WHERE paid) after N monthly runs", prop.ForAll(
		func(months uint8) bool {
			if months < 1 {
				months = 1
			}
			if months > 6 {
				months = 6
			}

			userID := propUniqueID()
			startDate := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
			planID := seedPropPlan(t, pool, userID, "TRY_COIN", startDate)

			for i := 0; i < int(months); i++ {
				month := time.Month(i + 1)
				asOf := time.Date(2026, month, 28, 23, 59, 0, 0, time.UTC)
				svc := propCronSvc(pool)
				if _, err := svc.PayMonthlyInstallments(ctx, asOf); err != nil {
					t.Logf("PayMonthlyInstallments month=%d: %v", i+1, err)
					return false
				}
			}

			var madeCache int
			var paidCount int
			if err := pool.QueryRow(ctx,
				`SELECT payments_made FROM cashback_schema.plans WHERE id=$1`,
				planID).Scan(&madeCache); err != nil {
				t.Logf("read payments_made cache: %v", err)
				return false
			}
			if err := pool.QueryRow(ctx,
				`SELECT COUNT(*) FROM cashback_schema.payments WHERE plan_id=$1 AND status='paid'`,
				planID).Scan(&paidCount); err != nil {
				t.Logf("read paid count: %v", err)
				return false
			}
			if madeCache != paidCount {
				t.Logf("cache divergence: plan=%d payments_made=%d count(paid)=%d",
					planID, madeCache, paidCount)
				return false
			}
			return true
		},
		gen.UInt8Range(1, 6),
	))

	properties.TestingRun(t, gopter.ConsoleReporter(false))
}

func cronNetBalance(pool *pgxpool.Pool, currency string) int64 {
	var net int64
	pool.QueryRow(context.Background(), `
		SELECT COALESCE(SUM(CASE WHEN le.direction='D' THEN le.amount_minor ELSE -le.amount_minor END), 0)
		FROM wallet_schema.ledger_entries le
		JOIN wallet_schema.accounts a ON a.id = le.account_id
		WHERE a.currency = $1`, currency).Scan(&net)
	return net
}

// ── Property 6: ListDuePlans excludes plans already paid for the run period ───
// The v6 storage-layer idempotency guard pairs a UNIQUE(plan_id, period_yyyymm)
// constraint at ClaimPaymentPeriod with a NOT EXISTS period filter in
// ListDuePlans. This property locks the filter invariant surfaced by PR #10:
// for any (plan, asOf), once cashback_schema.payments holds a row with
// period_yyyymm = period(asOf), ListDuePlans must never return that plan for
// that period again — regardless of the cache value in plans.payments_made.

func TestCronProperty_ListDuePlansExcludesPaidPeriods(t *testing.T) {
	pool := propCronPool(t)
	repo := cashback.NewRepository(pool)
	ctx := context.Background()

	properties := gopter.NewProperties(func() *gopter.TestParameters {
		p := gopter.DefaultTestParameters()
		p.MinSuccessfulTests = 100
		p.SetSeed(0xCA4E00) // deterministic: reproducible shrinking on failure
		return p
	}())

	properties.Property("a plan with a payment for period(asOf) is never returned by ListDuePlans", prop.ForAll(
		func(monthOffset uint8) bool {
			month := time.Month(int(monthOffset%12) + 1)
			asOf := time.Date(2026, month, 28, 12, 0, 0, 0, time.UTC)
			runPeriod := 2026*100 + int(month)

			userID := propUniqueID()
			startDate := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
			planID := seedPropPlan(t, pool, userID, "TRY_COIN", startDate)

			// Precondition (keeps the test non-vacuous): with no payment for the
			// run period, the freshly-seeded active plan IS due and appears.
			if !propListDueContains(t, repo, ctx, asOf, runPeriod, planID) {
				t.Logf("precondition failed: plan %d not due for period %d before any payment", planID, runPeriod)
				return false
			}

			// Insert a payment row for exactly that period (any status counts
			// toward the NOT EXISTS guard; 'paid' is the representative case).
			propInsertPayment(t, pool, planID, runPeriod)

			// Invariant: ListDuePlans must now exclude the plan for this period.
			if propListDueContains(t, repo, ctx, asOf, runPeriod, planID) {
				t.Logf("invariant violated: plan %d returned for already-paid period %d", planID, runPeriod)
				return false
			}
			return true
		},
		gen.UInt8Range(0, 23),
	))

	properties.TestingRun(t, gopter.ConsoleReporter(false))
}

// propListDueContains reports whether planID appears in ListDuePlans for the
// given run date/period. Uses a very large limit so plans accumulated by other
// property iterations never push the target out of the result window.
func propListDueContains(t *testing.T, repo cashback.Repository, ctx context.Context, asOf time.Time, runPeriod int, planID int64) bool {
	t.Helper()
	plans, err := repo.ListDuePlans(ctx, asOf, runPeriod, 1_000_000)
	if err != nil {
		t.Fatalf("ListDuePlans: %v", err)
	}
	for i := range plans {
		if plans[i].ID == planID {
			return true
		}
	}
	return false
}

// propInsertPayment inserts a 'paid' payment row for (planID, period) to
// simulate the run period already having been claimed/paid.
func propInsertPayment(t *testing.T, pool *pgxpool.Pool, planID int64, period int) {
	t.Helper()
	_, err := pool.Exec(context.Background(), `
		INSERT INTO cashback_schema.payments
		    (plan_id, period_yyyymm, scheduled_date, amount_minor, status, idempotency_key, attempt_count)
		VALUES ($1, $2, now(), 500, 'paid', $3, 1)`,
		planID, period, fmt.Sprintf("prop:listdue:pay:%d:%d", planID, period),
	)
	if err != nil {
		t.Fatalf("propInsertPayment plan=%d period=%d: %v", planID, period, err)
	}
}
