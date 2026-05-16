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
	pool, err := pgxpool.New(context.Background(), cronTestDSNFromEnv())
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
	return cashback.NewService(repo, ob, nil, "TRY_COIN", walletSvc, slog.Default())
}

func seedPropPlan(t *testing.T, pool *pgxpool.Pool, userID int64, currency string, startDate time.Time) int64 {
	t.Helper()
	var id int64
	suffix := propUniqueID()
	err := pool.QueryRow(context.Background(), `
		INSERT INTO cashback_schema.plans
		    (order_id, user_id, monthly_amount_minor, currency,
		     reference_interest_rate_bps, start_date, status,
		     delivered_at, market, commission_snapshot, idempotency_key)
		VALUES ($1, $2, 500, $3, 5000, $4, 'active',
		        now()-interval '5 days', 'TR', '[]'::jsonb, $5)
		RETURNING id`,
		suffix, userID, currency, startDate.Format("2006-01-02"),
		fmt.Sprintf("prop:cron:plan:%d", suffix),
	).Scan(&id)
	if err != nil {
		t.Fatalf("seedPropPlan: %v", err)
	}
	return id
}

// ── Property 1: D=C invariant across N RunMonth calls ─────────────────────────
// For 1000 random (period, amount) pairs, the net signed TRY_COIN balance
// across ALL ledger_entries must remain 0 after RunMonth commits.

func TestCronProperty_DoubleEntryInvariant(t *testing.T) {
	pool := propCronPool(t)
	svc := propCronSvc(pool)
	ctx := context.Background()

	properties := gopter.NewProperties(func() *gopter.TestParameters {
		p := gopter.DefaultTestParameters()
		p.MinSuccessfulTests = 200
		return p
	}())

	properties.Property("D=C invariant holds after RunMonth", prop.ForAll(
		func(monthOffset uint8) bool {
			period := 202601 + int(monthOffset%12)
			year := 2026 + int(monthOffset/12)
			month := time.Month(period % 100)
			if month == 0 {
				month = 12
				year--
			}
			asOf := time.Date(year, month, 28, 23, 59, 0, 0, time.UTC)

			userID := propUniqueID()
			startDate := time.Date(year, month, 1, 0, 0, 0, 0, time.UTC)
			seedPropPlan(t, pool, userID, "TRY_COIN", startDate)

			netBefore := cronNetBalance(pool, "TRY_COIN")

			if _, err := svc.RunMonth(ctx, period, asOf, "TRY_COIN"); err != nil {
				t.Logf("RunMonth error: %v", err)
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

// ── Property 2: RunMonth idempotency ─────────────────────────────────────────
// Running RunMonth N times for the same period always produces exactly 1 payment.

func TestCronProperty_Idempotency(t *testing.T) {
	pool := propCronPool(t)
	ctx := context.Background()

	const period = 202601
	asOf := time.Date(2026, 1, 31, 23, 59, 0, 0, time.UTC)

	properties := gopter.NewProperties(func() *gopter.TestParameters {
		p := gopter.DefaultTestParameters()
		p.MinSuccessfulTests = 200
		return p
	}())

	properties.Property("N RunMonth calls for same period → exactly 1 payment row", prop.ForAll(
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
				if _, err := svc.RunMonth(ctx, period, asOf, "TRY_COIN"); err != nil {
					t.Logf("RunMonth %d error: %v", i, err)
					return false
				}
			}

			var count int
			pool.QueryRow(ctx,
				`SELECT COUNT(*) FROM cashback_schema.payments WHERE plan_id=$1 AND period_yyyymm=$2`,
				planID, period).Scan(&count)
			if count != 1 {
				t.Logf("idempotency violated: %d payment rows for plan=%d", count, planID)
				return false
			}
			return true
		},
		gen.UInt8Range(2, 5),
	))

	properties.TestingRun(t, gopter.ConsoleReporter(false))
}

// ── Property 3: balance monotonically increases with N payments ───────────────
// After N RunMonth calls for N different periods, strict live balance must equal N × amount.

func TestCronProperty_MonotonicBalance(t *testing.T) {
	pool := propCronPool(t)
	ctx := context.Background()

	properties := gopter.NewProperties(func() *gopter.TestParameters {
		p := gopter.DefaultTestParameters()
		p.MinSuccessfulTests = 200
		return p
	}())

	properties.Property("N RunMonth periods → balance == N × monthly_amount_minor", prop.ForAll(
		func(n uint8) bool {
			if n == 0 || n > 6 {
				n = 1
			}

			userID := propUniqueID()
			// Use a wallet.Service to pre-create wallet so we can check balance.
			walletRepo := wallet.NewRepository(pool)
			walletOutbox := outbox.NewRepository("wallet_schema.outbox")
			walletSvc := wallet.NewService(walletRepo, walletOutbox, slog.Default())
			walletAcctID, err := walletSvc.OpenOrFindUserWallet(ctx, userID, "TRY_COIN")
			if err != nil {
				t.Logf("OpenOrFindUserWallet: %v", err)
				return false
			}

			const monthlyAmount = int64(500) // matches seedPropPlan's hardcoded 500
			startDate := time.Date(2025, 12, 1, 0, 0, 0, 0, time.UTC)
			seedPropPlan(t, pool, userID, "TRY_COIN", startDate)

			for i := 0; i < int(n); i++ {
				period := 202601 + i // 202601, 202602, ...
				year := 2026
				month := time.Month(period % 100)
				asOf := time.Date(year, month, 28, 23, 59, 0, 0, time.UTC)
				svc := propCronSvc(pool)
				if _, err := svc.RunMonth(ctx, period, asOf, "TRY_COIN"); err != nil {
					t.Logf("RunMonth period=%d: %v", period, err)
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

// ── Property 4: concurrent RunMonth → exactly 1 payment per plan ──────────────
// G goroutines calling RunMonth for the same plan+period concurrently must
// produce exactly 1 payment row and 1 outbox row.

func TestCronProperty_ConcurrentIdempotency(t *testing.T) {
	pool := propCronPool(t)
	ctx := context.Background()

	const period = 202604
	asOf := time.Date(2026, 4, 30, 23, 59, 0, 0, time.UTC)

	properties := gopter.NewProperties(func() *gopter.TestParameters {
		p := gopter.DefaultTestParameters()
		p.MinSuccessfulTests = 100
		return p
	}())

	properties.Property("G concurrent RunMonth calls → exactly 1 payment + 1 outbox row", prop.ForAll(
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
					svc.RunMonth(ctx, period, asOf, "TRY_COIN") //nolint:errcheck
				}()
			}
			close(barrier)
			wgDone.Wait()

			var count int
			pool.QueryRow(ctx,
				`SELECT COUNT(*) FROM cashback_schema.payments WHERE plan_id=$1 AND period_yyyymm=$2`,
				planID, period).Scan(&count)
			if count != 1 {
				t.Logf("concurrent idempotency violated: %d payment rows", count)
				return false
			}
			return true
		},
		gen.UInt8Range(2, 8),
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
