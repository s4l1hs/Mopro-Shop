//go:build integration

package wallet_test

// Non-fragile regression guards for the financial-domain pool-acquisition
// discipline (fix/financial-domain-pool-discipline; deadlock origin PR #41/#42).
//
// Every financial ledger write funnels through wallet.PostInTx, so this single
// function is the whole "pool-read inside a tx" surface. Two contracts:
//
//   1. The NORMAL write path must not acquire a second pool connection inside the
//      tx (GetAccountCurrencies + GetSystemState are tx-routed, #42/#43). If a
//      future change reverts one to a pool read, N concurrent Posts on a small
//      pool deadlock. TestProperty_FinancialWritePathDoesNotDeadlock guards this
//      with a context-timeout (deadlock-detection) rather than a fragile
//      per-goroutine connection-count assertion (PR #42's MaxConns=1 guard was
//      too tight and was dropped).
//
//   2. The REPLAY-path idempotency lookup (GetTransactionByIdempotencyKey) must
//      stay on the pool (documented-pool-access) so concurrent same-key callers
//      observe the winner's just-committed row. TestProperty_IdempotencyLookup-
//      ObservesConcurrentCommits asserts that contract — it fails if the lookup
//      is "fixed" to read the calling tx.

import (
	"context"
	"fmt"
	"log/slog"
	"sync"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/mopro/platform/internal/ledger"
	"github.com/mopro/platform/internal/outbox"
	"github.com/mopro/platform/internal/wallet"
)

// newSvcWithMaxConns wires the wallet service against a pool with a pinned
// MaxConns, so the contention budget is reproducible across runner CPU counts
// (pgx's default is max(4, NumCPU) — a 6-core dev box masked PR #41's deadlock
// that a 2-vCPU CI runner with 4 conns exposed).
func newSvcWithMaxConns(t *testing.T, maxConns int32) (wallet.Service, *pgxpool.Pool) {
	t.Helper()
	cfg, err := pgxpool.ParseConfig(testDSNFromEnv())
	if err != nil {
		t.Fatalf("ParseConfig: %v", err)
	}
	cfg.MaxConns = maxConns
	pool, err := pgxpool.NewWithConfig(context.Background(), cfg)
	if err != nil {
		t.Fatalf("NewWithConfig: %v", err)
	}
	if err := pool.Ping(context.Background()); err != nil {
		t.Fatalf("Ping: %v (is pg-test on port 6434?)", err)
	}
	t.Cleanup(pool.Close)
	repo := wallet.NewRepository(pool)
	svc := wallet.NewService(repo, outbox.NewRepository("wallet_schema.outbox"), slog.Default())
	return svc, pool
}

// jitter spreads goroutine start times to broaden the contention surface beyond
// a single timing, without math/rand (avoids a weak-RNG lint in test code).
func jitter(i int) { time.Sleep(time.Duration((i*7)%11) * time.Millisecond) }

func TestProperty_FinancialWritePathDoesNotDeadlock(t *testing.T) {
	// MaxConns=4 = the CI default that exposed PR #41's deadlock; broad enough
	// not to over-constrain, tight enough that any pool-read-inside-tx exhausts
	// the budget under N=8 contention.
	svc, pool := newSvcWithMaxConns(t, 4)
	ctx := context.Background()

	distID, err := svc.FindAccount(ctx, "equity:cashback_distribution", "TRY_COIN")
	if err != nil {
		t.Fatalf("FindAccount: %v", err)
	}
	walletID, err := svc.OpenOrFindUserWallet(ctx, int64(79001), "TRY_COIN")
	if err != nil {
		t.Fatalf("OpenOrFindUserWallet: %v", err)
	}

	const N = 8
	runCtx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()

	var wg sync.WaitGroup
	errs := make([]error, N)
	for i := 0; i < N; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			jitter(i)
			// UNIQUE idempotency key per goroutine → the normal (winner) write
			// path: GetAccountCurrencies + GetSystemState, both tx-routed. Pre
			// #42/#43 these were pool reads = a 2nd connection inside the tx =
			// deadlock here at MaxConns=4. (The same-key REPLAY path is exercised
			// for correctness, not deadlock-resistance, in the idempotency test.)
			_, errs[i] = svc.Post(runCtx, ledger.PostInput{
				Type:           "cashback_payment",
				IdempotencyKey: fmt.Sprintf("pool-discipline:%d:%d", uniqueSuffix(), i),
				Market:         "TR",
				Currency:       "TRY_COIN",
				Entries: []ledger.Entry{
					{AccountID: distID, Direction: ledger.Debit, AmountMinor: 100},
					{AccountID: walletID, Direction: ledger.Credit, AmountMinor: 100},
				},
			})
		}(i)
	}

	done := make(chan struct{})
	go func() { wg.Wait(); close(done) }()
	select {
	case <-done:
	case <-runCtx.Done():
		t.Fatalf("DEADLOCK: %d concurrent Post calls did not complete within 15s at MaxConns=4. "+
			"A pool read inside PostInTx's tx (a regression of the #42/#43 tx-routing) is the likely cause. "+
			"pool.Stat: acquired=%d total=%d", N, pool.Stat().AcquiredConns(), pool.Stat().TotalConns())
	}

	for i, e := range errs {
		if e != nil {
			t.Errorf("goroutine %d: Post: %v", i, e)
		}
	}

	// Leak check: all connections returned to the pool. pgxpool.Stat exposes
	// AcquiredConns() (currently in-use); it has no ReleaseCount(). Poll briefly
	// to let the background health-check settle.
	deadline := time.Now().Add(2 * time.Second)
	for pool.Stat().AcquiredConns() != 0 && time.Now().Before(deadline) {
		time.Sleep(20 * time.Millisecond)
	}
	if acq := pool.Stat().AcquiredConns(); acq != 0 {
		t.Fatalf("connection leak: %d connections still acquired after all Posts completed", acq)
	}
}

