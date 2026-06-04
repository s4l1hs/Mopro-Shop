//go:build integration

// Package e2e_test runs end-to-end integration tests that span multiple modules.
// It requires two running PostgreSQL instances:
//
//	ORDER_E2E_DSN  (postgres-ecom, default port 6435)
//	LEDGER_E2E_DSN (postgres-ledger, default port 6436)
//
// Start both with: make test-e2e
package e2e_test

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/mopro/platform/internal/cart"
	"github.com/mopro/platform/internal/cashback"
	"github.com/mopro/platform/internal/catalog"
	"github.com/mopro/platform/internal/order"
	"github.com/mopro/platform/internal/outbox"
	"github.com/mopro/platform/internal/sellerpayout"
	"github.com/mopro/platform/pkg/timex"
)

const (
	defaultOrderE2EDSN  = "postgres://ecom_admin:test123@localhost:6435/mopro_ecom"     //nolint:gosec
	defaultLedgerE2EDSN = "postgres://ledger_admin:test123@localhost:6436/mopro_ledger" //nolint:gosec
)

var (
	ecomPool   *pgxpool.Pool
	ledgerPool *pgxpool.Pool
)

func TestMain(m *testing.M) {
	ctx := context.Background()
	orderDSN := getEnvOr("ORDER_E2E_DSN", defaultOrderE2EDSN)
	ledgerDSN := getEnvOr("LEDGER_E2E_DSN", defaultLedgerE2EDSN)

	var err error
	ecomPool, err = pgxpool.New(ctx, orderDSN)
	if err != nil {
		fmt.Fprintf(os.Stderr, "e2e: ecom pool: %v\n", err)
		os.Exit(1)
	}
	if err := ecomPool.Ping(ctx); err != nil {
		fmt.Fprintf(os.Stderr, "e2e: ecom ping: %v\n", err)
		os.Exit(1)
	}

	ledgerPool, err = pgxpool.New(ctx, ledgerDSN)
	if err != nil {
		fmt.Fprintf(os.Stderr, "e2e: ledger pool: %v\n", err)
		os.Exit(1)
	}
	if err := ledgerPool.Ping(ctx); err != nil {
		fmt.Fprintf(os.Stderr, "e2e: ledger ping: %v\n", err)
		os.Exit(1)
	}

	if err := setupEcomSchema(ctx); err != nil {
		fmt.Fprintf(os.Stderr, "e2e: ecom schema: %v\n", err)
		os.Exit(1)
	}
	if err := setupLedgerSchema(ctx); err != nil {
		fmt.Fprintf(os.Stderr, "e2e: ledger schema: %v\n", err)
		os.Exit(1)
	}

	code := m.Run()
	ecomPool.Close()
	ledgerPool.Close()
	os.Exit(code)
}

