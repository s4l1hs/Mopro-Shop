//go:build integration

package wallet_test

import (
	"context"
	"errors"
	"log/slog"
	"os"
	"sync"
	"testing"

	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/mopro/platform/internal/ledger"
	"github.com/mopro/platform/internal/outbox"
	"github.com/mopro/platform/internal/wallet"
)

// testDSN returns the integration test DSN. Defaults to pg-test on port 6434.
const testDSN = "postgres://ledger_admin:test123@localhost:6434/mopro_ledger"

func testDSNFromEnv() string {
	if v := os.Getenv("LEDGER_TEST_DSN"); v != "" {
		return v
	}
	return testDSN
}

// newTestSvc connects to pg-test and wires the wallet service.
func newTestSvc(t *testing.T) (wallet.Service, *pgxpool.Pool) {
	t.Helper()
	ctx := context.Background()
	pool, err := pgxpool.New(ctx, testDSNFromEnv())
	if err != nil {
		t.Fatalf("pgxpool.New: %v", err)
	}
	if err := pool.Ping(ctx); err != nil {
		t.Fatalf("pool.Ping: %v (is pg-test running on port 6434?)", err)
	}
	t.Cleanup(pool.Close)

	repo := wallet.NewRepository(pool)
	outboxRepo := outbox.NewRepository("wallet_schema.outbox")
	svc := wallet.NewService(repo, outboxRepo, slog.Default())
	return svc, pool
}

// refreshMV forces a REFRESH MATERIALIZED VIEW so GetBalance (MV path) is current.
func refreshMV(t *testing.T, pool *pgxpool.Pool) {
	t.Helper()
	if _, err := pool.Exec(context.Background(),
		"REFRESH MATERIALIZED VIEW CONCURRENTLY wallet_schema.balances"); err != nil {
		t.Fatalf("refresh MV: %v", err)
	}
}

// netBalance returns Sum(D)-Sum(C) for a currency across ALL ledger entries.
// For a correct ledger this MUST always be 0.
func netBalance(t *testing.T, pool *pgxpool.Pool, currency string) int64 {
	t.Helper()
	var net int64
	err := pool.QueryRow(context.Background(), `
		SELECT COALESCE(SUM(CASE WHEN le.direction='D' THEN le.amount_minor ELSE -le.amount_minor END), 0)
		FROM wallet_schema.ledger_entries le
		JOIN wallet_schema.accounts a ON a.id = le.account_id
		WHERE a.currency = $1`, currency).Scan(&net)
	if err != nil {
		t.Fatalf("netBalance(%s): %v", currency, err)
	}
	return net
}

func countEntries(t *testing.T, pool *pgxpool.Pool, txnID int64) int {
	t.Helper()
	var n int
	if err := pool.QueryRow(context.Background(),
		"SELECT COUNT(*) FROM wallet_schema.ledger_entries WHERE transaction_id = $1", txnID).Scan(&n); err != nil {
		t.Fatalf("countEntries: %v", err)
	}
	return n
}

// ── Test A: Single-currency happy path ────────────────────────────────────────

