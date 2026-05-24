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
	duePlans        []Plan
	insertPlanRet   Plan
	insertPlanIsNew bool
	insertPlanErr   error
	incrCountRet    int
	incrCompleted   bool
	incrErr         error
	withTxErr       error
	getPlans        []Plan
}

func (m *mockCashbackRepo) InsertPlanIfAbsent(_ context.Context, _ pgx.Tx, p Plan) (Plan, bool, error) {
	if m.insertPlanErr != nil {
		return Plan{}, false, m.insertPlanErr
	}
	if m.insertPlanRet.ID != 0 {
		return m.insertPlanRet, m.insertPlanIsNew, nil
	}
	p.ID = 1
	return p, true, nil
}

func (m *mockCashbackRepo) ListDuePlans(_ context.Context, _ time.Time, _ int) ([]Plan, error) {
	defer func() { m.duePlans = nil }() // return once then empty
	return m.duePlans, nil
}

func (m *mockCashbackRepo) IncrPaymentsMade(_ context.Context, _ pgx.Tx, _ int64) (int, bool, error) {
	return m.incrCountRet, m.incrCompleted, m.incrErr
}

func (m *mockCashbackRepo) WithTx(_ context.Context, _ pgx.TxIsoLevel, fn func(pgx.Tx) error) error {
	if m.withTxErr != nil {
		return m.withTxErr
	}
	return fn(nil)
}

func (m *mockCashbackRepo) GetPlan(_ context.Context, _, _ int64) (Plan, error) {
	if len(m.getPlans) == 0 {
		return Plan{}, ErrPlanNotFound
	}
	p := m.getPlans[0]
	m.getPlans = m.getPlans[1:]
	return p, nil
}

func (m *mockCashbackRepo) ListPlansByUser(_ context.Context, _ int64, _ int, _ int64, _ *PlanStatus) ([]Plan, error) {
	return nil, nil
}

func (m *mockCashbackRepo) ListPaymentsByPlanID(_ context.Context, _ int64, _ int, _ int64) ([]Payment, error) {
	return nil, nil
}

// ── mock WalletPoster ─────────────────────────────────────────────────────────

type mockWalletPoster struct {
	postTxnID          int64
	postErr            error
	findAccountID      int64
	findAccountErr     error
	openWalletID       int64
	openWalletErr      error
	findByOwnerAnyID   int64
	findByOwnerAnyStat string
	findByOwnerAnyErr  error
	postCalled         bool
}

func (m *mockWalletPoster) PostInTx(_ context.Context, _ pgx.Tx, _ ledger.PostInput) (int64, error) {
	m.postCalled = true
	return m.postTxnID, m.postErr
}
func (m *mockWalletPoster) FindAccount(_ context.Context, _, _ string) (int64, error) {
	return m.findAccountID, m.findAccountErr
}
func (m *mockWalletPoster) OpenOrFindUserWallet(_ context.Context, _ int64, _ string) (int64, error) {
	return m.openWalletID, m.openWalletErr
}
func (m *mockWalletPoster) FindAccountByOwnerAnyStatus(_ context.Context, _ string, _ int64, _ string) (int64, string, error) {
	return m.findByOwnerAnyID, m.findByOwnerAnyStat, m.findByOwnerAnyErr
}

// ── helpers ───────────────────────────────────────────────────────────────────

func newCronSvc(repo Repository, wp WalletPoster) Service {
	return NewService(repo, &mockCronOutbox{}, nil, "TRY_COIN", wp, nil, nil)
}

type mockCronOutbox struct{}

func (m *mockCronOutbox) Insert(_ context.Context, _ pgx.Tx, _ outbox.Row) error { return nil }
func (m *mockCronOutbox) FetchUnpublished(_ context.Context, _ pgx.Tx, _ int) ([]outbox.Row, error) {
	return nil, nil
}
func (m *mockCronOutbox) MarkPublished(_ context.Context, _ pgx.Tx, _ int64) error { return nil }

// activePlan builds a v8-compatible active Plan for unit tests.
func activePlan(id, userID int64) Plan {
	return Plan{
		ID:                     id,
		UserID:                 userID,
		PriceMinor:             100000,
		CommissionBps:          2000,
		TotalMonths:            78,
		MonthlyAmountMinor:     1282,
		MonthlyAmountLastMinor: 1344, // 77*1282 + 1344 = 100000
		PaymentsMade:           0,
		Currency:               "TRY_COIN",
		StartDate:              time.Now().AddDate(0, -1, 0),
		Status:                 PlanStatusActive,
		Market:                 "TR",
	}
}

// ── unit tests ────────────────────────────────────────────────────────────────

func TestPayMonthlyInstallments_NoPlansDue(t *testing.T) {
	repo := &mockCashbackRepo{} // ListDuePlans returns nil
	wp := &mockWalletPoster{findAccountID: 1, openWalletID: 2, postTxnID: 99}
	svc := newCronSvc(repo, wp)

	summary, err := svc.PayMonthlyInstallments(context.Background(), time.Now())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if summary.Processed != 0 || summary.Failed != 0 {
		t.Fatalf("want zero processed/failed, got %+v", summary)
	}
}

