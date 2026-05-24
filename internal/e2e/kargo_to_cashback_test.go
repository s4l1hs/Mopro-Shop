//go:build integration

package e2e_test

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strconv"
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
	"github.com/mopro/platform/internal/shipping"
	"github.com/mopro/platform/internal/shipping/surat"
	"github.com/mopro/platform/pkg/timex"
)

// TestE2E_KargoWebhookToCashbackPlan is the Phase 1.6 full-chain happy-path.
// Chain verified:
//  1. Seed order (status='shipped') + shipment (state='in_transit', carrier='surat')
//  2. POST /shipping/webhook/surat with valid HMAC → httptest.Server
//  3. Poll (5s / 50ms): shipments.state='delivered', orders.status='delivered', outbox row
//  4. RunBatch publishes outbox → Redis Streams; assert published_at NOT NULL
//  5. Assert ecom.order.delivered.v1 in Redis Streams (XRange)
//  6. Simulate fin-svc consumer: cashback.CreatePlanForOrder + sellerpayout.SchedulePayoutsForOrder
//  7. Assert cashback_schema.plans.monthly_amount_minor > 0
//  8. Assert commission_schema.seller_payouts.status='scheduled'
func TestE2E_KargoWebhookToCashbackPlan(t *testing.T) { //nolint:gocyclo,cyclop
	ctx := context.Background()

	// ── Redis client ────────────────────────────────────────────────────────────
	redisAddr := getEnvOr("REDIS_E2E_ADDR", "localhost:6381")
	rc := redis.NewClient(&redis.Options{Addr: redisAddr})
	if err := rc.Ping(ctx).Err(); err != nil {
		t.Fatalf("Redis at %s not available: %v", redisAddr, err)
	}
	t.Cleanup(func() { _ = rc.Close() })
	// Flush so stale streams don't interfere.
	if err := rc.FlushDB(ctx).Err(); err != nil {
		t.Fatalf("redis flush: %v", err)
	}

	// ── constants ───────────────────────────────────────────────────────────────
	const market = "TR"
	const payoutCurrency = "TRY"
	const coinCurrency = "TRY_COIN"
	const webhookSecret = "e2e-surat-webhook-secret"
	const carrier = "surat"
	const tracking = "SURAT-E2E-FULL-001"

	const variantID = int64(6001)
	const sellerID = int64(88)
	const categoryID = int64(30)
	const priceMinor = int64(100000) // 1000.00 TL
	const commPctBps = 700           // 7%
	const kdvPctBps = 2000           // 20%

	gross := priceMinor * 1
	commAmt := gross * commPctBps / 10000
	kdvAmt := commAmt * kdvPctBps / 10000
	sellerNet := gross - commAmt - kdvAmt

	// ── 1. Seed order in 'shipped' state ───────────────────────────────────────
	idempKey := fmt.Sprintf("e2e-kargo-full-%d", time.Now().UnixNano())
	var orderID int64
	if err := ecomPool.QueryRow(ctx, `
		INSERT INTO order_schema.orders
			(user_id, status, subtotal_minor, total_minor, currency, market,
			 cashback_eligible, cashback_currency, idempotency_key)
		VALUES ($1,'shipped',$2,$2,$3,$4,true,$5,$6)
		RETURNING id`,
		int64(999), priceMinor, payoutCurrency, market, coinCurrency, idempKey,
	).Scan(&orderID); err != nil {
		t.Fatalf("seed order: %v", err)
	}
	if _, err := ecomPool.Exec(ctx, `
		INSERT INTO order_schema.order_items
			(order_id, variant_id, seller_id, category_id, qty,
			 unit_price_minor, unit_price_currency,
			 commission_pct_bps, kdv_pct_bps,
			 commission_amount_minor, kdv_amount_minor, seller_net_minor)
		VALUES ($1,$2,$3,$4,1,$5,$6,$7,$8,$9,$10,$11)`,
		orderID, variantID, sellerID, categoryID,
		priceMinor, payoutCurrency, commPctBps, kdvPctBps,
		commAmt, kdvAmt, sellerNet,
	); err != nil {
		t.Fatalf("seed order_item: %v", err)
	}
	t.Logf("seeded orderID=%d commAmt=%d sellerNet=%d", orderID, commAmt, sellerNet)

	// ── 2. Seed shipment ────────────────────────────────────────────────────────
	var shipmentID int64
	shipIdempKey := fmt.Sprintf("ship-e2e-full-%d", time.Now().UnixNano())
	if err := ecomPool.QueryRow(ctx, `
		INSERT INTO shipping_schema.shipments
			(order_id, carrier, tracking_number, state, idempotency_key)
		VALUES ($1,$2,$3,'in_transit',$4)
		RETURNING id`,
		orderID, carrier, tracking, shipIdempKey,
	).Scan(&shipmentID); err != nil {
		t.Fatalf("seed shipment: %v", err)
	}
	t.Logf("seeded shipmentID=%d tracking=%s", shipmentID, tracking)

	// ── 3. Build shipping service wired to real repos ──────────────────────────
	shippingRepo := shipping.NewRepository(ecomPool)
	orderRepo := order.NewRepository(ecomPool)
	orderOutboxRepo := outbox.NewRepository("order_schema.outbox")

	mockCatalog := &catalogMock{
		variant: catalog.Variant{
			ID:            variantID,
			ProductID:     1001,
			CategoryID:    categoryID,
			SellerID:      sellerID,
			SKU:           "E2E-KARGO-FULL-SKU",
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
	mockCart := &cartMock{items: []cart.CartItem{{VariantID: variantID, Qty: 1}}}
	orderSvc := order.NewService(orderRepo, mockCart, mockCatalog, orderOutboxRepo, market, coinCurrency)

	suratAdapter := surat.New(shipping.SuratConfig{WebhookSecret: webhookSecret})
	shippingSvc, err := shipping.NewService(carrier,
		map[string]shipping.Adapter{carrier: suratAdapter},
		shippingRepo, orderSvc,
	)
	if err != nil {
		t.Fatalf("NewService: %v", err)
	}

	// ── 4. POST webhook via httptest.Server ────────────────────────────────────
	mux := http.NewServeMux()
	mux.HandleFunc("POST /shipping/webhook/surat", func(w http.ResponseWriter, r *http.Request) {
		rawBody, _ := io.ReadAll(r.Body)
		headers := make(map[string]string)
		for k := range r.Header {
			headers[k] = r.Header.Get(k)
		}
		event, err := shippingSvc.HandleWebhook(r.Context(), carrier, rawBody, headers)
		if err != nil {
			http.Error(w, "sig err", http.StatusBadRequest)
			return
		}
		if err := shippingSvc.ProcessWebhookEvent(r.Context(), carrier, event); err != nil {
			http.Error(w, "process err", http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusOK)
	})
	srv := httptest.NewServer(mux)
	defer srv.Close()

	eventAt := time.Now().UTC().Format(time.RFC3339)
	webhookBody := fmt.Sprintf(
		`{"trackingNumber":%q,"status":"DELIVERED","description":"Teslim edildi","eventAt":%q}`,
		tracking, eventAt,
	)
	mac := hmac.New(sha256.New, []byte(webhookSecret))
	mac.Write([]byte(webhookBody))
	sig := hex.EncodeToString(mac.Sum(nil))

	req, _ := http.NewRequestWithContext(ctx, http.MethodPost,
		srv.URL+"/shipping/webhook/surat", bytes.NewBufferString(webhookBody))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Surat-Sign", sig)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("POST webhook: %v", err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("webhook response: want 200, got %d", resp.StatusCode)
	}
	t.Log("webhook POST → 200 OK")

	// ── 5. Poll: shipments.state + orders.status + outbox row ─────────────────
	var outboxPayloadRaw json.RawMessage
	var outboxMarket string
	deadline := time.Now().Add(5 * time.Second)
	for {
		if time.Now().After(deadline) {
			t.Fatal("poll deadline exceeded: shipping/order state or outbox row not found within 5s")
		}

		var shipState string
		var shipDeliveredAt *time.Time
		if err := ecomPool.QueryRow(ctx,
			`SELECT state, delivered_at FROM shipping_schema.shipments WHERE id=$1`, shipmentID,
		).Scan(&shipState, &shipDeliveredAt); err != nil || shipState != "delivered" || shipDeliveredAt == nil {
			time.Sleep(50 * time.Millisecond)
			continue
		}

		var orderStatus string
		var orderDeliveredAt *time.Time
		if err := ecomPool.QueryRow(ctx,
			`SELECT status, delivered_at FROM order_schema.orders WHERE id=$1`, orderID,
		).Scan(&orderStatus, &orderDeliveredAt); err != nil || orderStatus != "delivered" || orderDeliveredAt == nil {
			time.Sleep(50 * time.Millisecond)
			continue
		}

		if err := ecomPool.QueryRow(ctx,
			`SELECT payload, market FROM order_schema.outbox
			 WHERE event_type='ecom.order.delivered.v1' AND payload->>'order_id'=$1::text
			 LIMIT 1`,
			strconv.FormatInt(orderID, 10),
		).Scan(&outboxPayloadRaw, &outboxMarket); err != nil {
			time.Sleep(50 * time.Millisecond)
			continue
		}
		t.Logf("poll PASS: ship_state=%s order_status=%s outbox_market=%s", shipState, orderStatus, outboxMarket)
		break
	}

	// Hard assertions.
	var gotShipState string
	var gotShipDeliveredAt *time.Time
	if err := ecomPool.QueryRow(ctx,
		`SELECT state, delivered_at FROM shipping_schema.shipments WHERE id=$1`, shipmentID,
	).Scan(&gotShipState, &gotShipDeliveredAt); err != nil {
		t.Fatalf("check shipment: %v", err)
	}
	if gotShipState != "delivered" {
		t.Errorf("shipment state: want delivered, got %s", gotShipState)
	}
	if gotShipDeliveredAt == nil {
		t.Error("shipment delivered_at: want NOT NULL, got NULL")
	}

	var gotOrderStatus string
	var gotOrderDeliveredAt *time.Time
	if err := ecomPool.QueryRow(ctx,
		`SELECT status, delivered_at FROM order_schema.orders WHERE id=$1`, orderID,
	).Scan(&gotOrderStatus, &gotOrderDeliveredAt); err != nil {
		t.Fatalf("check order: %v", err)
	}
	if gotOrderStatus != "delivered" {
		t.Errorf("order status: want delivered, got %s", gotOrderStatus)
	}
	if gotOrderDeliveredAt == nil {
		t.Error("order delivered_at: want NOT NULL, got NULL")
	}
	if outboxMarket != market {
		t.Errorf("outbox market: want %s, got %s", market, outboxMarket)
	}
	t.Log("ASSERT shipping_schema.shipments.state='delivered' delivered_at NOT NULL — PASS")
	t.Log("ASSERT order_schema.orders.status='delivered' delivered_at NOT NULL — PASS")
	t.Log("ASSERT order_schema.outbox row exists event_type='ecom.order.delivered.v1' — PASS")

	// ── 6. Publish outbox → Redis Streams; assert published_at NOT NULL ────────
	bus := eventbus.NewRedisBus(rc, slog.Default())
	pub, err := outbox.NewPublisher(ecomPool, orderOutboxRepo, bus, slog.Default())
	if err != nil {
		t.Fatalf("outbox publisher init: %v", err)
	}
	published, err := pub.RunBatch(ctx)
	if err != nil {
		t.Fatalf("outbox RunBatch: %v", err)
	}
	t.Logf("outbox RunBatch published %d event(s)", published)
	if published == 0 {
		t.Fatal("outbox RunBatch: expected ≥1 published event, got 0")
	}

	// Poll for published_at NOT NULL.
	deadline = time.Now().Add(5 * time.Second)
	var publishedAt sql.NullTime
	for time.Now().Before(deadline) {
		err := ecomPool.QueryRow(ctx,
			`SELECT published_at FROM order_schema.outbox
			 WHERE event_type='ecom.order.delivered.v1' AND payload->>'order_id'=$1`,
			strconv.FormatInt(orderID, 10),
		).Scan(&publishedAt)
		if err == nil && publishedAt.Valid {
			break
		}
		time.Sleep(50 * time.Millisecond)
	}
	if !publishedAt.Valid {
		t.Fatal("ASSERT outbox.published_at NOT NULL — FAIL: not set within 5s after RunBatch")
	}
	t.Logf("ASSERT outbox.published_at NOT NULL — PASS: published_at=%s", publishedAt.Time.Format(time.RFC3339))

	// ── 7. Verify event landed in Redis Streams ────────────────────────────────
	streamResult, err := rc.XRange(ctx, "ecom.order.delivered.v1", "-", "+").Result()
	if err != nil {
		t.Fatalf("XRange ecom.order.delivered.v1: %v", err)
	}
	expectedKey := fmt.Sprintf("order:delivered:order_%d", orderID)
	found := false
	for _, msg := range streamResult {
		if v, ok := msg.Values["idempotency_key"]; ok {
			if s, ok := v.(string); ok && s == expectedKey {
				found = true
				t.Logf("ASSERT ecom.order.delivered.v1 in Redis Streams — PASS: msgID=%s", msg.ID)
				break
			}
		}
	}
	if !found {
		t.Logf("Redis stream contents (%d messages):", len(streamResult))
		for i, msg := range streamResult {
			t.Logf("  msg[%d] id=%s values=%+v", i, msg.ID, msg.Values)
		}
		t.Fatalf("ecom.order.delivered.v1 with idempotency_key=%q not found", expectedKey)
	}

	// ── 8. Simulate fin-svc consumer: cashback plan + seller payout ────────────
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
	if err := json.Unmarshal(outboxPayloadRaw, &evPayload); err != nil {
		t.Fatalf("unmarshal outbox payload: %v", err)
	}

	cal := timex.Calendar{Market: market, Holidays: map[string]struct{}{}}
	calLoader := timex.NewStaticCalendarLoader(map[string]timex.Calendar{market: cal})

	cashbackRepo := cashback.NewRepository(ledgerPool)
	cashbackOutboxRepo := outbox.NewRepository("wallet_schema.outbox")
	cashbackSvc := cashback.NewService(cashbackRepo, cashbackOutboxRepo, calLoader, coinCurrency, nil, nil)

	payoutRepo := sellerpayout.NewRepository(ledgerPool)
	payoutSvc := sellerpayout.NewService(payoutRepo, nil, nil, calLoader, payoutCurrency, nil)

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

	deliveredAtForFin := *gotOrderDeliveredAt
	if err := cashbackSvc.CreatePlanForOrder(ctx, cashback.OrderDeliveredEvent{
		OrderID:     evPayload.OrderID,
		UserID:      evPayload.UserID,
		DeliveredAt: deliveredAtForFin,
		Market:      market,
		Currency:    payoutCurrency,
		Items:       cbItems,
	}); err != nil {
		t.Fatalf("CreatePlanForOrder: %v", err)
	}

	spItems := make([]sellerpayout.DeliveredItem, len(evPayload.Items))
	for i, it := range evPayload.Items {
		spItems[i] = sellerpayout.DeliveredItem{
			SellerID:       it.SellerID,
			SellerNetMinor: it.SellerNetMinor,
		}
	}
	if err := payoutSvc.SchedulePayoutsForOrder(ctx, sellerpayout.OrderDeliveredEvent{
		OrderID:     evPayload.OrderID,
		DeliveredAt: deliveredAtForFin,
		Market:      market,
		Currency:    payoutCurrency,
		Items:       spItems,
	}); err != nil {
		t.Fatalf("SchedulePayoutsForOrder: %v", err)
	}

	// ── 9. ASSERT cashback plan ────────────────────────────────────────────────
	var planMonthly int64
	if err := ledgerPool.QueryRow(ctx,
		`SELECT monthly_amount_minor FROM cashback_schema.plans WHERE order_id=$1`, orderID,
	).Scan(&planMonthly); err != nil {
		t.Fatalf("ASSERT cashback_schema.plans — FAIL: %v", err)
	}
	if planMonthly <= 0 {
		t.Errorf("cashback monthly_amount_minor: want >0, got %d", planMonthly)
	}
	// Formula check: commAmt=7000, yearly=7000*5000/10000=3500, monthly=3500/12=291
	expectedMonthly := (commAmt * cashback.ReferenceInterestRateBpsConst / 10000) / 12
	if planMonthly != expectedMonthly {
		t.Errorf("monthly formula: want %d (commAmt=%d * 0.50 / 12), got %d", expectedMonthly, commAmt, planMonthly)
	}
	t.Logf("ASSERT cashback_schema.plans monthly_amount_minor=%d — PASS (formula: commAmt=%d → yearly=%d → monthly=%d)",
		planMonthly, commAmt, commAmt*cashback.ReferenceInterestRateBpsConst/10000, expectedMonthly)

	// ── 10. ASSERT seller payout ───────────────────────────────────────────────
	var payoutStatus string
	if err := ledgerPool.QueryRow(ctx,
		`SELECT status FROM commission_schema.seller_payouts WHERE order_id=$1 AND seller_id=$2`,
		orderID, sellerID,
	).Scan(&payoutStatus); err != nil {
		t.Fatalf("ASSERT commission_schema.seller_payouts — FAIL: %v", err)
	}
	if payoutStatus != "scheduled" {
		t.Errorf("payout status: want scheduled, got %s", payoutStatus)
	}
	t.Logf("ASSERT commission_schema.seller_payouts status='scheduled' — PASS")

	t.Logf("TestE2E_KargoWebhookToCashbackPlan PASS: order=%d ship=%d plan_monthly=%d payout=%s",
		orderID, shipmentID, planMonthly, payoutStatus)
}
