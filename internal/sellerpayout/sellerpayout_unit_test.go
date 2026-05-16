package sellerpayout

import (
	"context"
	"errors"
	"fmt"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/mopro/platform/internal/ledger"
	"github.com/mopro/platform/pkg/timex"
)

// ── mock repository ────────────────────────────────────────────────────────────

type mockPayoutRepo struct {
	payouts             []Payout
	insertPayoutErr     error
	findPayoutByKeyRet  Payout
	findPayoutByKeyErr  error

	batches             []PayoutBatch
	insertBatchRet      PayoutBatch
	insertBatchErr      error
	findBatchByKeyRet   PayoutBatch
	findBatchByKeyErr   error
	updateBatchPaidErr  error
	updateBatchStatusErr error
	updateBatchPspErr   error

	pspAccounts          map[int64]SellerPspAccount
	upsertPspErr         error
	findPspErr           error

	insertAlertErr      error
	hasOpenAlert        bool
	hasOpenAlertErr     error

	withTxErr           error
	lastBatchStatus     BatchStatus
	lastAlertInserted   *LedgerAlert
}

func (m *mockPayoutRepo) InsertPayout(_ context.Context, _ pgx.Tx, p Payout) (Payout, error) {
	if m.insertPayoutErr != nil {
		return Payout{}, m.insertPayoutErr
	}
	p.ID = 1
	return p, nil
}

func (m *mockPayoutRepo) FindPayoutByKey(_ context.Context, _ string) (Payout, error) {
	return m.findPayoutByKeyRet, m.findPayoutByKeyErr
}

func (m *mockPayoutRepo) FetchScheduledPayouts(_ context.Context, _ time.Time, _ string, _ int) ([]Payout, error) {
	defer func() { m.payouts = nil }()
	return m.payouts, nil
}

func (m *mockPayoutRepo) UpdatePayoutBatchID(_ context.Context, _ pgx.Tx, _, _ int64) error { return nil }

func (m *mockPayoutRepo) InsertBatch(_ context.Context, _ pgx.Tx, b PayoutBatch) (PayoutBatch, error) {
	if m.insertBatchErr != nil {
		return PayoutBatch{}, m.insertBatchErr
	}
	if m.insertBatchRet.ID != 0 {
		return m.insertBatchRet, nil
	}
	b.ID = 100
	b.Status = BatchStatusProcessing
	return b, nil
}

func (m *mockPayoutRepo) FindBatchByKey(_ context.Context, _ string) (PayoutBatch, error) {
	return m.findBatchByKeyRet, m.findBatchByKeyErr
}

func (m *mockPayoutRepo) UpdateBatchPspTransferID(_ context.Context, _ int64, _ string) error {
	return m.updateBatchPspErr
}

func (m *mockPayoutRepo) UpdateBatchPaid(_ context.Context, _ pgx.Tx, _, _ int64, _ string, _ time.Time) error {
	return m.updateBatchPaidErr
}

func (m *mockPayoutRepo) MarkPayoutsPaidByBatch(_ context.Context, _ pgx.Tx, _ int64) error { return nil }

func (m *mockPayoutRepo) UpdateBatchStatus(_ context.Context, _ int64, status BatchStatus, _ string) error {
	m.lastBatchStatus = status
	return m.updateBatchStatusErr
}

func (m *mockPayoutRepo) FetchProcessingBatches(_ context.Context) ([]PayoutBatch, error) {
	defer func() { m.batches = nil }()
	return m.batches, nil
}

func (m *mockPayoutRepo) UpsertSellerPspAccount(_ context.Context, acc SellerPspAccount) error {
	if m.pspAccounts == nil {
		m.pspAccounts = make(map[int64]SellerPspAccount)
	}
	m.pspAccounts[acc.SellerID] = acc
	return m.upsertPspErr
}

func (m *mockPayoutRepo) FindSellerPspAccount(_ context.Context, sellerID int64) (SellerPspAccount, error) {
	if m.findPspErr != nil {
		return SellerPspAccount{}, m.findPspErr
	}
	if m.pspAccounts != nil {
		if acc, ok := m.pspAccounts[sellerID]; ok {
			return acc, nil
		}
	}
	return SellerPspAccount{PspMemberID: "member123", SellerID: sellerID, Market: "TR"}, nil
}

func (m *mockPayoutRepo) InsertLedgerAlert(_ context.Context, alert LedgerAlert) error {
	m.lastAlertInserted = &alert
	return m.insertAlertErr
}

func (m *mockPayoutRepo) HasOpenAlertForBatch(_ context.Context, _ int64) (bool, error) {
	return m.hasOpenAlert, m.hasOpenAlertErr
}

