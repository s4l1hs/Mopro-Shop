//go:build integration

package wallet_test

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

	"github.com/mopro/platform/internal/ledger"
	"github.com/mopro/platform/internal/outbox"
	"github.com/mopro/platform/internal/wallet"
)

// propertyTestPool opens a shared pool for property tests; caller must close.
func propertyTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	ctx := context.Background()
	pool, err := pgxpool.New(ctx, testDSNFromEnv())
	if err != nil {
		t.Fatalf("property pool: %v", err)
	}
	if err := pool.Ping(ctx); err != nil {
		t.Fatalf("property pool ping: %v", err)
	}
	t.Cleanup(pool.Close)
	return pool
}

// newPropertySvc wires a fresh wallet.Service backed by pool.
func newPropertySvc(pool *pgxpool.Pool) wallet.Service {
	repo := wallet.NewRepository(pool)
	outboxRepo := outbox.NewRepository("wallet_schema.outbox")
	return wallet.NewService(repo, outboxRepo, slog.Default())
}

// seedPropertyAccounts inserts a debit + credit account pair for property tests.
// Returns (debitID, creditID). Uses a direct SQL INSERT so property tests don't
// depend on wallet.Service for fixtures.
func seedPropertyAccounts(t *testing.T, pool *pgxpool.Pool, currency, label string) (debitID, creditID int64) {
	t.Helper()
	ctx := context.Background()

	insert := func(acctType, ownerType string, ownerID *int64) int64 {
		var id int64
		err := pool.QueryRow(ctx,
			`INSERT INTO wallet_schema.accounts (type, owner_type, owner_id, currency, status)
			 VALUES ($1, $2, $3, $4, 'active') RETURNING id`,
			acctType, ownerType, ownerID, currency,
		).Scan(&id)
		if err != nil {
			t.Fatalf("seedPropertyAccounts insert %s/%s: %v", acctType, ownerType, err)
		}
		return id
	}

	debitID = insert("asset:prop:debit:"+label, "platform", nil)
	creditID = insert("liability:prop:credit:"+label, "platform", nil)
	return debitID, creditID
}

// ── Property 1: per-currency D=C invariant ───────────────────────────────────
//
// For 1000+ random (amount, currency) pairs the net signed balance across
// debit and credit accounts MUST be zero after any set of committed transactions.

func TestProperty_DoubleEntryInvariant(t *testing.T) {
	pool := propertyTestPool(t)
	svc := newPropertySvc(pool)
	ctx := context.Background()

	// Seed one pair per currency so different test iterations share no state.
	debitTRY, creditTRY := seedPropertyAccounts(t, pool, "TRY", fmt.Sprintf("dcprop_try_%d", uniqueSuffix()))
	debitCOIN, creditCOIN := seedPropertyAccounts(t, pool, "TRY_COIN", fmt.Sprintf("dcprop_coin_%d", uniqueSuffix()))

	properties := gopter.NewProperties(gopterSettings(1000))

	properties.Property("per-currency D=C invariant", prop.ForAll(
		func(amountMinor int64, useCoin bool) bool {
			if amountMinor <= 0 {
				return true // skip degenerate input
			}
			currency := "TRY"
			dID, cID := debitTRY, creditTRY
			if useCoin {
				currency = "TRY_COIN"
				dID, cID = debitCOIN, creditCOIN
			}

			key := fmt.Sprintf("prop:dc:%s:%d:%d", currency, amountMinor, uniqueSuffix())
			in := ledger.PostInput{
				Type:           "cashback_payment",
				IdempotencyKey: key,
				Market:         "TR",
				Currency:       currency,
				Entries: []ledger.Entry{
					{AccountID: dID, Direction: ledger.Debit, AmountMinor: amountMinor},
					{AccountID: cID, Direction: ledger.Credit, AmountMinor: amountMinor},
				},
			}
			if _, err := svc.Post(ctx, in); err != nil {
				t.Logf("Post failed: %v", err)
				return false
			}

			// Net signed balance across both accounts must be 0.
			dBal, err := netBalanceDirect(pool, dID)
			if err != nil {
				return false
			}
			cBal, err := netBalanceDirect(pool, cID)
			if err != nil {
				return false
			}
			// debit account: net = credits - debits = -amount; credit account: net = +amount.
			// sum must be zero.
			return dBal+cBal == 0
		},
		gen.Int64Range(1, 100_000),
		gen.Bool(),
	))

	properties.TestingRun(t, gopter.ConsoleReporter(false))
}

