package wallet

import (
	"context"
	"errors"
	"testing"

	"github.com/jackc/pgx/v5"

	"github.com/mopro/platform/internal/ledger"
	"github.com/mopro/platform/internal/outbox"
)

// ── mock repository ───────────────────────────────────────────────────────────

type mockRepo struct {
	insertTxnID           int64
	insertTxnErr          error
	getTxnID              int64
	getTxnErr             error
	insertEntryErr        error
	getCurrencies         map[int64]string
	getCurrErr            error
	findByTypeAcct        Account
	findByTypeErr         error
	findByOwnerAcct       Account
	findByOwnerErr        error
	findByOwnerAnyAcct    Account
	findByOwnerAnyErr     error
	getAccountAcct        Account
	getAccountErr         error
	insertAcctID          int64
	insertAcctErr         error
	balanceMV             int64
	balanceMVErr          error
	balanceStrict         int64
	balanceStrictErr      error
	sysState              SystemState
	sysStateErr           error
	setSysStateCalled     bool
}

func (m *mockRepo) WithTx(ctx context.Context, level pgx.TxIsoLevel, fn func(pgx.Tx) error) error {
	return fn(nil) // nil tx — unit tests don't exercise DB
}
func (m *mockRepo) InsertTransaction(_ context.Context, _ pgx.Tx, _ ledger.Transaction) (int64, error) {
	return m.insertTxnID, m.insertTxnErr
}
func (m *mockRepo) GetTransactionByIdempotencyKey(_ context.Context, _ string) (int64, error) {
	return m.getTxnID, m.getTxnErr
}
func (m *mockRepo) InsertEntry(_ context.Context, _ pgx.Tx, _ int64, _ ledger.Entry) error {
	return m.insertEntryErr
}
func (m *mockRepo) GetAccountCurrencies(_ context.Context, _ []int64) (map[int64]string, error) {
	return m.getCurrencies, m.getCurrErr
}
func (m *mockRepo) FindAccountByType(_ context.Context, _, _ string) (Account, error) {
	return m.findByTypeAcct, m.findByTypeErr
}
func (m *mockRepo) FindAccountByOwner(_ context.Context, _ string, _ int64, _ string) (Account, error) {
	return m.findByOwnerAcct, m.findByOwnerErr
}
func (m *mockRepo) FindAccountByOwnerAnyStatus(_ context.Context, _ string, _ int64, _ string) (Account, error) {
	return m.findByOwnerAnyAcct, m.findByOwnerAnyErr
}
func (m *mockRepo) GetAccount(_ context.Context, _ int64) (Account, error) {
	return m.getAccountAcct, m.getAccountErr
}
func (m *mockRepo) InsertAccount(_ context.Context, _ pgx.Tx, _ Account) (int64, error) {
	return m.insertAcctID, m.insertAcctErr
}
func (m *mockRepo) GetBalanceMV(_ context.Context, _ int64) (int64, error) {
	return m.balanceMV, m.balanceMVErr
}
func (m *mockRepo) GetBalanceStrict(_ context.Context, _ int64) (int64, error) {
	return m.balanceStrict, m.balanceStrictErr
}
func (m *mockRepo) GetSystemState(_ context.Context) (SystemState, error) {
	return m.sysState, m.sysStateErr
}
func (m *mockRepo) SetSystemState(_ context.Context, _ pgx.Tx, _ bool, _ string) error {
	m.setSysStateCalled = true
	return nil
}

// ── mock outbox ───────────────────────────────────────────────────────────────

type mockOutbox struct{ insertErr error }

func (m *mockOutbox) Insert(_ context.Context, _ pgx.Tx, _ outbox.Row) error {
	return m.insertErr
}
func (m *mockOutbox) FetchUnpublished(_ context.Context, _ pgx.Tx, _ int) ([]outbox.Row, error) {
	return nil, nil
}
func (m *mockOutbox) MarkPublished(_ context.Context, _ pgx.Tx, _ int64) error { return nil }

// ── helpers ───────────────────────────────────────────────────────────────────

func newUnitSvc(repo Repository, ob outbox.Repository) Service {
	return NewService(repo, ob, nil)
}

