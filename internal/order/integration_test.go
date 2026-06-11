//go:build integration

package order_test

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/mopro/platform/internal/order"
	"github.com/mopro/platform/internal/outbox"
)

const defaultOrderTestDSN = "postgres://ecom_admin:test123@localhost:6435/mopro_ecom"

var integOrderPool *pgxpool.Pool

func TestMain(m *testing.M) {
	dsn := os.Getenv("ORDER_TEST_DSN")
	if dsn == "" {
		dsn = defaultOrderTestDSN
	}
	ctx := context.Background()
	var err error
	integOrderPool, err = pgxpool.New(ctx, dsn)
	if err != nil {
		fmt.Fprintf(os.Stderr, "order integration: cannot create pool: %v\n", err)
		os.Exit(1)
	}
	if err := integOrderPool.Ping(ctx); err != nil {
		fmt.Fprintf(os.Stderr, "order integration: ping failed: %v\n", err)
		os.Exit(1)
	}
	if err := setupOrderSchema(ctx, integOrderPool); err != nil {
		fmt.Fprintf(os.Stderr, "order integration: schema setup failed: %v\n", err)
		os.Exit(1)
	}
	code := m.Run()
	integOrderPool.Close()
	os.Exit(code)
}

func setupOrderSchema(ctx context.Context, pool *pgxpool.Pool) error {
	ddl := `
CREATE SCHEMA IF NOT EXISTS order_schema;

DROP TABLE IF EXISTS order_schema.order_items CASCADE;
DROP TABLE IF EXISTS order_schema.orders CASCADE;
DROP TABLE IF EXISTS order_schema.outbox CASCADE;

CREATE TABLE order_schema.orders (
  id                BIGSERIAL    PRIMARY KEY,
  user_id           BIGINT       NOT NULL,
  status            TEXT         NOT NULL
                    CHECK (status IN ('pending_payment','paid','shipped','delivered',
                                      'cancelled','refunded','partially_refunded')),
  subtotal_minor    BIGINT       NOT NULL CHECK (subtotal_minor >= 0),
  shipping_minor    BIGINT       NOT NULL DEFAULT 0,
  shipping_payer    TEXT         NOT NULL DEFAULT 'buyer'
                    CHECK (shipping_payer IN ('buyer','seller','split','threshold_free')),
  total_minor       BIGINT       NOT NULL CHECK (total_minor >= 0),
  discount_minor    BIGINT       NOT NULL DEFAULT 0 CHECK (discount_minor >= 0),
  -- CT-03 coupon (migration 0092): the order repo SELECTs these on every order
  -- scan, so the hand-rolled schema must carry them or scans error 42703.
  coupon_code           TEXT,
  coupon_discount_minor BIGINT   NOT NULL DEFAULT 0 CHECK (coupon_discount_minor >= 0),
  currency          TEXT         NOT NULL,
  market            TEXT         NOT NULL DEFAULT 'TR',
  delivered_at      TIMESTAMPTZ,
  cashback_eligible BOOLEAN      NOT NULL DEFAULT TRUE,
  cashback_currency TEXT         NOT NULL DEFAULT 'TRY_COIN',
  idempotency_key   TEXT         NOT NULL UNIQUE,
  -- v8 multi-seller split (0059_orders_v8): repo scans both via COALESCE.
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
  list_unit_price_minor    BIGINT    NOT NULL DEFAULT 0 CHECK (list_unit_price_minor >= 0),
  basket_discount_pct      SMALLINT  NOT NULL DEFAULT 0
                           CHECK (basket_discount_pct >= 0 AND basket_discount_pct <= 100),
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
`
	_, err := pool.Exec(ctx, ddl)
	return err
}