func (m *mockPayoutRepo) WithTx(_ context.Context, _ pgx.TxIsoLevel, fn func(pgx.Tx) error) error {
	if m.withTxErr != nil {
		return m.withTxErr
	}
	return fn(nil)
}

// ── mock WalletPoster ──────────────────────────────────────────────────────────

type mockWalletPoster struct {
	findAccountID  int64
	findAccountErr error
	payableID      int64
	payableErr     error
	postTxnID      int64
	postErr        error
}

func (m *mockWalletPoster) PostInTx(_ context.Context, _ pgx.Tx, _ ledger.PostInput) (int64, error) {
	return m.postTxnID, m.postErr
}
func (m *mockWalletPoster) FindAccount(_ context.Context, _, _ string) (int64, error) {
	return m.findAccountID, m.findAccountErr
}
func (m *mockWalletPoster) FindOrOpenSellerPayable(_ context.Context, _ int64, _ string) (int64, error) {
	return m.payableID, m.payableErr
}

// ── mock PspTransferer ─────────────────────────────────────────────────────────

type mockPsp struct {
	transferResp  TransferResponse
	transferErr   error
	statusResp    TransferResponse
	statusErr     error
	callCount     int
}

func (m *mockPsp) Transfer(_ context.Context, _ TransferRequest) (TransferResponse, error) {
	m.callCount++
	return m.transferResp, m.transferErr
}
func (m *mockPsp) GetTransferStatus(_ context.Context, _ string) (TransferResponse, error) {
	return m.statusResp, m.statusErr
}

// ── mock CalendarLoader ────────────────────────────────────────────────────────

type mockCalLoader struct{}

func (m *mockCalLoader) Load(_ context.Context, market string) (timex.Calendar, error) {
	return timex.Calendar{Market: market, Holidays: map[string]struct{}{}}, nil
}

// ── helpers ────────────────────────────────────────────────────────────────────

func newSvc(repo Repository, wp WalletPoster, psp PspTransferer) Service {
	return NewService(repo, wp, psp, &mockCalLoader{}, "TRY", nil)
}

func scheduledPayout(id, sellerID int64) Payout {
	return Payout{
		ID:             id,
		OrderID:        1000,
		SellerID:       sellerID,
		AmountMinor:    5000_00, // 5000.00 TRY
		Currency:       "TRY",
		DeliveredAt:    time.Now().AddDate(0, 0, -5),
		UnlockAt:       time.Now().AddDate(0, 0, -2),
		Status:         PayoutStatusScheduled,
		Market:         "TR",
		IdempotencyKey: "payout:order_1000:seller_" + strFromInt(sellerID),
	}
}

func strFromInt(n int64) string {
	return fmt.Sprintf("%d", n)
}

// ── trackingRepo — records which repo methods are called inside WithTx ────────

// trackingRepo embeds mockPayoutRepo and records every repository method call
// that occurs while a WithTx callback is executing. Used to verify that
// SchedulePayoutsForOrder's WithTx block contains ONLY InsertPayout.
type trackingRepo struct {
	*mockPayoutRepo
	inTx    bool
	txCalls []string // method names called while inTx==true
}

func (r *trackingRepo) WithTx(ctx context.Context, level pgx.TxIsoLevel, fn func(pgx.Tx) error) error {
	r.inTx = true
	r.txCalls = nil
	err := fn(nil)
	r.inTx = false
	return err
}

func (r *trackingRepo) recordTx(name string) {
	if r.inTx {
		r.txCalls = append(r.txCalls, name)
	}
}

func (r *trackingRepo) InsertPayout(ctx context.Context, tx pgx.Tx, p Payout) (Payout, error) {
	r.recordTx("InsertPayout")
	return r.mockPayoutRepo.InsertPayout(ctx, tx, p)
}

func (r *trackingRepo) InsertBatch(ctx context.Context, tx pgx.Tx, b PayoutBatch) (PayoutBatch, error) {
	r.recordTx("InsertBatch")
	return r.mockPayoutRepo.InsertBatch(ctx, tx, b)
}

func (r *trackingRepo) UpdatePayoutBatchID(ctx context.Context, tx pgx.Tx, payoutID, batchID int64) error {
	r.recordTx("UpdatePayoutBatchID")
	return r.mockPayoutRepo.UpdatePayoutBatchID(ctx, tx, payoutID, batchID)
}

