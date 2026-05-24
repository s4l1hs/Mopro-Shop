package api_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"

	finapi "github.com/mopro/platform/internal/api"
	genfin "github.com/mopro/platform/internal/api/gen/fin"
	"github.com/mopro/platform/internal/cashback"
	identitymw "github.com/mopro/platform/internal/identity/middleware"
	"github.com/mopro/platform/internal/identity/testutil"
	"github.com/mopro/platform/internal/ledger"
	"github.com/mopro/platform/internal/wallet"
)

// ── wallet.Service stub ────────────────────────────────────────────────────────

type stubWalletSvc struct {
	findByOwnerAnyStatusFn func(ctx context.Context, ownerType string, ownerID int64, currency string) (int64, string, error)
	getBalanceFn           func(ctx context.Context, accountID int64) (int64, error)
	listEntriesFn          func(ctx context.Context, accountID int64, limit int, beforeID int64) ([]wallet.LedgerEntryRow, error)
}

func (s *stubWalletSvc) Post(_ context.Context, _ ledger.PostInput) (int64, error) {
	panic("not expected in unit test")
}
func (s *stubWalletSvc) PostInTx(_ context.Context, _ pgx.Tx, _ ledger.PostInput) (int64, error) {
	panic("not expected in unit test")
}
func (s *stubWalletSvc) GetBalance(ctx context.Context, accountID int64) (int64, error) {
	if s.getBalanceFn != nil {
		return s.getBalanceFn(ctx, accountID)
	}
	return 0, nil
}
func (s *stubWalletSvc) GetBalanceStrict(_ context.Context, _ int64) (int64, error) { return 0, nil }
func (s *stubWalletSvc) FindAccount(_ context.Context, _, _ string) (int64, error) {
	return 0, nil
}
func (s *stubWalletSvc) OpenOrFindUserWallet(_ context.Context, _ int64, _ string) (int64, error) {
	return 1, nil
}
func (s *stubWalletSvc) FindOrOpenSellerPayable(_ context.Context, _ int64, _ string) (int64, error) {
	return 1, nil
}
func (s *stubWalletSvc) FindAccountByOwnerAnyStatus(ctx context.Context, ownerType string, ownerID int64, currency string) (int64, string, error) {
	if s.findByOwnerAnyStatusFn != nil {
		return s.findByOwnerAnyStatusFn(ctx, ownerType, ownerID, currency)
	}
	return 1, "active", nil
}
func (s *stubWalletSvc) GetAccount(_ context.Context, _ int64) (wallet.Account, error) {
	return wallet.Account{}, nil
}
func (s *stubWalletSvc) SetReadOnly(_ context.Context, _ string) error { return nil }
func (s *stubWalletSvc) ClearReadOnly(_ context.Context) error         { return nil }
func (s *stubWalletSvc) InvalidateReadOnlyCache()                      {}
func (s *stubWalletSvc) StartRefresher(_ context.Context)              {}
func (s *stubWalletSvc) ListEntriesByAccount(ctx context.Context, accountID int64, limit int, beforeID int64) ([]wallet.LedgerEntryRow, error) {
	if s.listEntriesFn != nil {
		return s.listEntriesFn(ctx, accountID, limit, beforeID)
	}
	return nil, nil
}

// ── cashback.Repository stub ───────────────────────────────────────────────────

type stubCashbackRepo struct {
	listPlansFn    func(ctx context.Context, userID int64, limit int, beforeID int64, status *cashback.PlanStatus) ([]cashback.Plan, error)
	getPlanFn      func(ctx context.Context, userID, planID int64) (cashback.Plan, error)
	listPaymentsFn func(ctx context.Context, planID int64, limit int, beforeID int64) ([]cashback.Payment, error)
}

func (r *stubCashbackRepo) InsertPlanIfAbsent(_ context.Context, _ pgx.Tx, _ cashback.Plan) (cashback.Plan, bool, error) {
	panic("not expected in unit test")
}
func (r *stubCashbackRepo) ListDuePlans(_ context.Context, _ time.Time, _ int) ([]cashback.Plan, error) {
	panic("not expected in unit test")
}
func (r *stubCashbackRepo) IncrPaymentsMade(_ context.Context, _ pgx.Tx, _ int64) (int, bool, error) {
	panic("not expected in unit test")
}
func (r *stubCashbackRepo) WithTx(_ context.Context, _ pgx.TxIsoLevel, _ func(pgx.Tx) error) error {
	panic("not expected in unit test")
}
func (r *stubCashbackRepo) ListPlansByUser(ctx context.Context, userID int64, limit int, beforeID int64, status *cashback.PlanStatus) ([]cashback.Plan, error) {
	if r.listPlansFn != nil {
		return r.listPlansFn(ctx, userID, limit, beforeID, status)
	}
	return nil, nil
}
func (r *stubCashbackRepo) GetPlan(ctx context.Context, userID, planID int64) (cashback.Plan, error) {
	if r.getPlanFn != nil {
		return r.getPlanFn(ctx, userID, planID)
	}
	return cashback.Plan{}, cashback.ErrPlanNotFound
}
func (r *stubCashbackRepo) ListPaymentsByPlanID(ctx context.Context, planID int64, limit int, beforeID int64) ([]cashback.Payment, error) {
	if r.listPaymentsFn != nil {
		return r.listPaymentsFn(ctx, planID, limit, beforeID)
	}
	return nil, nil
}