func TestIntegration_InsertAndGetOrder(t *testing.T) {
	ctx := context.Background()
	repo := order.NewRepository(integOrderPool)

	o := order.Order{
		UserID:           10,
		Status:           order.StatusPendingPayment,
		SubtotalMinor:    20000,
		ShippingMinor:    0,
		ShippingPayer:    "buyer",
		TotalMinor:       20000,
		Currency:         "TRY",
		Market:           "TR",
		CashbackEligible: true,
		CashbackCurrency: "TRY_COIN",
		IdempotencyKey:   fmt.Sprintf("integ-order-%d", time.Now().UnixNano()),
	}

	var created order.Order
	var createdItem order.OrderItem

	err := integOrderPool.QueryRow(ctx,
		`INSERT INTO order_schema.orders
			(user_id,status,subtotal_minor,shipping_minor,shipping_payer,
			 total_minor,currency,market,cashback_eligible,cashback_currency,idempotency_key)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
		RETURNING id,created_at,updated_at`,
		o.UserID, string(o.Status), o.SubtotalMinor, o.ShippingMinor, o.ShippingPayer,
		o.TotalMinor, o.Currency, o.Market, o.CashbackEligible, o.CashbackCurrency, o.IdempotencyKey,
	).Scan(&created.ID, &created.CreatedAt, &created.UpdatedAt)
	if err != nil {
		t.Fatalf("InsertOrder: %v", err)
	}

	// Insert an item
	err = integOrderPool.QueryRow(ctx,
		`INSERT INTO order_schema.order_items
			(order_id,variant_id,seller_id,category_id,qty,
			 unit_price_minor,unit_price_currency,
			 commission_pct_bps,kdv_pct_bps,
			 commission_amount_minor,kdv_amount_minor,seller_net_minor)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
		RETURNING id`,
		created.ID, 101, 77, 30, 2,
		10000, "TRY",
		700, 2000,
		1400, 280, 18320,
	).Scan(&createdItem.ID)
	if err != nil {
		t.Fatalf("InsertOrderItem: %v", err)
	}

	// GetOrder round-trip
	got, items, err := repo.GetOrder(ctx, created.ID)
	if err != nil {
		t.Fatalf("GetOrder: %v", err)
	}
	if got.UserID != 10 {
		t.Errorf("UserID: want 10, got %d", got.UserID)
	}
	if got.Status != order.StatusPendingPayment {
		t.Errorf("status: want pending_payment, got %s", got.Status)
	}
	if len(items) != 1 {
		t.Fatalf("items: want 1, got %d", len(items))
	}
	if items[0].CommissionAmountMinor != 1400 {
		t.Errorf("commission: want 1400, got %d", items[0].CommissionAmountMinor)
	}
	if items[0].SellerNetMinor != 18320 {
		t.Errorf("seller_net: want 18320, got %d", items[0].SellerNetMinor)
	}

	t.Logf("order integration PASS: orderID=%d itemID=%d", created.ID, createdItem.ID)
}

func TestIntegration_IdempotencyKeyUnique(t *testing.T) {
	ctx := context.Background()

	idempKey := fmt.Sprintf("integ-idem-%d", time.Now().UnixNano())
	for i := range 2 {
		_, err := integOrderPool.Exec(ctx,
			`INSERT INTO order_schema.orders
				(user_id,status,subtotal_minor,shipping_payer,total_minor,currency,market,
				 cashback_currency,idempotency_key)
			VALUES (1,'pending_payment',1000,'buyer',1000,'TRY','TR','TRY_COIN',$1)`,
			idempKey,
		)
		if i == 0 && err != nil {
			t.Fatalf("first insert failed: %v", err)
		}
		if i == 1 && err == nil {
			t.Fatal("second insert with same idempotency_key must fail")
		}
	}
}