// ── Property 2: idempotency ───────────────────────────────────────────────────
//
// Posting the same PostInput (same IdempotencyKey) N times returns the original
// txnID every time, and the entry count in the DB does NOT grow.

func TestProperty_Idempotency(t *testing.T) {
	pool := propertyTestPool(t)
	svc := newPropertySvc(pool)
	ctx := context.Background()

	debitID, creditID := seedPropertyAccounts(t, pool, "TRY", fmt.Sprintf("idem_try_%d", uniqueSuffix()))

	properties := gopter.NewProperties(gopterSettings(1000))

	properties.Property("idempotency: same key N times → same txnID, no extra entries", prop.ForAll(
		func(amount int64, repeats uint8) bool {
			if amount <= 0 {
				return true
			}
			if repeats < 2 {
				repeats = 2
			}
			key := fmt.Sprintf("prop:idem:%d:%d", amount, uniqueSuffix())
			in := ledger.PostInput{
				Type:           "cashback_payment",
				IdempotencyKey: key,
				Market:         "TR",
				Currency:       "TRY",
				Entries: []ledger.Entry{
					{AccountID: debitID, Direction: ledger.Debit, AmountMinor: amount},
					{AccountID: creditID, Direction: ledger.Credit, AmountMinor: amount},
				},
			}

			firstTxnID, err := svc.Post(ctx, in)
			if err != nil {
				t.Logf("first Post failed: %v", err)
				return false
			}

			entryCountBefore := txnEntryCount(t, pool, firstTxnID)

			for i := 1; i < int(repeats); i++ {
				got, err := svc.Post(ctx, in)
				if err != nil {
					t.Logf("repeat %d Post failed: %v", i, err)
					return false
				}
				if got != firstTxnID {
					t.Logf("repeat %d: got txnID=%d, want %d", i, got, firstTxnID)
					return false
				}
			}

			entryCountAfter := txnEntryCount(t, pool, firstTxnID)
			if entryCountAfter != entryCountBefore {
				t.Logf("entry count grew: before=%d after=%d", entryCountBefore, entryCountAfter)
				return false
			}
			return true
		},
		gen.Int64Range(1, 50_000),
		gen.UInt8Range(2, 5),
	))

	properties.TestingRun(t, gopter.ConsoleReporter(false))
}

// ── Property 3: monotonic balance ────────────────────────────────────────────
//
// After N credit-only transactions of amount M to a user wallet, the strict
// live balance must equal N×M (no rounding loss, no missing entries).

func TestProperty_MonotonicBalance(t *testing.T) {
	pool := propertyTestPool(t)
	svc := newPropertySvc(pool)
	ctx := context.Background()

	properties := gopter.NewProperties(gopterSettings(500)) // 500 iterations; each may do up to 10 Posts

	properties.Property("monotonic balance: N credits of M → balance == N×M", prop.ForAll(
		func(amountMinor int64, n uint8) bool {
			if amountMinor <= 0 || n == 0 {
				return true
			}
			if n > 10 {
				n = 10 // cap to keep test fast
			}

			// Fresh accounts per iteration (unique suffix) so iterations don't interfere.
			suffix := uniqueSuffix()
			srcID, dstID := seedPropertyAccounts(t, pool, "TRY_COIN", fmt.Sprintf("mono_%d", suffix))

			var accumulated int64
			for i := 0; i < int(n); i++ {
				key := fmt.Sprintf("prop:mono:%d:%d:%d", suffix, i, uniqueSuffix())
				in := ledger.PostInput{
					Type:           "cashback_payment",
					IdempotencyKey: key,
					Market:         "TR",
					Currency:       "TRY_COIN",
					Entries: []ledger.Entry{
						{AccountID: srcID, Direction: ledger.Debit, AmountMinor: amountMinor},
						{AccountID: dstID, Direction: ledger.Credit, AmountMinor: amountMinor},
					},
				}
				if _, err := svc.Post(ctx, in); err != nil {
					t.Logf("Post %d failed: %v", i, err)
					return false
				}
				accumulated += amountMinor
			}

			got, err := svc.GetBalanceStrict(ctx, dstID)
			if err != nil {
				t.Logf("GetBalanceStrict: %v", err)
				return false
			}
			if got != accumulated {
				t.Logf("balance mismatch: got=%d want=%d (n=%d, amount=%d)", got, accumulated, n, amountMinor)
				return false
			}
			return true
		},
		gen.Int64Range(1, 10_000),
		gen.UInt8Range(1, 10),
	))

	properties.TestingRun(t, gopter.ConsoleReporter(false))
}