// TestE2E_OrderToCashbackAndPayout is the full Phase 1.3 happy-path:
//
//	checkout → mark-delivered → cashback plan created → seller payout scheduled
func TestE2E_OrderToCashbackAndPayout(t *testing.T) { //nolint:gocyclo,cyclop
	ctx := context.Background()

	// ── wiring ────────────────────────────────────────────────────────────────
	orderOutbox := outbox.NewRepository("order_schema.outbox")
	orderRepo := order.NewRepository(ecomPool)

	const market = "TR"
	const payoutCurrency = "TRY"
	const coinCurrency = "TRY_COIN"

	// Static empty calendar (weekends still skipped; no holidays for this test).
	cal := timex.Calendar{Market: market, Holidays: map[string]struct{}{}}
	calLoader := timex.NewStaticCalendarLoader(map[string]timex.Calendar{market: cal})

	cashbackRepo := cashback.NewRepository(ledgerPool)
	cashbackOutbox := outbox.NewRepository("wallet_schema.outbox")
	cashbackSvc := cashback.NewService(cashbackRepo, cashbackOutbox, calLoader, coinCurrency, nil, nil, nil)

	payoutRepo := sellerpayout.NewRepository(ledgerPool)
	payoutSvc := sellerpayout.NewService(payoutRepo, nil, nil, calLoader, payoutCurrency, nil)

	// Mock catalog and cart services — real DB not needed for this flow.
	const variantID = int64(5001)
	const sellerID = int64(77)
	const categoryID = int64(30)
	const priceMinor = int64(50000) // 500.00 TL
	const commPctBps = 700          // 7%
	const kdvPctBps = 2000          // 20%

	gross := priceMinor * 1
	commAmt := gross * commPctBps / 10000
	kdvAmt := commAmt * kdvPctBps / 10000
	sellerNet := gross - commAmt - kdvAmt

	mockCatalog := &catalogMock{
		variant: catalog.Variant{
			ID:            variantID,
			ProductID:     1001,
			CategoryID:    categoryID,
			SellerID:      sellerID,
			SKU:           "E2E-SKU-001",
			PriceMinor:    priceMinor,
			PriceCurrency: payoutCurrency,
			Stock:         100,
		},
		commission: catalog.CategoryCommission{
			CategoryID:       categoryID,
			Market:           market,
			CommissionPctBps: commPctBps,
			KdvPctBps:        kdvPctBps,
		},
	}
	mockCartSvc := &cartMock{
		items: []cart.CartItem{{VariantID: variantID, Qty: 1}},
	}

	orderSvc := order.NewService(
		orderRepo, mockCartSvc, mockCatalog, orderOutbox, market, coinCurrency,
	)

	// ── step 1: checkout ──────────────────────────────────────────────────────
	idempKey := fmt.Sprintf("e2e-checkout-%d", time.Now().UnixNano())
	createdOrder, items, err := orderSvc.Checkout(ctx, order.CheckoutRequest{
		UserID:         999,
		Market:         market,
		Currency:       payoutCurrency,
		IdempotencyKey: idempKey,
	})
	if err != nil {
		t.Fatalf("Checkout: %v", err)
	}
	if len(items) != 1 {
		t.Fatalf("want 1 item, got %d", len(items))
	}
	if items[0].CommissionAmountMinor != commAmt {
		t.Errorf("commission_amount: want %d, got %d", commAmt, items[0].CommissionAmountMinor)
	}
	if items[0].SellerNetMinor != sellerNet {
		t.Errorf("seller_net: want %d, got %d", sellerNet, items[0].SellerNetMinor)
	}
	t.Logf("checkout OK: orderID=%d commAmt=%d sellerNet=%d", createdOrder.ID, commAmt, sellerNet)

	// ── step 2: mark delivered ────────────────────────────────────────────────
	deliveredAt := time.Date(2026, 5, 12, 10, 0, 0, 0, time.UTC)
	if err := orderSvc.MarkDelivered(ctx, createdOrder.ID, deliveredAt); err != nil {
		t.Fatalf("MarkDelivered: %v", err)
	}

	// Verify order status.
	gotOrder, _, err := orderRepo.GetOrder(ctx, createdOrder.ID)
	if err != nil {
		t.Fatalf("GetOrder after deliver: %v", err)
	}
	if gotOrder.Status != order.StatusDelivered {
		t.Errorf("order status: want delivered, got %s", gotOrder.Status)
	}

	// Read outbox row written by MarkDelivered.
	var outboxPayload json.RawMessage
	var outboxMarket string
	if err := ecomPool.QueryRow(ctx,
		`SELECT payload, market FROM order_schema.outbox
		 WHERE aggregate='order' AND event_type='ecom.order.delivered.v1'
		 ORDER BY id DESC LIMIT 1`,
	).Scan(&outboxPayload, &outboxMarket); err != nil {
		t.Fatalf("read outbox: %v", err)
	}
	if outboxMarket != market {
		t.Errorf("outbox.market: want %s, got %s", market, outboxMarket)
	}
	t.Logf("outbox written: market=%s", outboxMarket)

	// ── step 3: decode event and create cashback plan ────────────────────────
	var evPayload struct {
		OrderID int64 `json:"order_id"`
		UserID  int64 `json:"user_id"`
		Items   []struct {
			SellerID              int64 `json:"seller_id"`
			CategoryID            int64 `json:"category_id"`
			VariantID             int64 `json:"variant_id"`
			Qty                   int   `json:"qty"`
			UnitPriceMinor        int64 `json:"unit_price_minor"`
			CommissionPctBps      int   `json:"commission_pct_bps"`
			KdvPctBps             int   `json:"kdv_pct_bps"`
			CommissionAmountMinor int64 `json:"commission_amount_minor"`
			KdvAmountMinor        int64 `json:"kdv_amount_minor"`
			SellerNetMinor        int64 `json:"seller_net_minor"`
		} `json:"items"`
	}
	if err := json.Unmarshal(outboxPayload, &evPayload); err != nil {
		t.Fatalf("unmarshal outbox payload: %v", err)
	}

	cbItems := make([]cashback.CommissionSnapshotItem, len(evPayload.Items))
	for i, it := range evPayload.Items {
		cbItems[i] = cashback.CommissionSnapshotItem{
			VariantID:             it.VariantID,
			SellerID:              it.SellerID,
			CategoryID:            it.CategoryID,
			Qty:                   it.Qty,
			UnitPriceMinor:        it.UnitPriceMinor,
			CommissionPctBps:      it.CommissionPctBps,
			KdvPctBps:             it.KdvPctBps,
			CommissionAmountMinor: it.CommissionAmountMinor,
			KdvAmountMinor:        it.KdvAmountMinor,
			SellerNetMinor:        it.SellerNetMinor,
		}
	}

	// v8: CreatePlanFromDelivery reads PriceMinor + CommissionBps directly from the
	// event (the "v8 direct fields"). Derive them from the item snapshot exactly as
	// the production consumer does (internal/cashback/consumer.go) so a missing price
	// doesn't silently trip the PriceMinor<=0 skip guard.
	var cbPriceMinor int64
	for _, it := range cbItems {
		cbPriceMinor += it.UnitPriceMinor * int64(it.Qty)
	}
	cbCommissionBps := 0
	if len(cbItems) > 0 {
		cbCommissionBps = cbItems[0].CommissionPctBps
	}

	cbEv := cashback.OrderDeliveredEvent{
		OrderID:       createdOrder.ID,
		UserID:        createdOrder.UserID,
		DeliveredAt:   deliveredAt,
		Market:        market,
		Currency:      payoutCurrency,
		PriceMinor:    cbPriceMinor,
		CommissionBps: cbCommissionBps,
		Items:         cbItems,
	}

	if _, err := cashbackSvc.CreatePlanFromDelivery(ctx, cbEv); err != nil {
		t.Fatalf("CreatePlanFromDelivery: %v", err)
	}

	// Idempotent second call.
	if _, err := cashbackSvc.CreatePlanFromDelivery(ctx, cbEv); err != nil {
		t.Fatalf("CreatePlanFromDelivery idempotent: %v", err)
	}

	// Verify plan was created.
	var planID int64
	var monthlyMinor int64
	var planCurrency string
	var planStatus string
	if err := ledgerPool.QueryRow(ctx,
		`SELECT id, monthly_amount_minor, currency, status
		 FROM cashback_schema.plans WHERE order_id = $1`,
		createdOrder.ID,
	).Scan(&planID, &monthlyMinor, &planCurrency, &planStatus); err != nil {
		t.Fatalf("query cashback plan: %v", err)
	}
	if planStatus != "active" {
		t.Errorf("plan status: want active, got %s", planStatus)
	}
	if planCurrency != coinCurrency {
		t.Errorf("plan currency: want %s, got %s", coinCurrency, planCurrency)
	}

	// v8 accelerated model: monthly = (price × commissionBps) / CashbackK, computed
	// via the engine's own ComputePlanTerms so the expectation tracks production
	// exactly (price=50000, commissionBps=700 → 224).
	terms, err := cashback.ComputePlanTerms(priceMinor, commPctBps)
	if err != nil {
		t.Fatalf("ComputePlanTerms(price=%d, bps=%d): %v", priceMinor, commPctBps, err)
	}
	if monthlyMinor != terms.MonthlyAmountMinor {
		t.Errorf("monthly_amount_minor: want %d (v8 ComputePlanTerms), got %d", terms.MonthlyAmountMinor, monthlyMinor)
	}
	t.Logf("cashback plan OK: planID=%d monthly=%d currency=%s", planID, monthlyMinor, planCurrency)

	// ── step 4: schedule seller payout ────────────────────────────────────────
	spItems := make([]sellerpayout.DeliveredItem, len(evPayload.Items))
	for i, it := range evPayload.Items {
		spItems[i] = sellerpayout.DeliveredItem{
			SellerID:       it.SellerID,
			SellerNetMinor: it.SellerNetMinor,
		}
	}

	spEv := sellerpayout.OrderDeliveredEvent{
		OrderID:     createdOrder.ID,
		DeliveredAt: deliveredAt,
		Market:      market,
		Currency:    payoutCurrency,
		Items:       spItems,
	}

	if err := payoutSvc.SchedulePayoutsForOrder(ctx, spEv); err != nil {
		t.Fatalf("SchedulePayoutsForOrder: %v", err)
	}

	// Idempotent second call.
	if err := payoutSvc.SchedulePayoutsForOrder(ctx, spEv); err != nil {
		t.Fatalf("SchedulePayoutsForOrder idempotent: %v", err)
	}

	// Verify payout row.
	var payoutID int64
	var payoutAmount int64
	var payoutStatus string
	var unlockAt time.Time
	if err := ledgerPool.QueryRow(ctx,
		`SELECT id, amount_minor, status, unlock_at
		 FROM sellerpayout_schema.seller_payouts
		 WHERE order_id = $1 AND seller_id = $2`,
		createdOrder.ID, sellerID,
	).Scan(&payoutID, &payoutAmount, &payoutStatus, &unlockAt); err != nil {
		t.Fatalf("query seller_payouts: %v", err)
	}
	if payoutStatus != "scheduled" {
		t.Errorf("payout status: want scheduled, got %s", payoutStatus)
	}
	if payoutAmount != sellerNet {
		t.Errorf("payout amount: want %d, got %d", sellerNet, payoutAmount)
	}

	// unlock_at is stored as Postgres DATE (read back as midnight UTC).
	// Compare date portions only — preserving time-of-day in deliveredAt would
	// make any non-midnight deliveredAt fail this assertion incorrectly.
	minUnlockDate := time.Date(deliveredAt.Year(), deliveredAt.Month(), deliveredAt.Day(), 0, 0, 0, 0, time.UTC).AddDate(0, 0, 3)
	if unlockAt.Before(minUnlockDate) {
		t.Errorf("unlock_at %v is before deliveredAt+3d %v", unlockAt, minUnlockDate)
	}

	t.Logf("seller payout OK: payoutID=%d amount=%d unlockAt=%s",
		payoutID, payoutAmount, unlockAt.Format("2006-01-02"))
	t.Logf("e2e PASS: order=%d plan=%d payout=%d", createdOrder.ID, planID, payoutID)
}

