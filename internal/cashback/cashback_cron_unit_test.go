package cashback

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/mopro/platform/internal/ledger"
	"github.com/mopro/platform/internal/outbox"
)

// ── mock repository ───────────────────────────────────────────────────────────

type mockCashbackRepo struct {
	plans              []Plan
	insertPaymentRet   Payment
	insertPaymentErr   error
	walletStatus       string
	walletStatusErr    error
	withTxErr          error
	markPaidErr        error
	markFailedErr      error
	updatePeriodErr    error
	lastDistribPeriod  int
}

func (m *mockCashbackRepo) InsertPlan(_ context.Context, _ pgx.Tx, p Plan) (Plan, error) {
	return p, nil
}
func (m *mockCashbackRepo) FindPlanByOrderID(_ context.Context, _ int64) (Plan, error) {
	return Plan{}, ErrPlanNotFound
}
func (m *mockCashbackRepo) FetchPlansBatch(_ context.Context, _ int, _ time.Time, _ string, _ int) ([]Plan, error) {
	defer func() { m.plans = nil }() // return once then empty
	return m.plans, nil
}
func (m *mockCashbackRepo) InsertPayment(_ context.Context, _ pgx.Tx, pay Payment) (Payment, error) {
	if m.insertPaymentErr != nil {
		return Payment{}, m.insertPaymentErr
	}
	pay.ID = 1
	return pay, nil
}
func (m *mockCashbackRepo) MarkPaymentPaid(_ context.Context, _ pgx.Tx, _ int64, _ int64, _ time.Time) error {
	return m.markPaidErr
}
func (m *mockCashbackRepo) MarkPaymentFailed(_ context.Context, _ pgx.Tx, _ int64, _ string) error {
	return m.markFailedErr
}
func (m *mockCashbackRepo) UpdateLastDistributedPeriod(_ context.Context, _ pgx.Tx, _ int64, period int) error {
	m.lastDistribPeriod = period
	return m.updatePeriodErr
}
func (m *mockCashbackRepo) GetWalletAccountStatus(_ context.Context, _ int64) (string, error) {
	return m.walletStatus, m.walletStatusErr
}
func (m *mockCashbackRepo) WithTx(_ context.Context, _ pgx.TxIsoLevel, fn func(pgx.Tx) error) error {
	if m.withTxErr != nil {
		return m.withTxErr
	}
	return fn(nil)
}

// ── mock WalletPoster ─────────────────────────────────────────────────────────

type mockWalletPoster struct {
	postTxnID      int64
	postErr        error
	findAccountID  int64
	findAccountErr error
	openWalletID   int64
	openWalletErr  error
}

func (m *mockWalletPoster) PostInTx(_ context.Context, _ pgx.Tx, _ ledger.PostInput) (int64, error) {
	return m.postTxnID, m.postErr
}
func (m *mockWalletPoster) FindAccount(_ context.Context, _, _ string) (int64, error) {
	return m.findAccountID, m.findAccountErr
}
func (m *mockWalletPoster) OpenOrFindUserWallet(_ context.Context, _ int64, _ string) (int64, error) {
	return m.openWalletID, m.openWalletErr
}

// ── helpers ───────────────────────────────────────────────────────────────────

func newCronSvc(repo Repository, wp WalletPoster) Service {
	return NewService(repo, &mockCronOutbox{}, nil, "TRY_COIN", wp, nil)
}

type mockCronOutbox struct{}

func (m *mockCronOutbox) Insert(_ context.Context, _ pgx.Tx, _ outbox.Row) error { return nil }
func (m *mockCronOutbox) FetchUnpublished(_ context.Context, _ pgx.Tx, _ int) ([]outbox.Row, error) {
	return nil, nil
}
func (m *mockCronOutbox) MarkPublished(_ context.Context, _ pgx.Tx, _ int64) error { return nil }

func activePlan(id, userID int64) Plan {
	return Plan{
		ID:                 id,
		UserID:             userID,
		MonthlyAmountMinor: 500,
		Currency:           "TRY_COIN",
		StartDate:          time.Now().AddDate(0, -1, 0),
		Status:             PlanStatusActive,
		Market:             "TR",
	}
}

// ── unit tests ────────────────────────────────────────────────────────────────

func TestRunMonth_NoPlansDue(t *testing.T) {
	repo := &mockCashbackRepo{} // FetchPlansBatch returns nil
	wp := &mockWalletPoster{findAccountID: 1, openWalletID: 2, postTxnID: 99}
	svc := newCronSvc(repo, wp)

	res, err := svc.RunMonth(context.Background(), 202607, time.Now(), "TRY_COIN")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if res.Processed != 0 || res.Failed != 0 {
		t.Fatalf("want zero processed/failed, got %+v", res)
	}
}

func TestRunMonth_HappyPath(t *testing.T) {
	plan := activePlan(1, 100)
	repo := &mockCashbackRepo{plans: []Plan{plan}, walletStatus: "active"}
	wp := &mockWalletPoster{findAccountID: 10, openWalletID: 20, postTxnID: 99}
	svc := newCronSvc(repo, wp)

	res, err := svc.RunMonth(context.Background(), 202607, time.Now(), "TRY_COIN")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if res.Processed != 1 {
		t.Fatalf("want processed=1, got %d", res.Processed)
	}
	if repo.lastDistribPeriod != 202607 {
		t.Fatalf("want lastDistribPeriod=202607, got %d", repo.lastDistribPeriod)
	}
}