func TestIntegration_SingleCurrencyHappyPath(t *testing.T) {
	svc, pool := newTestSvc(t)
	ctx := context.Background()

	distID, err := svc.FindAccount(ctx, "equity:cashback_distribution", "TRY_COIN")
	if err != nil {
		t.Fatalf("FindAccount dist: %v", err)
	}

	const uniqueUserID = int64(70001)
	walletID, err := svc.OpenOrFindUserWallet(ctx, uniqueUserID, "TRY_COIN")
	if err != nil {
		t.Fatalf("OpenOrFindUserWallet: %v", err)
	}
	if walletID <= 0 {
		t.Fatalf("expected positive walletID, got %d", walletID)
	}

	const amount = int64(500_00) // 500.00 TRY_COIN in kuruş
	txnID, err := svc.Post(ctx, ledger.PostInput{
		Type:           "cashback_payment",
		IdempotencyKey: "integ:a:happy:1",
		Market:         "TR",
		Currency:       "TRY_COIN",
		Entries: []ledger.Entry{
			{AccountID: distID, Direction: ledger.Debit, AmountMinor: amount},
			{AccountID: walletID, Direction: ledger.Credit, AmountMinor: amount},
		},
	})
	if err != nil {
		t.Fatalf("Post: %v", err)
	}
	if txnID <= 0 {
		t.Fatalf("expected positive txnID, got %d", txnID)
	}

	// Strict balance (live from ledger_entries)
	bal, err := svc.GetBalanceStrict(ctx, walletID)
	if err != nil {
		t.Fatalf("GetBalanceStrict: %v", err)
	}
	if bal != amount {
		t.Errorf("GetBalanceStrict: want %d, got %d", amount, bal)
	}

	// MV balance after manual refresh
	refreshMV(t, pool)
	mvBal, err := svc.GetBalance(ctx, walletID)
	if err != nil {
		t.Fatalf("GetBalance (MV): %v", err)
	}
	if mvBal != amount {
		t.Errorf("GetBalance (MV): want %d, got %d", amount, mvBal)
	}

	// Exactly 2 ledger entries
	if n := countEntries(t, pool, txnID); n != 2 {
		t.Errorf("want 2 ledger entries, got %d", n)
	}

	// Outbox row exists
	var obCount int
	_ = pool.QueryRow(ctx,
		"SELECT COUNT(*) FROM wallet_schema.outbox WHERE idempotency_key = $1",
		"integ:a:happy:1").Scan(&obCount)
	if obCount != 1 {
		t.Errorf("want 1 outbox row, got %d", obCount)
	}

	// Per-currency D=C invariant holds
	if net := netBalance(t, pool, "TRY_COIN"); net != 0 {
		t.Errorf("TRY_COIN net balance %d ≠ 0 (D=C violated)", net)
	}
	t.Logf("PASS: txnID=%d walletID=%d balance=%d outbox=1", txnID, walletID, bal)
}

// ── Test B: Mixed-currency rejection ─────────────────────────────────────────

func TestIntegration_MixedCurrencyRejection(t *testing.T) {
	svc, pool := newTestSvc(t)
	ctx := context.Background()

	tryEscrowID, err := svc.FindAccount(ctx, "asset:bank:escrow", "TRY")
	if err != nil {
		t.Fatalf("FindAccount escrow: %v", err)
	}
	coinDistID, err := svc.FindAccount(ctx, "equity:cashback_distribution", "TRY_COIN")
	if err != nil {
		t.Fatalf("FindAccount dist: %v", err)
	}

	// Wallet service rejects before DB because defensive currency check sees TRY vs TRY_COIN.
	_, err = svc.Post(ctx, ledger.PostInput{
		Type:           "bad_fx",
		IdempotencyKey: "integ:b:mixed:1",
		Market:         "TR",
		Currency:       "TRY", // stated TRY, but coinDistID has TRY_COIN
		Entries: []ledger.Entry{
			{AccountID: tryEscrowID, Direction: ledger.Debit, AmountMinor: 100_00},
			{AccountID: coinDistID, Direction: ledger.Credit, AmountMinor: 100_00},
		},
	})
	if err == nil {
		t.Fatal("expected error for mixed-currency, got nil")
	}
	if !errors.Is(err, wallet.ErrCurrencyMismatch) {
		t.Errorf("want ErrCurrencyMismatch, got %v", err)
	}

	// No ledger entries for this key
	var txnCount int
	_ = pool.QueryRow(ctx,
		"SELECT COUNT(*) FROM wallet_schema.transactions WHERE idempotency_key = $1",
		"integ:b:mixed:1").Scan(&txnCount)
	if txnCount != 0 {
		t.Errorf("want 0 transactions (rejected before write), got %d", txnCount)
	}
	t.Logf("PASS: mixed-currency rejected with %v; no DB writes", err)
}

