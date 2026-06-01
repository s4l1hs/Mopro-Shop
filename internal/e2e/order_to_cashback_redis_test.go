//go:build integration

// Package e2e_test — Redis-routed end-to-end test.
// Requires the same two PostgreSQL containers as order_to_cashback_test.go
// plus a Redis container on REDIS_E2E_ADDR (default localhost:6381).
//
// Start all three containers with: make test-e2e
package e2e_test

import (
	"context"
	"fmt"
	"log/slog"
	"strings"
	"testing"
	"time"

	"github.com/redis/go-redis/v9"

	"github.com/mopro/platform/internal/cart"
	"github.com/mopro/platform/internal/cashback"
	"github.com/mopro/platform/internal/catalog"
	"github.com/mopro/platform/internal/eventbus"
	"github.com/mopro/platform/internal/order"
	"github.com/mopro/platform/internal/outbox"
	"github.com/mopro/platform/internal/sellerpayout"
	"github.com/mopro/platform/pkg/timex"
)

// TestE2E_FullCheckoutToPayoutViaRedis exercises the full chain through Redis Streams.
// It publishes via the real outbox.Publisher (XADD) and consumes via the real
// cashback + sellerpayout consumers (XREADGROUP), verifying that the async chain
// produces the correct plan and payout rows in the ledger DB.
func TestE2E_FullCheckoutToPayoutViaRedis(t *testing.T) { //nolint:gocyclo,cyclop
	ctx := context.Background()

	// ── Redis setup ─────────────────────────────────────────────────────────
	redisAddr := getEnvOr("REDIS_E2E_ADDR", "localhost:6381")
	rc := redis.NewClient(&redis.Options{Addr: redisAddr})
	if err := rc.Ping(ctx).Err(); err != nil {
		t.Skipf("Redis at %s not available (start with make test-e2e): %v", redisAddr, err)
	}
	t.Cleanup(func() { _ = rc.Close() })

	// Flush Redis so no stale streams or consumer groups interfere.
	if err := rc.FlushDB(ctx).Err(); err != nil {
		t.Fatalf("redis flush: %v", err)
	}

	// Pre-create consumer groups with ID "0" so consumers read all messages
	// published in this test, regardless of goroutine scheduling order.
	for _, grp := range []struct{ topic, group string }{
		{cashback.TopicOrderDelivered, cashback.ConsumerGroup},
		{sellerpayout.TopicOrderDelivered, sellerpayout.ConsumerGroup},
	} {
		err := rc.XGroupCreateMkStream(ctx, grp.topic, grp.group, "0").Err()
		if err != nil && !strings.HasPrefix(err.Error(), "BUSYGROUP") {
			t.Fatalf("create consumer group %s: %v", grp.group, err)
		}
	}

	// ── Wiring ──────────────────────────────────────────────────────────────
	const market = "TR"
	const payoutCurrency = "TRY"
	const coinCurrency = "TRY_COIN"

	cal := timex.Calendar{Market: market, Holidays: map[string]struct{}{}}
	calLoader := timex.NewStaticCalendarLoader(map[string]timex.Calendar{market: cal})

	orderOutboxRepo := outbox.NewRepository("order_schema.outbox")
	orderRepo := order.NewRepository(ecomPool)

	cashbackRepo := cashback.NewRepository(ledgerPool)
	cashbackOutboxRepo := outbox.NewRepository("wallet_schema.outbox")
	cashbackSvc := cashback.NewService(cashbackRepo, cashbackOutboxRepo, calLoader, coinCurrency, nil, nil, nil)

	payoutRepo := sellerpayout.NewRepository(ledgerPool)
	payoutSvc := sellerpayout.NewService(payoutRepo, nil, nil, calLoader, payoutCurrency, nil)

	// ── Outbox publisher (ecom side) ─────────────────────────────────────────
	bus := eventbus.NewRedisBus(rc, slog.Default())
	pub, err := outbox.NewPublisher(ecomPool, orderOutboxRepo, bus, slog.Default())
	if err != nil {
		t.Fatalf("outbox publisher init: %v", err)
	}

	// ── Test constants (same as the direct-call e2e test) ───────────────────
	const variantID = int64(5001)
	const sellerID = int64(77)
	const categoryID = int64(30)
	const priceMinor = int64(50000)
	const commPctBps = 700
	const kdvPctBps = 2000

	gross := priceMinor * 1
	commAmt := gross * commPctBps / 10000
	kdvAmt := commAmt * kdvPctBps / 10000
	sellerNet := gross - commAmt - kdvAmt

	mockCat := &catalogMock{
		variant: catalog.Variant{
			ID:            variantID,
			ProductID:     1001,
			CategoryID:    categoryID,
			SellerID:      sellerID,
			SKU:           "E2E-REDIS-001",
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
	mockCart := &cartMock{
		items: []cart.CartItem{{VariantID: variantID, Qty: 1}},
	}

	orderSvc := order.NewService(orderRepo, mockCart, mockCat, orderOutboxRepo, market, coinCurrency)

	// ── Step 1: Checkout ─────────────────────────────────────────────────────
	idempKey := fmt.Sprintf("e2e-redis-checkout-%d", time.Now().UnixNano())
	createdOrder, items, err := orderSvc.Checkout(ctx, order.CheckoutRequest{
		UserID:         998,
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
	t.Logf("checkout OK: orderID=%d commAmt=%d sellerNet=%d", createdOrder.ID, commAmt, sellerNet)

	// ── Step 2: MarkDelivered → writes ecom.order.delivered.v1 to outbox ────
	deliveredAt := time.Date(2026, 5, 12, 12, 0, 0, 0, time.UTC)
	if err := orderSvc.MarkDelivered(ctx, createdOrder.ID, deliveredAt); err != nil {
		t.Fatalf("MarkDelivered: %v", err)
	}

	// ── Step 3: Run outbox publisher — XADDs the event to Redis Streams ─────
	published, err := pub.RunBatch(ctx)
	if err != nil {
		t.Fatalf("outbox RunBatch: %v", err)
	}
	if published == 0 {
		t.Fatal("outbox RunBatch: expected at least 1 published event, got 0")
	}
	t.Logf("outbox published %d event(s)", published)

	// ── Step 4: Start consumers — they subscribe to ecom.order.delivered.v1 ──
	// Context with deadline so goroutines stop after test, even if no message arrives.
	consumerCtx, cancelConsumers := context.WithTimeout(ctx, 8*time.Second)
	defer cancelConsumers()

	go func() {
		_ = cashback.StartConsumer(consumerCtx, bus, cashbackSvc)
	}()
	go func() {
		_ = sellerpayout.StartConsumer(consumerCtx, bus, payoutSvc)
	}()

	// ── Step 5: Poll for cashback plan ────────────────────────────────────────
	// D3: stdlib polling loop, no testify.
	const wantMonthlyMinor int64 = 145 // commAmt=3500, yearly=1750, monthly=145
	var planExists bool
	deadline := time.Now().Add(6 * time.Second)
	for time.Now().Before(deadline) {
		var monthly int64
		err := ledgerPool.QueryRow(ctx,
			`SELECT monthly_amount_minor FROM cashback_schema.plans WHERE order_id = $1`,
			createdOrder.ID,
		).Scan(&monthly)
		if err == nil {
			planExists = true
			if monthly != wantMonthlyMinor {
				t.Errorf("cashback plan monthly_amount_minor: want %d, got %d", wantMonthlyMinor, monthly)
			}
			break
		}
		time.Sleep(50 * time.Millisecond)
	}
	if !planExists {
		t.Fatalf("cashback plan not created within 6s after delivery event (order_id=%d)", createdOrder.ID)
	}
	t.Logf("cashback plan OK: monthly=%d", wantMonthlyMinor)

	// ── Step 6: Poll for seller payout ───────────────────────────────────────
	var payoutExists bool
	deadline = time.Now().Add(6 * time.Second)
	for time.Now().Before(deadline) {
		var amount int64
		var status string
		var unlockAt time.Time
		err := ledgerPool.QueryRow(ctx,
			`SELECT amount_minor, status, unlock_at
			 FROM sellerpayout_schema.seller_payouts
			 WHERE order_id = $1 AND seller_id = $2`,
			createdOrder.ID, sellerID,
		).Scan(&amount, &status, &unlockAt)
		if err == nil {
			payoutExists = true
			if amount != sellerNet {
				t.Errorf("payout amount_minor: want %d, got %d", sellerNet, amount)
			}
			if status != "scheduled" {
				t.Errorf("payout status: want scheduled, got %s", status)
			}
			// unlock_at is stored as Postgres DATE (read back as midnight UTC).
			// Compare date portions only — preserving time-of-day in deliveredAt
			// would make any non-midnight deliveredAt fail this assertion incorrectly.
			minUnlockDate := time.Date(deliveredAt.Year(), deliveredAt.Month(), deliveredAt.Day(), 0, 0, 0, 0, time.UTC).AddDate(0, 0, 3)
			if unlockAt.Before(minUnlockDate) {
				t.Errorf("unlock_at %v is before deliveredAt+3d %v", unlockAt, minUnlockDate)
			}
			t.Logf("seller payout OK: amount=%d unlock=%s", amount, unlockAt.Format("2006-01-02"))
			break
		}
		time.Sleep(50 * time.Millisecond)
	}
	if !payoutExists {
		t.Fatalf("seller payout not created within 6s after delivery event (order_id=%d)", createdOrder.ID)
	}

	// ── Step 7: Idempotency — second RunBatch + consumer cycle must be no-op ──
	pub2Published, err := pub.RunBatch(ctx)
	if err != nil {
		t.Fatalf("outbox RunBatch (idempotent): %v", err)
	}
	if pub2Published > 0 {
		t.Logf("second RunBatch published %d (may be other events from wallet_schema.outbox)", pub2Published)
	}

	// Allow consumer goroutines to process any re-delivered PEL.
	time.Sleep(200 * time.Millisecond)

	var planCount int
	if err := ledgerPool.QueryRow(ctx,
		`SELECT COUNT(*) FROM cashback_schema.plans WHERE order_id = $1`,
		createdOrder.ID,
	).Scan(&planCount); err != nil {
		t.Fatalf("count plans: %v", err)
	}
	if planCount != 1 {
		t.Errorf("idempotency: want 1 plan, got %d", planCount)
	}

	var payoutCount int
	if err := ledgerPool.QueryRow(ctx,
		`SELECT COUNT(*) FROM sellerpayout_schema.seller_payouts WHERE order_id = $1`,
		createdOrder.ID,
	).Scan(&payoutCount); err != nil {
		t.Fatalf("count payouts: %v", err)
	}
	if payoutCount != 1 {
		t.Errorf("idempotency: want 1 payout, got %d", payoutCount)
	}

	t.Logf("e2e Redis PASS: order=%d plan_count=%d payout_count=%d", createdOrder.ID, planCount, payoutCount)
}
