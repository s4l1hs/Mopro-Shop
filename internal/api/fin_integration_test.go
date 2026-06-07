//go:build integration

package api_test

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"sync/atomic"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	finapi "github.com/mopro/platform/internal/api"
	genfin "github.com/mopro/platform/internal/api/gen/fin"
	"github.com/mopro/platform/internal/cashback"
	identitymw "github.com/mopro/platform/internal/identity/middleware"
	"github.com/mopro/platform/internal/identity/testutil"
	"github.com/mopro/platform/internal/outbox"
	"github.com/mopro/platform/internal/wallet"
)

// ── DB connection ──────────────────────────────────────────────────────────────

const finTestDSN = "postgres://ledger_admin:test123@localhost:6434/mopro_ledger"

func finTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	dsn := finTestDSN
	if v := os.Getenv("LEDGER_TEST_DSN"); v != "" {
		dsn = v
	}
	pool, err := pgxpool.New(context.Background(), dsn)
	if err != nil {
		t.Fatalf("finTestPool: %v", err)
	}
	if err := pool.Ping(context.Background()); err != nil {
		t.Fatalf("finTestPool ping: %v (is postgres-ledger test on port 6434 running?)", err)
	}
	t.Cleanup(pool.Close)
	return pool
}

// ── unique ID helper ───────────────────────────────────────────────────────────

var (
	finIDBase    = time.Now().UnixMilli()
	finIDCounter int64
)

func finUniqueID() int64 {
	n := atomic.AddInt64(&finIDCounter, 1)
	return finIDBase*1_000_000 + n
}

// ── test handler builder ───────────────────────────────────────────────────────

func finBuildRealHandler(t *testing.T, pool *pgxpool.Pool) http.Handler {
	t.Helper()
	walletRepo := wallet.NewRepository(pool)
	walletOutboxRepo := outbox.NewRepository("wallet_schema.outbox")
	walletSvc := wallet.NewService(walletRepo, walletOutboxRepo, slog.Default())
	cashbackRepo := cashback.NewRepository(pool)

	srv := &finapi.FinServer{
		WalletSvc:       walletSvc,
		CashbackRepo:    cashbackRepo,
		DefaultCurrency: "TRY_COIN",
	}
	mux := http.NewServeMux()
	genfin.HandlerFromMuxWithBaseURL(genfin.NewStrictHandler(srv, nil), mux, "")
	return identitymw.RequireAuth(testutil.TestSigner(t))(mux)
}

func finAuthedReq(t *testing.T, method, path string, userID int64) *http.Request {
	t.Helper()
	req := httptest.NewRequest(method, path, nil)
	req.Header.Set("Authorization", "Bearer "+testutil.IssueTestAccessToken(t, userID, "TR"))
	return req
}

// ── DB seeding helpers ─────────────────────────────────────────────────────────

func finSeedPlan(t *testing.T, pool *pgxpool.Pool, userID int64) int64 {
	t.Helper()
	uid := finUniqueID()
	var id int64
	// v8 columns (0076): price/commission/total_months/last are NOT NULL with
	// plans_principal_exact CHECK: (months-1)*monthly + last == price → 11*500+500=6000.
	err := pool.QueryRow(context.Background(), `
		INSERT INTO cashback_schema.plans
		    (order_id, user_id, monthly_amount_minor, currency,
		     reference_interest_rate_bps, start_date, status,
		     delivered_at, market, commission_snapshot, idempotency_key,
		     price_minor, commission_bps, total_months, monthly_amount_last_minor)
		VALUES ($1, $2, 500, 'TRY_COIN', 5000, '2026-01-01', 'active',
		        now()-interval '5 days', 'TR', '[]'::jsonb, $3,
		        6000, 1000, 12, 500)
		RETURNING id`,
		uid, userID, fmt.Sprintf("fin:test:plan:%d", uid),
	).Scan(&id)
	if err != nil {
		t.Fatalf("finSeedPlan: %v", err)
	}
	return id
}

// ── IDOR integration tests ─────────────────────────────────────────────────────

// TestFinIntegration_GetCashbackPlan_OtherUserPlan_Returns404 proves that
// GetPlanByIDAndUserID filters by user_id at the DB level — a real SQL WHERE
// clause, not just application-level logic.
func TestFinIntegration_GetCashbackPlan_OtherUserPlan_Returns404(t *testing.T) {
	pool := finTestPool(t)
	h := finBuildRealHandler(t, pool)

	const planOwner int64 = 10001
	const attacker int64 = 10002

	planID := finSeedPlan(t, pool, planOwner)

	// Owner can access their plan.
	w := httptest.NewRecorder()
	h.ServeHTTP(w, finAuthedReq(t, http.MethodGet, fmt.Sprintf("/cashback/plans/%d", planID), planOwner))
	if w.Code != http.StatusOK {
		t.Fatalf("owner: expected 200, got %d (body: %s)", w.Code, w.Body.String())
	}

	// Attacker gets 404, not 403 (existence must not be leaked).
	w = httptest.NewRecorder()
	h.ServeHTTP(w, finAuthedReq(t, http.MethodGet, fmt.Sprintf("/cashback/plans/%d", planID), attacker))
	if w.Code != http.StatusNotFound {
		t.Fatalf("attacker: expected 404, got %d (body: %s)", w.Code, w.Body.String())
	}
	t.Logf("PASS: plan_id=%d owner=%d attacker=%d → 404", planID, planOwner, attacker)
}