func validInput(currencies map[int64]string) ledger.PostInput {
	ids := make([]int64, 0, len(currencies))
	entries := make([]ledger.Entry, 0, len(currencies))
	first := true
	for id := range currencies {
		dir := ledger.Credit
		if first {
			dir = ledger.Debit
			first = false
		}
		ids = append(ids, id)
		entries = append(entries, ledger.Entry{AccountID: id, Direction: dir, AmountMinor: 100})
	}
	_ = ids
	return ledger.PostInput{
		Type:           "cashback_payment",
		IdempotencyKey: "unit-test:key-1",
		Market:         "TR",
		Currency:       "TRY_COIN",
		Entries:        entries,
	}
}

// ── validation tests ──────────────────────────────────────────────────────────

func TestPostInTx_EmptyIdempotencyKey(t *testing.T) {
	svc := newUnitSvc(&mockRepo{}, &mockOutbox{})
	in := ledger.PostInput{Currency: "TRY_COIN", Entries: []ledger.Entry{
		{AccountID: 1, Direction: ledger.Debit, AmountMinor: 100},
		{AccountID: 2, Direction: ledger.Credit, AmountMinor: 100},
	}}
	_, err := svc.PostInTx(context.Background(), nil, in)
	if !errors.Is(err, ErrIdempotencyKeyRequired) {
		t.Fatalf("want ErrIdempotencyKeyRequired, got %v", err)
	}
}

func TestPostInTx_EmptyCurrency(t *testing.T) {
	svc := newUnitSvc(&mockRepo{}, &mockOutbox{})
	in := ledger.PostInput{IdempotencyKey: "k", Entries: []ledger.Entry{
		{AccountID: 1, Direction: ledger.Debit, AmountMinor: 100},
		{AccountID: 2, Direction: ledger.Credit, AmountMinor: 100},
	}}
	_, err := svc.PostInTx(context.Background(), nil, in)
	if !errors.Is(err, ErrCurrencyRequired) {
		t.Fatalf("want ErrCurrencyRequired, got %v", err)
	}
}

func TestPostInTx_TooFewEntries(t *testing.T) {
	svc := newUnitSvc(&mockRepo{}, &mockOutbox{})
	in := ledger.PostInput{IdempotencyKey: "k", Currency: "TRY", Entries: []ledger.Entry{
		{AccountID: 1, Direction: ledger.Debit, AmountMinor: 100},
	}}
	_, err := svc.PostInTx(context.Background(), nil, in)
	if !errors.Is(err, ErrInvalidAmount) {
		t.Fatalf("want ErrInvalidAmount, got %v", err)
	}
}

func TestPostInTx_ZeroAmount(t *testing.T) {
	svc := newUnitSvc(&mockRepo{}, &mockOutbox{})
	in := ledger.PostInput{IdempotencyKey: "k", Currency: "TRY", Entries: []ledger.Entry{
		{AccountID: 1, Direction: ledger.Debit, AmountMinor: 0},
		{AccountID: 2, Direction: ledger.Credit, AmountMinor: 100},
	}}
	_, err := svc.PostInTx(context.Background(), nil, in)
	if !errors.Is(err, ErrInvalidAmount) {
		t.Fatalf("want ErrInvalidAmount, got %v", err)
	}
}

func TestPostInTx_NegativeAmount(t *testing.T) {
	svc := newUnitSvc(&mockRepo{}, &mockOutbox{})
	in := ledger.PostInput{IdempotencyKey: "k", Currency: "TRY", Entries: []ledger.Entry{
		{AccountID: 1, Direction: ledger.Debit, AmountMinor: -1},
		{AccountID: 2, Direction: ledger.Credit, AmountMinor: 100},
	}}
	_, err := svc.PostInTx(context.Background(), nil, in)
	if !errors.Is(err, ErrInvalidAmount) {
		t.Fatalf("want ErrInvalidAmount, got %v", err)
	}
}

func TestPostInTx_InvalidDirection(t *testing.T) {
	svc := newUnitSvc(&mockRepo{}, &mockOutbox{})
	in := ledger.PostInput{IdempotencyKey: "k", Currency: "TRY", Entries: []ledger.Entry{
		{AccountID: 1, Direction: "X", AmountMinor: 100},
		{AccountID: 2, Direction: ledger.Credit, AmountMinor: 100},
	}}
	_, err := svc.PostInTx(context.Background(), nil, in)
	if !errors.Is(err, ErrInvalidAmount) {
		t.Fatalf("want ErrInvalidAmount, got %v", err)
	}
}

// ── currency mismatch guard ───────────────────────────────────────────────────