// ── mock implementations ──────────────────────────────────────────────────────

type catalogMock struct {
	variant    catalog.Variant
	commission catalog.CategoryCommission
}

func (m *catalogMock) CreateProduct(_ context.Context, _ catalog.CreateProductRequest) (catalog.Product, error) {
	return catalog.Product{}, nil
}
func (m *catalogMock) AddVariant(_ context.Context, _ int64, _ catalog.AddVariantRequest) (catalog.Variant, error) {
	return catalog.Variant{}, nil
}
func (m *catalogMock) UpdateTranslation(_ context.Context, _ int64, _, _, _ string) error {
	return nil
}
func (m *catalogMock) GetByID(_ context.Context, _ int64) (catalog.Product, []catalog.Variant, []catalog.ProductTranslation, error) {
	return catalog.Product{}, nil, nil, nil
}
func (m *catalogMock) Search(_ context.Context, _, _, _ string) ([]catalog.Product, error) {
	return nil, nil
}
func (m *catalogMock) GetCommissionForCategory(_ context.Context, _ string, _ int64) (catalog.CategoryCommission, error) {
	return m.commission, nil
}
func (m *catalogMock) GetVariantByID(_ context.Context, _ int64) (catalog.Variant, error) {
	return m.variant, nil
}

// E2E_MOCK: the discovery/reviews surface (Phase 4.4a+) that catalog.Service grew.
// Stubs for interface compliance; no behavior asserted by current e2e scenarios.
func (m *catalogMock) ListCategories(_ context.Context, _ string, _ int) ([]catalog.CategoryRow, error) {
	return nil, nil
}
func (m *catalogMock) ListProductsByCategory(_ context.Context, _ int64, _, _ string, _ catalog.ProductFilter, _, _ int) ([]catalog.ProductSummaryRow, int, error) {
	return nil, 0, nil
}
func (m *catalogMock) SearchSummary(_ context.Context, _, _, _ string, _ catalog.ProductFilter, _, _ int) ([]catalog.ProductSummaryRow, int, error) {
	return nil, 0, nil
}
func (m *catalogMock) ListProductsByIDs(_ context.Context, _ []int64, _, _ string) ([]catalog.ProductSummaryRow, error) {
	return nil, nil
}
func (m *catalogMock) HomeRails(_ context.Context, _ string) ([]catalog.HomeRailRow, error) {
	return nil, nil
}
func (m *catalogMock) HomeBanners(_ context.Context) ([]catalog.HomeBannerRow, error) {
	return nil, nil
}
func (m *catalogMock) HomeMoodStories(_ context.Context) ([]catalog.HomeMoodStoryRow, error) {
	return nil, nil
}
func (m *catalogMock) HomeFlashDeals(_ context.Context, _ string, _ *int64) (*catalog.FlashDealsResult, error) {
	return nil, nil
}
func (m *catalogMock) ListReviews(_ context.Context, _ int64, _ catalog.ReviewSort, _, _ int, _ int64) ([]catalog.ProductReviewRow, int, error) {
	return nil, 0, nil
}
func (m *catalogMock) ReviewsSummary(_ context.Context, _ int64) (catalog.ReviewsSummary, error) {
	return catalog.ReviewsSummary{}, nil
}
func (m *catalogMock) ReviewProductID(_ context.Context, _ int64) (int64, error) {
	return 0, nil
}
func (m *catalogMock) ToggleHelpfulVote(_ context.Context, _, _ int64) (catalog.HelpfulVoteResult, error) {
	return catalog.HelpfulVoteResult{}, nil
}
func (m *catalogMock) ListAllVariantStocks(_ context.Context) ([]catalog.VariantStock, error) {
	return nil, nil
}