// ── Property 4: concurrent open-or-find safety ───────────────────────────────
//
// G goroutines concurrently call OpenOrFindUserWallet for the SAME (userID, currency).
// All must return the SAME accountID, and exactly ONE row must exist in the DB.

func TestProperty_ConcurrentOpenOrFind(t *testing.T) {
	pool := propertyTestPool(t)
	svc := newPropertySvc(pool)
	ctx := context.Background()

	properties := gopter.NewProperties(gopterSettings(200)) // fewer iterations; each spawns goroutines

	properties.Property("concurrent open-or-find: all goroutines return same accountID", prop.ForAll(
		func(userID int64, goroutines uint8) bool {
			if userID <= 0 {
				return true
			}
			if goroutines < 2 {
				goroutines = 2
			}
			if goroutines > 10 {
				goroutines = 10
			}

			// Use a unique userID derived from the generated value to avoid cross-iteration collisions.
			uniqueUserID := userID*100_000 + int64(uniqueSuffix()%100_000)

			results := make([]int64, goroutines)
			errs := make([]error, goroutines)
			var wg sync.WaitGroup
			for i := 0; i < int(goroutines); i++ {
				wg.Add(1)
				go func(idx int) {
					defer wg.Done()
					id, err := svc.OpenOrFindUserWallet(ctx, uniqueUserID, "TRY_COIN")
					results[idx] = id
					errs[idx] = err
				}(i)
			}
			wg.Wait()

			for i, err := range errs {
				if err != nil {
					t.Logf("goroutine %d error: %v", i, err)
					return false
				}
			}

			first := results[0]
			for i, r := range results {
				if r != first || r == 0 {
					t.Logf("goroutine %d returned accountID=%d, want %d", i, r, first)
					return false
				}
			}

			// Verify exactly one row in DB for this (ownerType, ownerID, currency).
			var count int
			err := pool.QueryRow(ctx,
				`SELECT COUNT(*) FROM wallet_schema.accounts
				 WHERE owner_type='user' AND owner_id=$1 AND currency='TRY_COIN'`,
				uniqueUserID,
			).Scan(&count)
			if err != nil {
				t.Logf("count query: %v", err)
				return false
			}
			if count != 1 {
				t.Logf("expected 1 account row, got %d for userID=%d", count, uniqueUserID)
				return false
			}
			return true
		},
		gen.Int64Range(1, 9_000_000),
		gen.UInt8Range(2, 10),
	))

	properties.TestingRun(t, gopter.ConsoleReporter(false))
}

// ── helpers ───────────────────────────────────────────────────────────────────

// suffixBase is a per-process epoch (milliseconds) so that each test run
// produces type names that don't collide with rows left in the persistent test DB.
var (
	suffixBase    = time.Now().UnixMilli()
	suffixCounter int64
)

func uniqueSuffix() int64 {
	n := atomic.AddInt64(&suffixCounter, 1)
	return suffixBase*1_000_000 + n
}

func gopterSettings(minSuccessful int) *gopter.TestParameters {
	params := gopter.DefaultTestParameters()
	params.MinSuccessfulTests = minSuccessful
	params.MaxSize = 50
	return params
}

// netBalanceDirect returns the signed net balance for accountID:
// SUM(credit amounts) - SUM(debit amounts) from ledger_entries.
func netBalanceDirect(pool *pgxpool.Pool, accountID int64) (int64, error) {
	var bal int64
	err := pool.QueryRow(context.Background(),
		`SELECT COALESCE(SUM(CASE WHEN direction='C' THEN amount_minor ELSE -amount_minor END), 0)
		 FROM wallet_schema.ledger_entries WHERE account_id = $1`,
		accountID,
	).Scan(&bal)
	return bal, err
}

// txnEntryCount returns the number of ledger_entries rows for the given transaction.
func txnEntryCount(t *testing.T, pool *pgxpool.Pool, txnID int64) int {
	t.Helper()
	var n int
	err := pool.QueryRow(context.Background(),
		`SELECT COUNT(*) FROM wallet_schema.ledger_entries WHERE transaction_id = $1`,
		txnID,
	).Scan(&n)
	if err != nil {
		t.Fatalf("txnEntryCount: %v", err)
	}
	return n
}