func TestRunMonth_WalletFrozen_Skipped(t *testing.T) {
	plan := activePlan(1, 100)
	repo := &mockCashbackRepo{plans: []Plan{plan}, walletStatus: "frozen"}
	wp := &mockWalletPoster{findAccountID: 10, openWalletID: 20}
	svc := newCronSvc(repo, wp)

	res, err := svc.RunMonth(context.Background(), 202607, time.Now(), "TRY_COIN")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if res.Skipped != 1 || res.Processed != 0 {
		t.Fatalf("want skipped=1 processed=0, got %+v", res)
	}
}

func TestRunMonth_WalletMissing_Skipped(t *testing.T) {
	plan := activePlan(1, 100)
	// GetWalletAccountStatus returns "" (account not found) → treated as not active → skip
	repo := &mockCashbackRepo{plans: []Plan{plan}, walletStatus: ""}
	wp := &mockWalletPoster{findAccountID: 10, openWalletID: 20}
	svc := newCronSvc(repo, wp)

	res, err := svc.RunMonth(context.Background(), 202607, time.Now(), "TRY_COIN")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if res.Skipped != 1 {
		t.Fatalf("want skipped=1, got %+v", res)
	}
}

func TestRunMonth_DuplicatePayment_Skipped(t *testing.T) {
	plan := activePlan(1, 100)
	repo := &mockCashbackRepo{
		plans:            []Plan{plan},
		walletStatus:     "active",
		insertPaymentErr: ErrPaymentAlreadyExists,
	}
	wp := &mockWalletPoster{findAccountID: 10, openWalletID: 20}
	svc := newCronSvc(repo, wp)

	res, err := svc.RunMonth(context.Background(), 202607, time.Now(), "TRY_COIN")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if res.Skipped != 1 {
		t.Fatalf("want skipped=1 (idempotent re-run), got %+v", res)
	}
}

func TestRunMonth_PostInTxError_Failed(t *testing.T) {
	plan := activePlan(1, 100)
	repo := &mockCashbackRepo{plans: []Plan{plan}, walletStatus: "active"}
	wp := &mockWalletPoster{
		findAccountID: 10,
		openWalletID:  20,
		postErr:       errors.New("ledger: some db error"),
	}
	svc := newCronSvc(repo, wp)

	res, err := svc.RunMonth(context.Background(), 202607, time.Now(), "TRY_COIN")
	if err != nil {
		t.Fatalf("unexpected top-level error: %v", err)
	}
	if res.Failed != 1 {
		t.Fatalf("want failed=1, got %+v", res)
	}
}

func TestRunMonth_FindEquityAccountError_ReturnsError(t *testing.T) {
	repo := &mockCashbackRepo{}
	wp := &mockWalletPoster{findAccountErr: errors.New("equity account not found")}
	svc := newCronSvc(repo, wp)

	_, err := svc.RunMonth(context.Background(), 202607, time.Now(), "TRY_COIN")
	if err == nil {
		t.Fatal("expected error when equity account lookup fails")
	}
}

func TestRunMonth_MultiplePlans(t *testing.T) {
	plans := []Plan{activePlan(1, 101), activePlan(2, 102), activePlan(3, 103)}
	repo := &mockCashbackRepo{plans: plans, walletStatus: "active"}
	wp := &mockWalletPoster{findAccountID: 10, openWalletID: 20, postTxnID: 99}
	svc := newCronSvc(repo, wp)

	res, err := svc.RunMonth(context.Background(), 202607, time.Now(), "TRY_COIN")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if res.Processed != 3 {
		t.Fatalf("want processed=3, got %d", res.Processed)
	}
}

func TestPeriodHelpers(t *testing.T) {
	t.Run("timeToPeriod", func(t *testing.T) {
		ts := time.Date(2026, 7, 15, 10, 30, 0, 0, time.UTC)
		if got := timeToPeriod(ts); got != 202607 {
			t.Fatalf("timeToPeriod: got %d, want 202607", got)
		}
	})
	t.Run("periodToFirstDay", func(t *testing.T) {
		d := periodToFirstDay(202607)
		if d.Year() != 2026 || d.Month() != 7 || d.Day() != 1 {
			t.Fatalf("periodToFirstDay: got %v, want 2026-07-01", d)
		}
	})
}

func TestParseMarketConfigs(t *testing.T) {
	configs, err := ParseMarketConfigs("TR:TRY_COIN,DE:EUR_COIN")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(configs) != 2 {
		t.Fatalf("want 2 configs, got %d", len(configs))
	}
	if configs[0].Market != "TR" || configs[0].Currency != "TRY_COIN" {
		t.Fatalf("unexpected config[0]: %+v", configs[0])
	}
	if configs[1].Market != "DE" || configs[1].Currency != "EUR_COIN" {
		t.Fatalf("unexpected config[1]: %+v", configs[1])
	}
}

func TestParseMarketConfigs_Invalid(t *testing.T) {
	cases := []string{"", "TR", "TR:", ":TRY_COIN"}
	for _, raw := range cases {
		_, err := ParseMarketConfigs(raw)
		if err == nil {
			t.Errorf("ParseMarketConfigs(%q): expected error", raw)
		}
	}
}