// ── test setup helpers ─────────────────────────────────────────────────────────

// buildHandler wires the FinServer into an http.Handler with JWT auth middleware.
func buildHandler(t *testing.T, walletSvc wallet.Service, cashbackRepo cashback.Repository) http.Handler {
	t.Helper()
	srv := &finapi.FinServer{
		WalletSvc:       walletSvc,
		CashbackRepo:    cashbackRepo,
		DefaultCurrency: "TRY_COIN",
	}
	mux := http.NewServeMux()
	genfin.HandlerFromMuxWithBaseURL(genfin.NewStrictHandler(srv, nil), mux, "")
	return identitymw.RequireAuth(testutil.TestSigner(t))(mux)
}

// authedReq builds an http.Request with a valid JWT for the given userID.
func authedReq(t *testing.T, method, path string, userID int64) *http.Request {
	t.Helper()
	req := httptest.NewRequest(method, path, nil)
	token := testutil.IssueTestAccessToken(t, userID, "TR")
	req.Header.Set("Authorization", "Bearer "+token)
	return req
}

// ── IDOR security tests ────────────────────────────────────────────────────────

// TestGetCashbackPlan_OtherUserPlan_Returns404 verifies that user 2 cannot access
// user 1's cashback plan. The server MUST return 404 (NOT 403) to avoid leaking
// plan existence.
func TestGetCashbackPlan_OtherUserPlan_Returns404(t *testing.T) {
	const planOwner int64 = 1
	const attacker int64 = 2
	const planID int64 = 99

	repo := &stubCashbackRepo{
		getPlanFn: func(_ context.Context, userID, pid int64) (cashback.Plan, error) {
			// Plan exists for owner but NOT for attacker — DB-level IDOR prevention.
			if userID == planOwner && pid == planID {
				return cashback.Plan{ID: planID, UserID: planOwner, Status: cashback.PlanStatusActive}, nil
			}
			return cashback.Plan{}, cashback.ErrPlanNotFound
		},
	}
	h := buildHandler(t, &stubWalletSvc{}, repo)

	w := httptest.NewRecorder()
	h.ServeHTTP(w, authedReq(t, http.MethodGet, "/v1/cashback/plans/99", attacker))

	if w.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d (body: %s)", w.Code, w.Body.String())
	}
}

// TestListCashbackPayments_OtherUserPlan_Returns404 verifies that requesting
// payments for a plan owned by another user returns 404, not the payment list.
func TestListCashbackPayments_OtherUserPlan_Returns404(t *testing.T) {
	const planOwner int64 = 1
	const attacker int64 = 2
	const planID int64 = 99

	repo := &stubCashbackRepo{
		getPlanFn: func(_ context.Context, userID, pid int64) (cashback.Plan, error) {
			if userID == planOwner && pid == planID {
				return cashback.Plan{ID: planID, UserID: planOwner}, nil
			}
			return cashback.Plan{}, cashback.ErrPlanNotFound
		},
		listPaymentsFn: func(_ context.Context, _ int64, _ int, _ int64) ([]cashback.Payment, error) {
			t.Error("listPayments must not be called when IDOR check fails")
			return nil, nil
		},
	}
	h := buildHandler(t, &stubWalletSvc{}, repo)

	w := httptest.NewRecorder()
	h.ServeHTTP(w, authedReq(t, http.MethodGet, "/v1/cashback/plans/99/payments", attacker))

	if w.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", w.Code)
	}
}

// TestListWalletTransactions_OnlyShowsCurrentUserWallet verifies that wallet lookup
// uses the context user ID, not any other ID.
func TestListWalletTransactions_OnlyShowsCurrentUserWallet(t *testing.T) {
	const ctxUser int64 = 42
	var capturedOwnerID int64

	walletSvc := &stubWalletSvc{
		findByOwnerAnyStatusFn: func(_ context.Context, ownerType string, ownerID int64, _ string) (int64, string, error) {
			capturedOwnerID = ownerID
			return 10, "active", nil
		},
		listEntriesFn: func(_ context.Context, _ int64, _ int, _ int64) ([]wallet.LedgerEntryRow, error) {
			return nil, nil
		},
	}
	h := buildHandler(t, walletSvc, &stubCashbackRepo{})

	w := httptest.NewRecorder()
	h.ServeHTTP(w, authedReq(t, http.MethodGet, "/v1/wallet/transactions", ctxUser))

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d (body: %s)", w.Code, w.Body.String())
	}
	if capturedOwnerID != ctxUser {
		t.Fatalf("wallet lookup used ownerID=%d, want %d", capturedOwnerID, ctxUser)
	}
}