// ── Test B2: DB-level mixed-currency rejection (trigger) ─────────────────────
// This test bypasses the defensive check by using accounts that both report TRY
// to GetAccountCurrencies but actually have different currencies at the DB level.
// Since the defensive check uses the pool and reads real account currencies,
// the only way to trigger the DB check_violation in a unit-like path is to
// directly test the trigger via raw SQL — which we do here as a sanity check.
func TestIntegration_TriggerCatchesMixedCurrency(t *testing.T) {
	svc, pool := newTestSvc(t)
	ctx := context.Background()
	_ = svc

	// Insert a transaction directly, then try to insert entries from mixed-currency accounts.
	// This bypasses the service layer to test the trigger in isolation.
	tx, err := pool.Begin(ctx)
	if err != nil {
		t.Fatalf("begin: %v", err)
	}
	defer tx.Rollback(ctx) //nolint:errcheck

	var txnID int64
	if err := tx.QueryRow(ctx,
		`INSERT INTO wallet_schema.transactions (type, idempotency_key) VALUES ('test_mixed', 'integ:b2:trigger:1') RETURNING id`,
	).Scan(&txnID); err != nil {
		t.Fatalf("insert txn: %v", err)
	}

	// Get one TRY account and one TRY_COIN account
	var tryAcctID, coinAcctID int64
	_ = pool.QueryRow(ctx, `SELECT id FROM wallet_schema.accounts WHERE type='asset:bank:escrow' AND currency='TRY' LIMIT 1`).Scan(&tryAcctID)
	_ = pool.QueryRow(ctx, `SELECT id FROM wallet_schema.accounts WHERE type='equity:cashback_distribution' AND currency='TRY_COIN' LIMIT 1`).Scan(&coinAcctID)

	if tryAcctID == 0 || coinAcctID == 0 {
		t.Skip("platform accounts not seeded")
	}

	_, _ = tx.Exec(ctx, `INSERT INTO wallet_schema.ledger_entries (transaction_id, account_id, direction, amount_minor) VALUES ($1, $2, 'D', 100)`, txnID, tryAcctID)
	_, _ = tx.Exec(ctx, `INSERT INTO wallet_schema.ledger_entries (transaction_id, account_id, direction, amount_minor) VALUES ($1, $2, 'C', 100)`, txnID, coinAcctID)

	commitErr := tx.Commit(ctx)
	if commitErr == nil {
		t.Fatal("expected check_violation on COMMIT for mixed-currency, got nil")
	}
	var pgErr *pgconn.PgError
	if !errors.As(commitErr, &pgErr) {
		t.Fatalf("expected PgError, got %T: %v", commitErr, commitErr)
	}
	// SQLSTATE 23514 = check_violation
	if pgErr.Code != "23514" {
		t.Errorf("want SQLSTATE 23514 (check_violation), got %s: %s", pgErr.Code, pgErr.Message)
	}
	t.Logf("PASS: trigger raised SQLSTATE %s: %s", pgErr.Code, pgErr.Message)
}

// ── Test C: FX pair ──────────────────────────────────────────────────────────

func TestIntegration_FXPair(t *testing.T) {
	svc, pool := newTestSvc(t)
	ctx := context.Background()

	const uniqueUserID = int64(70002)
	userCoinID, _ := svc.OpenOrFindUserWallet(ctx, uniqueUserID, "TRY_COIN")
	coinDistID, _ := svc.FindAccount(ctx, "equity:cashback_distribution", "TRY_COIN")
	escrowID, _ := svc.FindAccount(ctx, "asset:bank:escrow", "TRY")
	commID, _ := svc.FindAccount(ctx, "equity:retained_commission", "TRY")

	fxPairID := "integ:c:fxpair:1"

	// TX A — TRY_COIN: simulate cashback credit
	_, err := svc.Post(ctx, ledger.PostInput{
		Type:           "cashback_payment",
		FxPairID:       fxPairID,
		IdempotencyKey: fxPairID + ":try_coin",
		Market:         "TR",
		Currency:       "TRY_COIN",
		Entries: []ledger.Entry{
			{AccountID: coinDistID, Direction: ledger.Debit, AmountMinor: 1000_00},
			{AccountID: userCoinID, Direction: ledger.Credit, AmountMinor: 1000_00},
		},
	})
	if err != nil {
		t.Fatalf("Post TX A: %v", err)
	}

	// TX B — TRY: simulate commission accrual
	_, err = svc.Post(ctx, ledger.PostInput{
		Type:           "commission_accrual",
		FxPairID:       fxPairID,
		IdempotencyKey: fxPairID + ":try",
		Market:         "TR",
		Currency:       "TRY",
		Entries: []ledger.Entry{
			{AccountID: escrowID, Direction: ledger.Debit, AmountMinor: 2000_00},
			{AccountID: commID, Direction: ledger.Credit, AmountMinor: 2000_00},
		},
	})
	if err != nil {
		t.Fatalf("Post TX B: %v", err)
	}

	// Per-currency D=C holds for both currencies
	if net := netBalance(t, pool, "TRY_COIN"); net != 0 {
		t.Errorf("TRY_COIN net %d ≠ 0", net)
	}
	if net := netBalance(t, pool, "TRY"); net != 0 {
		t.Errorf("TRY net %d ≠ 0", net)
	}

	// Both transactions have the same fx_pair_id
	var count int
	_ = pool.QueryRow(ctx,
		"SELECT COUNT(*) FROM wallet_schema.transactions WHERE fx_pair_id = $1", fxPairID).Scan(&count)
	if count != 2 {
		t.Errorf("want 2 transactions with fx_pair_id=%q, got %d", fxPairID, count)
	}
	t.Logf("PASS: FX pair, both currencies balanced, fx_pair_id=%s", fxPairID)
}