type cartMock struct {
	items []cart.CartItem
}

func (m *cartMock) AddItem(_ context.Context, _, _ int64, _ int) error { return nil }
func (m *cartMock) RemoveItem(_ context.Context, _, _ int64) error     { return nil }
func (m *cartMock) GetCart(_ context.Context, _ int64) (cart.Cart, error) {
	return cart.Cart{Items: m.items}, nil
}
func (m *cartMock) Reserve(_ context.Context, _ int64) (string, time.Time, error) {
	return "", time.Time{}, nil
}
func (m *cartMock) Release(_ context.Context, _ string) error           { return nil }
func (m *cartMock) CommitReservation(_ context.Context, _ string) error { return nil }
func (m *cartMock) SeedStock(_ context.Context, _ int64, _ int) error   { return nil }

// E2E_MOCK: cart.Service grew SeedStockIfAbsent (startup SET-NX). Stub for interface
// compliance; no behavior asserted by current e2e scenarios.
func (m *cartMock) SeedStockIfAbsent(_ context.Context, _ int64, _ int) error { return nil }

// ── schema setup ─────────────────────────────────────────────────────────────

func setupEcomSchema(ctx context.Context) error {
	_, err := ecomPool.Exec(ctx, `
CREATE SCHEMA IF NOT EXISTS order_schema;
CREATE SCHEMA IF NOT EXISTS shipping_schema;

DROP TABLE IF EXISTS shipping_schema.shipment_events CASCADE;
DROP TABLE IF EXISTS shipping_schema.shipments CASCADE;
DROP TABLE IF EXISTS order_schema.outbox CASCADE;
DROP TABLE IF EXISTS order_schema.order_items CASCADE;
DROP TABLE IF EXISTS order_schema.orders CASCADE;

CREATE TABLE shipping_schema.shipments (
  id                    BIGSERIAL    PRIMARY KEY,
  order_id              BIGINT       NOT NULL,
  carrier               TEXT         NOT NULL,
  tracking_number       TEXT,
  carrier_shipment_id   TEXT,
  state                 TEXT         NOT NULL DEFAULT 'pending'
                        CHECK (state IN ('pending','picked_up','in_transit',
                                         'out_for_delivery','delivered',
                                         'returned','cancelled','failed')),
  label_pdf_b2_key      TEXT,
  estimated_delivery_at TIMESTAMPTZ,
  delivered_at          TIMESTAMPTZ,
  last_polled_at        TIMESTAMPTZ,
  idempotency_key       TEXT         NOT NULL UNIQUE,
  cost_minor            BIGINT,
  cost_currency         TEXT,
  created_at            TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_shipments_tracking ON shipping_schema.shipments (carrier, tracking_number) WHERE tracking_number IS NOT NULL;

CREATE TABLE shipping_schema.shipment_events (
  id          BIGSERIAL PRIMARY KEY,
  shipment_id BIGINT    NOT NULL REFERENCES shipping_schema.shipments(id),
  state       TEXT      NOT NULL,
  source      TEXT      NOT NULL CHECK (source IN ('webhook','poll','api')),
  carrier_raw JSONB,
  event_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE order_schema.orders (
  id                BIGSERIAL    PRIMARY KEY,
  user_id           BIGINT       NOT NULL,
  status            TEXT         NOT NULL
                    CHECK (status IN ('pending_payment','paid','shipped','delivered',
                                      'cancelled','refunded','partially_refunded')),
  subtotal_minor    BIGINT       NOT NULL CHECK (subtotal_minor >= 0),
  shipping_minor    BIGINT       NOT NULL DEFAULT 0,
  shipping_payer    TEXT         NOT NULL DEFAULT 'buyer',
  total_minor       BIGINT       NOT NULL CHECK (total_minor >= 0),
  currency          TEXT         NOT NULL,
  market            TEXT         NOT NULL DEFAULT 'TR',
  delivered_at      TIMESTAMPTZ,
  cashback_eligible BOOLEAN      NOT NULL DEFAULT TRUE,
  cashback_currency TEXT         NOT NULL DEFAULT 'TRY_COIN',
  idempotency_key   TEXT         NOT NULL UNIQUE,
  -- v8 multi-seller checkout (migration 0059_orders_v8); both nullable, repo
  -- writes NULL via NULLIF for the legacy single-order flow. FK on
  -- checkout_session_id omitted — the e2e schema has no checkout_sessions table
  -- and only ever inserts NULL here.
  seller_id           BIGINT,
  checkout_session_id TEXT,
  created_at        TIMESTAMPTZ  NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE order_schema.order_items (
  id                       BIGSERIAL PRIMARY KEY,
  order_id                 BIGINT    NOT NULL REFERENCES order_schema.orders(id),
  variant_id               BIGINT    NOT NULL,
  seller_id                BIGINT    NOT NULL,
  category_id              BIGINT    NOT NULL,
  qty                      INTEGER   NOT NULL CHECK (qty > 0),
  unit_price_minor         BIGINT    NOT NULL CHECK (unit_price_minor >= 0),
  unit_price_currency      TEXT      NOT NULL,
  commission_pct_bps       INTEGER   NOT NULL,
  kdv_pct_bps              INTEGER   NOT NULL,
  commission_amount_minor  BIGINT    NOT NULL CHECK (commission_amount_minor >= 0),
  kdv_amount_minor         BIGINT    NOT NULL CHECK (kdv_amount_minor >= 0),
  seller_net_minor         BIGINT    NOT NULL CHECK (seller_net_minor >= 0)
);

CREATE TABLE order_schema.outbox (
  id              BIGSERIAL PRIMARY KEY,
  aggregate       TEXT NOT NULL,
  event_type      TEXT NOT NULL,
  payload         JSONB NOT NULL,
  idempotency_key TEXT NOT NULL UNIQUE,
  trace_id        TEXT,
  span_id         TEXT,
  market          TEXT NOT NULL,
  currency        TEXT NOT NULL,
  published_at    TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
`)
	return err
}