func TestPayMonthlyInstallments_HappyPath(t *testing.T) {
	plan := activePlan(1, 100)
	repo := &mockCashbackRepo{
		duePlans:      []Plan{plan},
		incrCountRet:  1,
		incrCompleted: false,
	}
	wp := &mockWalletPoster{findAccountID: 10, openWalletID: 20, postTxnID: 99}
	svc := newCronSvc(repo, wp)

	summary, err := svc.PayMonthlyInstallments(context.Background(), time.Now())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if summary.Processed != 1 {
		t.Fatalf("want processed=1, got %d", summary.Processed)
	}
	if !wp.postCalled {
		t.Fatal("PostInTx must be called for active plan")
	}
}

func TestPayMonthlyInstallments_FinalInstallment_Completed(t *testing.T) {
	plan := activePlan(1, 100)
	plan.PaymentsMade = plan.TotalMonths - 1 // next payment is the last one
	repo := &mockCashbackRepo{
		duePlans:      []Plan{plan},
		incrCountRet:  plan.TotalMonths,
		incrCompleted: true,
	}
	wp := &mockWalletPoster{findAccountID: 10, openWalletID: 20, postTxnID: 99}
	svc := newCronSvc(repo, wp)

	summary, err := svc.PayMonthlyInstallments(context.Background(), time.Now())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if summary.Processed != 1 {
		t.Fatalf("want processed=1, got %d", summary.Processed)
	}
}

func TestPayMonthlyInstallments_WalletFrozen_Skipped(t *testing.T) {
	plan := activePlan(1, 100)
	repo := &mockCashbackRepo{duePlans: []Plan{plan}}
	wp := &mockWalletPoster{
		findAccountID:      10,
		openWalletID:       20,
		findByOwnerAnyID:   20,
		findByOwnerAnyStat: "frozen",
	}
	svc := newCronSvc(repo, wp)

	summary, err := svc.PayMonthlyInstallments(context.Background(), time.Now())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if summary.Skipped != 1 || summary.Processed != 0 {
		t.Fatalf("want skipped=1 processed=0, got %+v", summary)
	}
	if wp.postCalled {
		t.Fatal("PostInTx must not be called for frozen wallet")
	}
}

func TestPayMonthlyInstallments_WalletDoesNotExist_LazilyCreated(t *testing.T) {
	plan := activePlan(1, 100)
	repo := &mockCashbackRepo{
		duePlans:      []Plan{plan},
		incrCountRet:  1,
		incrCompleted: false,
	}
	wp := &mockWalletPoster{
		findAccountID:      10,
		openWalletID:       20,
		findByOwnerAnyID:   0,
		findByOwnerAnyStat: "",
		postTxnID:          99,
	}
	svc := newCronSvc(repo, wp)

	summary, err := svc.PayMonthlyInstallments(context.Background(), time.Now())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if summary.Processed != 1 {
		t.Fatalf("want processed=1 (lazy create), got %+v", summary)
	}
}

func TestPayMonthlyInstallments_WalletSuspended_Skipped(t *testing.T) {
	plan := activePlan(1, 100)
	repo := &mockCashbackRepo{duePlans: []Plan{plan}}
	wp := &mockWalletPoster{
		findAccountID:      10,
		openWalletID:       20,
		findByOwnerAnyID:   20,
		findByOwnerAnyStat: "suspended",
	}
	svc := newCronSvc(repo, wp)

	summary, err := svc.PayMonthlyInstallments(context.Background(), time.Now())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if summary.Skipped != 1 || summary.Processed != 0 || summary.Failed != 0 {
		t.Fatalf("want skipped=1 processed=0 failed=0, got %+v", summary)
	}
	if wp.postCalled {
		t.Fatal("PostInTx must not be called for suspended wallet")
	}
}

func TestPayMonthlyInstallments_PostInTxError_Failed(t *testing.T) {
	plan := activePlan(1, 100)
	repo := &mockCashbackRepo{duePlans: []Plan{plan}}
	wp := &mockWalletPoster{
		findAccountID: 10,
		openWalletID:  20,
		postErr:       errors.New("ledger: some db error"),
	}
	svc := newCronSvc(repo, wp)

	summary, err := svc.PayMonthlyInstallments(context.Background(), time.Now())
	if err != nil {
		t.Fatalf("unexpected top-level error: %v", err)
	}
	if summary.Failed != 1 {
		t.Fatalf("want failed=1, got %+v", summary)
	}
}

func TestPayMonthlyInstallments_FindEquityAccountError_ReturnsError(t *testing.T) {
	plan := activePlan(1, 100)
	repo := &mockCashbackRepo{duePlans: []Plan{plan}}
	wp := &mockWalletPoster{findAccountErr: errors.New("equity account not found")}
	svc := newCronSvc(repo, wp)

	_, err := svc.PayMonthlyInstallments(context.Background(), time.Now())
	if err == nil {
		t.Fatal("expected error when equity account lookup fails")
	}
}

func TestPayMonthlyInstallments_MultiplePlans(t *testing.T) {
	plans := []Plan{activePlan(1, 101), activePlan(2, 102), activePlan(3, 103)}
	repo := &mockCashbackRepo{
		duePlans:      plans,
		incrCountRet:  1,
		incrCompleted: false,
	}
	wp := &mockWalletPoster{findAccountID: 10, openWalletID: 20, postTxnID: 99}
	svc := newCronSvc(repo, wp)

	summary, err := svc.PayMonthlyInstallments(context.Background(), time.Now())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if summary.Processed != 3 {
		t.Fatalf("want processed=3, got %d", summary.Processed)
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