func TestIntegration_MarkDeliveredWritesOutbox(t *testing.T) {
	ctx := context.Background()
	outboxRepo := outbox.NewRepository("order_schema.outbox")
	repo := order.NewRepository(integOrderPool)

	// Insert an order
	idempKey := fmt.Sprintf("integ-deliver-%d", time.Now().UnixNano())
	var orderID int64
	if err := integOrderPool.QueryRow(ctx,
		`INSERT INTO order_schema.orders
			(user_id,status,subtotal_minor,shipping_payer,total_minor,currency,market,
			 cashback_currency,idempotency_key)
		VALUES (20,'shipped',5000,'buyer',5000,'TRY','TR','TRY_COIN',$1)
		RETURNING id`, idempKey,
	).Scan(&orderID); err != nil {
		t.Fatalf("setup insert order: %v", err)
	}
	// Insert an item
	if _, err := integOrderPool.Exec(ctx,
		`INSERT INTO order_schema.order_items
			(order_id,variant_id,seller_id,category_id,qty,
			 unit_price_minor,unit_price_currency,
			 commission_pct_bps,kdv_pct_bps,
			 commission_amount_minor,kdv_amount_minor,seller_net_minor)
		VALUES ($1,201,88,30,1,5000,'TRY',700,2000,350,70,4580)`, orderID,
	); err != nil {
		t.Fatalf("setup insert item: %v", err)
	}

	deliveredAt := time.Date(2026, 5, 12, 12, 0, 0, 0, time.UTC)

	// Wire the service with the real repos
	svc := order.NewService(
		repo,
		&mockCartSvc{},
		&mockCatalogSvc{},
		outboxRepo,
		"TR", "TRY_COIN",
	)

	if err := svc.MarkDelivered(ctx, orderID, deliveredAt); err != nil {
		t.Fatalf("MarkDelivered: %v", err)
	}

	// Verify order status + delivered_at
	var status string
	var gotDeliveredAt *time.Time
	if err := integOrderPool.QueryRow(ctx,
		`SELECT status, delivered_at FROM order_schema.orders WHERE id = $1`, orderID,
	).Scan(&status, &gotDeliveredAt); err != nil {
		t.Fatalf("SELECT order: %v", err)
	}
	if status != "delivered" {
		t.Errorf("status: want delivered, got %s", status)
	}
	if gotDeliveredAt == nil {
		t.Fatal("delivered_at must not be nil")
	}
	if !gotDeliveredAt.UTC().Equal(deliveredAt.UTC()) {
		t.Errorf("delivered_at: want %v, got %v", deliveredAt, *gotDeliveredAt)
	}

	// Verify outbox row
	var eventType string
	var payload json.RawMessage
	if err := integOrderPool.QueryRow(ctx,
		`SELECT event_type, payload FROM order_schema.outbox
		 WHERE aggregate='order' AND market='TR' ORDER BY id DESC LIMIT 1`,
	).Scan(&eventType, &payload); err != nil {
		t.Fatalf("SELECT outbox: %v", err)
	}
	if eventType != "ecom.order.delivered.v1" {
		t.Errorf("event_type: want ecom.order.delivered.v1, got %q", eventType)
	}

	var ev struct {
		OrderID int64 `json:"order_id"`
		UserID  int64 `json:"user_id"`
	}
	if err := json.Unmarshal(payload, &ev); err != nil {
		t.Fatalf("unmarshal payload: %v", err)
	}
	if ev.OrderID != orderID {
		t.Errorf("payload.order_id: want %d, got %d", orderID, ev.OrderID)
	}
	if ev.UserID != 20 {
		t.Errorf("payload.user_id: want 20, got %d", ev.UserID)
	}

	// Idempotent second call must be a no-op
	if err := svc.MarkDelivered(ctx, orderID, deliveredAt); err != nil {
		t.Fatalf("second MarkDelivered must be no-op: %v", err)
	}

	t.Logf("MarkDelivered integration PASS: orderID=%d", orderID)
}

func TestIntegration_FindByIdempotencyKey(t *testing.T) {
	ctx := context.Background()
	repo := order.NewRepository(integOrderPool)

	idempKey := fmt.Sprintf("integ-find-%d", time.Now().UnixNano())
	var orderID int64
	if err := integOrderPool.QueryRow(ctx,
		`INSERT INTO order_schema.orders
			(user_id,status,subtotal_minor,shipping_payer,total_minor,currency,market,
			 cashback_currency,idempotency_key)
		VALUES (30,'pending_payment',3000,'buyer',3000,'TRY','TR','TRY_COIN',$1)
		RETURNING id`, idempKey,
	).Scan(&orderID); err != nil {
		t.Fatalf("setup: %v", err)
	}

	got, err := repo.FindByIdempotencyKey(ctx, idempKey)
	if err != nil {
		t.Fatalf("FindByIdempotencyKey: %v", err)
	}
	if got.ID != orderID {
		t.Errorf("want orderID=%d, got %d", orderID, got.ID)
	}

	_, err = repo.FindByIdempotencyKey(ctx, "nonexistent-key-xyz")
	if !errors.Is(err, order.ErrOrderNotFound) {
		t.Fatalf("expected ErrOrderNotFound, got %v", err)
	}
}