func setupLedgerSchema(ctx context.Context) error {
	// Clean slate against the REAL ledger schema. `make e2e-test-up` applies
	// deploy/postgres-ledger/init/*.sql + migrations/ledger/*.up.sql to
	// pg-ledger-e2e (the same recipe pg-ledger-test-up uses for the property
	// suites), so we no longer hand-roll a DDL snapshot here — that snapshot
	// silently drifted from the v8 plans schema (missing price_minor,
	// commission_bps, total_months, monthly_amount_last_minor, product_*) and is
	// exactly the rot this revival closes. Truncating every table in the
	// e2e-touched schemas is robust to future column/table additions.
	var hasPriceMinor bool
	if err := ledgerPool.QueryRow(ctx, `
		SELECT EXISTS (
			SELECT 1 FROM information_schema.columns
			WHERE table_schema = 'cashback_schema' AND table_name = 'plans'
			  AND column_name = 'price_minor')`).Scan(&hasPriceMinor); err != nil {
		return fmt.Errorf("probe ledger schema: %w", err)
	}
	if !hasPriceMinor {
		return fmt.Errorf("ledger schema not bootstrapped (cashback_schema.plans.price_minor missing) — " +
			"run `make e2e-test-up` (or `make integration-e2e`), which applies the real ledger init+migrations")
	}
	_, err := ledgerPool.Exec(ctx, `
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT schemaname, tablename FROM pg_tables
    WHERE schemaname IN ('cashback_schema','wallet_schema','sellerpayout_schema','commission_schema')
  LOOP
    EXECUTE format('TRUNCATE TABLE %I.%I RESTART IDENTITY CASCADE', r.schemaname, r.tablename);
  END LOOP;
END $$;`)
	return err
}

func getEnvOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