func TestPostInTx_CurrencyMismatch(t *testing.T) {
	repo := &mockRepo{
		getCurrencies: map[int64]string{1: "TRY", 2: "TRY_COIN"}, // mixed!
	}
	svc := newUnitSvc(repo, &mockOutbox{})
	in := ledger.PostInput{
		IdempotencyKey: "k", Currency: "TRY",
		Entries: []ledger.Entry{
			{AccountID: 1, Direction: ledger.Debit, AmountMinor: 100},
			{AccountID: 2, Direction: ledger.Credit, AmountMinor: 100},
		},
	}
	_, err := svc.PostInTx(context.Background(), nil, in)
	if !errors.Is(err, ErrCurrencyMismatch) {
		t.Fatalf("want ErrCurrencyMismatch, got %v", err)
	}
}

func TestPostInTx_AccountNotFoundInCurrencyCheck(t *testing.T) {
	repo := &mockRepo{
		getCurrencies: map[int64]string{1: "TRY"}, // account 2 missing
	}
	svc := newUnitSvc(repo, &mockOutbox{})
	in := ledger.PostInput{
		IdempotencyKey: "k", Currency: "TRY",
		Entries: []ledger.Entry{
			{AccountID: 1, Direction: ledger.Debit, AmountMinor: 100},
			{AccountID: 2, Direction: ledger.Credit, AmountMinor: 100},
		},
	}
	_, err := svc.PostInTx(context.Background(), nil, in)
	if !errors.Is(err, ErrAccountNotFound) {
		t.Fatalf("want ErrAccountNotFound, got %v", err)
	}
}

// ── idempotency dedup path ────────────────────────────────────────────────────

func TestPostInTx_IdempotencyDedup(t *testing.T) {
	const originalTxnID = int64(42)
	repo := &mockRepo{
		getCurrencies: map[int64]string{1: "TRY_COIN", 2: "TRY_COIN"},
		insertTxnErr:  ledger.ErrDuplicateIdempotency, // simulates re-apply
		getTxnID:      originalTxnID,
	}
	svc := newUnitSvc(repo, &mockOutbox{})
	in := ledger.PostInput{
		IdempotencyKey: "cashback:plan_1:period_202607",
		Currency:       "TRY_COIN",
		Entries: []ledger.Entry{
			{AccountID: 1, Direction: ledger.Debit, AmountMinor: 500},
			{AccountID: 2, Direction: ledger.Credit, AmountMinor: 500},
		},
	}
	txnID, err := svc.PostInTx(context.Background(), nil, in)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if txnID != originalTxnID {
		t.Fatalf("want original txnID=%d, got %d", originalTxnID, txnID)
	}
}

// ── happy path (all mocks succeed) ───────────────────────────────────────────

func TestPostInTx_HappyPath(t *testing.T) {
	repo := &mockRepo{
		getCurrencies: map[int64]string{1: "TRY_COIN", 2: "TRY_COIN"},
		insertTxnID:   99,
	}
	svc := newUnitSvc(repo, &mockOutbox{})
	in := ledger.PostInput{
		Type: "cashback_payment", IdempotencyKey: "k", Market: "TR", Currency: "TRY_COIN",
		Entries: []ledger.Entry{
			{AccountID: 1, Direction: ledger.Debit, AmountMinor: 500},
			{AccountID: 2, Direction: ledger.Credit, AmountMinor: 500},
		},
	}
	txnID, err := svc.PostInTx(context.Background(), nil, in)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if txnID != 99 {
		t.Fatalf("want txnID=99, got %d", txnID)
	}
}

// ── FindAccount delegation ────────────────────────────────────────────────────

func TestFindAccount_Delegates(t *testing.T) {
	repo := &mockRepo{findByTypeAcct: Account{ID: 7}}
	svc := newUnitSvc(repo, &mockOutbox{})
	id, err := svc.FindAccount(context.Background(), "asset:bank:escrow", "TRY")
	if err != nil || id != 7 {
		t.Fatalf("want id=7 err=nil, got id=%d err=%v", id, err)
	}
}

func TestFindAccount_NotFound(t *testing.T) {
	repo := &mockRepo{findByTypeErr: ErrAccountNotFound}
	svc := newUnitSvc(repo, &mockOutbox{})
	_, err := svc.FindAccount(context.Background(), "no:such:type", "TRY")
	if !errors.Is(err, ErrAccountNotFound) {
		t.Fatalf("want ErrAccountNotFound, got %v", err)
	}
}

// ── read-only guard tests ────────────────────────────────────────────────────