func TestProperty_IdempotencyLookupObservesConcurrentCommits(t *testing.T) {
	// Ample pool: this exercises the documented-pool-access REPLAY path
	// (GetTransactionByIdempotencyKey), which acquires a SECOND connection inside
	// the tx by design. That is deadlock-prone at a tiny pool under contention —
	// acceptable because PostInTx is singleton-cron-driven in prod — so give it
	// headroom (2×N). This test verifies the CORRECTNESS contract
	// (concurrent-commit observability), not deadlock-resistance.
	svc, pool := newSvcWithMaxConns(t, 16)
	ctx := context.Background()

	distID, err := svc.FindAccount(ctx, "equity:cashback_distribution", "TRY_COIN")
	if err != nil {
		t.Fatalf("FindAccount: %v", err)
	}
	walletID, err := svc.OpenOrFindUserWallet(ctx, int64(79002), "TRY_COIN")
	if err != nil {
		t.Fatalf("OpenOrFindUserWallet: %v", err)
	}

	const N = 8
	key := fmt.Sprintf("idem-contract:%d", uniqueSuffix()) // SAME key for all N

	ids := make([]int64, N)
	errs := make([]error, N)
	var wg sync.WaitGroup
	for i := 0; i < N; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			jitter(i)
			ids[i], errs[i] = svc.Post(ctx, ledger.PostInput{
				Type:           "cashback_payment",
				IdempotencyKey: key,
				Market:         "TR",
				Currency:       "TRY_COIN",
				Entries: []ledger.Entry{
					{AccountID: distID, Direction: ledger.Debit, AmountMinor: 100},
					{AccountID: walletID, Direction: ledger.Credit, AmountMinor: 100},
				},
			})
		}(i)
	}
	wg.Wait()

	for i := 0; i < N; i++ {
		if errs[i] != nil {
			t.Fatalf("goroutine %d: Post: %v", i, errs[i])
		}
	}

	// Contract: exactly one insert; every concurrent caller returns the SAME txn
	// id — the winner's id, observed by the losers via the pool-based replay
	// lookup. If GetTransactionByIdempotencyKey were routed through the calling
	// tx, the losers' SERIALIZABLE snapshot wouldn't see the winner's concurrent
	// commit and they'd error (not-found) instead of returning the existing id.
	first := ids[0]
	if first <= 0 {
		t.Fatalf("goroutine 0 returned non-positive txn id %d", first)
	}
	for i := 1; i < N; i++ {
		if ids[i] != first {
			t.Fatalf("idempotency contract violated: goroutine %d returned txn id %d, want %d "+
				"(all concurrent same-key callers must observe the single committed txn)", i, ids[i], first)
		}
	}

	// Exactly one ledger transaction row exists for the key.
	var cnt int
	if err := pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM wallet_schema.transactions WHERE idempotency_key = $1`, key).Scan(&cnt); err != nil {
		t.Fatalf("count transactions: %v", err)
	}
	if cnt != 1 {
		t.Fatalf("want exactly 1 transaction for key %q, got %d", key, cnt)
	}
}