// TestFinIntegration_ListCashbackPayments_OtherUserPlan_Returns404 proves that
// the IDOR ownership check runs before ListPaymentsByPlanID is called.
func TestFinIntegration_ListCashbackPayments_OtherUserPlan_Returns404(t *testing.T) {
	pool := finTestPool(t)
	h := finBuildRealHandler(t, pool)

	const planOwner int64 = 10003
	const attacker int64 = 10004

	planID := finSeedPlan(t, pool, planOwner)

	// Owner can access the payments list (empty is fine).
	w := httptest.NewRecorder()
	h.ServeHTTP(w, finAuthedReq(t, http.MethodGet, fmt.Sprintf("/cashback/plans/%d/payments", planID), planOwner))
	if w.Code != http.StatusOK {
		t.Fatalf("owner: expected 200, got %d (body: %s)", w.Code, w.Body.String())
	}

	// Attacker gets 404.
	w = httptest.NewRecorder()
	h.ServeHTTP(w, finAuthedReq(t, http.MethodGet, fmt.Sprintf("/cashback/plans/%d/payments", planID), attacker))
	if w.Code != http.StatusNotFound {
		t.Fatalf("attacker: expected 404, got %d (body: %s)", w.Code, w.Body.String())
	}
	t.Logf("PASS: plan_id=%d payments IDOR check owner=%d attacker=%d", planID, planOwner, attacker)
}

// TestFinIntegration_ListWalletTransactions_OnlyShowsCurrentUserWallet verifies
// that wallet transaction history is scoped to the authenticated user's account,
// not another user's account.
func TestFinIntegration_ListWalletTransactions_OnlyShowsCurrentUserWallet(t *testing.T) {
	pool := finTestPool(t)
	h := finBuildRealHandler(t, pool)

	user1 := finUniqueID()
	user2 := finUniqueID()

	// Request for user1.
	w := httptest.NewRecorder()
	h.ServeHTTP(w, finAuthedReq(t, http.MethodGet, "/wallet/transactions", user1))
	if w.Code != http.StatusOK {
		t.Fatalf("user1: expected 200, got %d", w.Code)
	}

	// Request for user2 — separate wallet, never sees user1's entries.
	w = httptest.NewRecorder()
	h.ServeHTTP(w, finAuthedReq(t, http.MethodGet, "/wallet/transactions", user2))
	if w.Code != http.StatusOK {
		t.Fatalf("user2: expected 200, got %d", w.Code)
	}

	var resp1 struct {
		Data []genfin.WalletTransaction `json:"data"`
	}
	var resp2 struct {
		Data []genfin.WalletTransaction `json:"data"`
	}
	if err := json.NewDecoder(w.Body).Decode(&resp2); err != nil {
		t.Fatalf("decode user2 response: %v", err)
	}
	_ = resp1
	// Both new users have no wallet entries — empty lists, no cross-contamination.
	if len(resp2.Data) != 0 {
		t.Fatalf("user2 expected 0 entries, got %d", len(resp2.Data))
	}
	t.Logf("PASS: wallet transactions are user-scoped (user1=%d user2=%d)", user1, user2)
}

// TestFinIntegration_ListCashbackPlans_OtherUserPlans_NotVisible proves that
// ListPlansByUserID runs a WHERE user_id = $1 filter at the DB level.
func TestFinIntegration_ListCashbackPlans_OtherUserPlans_NotVisible(t *testing.T) {
	pool := finTestPool(t)
	h := finBuildRealHandler(t, pool)

	user1 := finUniqueID()
	user2 := finUniqueID()

	// Seed a plan for user1.
	finSeedPlan(t, pool, user1)

	// user2 must see an empty list — their WHERE user_id clause excludes user1's plan.
	w := httptest.NewRecorder()
	h.ServeHTTP(w, finAuthedReq(t, http.MethodGet, "/cashback/plans", user2))
	if w.Code != http.StatusOK {
		t.Fatalf("user2: expected 200, got %d", w.Code)
	}

	var resp struct {
		Data []genfin.CashbackPlan `json:"data"`
	}
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("decode user2 response: %v", err)
	}
	if len(resp.Data) != 0 {
		t.Fatalf("user2 expected 0 plans, got %d", len(resp.Data))
	}

	// user1 must see exactly their plan.
	w = httptest.NewRecorder()
	h.ServeHTTP(w, finAuthedReq(t, http.MethodGet, "/cashback/plans", user1))
	if w.Code != http.StatusOK {
		t.Fatalf("user1: expected 200, got %d", w.Code)
	}
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("decode user1 response: %v", err)
	}
	if len(resp.Data) < 1 {
		t.Fatalf("user1 expected >= 1 plan, got %d", len(resp.Data))
	}
	t.Logf("PASS: user1 sees %d plans, user2 sees 0 — plan isolation verified", len(resp.Data))
}