// TestListCashbackPlans_OtherUserPlans_NotVisible verifies that ListPlansByUserID
// is called with the context user ID, so other users' plans are never returned.
func TestListCashbackPlans_OtherUserPlans_NotVisible(t *testing.T) {
	const ctxUser int64 = 7
	var capturedUserID int64

	repo := &stubCashbackRepo{
		listPlansFn: func(_ context.Context, userID int64, _ int, _ int64, _ *cashback.PlanStatus) ([]cashback.Plan, error) {
			capturedUserID = userID
			return nil, nil
		},
	}
	h := buildHandler(t, &stubWalletSvc{}, repo)

	w := httptest.NewRecorder()
	h.ServeHTTP(w, authedReq(t, http.MethodGet, "/v1/cashback/plans", ctxUser))

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d (body: %s)", w.Code, w.Body.String())
	}
	if capturedUserID != ctxUser {
		t.Fatalf("ListPlansByUserID called with userID=%d, want %d", capturedUserID, ctxUser)
	}
}

// TestGetWalletBalance_AlwaysScopedToContextUserID verifies balance lookup is
// scoped to the authenticated user ID from context.
func TestGetWalletBalance_AlwaysScopedToContextUserID(t *testing.T) {
	const ctxUser int64 = 55
	var capturedOwnerID int64

	walletSvc := &stubWalletSvc{
		findByOwnerAnyStatusFn: func(_ context.Context, _ string, ownerID int64, _ string) (int64, string, error) {
			capturedOwnerID = ownerID
			return 5, "active", nil
		},
		getBalanceFn: func(_ context.Context, _ int64) (int64, error) {
			return 12345, nil
		},
	}
	h := buildHandler(t, walletSvc, &stubCashbackRepo{})

	w := httptest.NewRecorder()
	h.ServeHTTP(w, authedReq(t, http.MethodGet, "/v1/wallet/balance", ctxUser))

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
	if capturedOwnerID != ctxUser {
		t.Fatalf("balance lookup used ownerID=%d, want %d", capturedOwnerID, ctxUser)
	}

	var body genfin.WalletBalance
	if err := json.NewDecoder(w.Body).Decode(&body); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if body.AmountMinor != 12345 {
		t.Fatalf("expected amount_minor=12345, got %d", body.AmountMinor)
	}
}

// ── general behavior tests ─────────────────────────────────────────────────────

func TestGetWalletBalance_NoWallet_ReturnsZeroBalance(t *testing.T) {
	walletSvc := &stubWalletSvc{
		findByOwnerAnyStatusFn: func(_ context.Context, _ string, _ int64, _ string) (int64, string, error) {
			return 0, "", nil // wallet never created
		},
	}
	h := buildHandler(t, walletSvc, &stubCashbackRepo{})

	w := httptest.NewRecorder()
	h.ServeHTTP(w, authedReq(t, http.MethodGet, "/v1/wallet/balance", 1))

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
	var body genfin.WalletBalance
	if err := json.NewDecoder(w.Body).Decode(&body); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if body.AmountMinor != 0 {
		t.Fatalf("expected 0 balance for wallet-less user, got %d", body.AmountMinor)
	}
}

func TestListCashbackPlans_EmptyList_Returns200(t *testing.T) {
	repo := &stubCashbackRepo{
		listPlansFn: func(_ context.Context, _ int64, _ int, _ int64, _ *cashback.PlanStatus) ([]cashback.Plan, error) {
			return nil, nil
		},
	}
	h := buildHandler(t, &stubWalletSvc{}, repo)

	w := httptest.NewRecorder()
	h.ServeHTTP(w, authedReq(t, http.MethodGet, "/v1/cashback/plans", 1))

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
}

func TestGetCashbackPlan_OwnPlan_Returns200(t *testing.T) {
	const userID int64 = 3
	const planID int64 = 7
	repo := &stubCashbackRepo{
		getPlanFn: func(_ context.Context, uid, pid int64) (cashback.Plan, error) {
			if uid == userID && pid == planID {
				return cashback.Plan{
					ID:                       planID,
					OrderID:                  100,
					UserID:                   userID,
					MonthlyAmountMinor:       625,
					Currency:                 "TRY_COIN",
					ReferenceInterestRateBps: 5000,
					StartDate:                time.Date(2026, 1, 18, 0, 0, 0, 0, time.UTC),
					Status:                   cashback.PlanStatusActive,
					CreatedAt:                time.Now().UTC(),
				}, nil
			}
			return cashback.Plan{}, cashback.ErrPlanNotFound
		},
	}
	h := buildHandler(t, &stubWalletSvc{}, repo)

	w := httptest.NewRecorder()
	h.ServeHTTP(w, authedReq(t, http.MethodGet, "/v1/cashback/plans/7", userID))

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d (body: %s)", w.Code, w.Body.String())
	}
}

func TestMissingAuth_Returns401(t *testing.T) {
	h := buildHandler(t, &stubWalletSvc{}, &stubCashbackRepo{})
	w := httptest.NewRecorder()
	h.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/v1/wallet/balance", nil))
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 without auth, got %d", w.Code)
	}
}