func (r *trackingRepo) UpdateBatchPaid(ctx context.Context, tx pgx.Tx, batchID, ledgerTxnID int64, pspTransferID string, paidAt time.Time) error {
	r.recordTx("UpdateBatchPaid")
	return r.mockPayoutRepo.UpdateBatchPaid(ctx, tx, batchID, ledgerTxnID, pspTransferID, paidAt)
}

func (r *trackingRepo) MarkPayoutsPaidByBatch(ctx context.Context, tx pgx.Tx, batchID int64) error {
	r.recordTx("MarkPayoutsPaidByBatch")
	return r.mockPayoutRepo.MarkPayoutsPaidByBatch(ctx, tx, batchID)
}

// ── SchedulePayoutsForOrder ────────────────────────────────────────────────────

func TestSchedulePayoutsForOrder_NoPreviousPayouts(t *testing.T) {
	repo := &mockPayoutRepo{findPayoutByKeyErr: ErrPayoutNotFound}
	wp := &mockWalletPoster{}
	psp := &mockPsp{}
	svc := newSvc(repo, wp, psp)

	err := svc.SchedulePayoutsForOrder(context.Background(), OrderDeliveredEvent{
		OrderID:     1,
		DeliveredAt: time.Now(),
		Market:      "TR",
		Currency:    "TRY",
		Items: []DeliveredItem{
			{SellerID: 10, SellerNetMinor: 1000},
		},
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestSchedulePayoutsForOrder_Idempotent(t *testing.T) {
	existing := Payout{ID: 99}
	repo := &mockPayoutRepo{findPayoutByKeyRet: existing}
	svc := newSvc(repo, &mockWalletPoster{}, &mockPsp{})

	err := svc.SchedulePayoutsForOrder(context.Background(), OrderDeliveredEvent{
		OrderID: 1,
		Items:   []DeliveredItem{{SellerID: 10, SellerNetMinor: 1000}},
		Market:  "TR",
	})
	if err != nil {
		t.Fatalf("idempotent call should not return error: %v", err)
	}
}

func TestSchedulePayoutsForOrder_NoItems(t *testing.T) {
	repo := &mockPayoutRepo{}
	svc := newSvc(repo, &mockWalletPoster{}, &mockPsp{})
	err := svc.SchedulePayoutsForOrder(context.Background(), OrderDeliveredEvent{
		OrderID: 1,
		Items:   []DeliveredItem{},
		Market:  "TR",
	})
	if err != nil {
		t.Fatalf("empty items should not error: %v", err)
	}
}

// TestSchedulePayoutsForOrder_TxContainsOnlyInsert enforces the INVARIANT that
// the WithTx block in SchedulePayoutsForOrder contains ONLY InsertPayout calls.
// Any other write inside that tx would be silently discarded on a concurrent
// retry (when ErrPayoutAlreadyExists aborts the tx).
func TestSchedulePayoutsForOrder_TxContainsOnlyInsert(t *testing.T) {
	repo := &trackingRepo{mockPayoutRepo: &mockPayoutRepo{}}
	svc := newSvc(repo, &mockWalletPoster{}, &mockPsp{})

	err := svc.SchedulePayoutsForOrder(context.Background(), OrderDeliveredEvent{
		OrderID:     42,
		DeliveredAt: time.Now(),
		Market:      "TR",
		Currency:    "TRY",
		Items: []DeliveredItem{
			{SellerID: 10, SellerNetMinor: 500},
			{SellerID: 11, SellerNetMinor: 750},
		},
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	// Only InsertPayout is permitted inside the transaction.
	for _, call := range repo.txCalls {
		if call != "InsertPayout" {
			t.Errorf("forbidden repo call inside WithTx: %q — only InsertPayout is permitted; "+
				"any other write would be silently rolled back on concurrent retry", call)
		}
	}
	// Two sellers → exactly two InsertPayout calls.
	var insertCount int
	for _, call := range repo.txCalls {
		if call == "InsertPayout" {
			insertCount++
		}
	}
	if insertCount != 2 {
		t.Errorf("expected 2 InsertPayout calls inside WithTx (one per seller), got %d", insertCount)
	}
}

// ── RunDailyPayouts ────────────────────────────────────────────────────────────

func TestRunDailyPayouts_NoDuePayouts(t *testing.T) {
	repo := &mockPayoutRepo{} // FetchScheduledPayouts returns nil
	wp := &mockWalletPoster{findAccountID: 1, payableID: 2, postTxnID: 99}
	svc := newSvc(repo, wp, &mockPsp{})

	res, err := svc.RunDailyPayouts(context.Background(), time.Now(), "TR", "TRY")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if res.Batched != 0 {
		t.Fatalf("expected batched=0, got %d", res.Batched)
	}
}

func TestRunDailyPayouts_HappyPath_ShadowMode(t *testing.T) {
	p := scheduledPayout(1, 10)
	repo := &mockPayoutRepo{
		payouts:           []Payout{p},
		findBatchByKeyErr: ErrBatchNotFound,
	}
	wp := &mockWalletPoster{findAccountID: 5, payableID: 6, postTxnID: 99}
	psp := &mockPsp{
		transferResp: TransferResponse{TransferID: "shadow_synthetic_100", Status: "paid"},
	}
	svc := newSvc(repo, wp, psp)

	res, err := svc.RunDailyPayouts(context.Background(), time.Now(), "TR", "TRY")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if res.Batched != 1 {
		t.Fatalf("expected batched=1, got %d", res.Batched)
	}
	if res.Failed != 0 {
		t.Fatalf("expected failed=0, got %d", res.Failed)
	}
}

func TestRunDailyPayouts_BatchAlreadyPaid_Skipped(t *testing.T) {
	p := scheduledPayout(1, 10)
	repo := &mockPayoutRepo{
		payouts: []Payout{p},
		findBatchByKeyRet: PayoutBatch{ID: 1, Status: BatchStatusPaid},
	}
	svc := newSvc(repo, &mockWalletPoster{findAccountID: 1}, &mockPsp{})

	res, err := svc.RunDailyPayouts(context.Background(), time.Now(), "TR", "TRY")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if res.Skipped != 1 {
		t.Fatalf("expected skipped=1, got %d", res.Skipped)
	}
}

func TestRunDailyPayouts_PspError_Failed(t *testing.T) {
	p := scheduledPayout(1, 10)
	repo := &mockPayoutRepo{
		payouts:           []Payout{p},
		findBatchByKeyErr: ErrBatchNotFound,
	}
	wp := &mockWalletPoster{findAccountID: 5, payableID: 6}
	psp := &mockPsp{transferErr: errors.New("sipay: connection refused")}
	svc := newSvc(repo, wp, psp)

	res, err := svc.RunDailyPayouts(context.Background(), time.Now(), "TR", "TRY")
	if err != nil {
		t.Fatalf("RunDailyPayouts should not return top-level error: %v", err)
	}
	if res.Failed != 1 {
		t.Fatalf("expected failed=1, got %d", res.Failed)
	}
}

func TestRunDailyPayouts_FraudHoldAlert_Tx2Skipped(t *testing.T) {
	p := scheduledPayout(1, 10)
	repo := &mockPayoutRepo{
		payouts:           []Payout{p},
		findBatchByKeyErr: ErrBatchNotFound,
		hasOpenAlert:      true, // fraud hold active
	}
	wp := &mockWalletPoster{findAccountID: 5, payableID: 6}
	psp := &mockPsp{transferResp: TransferResponse{TransferID: "transfer_abc", Status: "paid"}}
	svc := newSvc(repo, wp, psp)

	res, err := svc.RunDailyPayouts(context.Background(), time.Now(), "TR", "TRY")
	if err != nil {
		t.Fatalf("unexpected top-level error: %v", err)
	}
	// Tx2 was skipped (fraud hold), not failed — batch stays processing for reconcile.
	if res.Batched != 1 {
		t.Fatalf("expected batched=1, got %d", res.Batched)
	}
}

func TestRunDailyPayouts_FindEscrowError_ReturnsError(t *testing.T) {
	repo := &mockPayoutRepo{}
	wp := &mockWalletPoster{findAccountErr: errors.New("escrow account not found")}
	svc := newSvc(repo, wp, &mockPsp{})

	_, err := svc.RunDailyPayouts(context.Background(), time.Now(), "TR", "TRY")
	if err == nil {
		t.Fatal("expected error when escrow account not found")
	}
}

func TestRunDailyPayouts_MultipleSellersBatched(t *testing.T) {
	payouts := []Payout{
		scheduledPayout(1, 10),
		scheduledPayout(2, 11),
		scheduledPayout(3, 12),
	}
	repo := &mockPayoutRepo{
		payouts:           payouts,
		findBatchByKeyErr: ErrBatchNotFound,
	}
	wp := &mockWalletPoster{findAccountID: 5, payableID: 6, postTxnID: 99}
	psp := &mockPsp{transferResp: TransferResponse{TransferID: "t1", Status: "paid"}}
	svc := newSvc(repo, wp, psp)

	res, err := svc.RunDailyPayouts(context.Background(), time.Now(), "TR", "TRY")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if res.Batched != 3 {
		t.Fatalf("expected batched=3 (one per seller), got %d", res.Batched)
	}
}

// ── HandlePspOnboarded ─────────────────────────────────────────────────────────

func TestHandlePspOnboarded_UpsertsCalled(t *testing.T) {
	repo := &mockPayoutRepo{}
	svc := newSvc(repo, &mockWalletPoster{}, &mockPsp{})

	err := svc.HandlePspOnboarded(context.Background(), PspOnboardedEvent{
		SellerID:    99,
		PspMemberID: "sipay_member_99",
		Market:      "TR",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	acc, ok := repo.pspAccounts[99]
	if !ok {
		t.Fatal("expected psp account to be stored")
	}
	if acc.PspMemberID != "sipay_member_99" {
		t.Fatalf("expected psp_member_id=sipay_member_99, got %s", acc.PspMemberID)
	}
}

// ── HandleFraudHoldSet ─────────────────────────────────────────────────────────

func TestHandleFraudHoldSet_InsertsAlert(t *testing.T) {
	repo := &mockPayoutRepo{}
	svc := newSvc(repo, &mockWalletPoster{}, &mockPsp{})

	err := svc.HandleFraudHoldSet(context.Background(), FraudHoldSetEvent{
		SellerID: 55,
		Market:   "TR",
		Currency: "TRY",
		Reason:   "suspected account takeover",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if repo.lastAlertInserted == nil {
		t.Fatal("expected ledger_alert to be inserted")
	}
	if repo.lastAlertInserted.Severity != "SEV1" {
		t.Fatalf("expected severity=SEV1, got %s", repo.lastAlertInserted.Severity)
	}
}

// ── ReconcileProcessing ────────────────────────────────────────────────────────

func TestReconcileProcessing_NoBatches(t *testing.T) {
	repo := &mockPayoutRepo{} // FetchProcessingBatches returns nil
	svc := newSvc(repo, &mockWalletPoster{}, &mockPsp{})

	if err := svc.ReconcileProcessing(context.Background()); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestReconcileProcessing_StuckBatch_PspTransferIdStored(t *testing.T) {
	b := PayoutBatch{
		ID: 50, SellerID: 10, Currency: "TRY", TotalAmountMinor: 1000,
		PspTransferID:  "known_transfer_abc",
		IdempotencyKey: "payout:seller_10:date_20260516:ccy_TRY",
		Market:         "TR",
	}
	repo := &mockPayoutRepo{batches: []PayoutBatch{b}}
	wp := &mockWalletPoster{findAccountID: 5, payableID: 6, postTxnID: 99}
	psp := &mockPsp{statusResp: TransferResponse{TransferID: "known_transfer_abc", Status: "paid"}}
	svc := newSvc(repo, wp, psp)

	if err := svc.ReconcileProcessing(context.Background()); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	// Tx2 ran: no ambiguous status set.
	if repo.lastBatchStatus == BatchStatusAmbiguous {
		t.Fatal("should not have been marked ambiguous")
	}
}

func TestReconcileProcessing_AmbiguousTransferID(t *testing.T) {
	b := PayoutBatch{
		ID: 51, SellerID: 11, Currency: "TRY", TotalAmountMinor: 2000,
		PspTransferID:  "original_transfer",
		IdempotencyKey: "payout:seller_11:date_20260516:ccy_TRY",
		Market:         "TR",
	}
	repo := &mockPayoutRepo{batches: []PayoutBatch{b}}
	wp := &mockWalletPoster{findAccountID: 5, payableID: 6}
	psp := &mockPsp{statusResp: TransferResponse{TransferID: "different_transfer", Status: "paid"}}
	svc := newSvc(repo, wp, psp)

	_ = svc.ReconcileProcessing(context.Background())

	if repo.lastBatchStatus != BatchStatusAmbiguous {
		t.Fatalf("expected batch status=ambiguous, got %s", repo.lastBatchStatus)
	}
	if repo.lastAlertInserted == nil {
		t.Fatal("expected CRITICAL ledger_alert to be inserted for ambiguous transfer")
	}
	if repo.lastAlertInserted.AlertType != "ambiguous_transfer" {
		t.Fatalf("expected alert_type=ambiguous_transfer, got %s", repo.lastAlertInserted.AlertType)
	}
}

// ── batchIdempotencyKey ────────────────────────────────────────────────────────

func TestBatchIdempotencyKey(t *testing.T) {
	date := time.Date(2026, 5, 16, 0, 0, 0, 0, time.UTC)
	key := batchIdempotencyKey(42, date, "TRY")
	want := "payout:seller_42:date_20260516:ccy_TRY"
	if key != want {
		t.Fatalf("want %s, got %s", want, key)
	}
}