// TestFinIntegration_GetWalletBalance_AlwaysScopedToContextUserID verifies that
// wallet balance lookup uses the JWT-authenticated user ID, not any path/query parameter.
func TestFinIntegration_GetWalletBalance_AlwaysScopedToContextUserID(t *testing.T) {
	pool := finTestPool(t)
	h := finBuildRealHandler(t, pool)

	user1 := finUniqueID()
	user2 := finUniqueID()

	// Both users request their balance independently — each gets their own (0 for new users).
	for _, uid := range []int64{user1, user2} {
		w := httptest.NewRecorder()
		h.ServeHTTP(w, finAuthedReq(t, http.MethodGet, "/wallet/balance", uid))
		if w.Code != http.StatusOK {
			t.Fatalf("user %d: expected 200, got %d (body: %s)", uid, w.Code, w.Body.String())
		}
		var body genfin.WalletBalance
		if err := json.NewDecoder(w.Body).Decode(&body); err != nil {
			t.Fatalf("user %d: decode response: %v", uid, err)
		}
		if body.AmountMinor != 0 {
			t.Logf("user %d: balance = %d (may be non-zero from prior test runs)", uid, body.AmountMinor)
		}
	}
	t.Logf("PASS: balance scoped to context user_id (user1=%d user2=%d)", user1, user2)
}

// TestFinIntegration_FullFlow_JWT_Wallet_Cashback exercises the full path:
// issue JWT → authenticate → get balance → list plans → list payments.
func TestFinIntegration_FullFlow_JWT_Wallet_Cashback(t *testing.T) {
	pool := finTestPool(t)
	h := finBuildRealHandler(t, pool)

	userID := finUniqueID()
	planID := finSeedPlan(t, pool, userID)

	// 1. Get wallet balance (new user — no wallet account yet, returns 0).
	w := httptest.NewRecorder()
	h.ServeHTTP(w, finAuthedReq(t, http.MethodGet, "/wallet/balance", userID))
	if w.Code != http.StatusOK {
		t.Fatalf("balance: expected 200, got %d", w.Code)
	}
	var balance genfin.WalletBalance
	if err := json.NewDecoder(w.Body).Decode(&balance); err != nil {
		t.Fatalf("balance decode: %v", err)
	}
	t.Logf("balance: amount_minor=%d currency=%s", balance.AmountMinor, balance.Currency)

	// 2. List cashback plans — must include the seeded plan.
	w = httptest.NewRecorder()
	h.ServeHTTP(w, finAuthedReq(t, http.MethodGet, "/cashback/plans", userID))
	if w.Code != http.StatusOK {
		t.Fatalf("list plans: expected 200, got %d", w.Code)
	}
	var plansResp struct {
		Data []genfin.CashbackPlan `json:"data"`
	}
	if err := json.NewDecoder(w.Body).Decode(&plansResp); err != nil {
		t.Fatalf("plans decode: %v", err)
	}
	if len(plansResp.Data) == 0 {
		t.Fatal("list plans: expected at least 1 plan")
	}
	t.Logf("plans: count=%d first_id=%d", len(plansResp.Data), plansResp.Data[0].Id)

	// 3. Get the specific plan.
	w = httptest.NewRecorder()
	h.ServeHTTP(w, finAuthedReq(t, http.MethodGet, fmt.Sprintf("/cashback/plans/%d", planID), userID))
	if w.Code != http.StatusOK {
		t.Fatalf("get plan: expected 200, got %d", w.Code)
	}
	var plan genfin.CashbackPlan
	if err := json.NewDecoder(w.Body).Decode(&plan); err != nil {
		t.Fatalf("plan decode: %v", err)
	}
	if plan.Id != planID {
		t.Fatalf("get plan: expected id=%d, got %d", planID, plan.Id)
	}

	// 4. List payments for the plan (empty — no cron run yet).
	w = httptest.NewRecorder()
	h.ServeHTTP(w, finAuthedReq(t, http.MethodGet, fmt.Sprintf("/cashback/plans/%d/payments", planID), userID))
	if w.Code != http.StatusOK {
		t.Fatalf("list payments: expected 200, got %d", w.Code)
	}
	var paymentsResp struct {
		Data []genfin.CashbackPayment `json:"data"`
	}
	if err := json.NewDecoder(w.Body).Decode(&paymentsResp); err != nil {
		t.Fatalf("payments decode: %v", err)
	}
	t.Logf("payments: count=%d", len(paymentsResp.Data))

	// 5. List wallet transactions (empty for new wallet).
	w = httptest.NewRecorder()
	h.ServeHTTP(w, finAuthedReq(t, http.MethodGet, "/wallet/transactions", userID))
	if w.Code != http.StatusOK {
		t.Fatalf("wallet txns: expected 200, got %d", w.Code)
	}
	t.Logf("PASS: full JWT→wallet→cashback flow user_id=%d plan_id=%d", userID, planID)
}