// ── Test D: Lazy wallet open — idempotent, race-safe ─────────────────────────

func TestIntegration_LazyWalletOpen(t *testing.T) {
	svc, pool := newTestSvc(t)
	ctx := context.Background()

	const uniqueUserID = int64(70003)

	// First call: creates the account.
	id1, err := svc.OpenOrFindUserWallet(ctx, uniqueUserID, "TRY_COIN")
	if err != nil || id1 <= 0 {
		t.Fatalf("first OpenOrFindUserWallet: id=%d err=%v", id1, err)
	}

	// Second call: finds the existing account.
	id2, err := svc.OpenOrFindUserWallet(ctx, uniqueUserID, "TRY_COIN")
	if err != nil {
		t.Fatalf("second OpenOrFindUserWallet: %v", err)
	}
	if id1 != id2 {
		t.Fatalf("id mismatch: first=%d second=%d", id1, id2)
	}

	// Exactly one account row in DB.
	var count int
	_ = pool.QueryRow(ctx,
		"SELECT COUNT(*) FROM wallet_schema.accounts WHERE owner_type='user' AND owner_id=$1 AND currency='TRY_COIN'",
		uniqueUserID).Scan(&count)
	if count != 1 {
		t.Errorf("want 1 account row, got %d", count)
	}

	// Row has correct fields.
	var acctType, ownerType, status string
	_ = pool.QueryRow(ctx,
		"SELECT type, owner_type, status FROM wallet_schema.accounts WHERE id=$1", id1).
		Scan(&acctType, &ownerType, &status)
	if acctType != "liability:wallet:user" {
		t.Errorf("wrong type: %q", acctType)
	}
	if ownerType != "user" {
		t.Errorf("wrong owner_type: %q", ownerType)
	}
	if status != "active" {
		t.Errorf("wrong status: %q", status)
	}
	t.Logf("PASS: lazy wallet open; id=%d type=%s owner_type=%s status=%s", id1, acctType, ownerType, status)
}

// ── Test D2: Seller payable lazy open ─────────────────────────────────────────

func TestIntegration_LazySellerPayableOpen(t *testing.T) {
	svc, pool := newTestSvc(t)
	ctx := context.Background()

	const uniqueSellerID = int64(80001)

	id1, err := svc.FindOrOpenSellerPayable(ctx, uniqueSellerID, "TRY")
	if err != nil || id1 <= 0 {
		t.Fatalf("FindOrOpenSellerPayable: id=%d err=%v", id1, err)
	}
	id2, err := svc.FindOrOpenSellerPayable(ctx, uniqueSellerID, "TRY")
	if err != nil || id1 != id2 {
		t.Fatalf("idempotent: id1=%d id2=%d err=%v", id1, id2, err)
	}

	var count int
	_ = pool.QueryRow(ctx,
		"SELECT COUNT(*) FROM wallet_schema.accounts WHERE owner_type='seller' AND owner_id=$1 AND currency='TRY'",
		uniqueSellerID).Scan(&count)
	if count != 1 {
		t.Errorf("want 1 seller payable account, got %d", count)
	}
	t.Logf("PASS: seller payable lazy open; id=%d", id1)
}

// ── Test E: MV refresh worker ─────────────────────────────────────────────────

func TestIntegration_RefreshWorker(t *testing.T) {
	svc, pool := newTestSvc(t)
	ctx := context.Background()

	const uniqueUserID = int64(70004)
	distID, _ := svc.FindAccount(ctx, "equity:cashback_distribution", "TRY_COIN")
	walletID, _ := svc.OpenOrFindUserWallet(ctx, uniqueUserID, "TRY_COIN")

	// Post a transaction.
	const amount = int64(250_00)
	_, err := svc.Post(ctx, ledger.PostInput{
		Type:           "cashback_payment",
		IdempotencyKey: "integ:e:refresh:1",
		Market:         "TR",
		Currency:       "TRY_COIN",
		Entries: []ledger.Entry{
			{AccountID: distID, Direction: ledger.Debit, AmountMinor: amount},
			{AccountID: walletID, Direction: ledger.Credit, AmountMinor: amount},
		},
	})
	if err != nil {
		t.Fatalf("Post: %v", err)
	}

	// Before refresh: strict balance has the amount; MV may be 0 (new account).
	strict, _ := svc.GetBalanceStrict(ctx, walletID)
	if strict != amount {
		t.Errorf("strict balance: want %d, got %d", amount, strict)
	}

	// Trigger refresh via RefreshWorker.RefreshOnce.
	worker := wallet.NewRefreshWorker(pool, 0, nil)
	if err := worker.RefreshOnce(ctx); err != nil {
		t.Fatalf("RefreshOnce: %v", err)
	}

	// After refresh: MV balance should match.
	mv, err := svc.GetBalance(ctx, walletID)
	if err != nil {
		t.Fatalf("GetBalance (MV): %v", err)
	}
	if mv != amount {
		t.Errorf("MV balance after refresh: want %d, got %d", amount, mv)
	}
	t.Logf("PASS: strict=%d MV=%d after RefreshOnce", strict, mv)
}