func TestPostInTx_ErrOutboxNotConfigured(t *testing.T) {
	repo := &mockRepo{getCurrencies: map[int64]string{1: "TRY", 2: "TRY"}}
	// nil outboxRepo triggers ErrOutboxNotConfigured before any other work
	svc := NewService(repo, nil, nil)
	in := ledger.PostInput{
		IdempotencyKey: "k", Currency: "TRY",
		Entries: []ledger.Entry{
			{AccountID: 1, Direction: ledger.Debit, AmountMinor: 100},
			{AccountID: 2, Direction: ledger.Credit, AmountMinor: 100},
		},
	}
	_, err := svc.PostInTx(context.Background(), nil, in)
	if !errors.Is(err, ErrOutboxNotConfigured) {
		t.Fatalf("want ErrOutboxNotConfigured, got %v", err)
	}
}

func TestPostInTx_ErrSystemReadOnly(t *testing.T) {
	repo := &mockRepo{
		getCurrencies: map[int64]string{1: "TRY", 2: "TRY"},
		sysState:      SystemState{ReadOnly: true, ReadOnlyReason: "test"},
	}
	svc := NewService(repo, &mockOutbox{}, nil)
	in := ledger.PostInput{
		IdempotencyKey: "k", Currency: "TRY",
		Entries: []ledger.Entry{
			{AccountID: 1, Direction: ledger.Debit, AmountMinor: 100},
			{AccountID: 2, Direction: ledger.Credit, AmountMinor: 100},
		},
	}
	_, err := svc.PostInTx(context.Background(), nil, in)
	if !errors.Is(err, ErrSystemReadOnly) {
		t.Fatalf("want ErrSystemReadOnly, got %v", err)
	}
}

func TestSetReadOnly_EagerCache(t *testing.T) {
	repo := &mockRepo{}
	svc, ok := NewService(repo, &mockOutbox{}, nil).(*walletService)
	if !ok {
		t.Fatal("type assertion to *walletService failed")
	}
	if err := svc.SetReadOnly(context.Background(), "test reason"); err != nil {
		t.Fatalf("SetReadOnly: %v", err)
	}
	if !svc.sysReadOnly.Load() {
		t.Fatal("sysReadOnly should be true after SetReadOnly")
	}
	if !repo.setSysStateCalled {
		t.Fatal("SetSystemState should have been called on repo")
	}
}

func TestClearReadOnly_EagerCache(t *testing.T) {
	repo := &mockRepo{}
	svc, ok := NewService(repo, &mockOutbox{}, nil).(*walletService)
	if !ok {
		t.Fatal("type assertion to *walletService failed")
	}
	// Pre-set to true
	svc.sysReadOnly.Store(true)
	if err := svc.ClearReadOnly(context.Background()); err != nil {
		t.Fatalf("ClearReadOnly: %v", err)
	}
	if svc.sysReadOnly.Load() {
		t.Fatal("sysReadOnly should be false after ClearReadOnly")
	}
}

func TestInvalidateReadOnlyCache_ForcesRefresh(t *testing.T) {
	repo := &mockRepo{sysState: SystemState{ReadOnly: false}}
	svc, ok := NewService(repo, &mockOutbox{}, nil).(*walletService)
	if !ok {
		t.Fatal("type assertion to *walletService failed")
	}
	// Set a non-zero refreshed time so cache is considered warm
	svc.sysRefreshedAt.Store(99999999999999)
	// Invalidate the cache
	svc.InvalidateReadOnlyCache()
	if svc.sysRefreshedAt.Load() != 0 {
		t.Fatal("sysRefreshedAt should be 0 after InvalidateReadOnlyCache")
	}
}

// ── outbox event type mapping ─────────────────────────────────────────────────

func TestOutboxEventType(t *testing.T) {
	cases := []struct{ txType, want string }{
		{"cashback_payment", "fin.cashback.payment.posted.v1"},
		{"cashback_reversal", "fin.cashback.reversal.posted.v1"},
		{"seller_payout", "fin.seller.payout.posted.v1"},
		{"commission_accrual", "fin.commission.accrual.posted.v1"},
		{"fx_outbound", "fin.fx.outbound.posted.v1"},
		{"fx_inbound", "fin.fx.inbound.posted.v1"},
		{"unknown_type", "fin.ledger.posted.v1"},
	}
	for _, c := range cases {
		got := outboxEventType(c.txType)
		if got != c.want {
			t.Errorf("outboxEventType(%q) = %q, want %q", c.txType, got, c.want)
		}
	}
}