// ── Test F: Concurrent OpenOrFindUserWallet race ──────────────────────────────

func TestIntegration_ConcurrentLazyOpen(t *testing.T) {
	svc, pool := newTestSvc(t)
	ctx := context.Background()

	const uniqueUserID = int64(70005)
	const goroutines = 10

	results := make([]int64, goroutines)
	errs := make([]error, goroutines)
	var wg sync.WaitGroup
	for i := 0; i < goroutines; i++ {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			results[idx], errs[idx] = svc.OpenOrFindUserWallet(ctx, uniqueUserID, "TRY_COIN")
		}(i)
	}
	wg.Wait()

	for i, err := range errs {
		if err != nil {
			t.Errorf("goroutine %d: %v", i, err)
		}
	}

	first := results[0]
	if first <= 0 {
		t.Fatalf("invalid accountID %d", first)
	}
	for i, r := range results {
		if r != first {
			t.Errorf("goroutine %d returned accountID=%d, want %d", i, r, first)
		}
	}

	// Exactly one row in DB regardless of race outcome.
	var count int
	_ = pool.QueryRow(ctx,
		"SELECT COUNT(*) FROM wallet_schema.accounts WHERE owner_type='user' AND owner_id=$1 AND currency='TRY_COIN'",
		uniqueUserID).Scan(&count)
	if count != 1 {
		t.Errorf("want 1 account row after %d concurrent opens, got %d", goroutines, count)
	}
	t.Logf("PASS: %d goroutines all got accountID=%d; DB count=%d", goroutines, first, count)
}

// ── Test G: Append-only rule (UPDATE silently swallowed) ─────────────────────

func TestIntegration_AppendOnlyRule(t *testing.T) {
	svc, pool := newTestSvc(t)
	ctx := context.Background()

	distID, _ := svc.FindAccount(ctx, "equity:cashback_distribution", "TRY_COIN")
	walletID, _ := svc.OpenOrFindUserWallet(ctx, int64(70006), "TRY_COIN")

	txnID, err := svc.Post(ctx, ledger.PostInput{
		Type: "cashback_payment", IdempotencyKey: "integ:g:appendonly:1",
		Market: "TR", Currency: "TRY_COIN",
		Entries: []ledger.Entry{
			{AccountID: distID, Direction: ledger.Debit, AmountMinor: 100},
			{AccountID: walletID, Direction: ledger.Credit, AmountMinor: 100},
		},
	})
	if err != nil {
		t.Fatalf("Post: %v", err)
	}

	// Fetch an entry ID
	var entryID int64
	_ = pool.QueryRow(ctx,
		"SELECT id FROM wallet_schema.ledger_entries WHERE transaction_id=$1 AND direction='C' LIMIT 1",
		txnID).Scan(&entryID)
	if entryID == 0 {
		t.Fatal("no ledger entry found")
	}

	// Attempt UPDATE — PostgreSQL RULE silently swallows it (DO INSTEAD NOTHING)
	_, _ = pool.Exec(ctx,
		"UPDATE wallet_schema.ledger_entries SET amount_minor = 999999 WHERE id = $1", entryID)

	// Verify the amount is unchanged.
	var storedAmount int64
	_ = pool.QueryRow(ctx,
		"SELECT amount_minor FROM wallet_schema.ledger_entries WHERE id = $1", entryID).Scan(&storedAmount)
	if storedAmount != 100 {
		t.Errorf("append-only violated: amount_minor changed to %d (expected 100)", storedAmount)
	}
	t.Logf("PASS: UPDATE silently swallowed by RULE; entry id=%d amount unchanged=100", entryID)
}
