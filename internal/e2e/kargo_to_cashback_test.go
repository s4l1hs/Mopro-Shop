//go:build integration

package e2e_test

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/mopro/platform/internal/cart"
	"github.com/mopro/platform/internal/cashback"
	"github.com/mopro/platform/internal/catalog"
	"github.com/mopro/platform/internal/order"
	"github.com/mopro/platform/internal/outbox"
	"github.com/mopro/platform/internal/sellerpayout"
	"github.com/mopro/platform/internal/shipping"
	"github.com/mopro/platform/internal/shipping/surat"
	"github.com/mopro/platform/pkg/timex"
)

// TestE2E_KargoWebhookToCashbackPlan is the Phase 1.6 full-chain happy-path:
//
//  1. Seed order in 'shipped' state
//  2. Seed shipment in shipping_schema.shipments (state='in_transit', carrier='surat')
//  3. POST /v1/shipping/webhook/surat with valid HMAC body (state='delivered')
//  4. Poll (deadline 5s, 50ms): assert shipping state, order status, outbox row
//  5. Simulate fin-svc consumer: cashback plan + seller payout scheduled
//  6. Assert cashback_schema.plans + commission_schema.seller_payouts

func TestE2E_KargoWebhookToCashbackPlan(t *testing.T) { //nolint:gocyclo,cyclop
	ctx := context.Background()

	// ── constants ──────────────────────────────────────────────────────────────
	const market = "TR"
	const payoutCurrency = "TRY"
	const coinCurrency = "TRY_COIN"
	const webhookSecret = "e2e-surat-webhook-secret"
	const carrier = "surat"
	const tracking = "SURAT-E2E-001"

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

	// ── 1. Seed order in 'shipped' state ──────────────────────────────────────
	idempKey := fmt.Sprintf("e2e-kargo-%d", time.Now().UnixNano())
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
	t.Logf("seeded orderID=%d", orderID)

	// ── 2. Seed shipment ───────────────────────────────────────────────────────
	var shipmentID int64
	shipIdempKey := fmt.Sprintf("ship-e2e-%d", time.Now().UnixNano())
	if err := ecomPool.QueryRow(ctx, `
		INSERT INTO shipping_schema.shipments
			(order_id, carrier, tracking_number, state, idempotency_key)
		VALUES ($1,$2,$3,'in_transit',$4)
		RETURNING id`,
		orderID, carrier, tracking, shipIdempKey,
	).Scan(&shipmentID); err != nil {
		t.Fatalf("seed shipment: %v", err)
	}
	t.Logf("seeded shipmentID=%d", shipmentID)

	// ── 3. Build shipping service + httptest server ────────────────────────────
	shippingRepo := shipping.NewRepository(ecomPool)
	orderRepo := order.NewRepository(ecomPool)
	orderOutbox := outbox.NewRepository("order_schema.outbox")

	mockCatalog := &catalogMock{
		variant: catalog.Variant{
			ID:            variantID,
			ProductID:     1001,
			CategoryID:    categoryID,
			SellerID:      sellerID,
			SKU:           "E2E-KARGO-SKU",
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
	orderSvc := order.NewService(orderRepo, mockCart, mockCatalog, orderOutbox, market, coinCurrency)

	suratAdapter := surat.New(shipping.SuratConfig{WebhookSecret: webhookSecret})
	shippingSvc, err := shipping.NewService(carrier,
		map[string]shipping.Adapter{carrier: suratAdapter},
		shippingRepo, orderSvc,
	)
	if err != nil {
		t.Fatalf("NewService: %v", err)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("POST /v1/shipping/webhook/surat", func(w http.ResponseWriter, r *http.Request) {
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

	// ── 4. POST webhook with valid HMAC ────────────────────────────────────────
	eventAt := time.Now().UTC().Format(time.RFC3339)
	webhookBody := fmt.Sprintf(
		`{"trackingNumber":%q,"status":"DELIVERED","description":"Teslim edildi","eventAt":%q}`,
		tracking, eventAt,
	)
	mac := hmac.New(sha256.New, []byte(webhookSecret))
	mac.Write([]byte(webhookBody))
	sig := hex.EncodeToString(mac.Sum(nil))

	req, _ := http.NewRequestWithContext(ctx, http.MethodPost,
		srv.URL+"/v1/shipping/webhook/surat", bytes.NewBufferString(webhookBody))
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
	t.Log("webhook POST 200 OK")

	// ── 5. Poll for state changes (deadline 5s, interval 50ms) ────────────────
	deadline := time.Now().Add(5 * time.Second)
	var outboxPayloadRaw json.RawMessage
	var outboxMarket string
	for {
		if time.Now().After(deadline) {
			t.Fatal("poll deadline exceeded waiting for delivery state propagation")
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
			fmt.Sprintf("%d", orderID),
		).Scan(&outboxPayloadRaw, &outboxMarket); err != nil {
			time.Sleep(50 * time.Millisecond)
			continue
		}
		t.Logf("poll PASS: ship=%s order=%s outbox market=%s", shipState, orderStatus, outboxMarket)
		break
	}

	// Hard assertions after polling loop exits.
	var gotShipState string
	var gotShipDeliveredAt *time.Time
	if err := ecomPool.QueryRow(ctx,
		`SELECT state, delivered_at FROM shipping_schema.shipments WHERE id=$1`, shipmentID,
	).Scan(&gotShipState, &gotShipDeliveredAt); err != nil {
		t.Fatalf("final check shipment: %v", err)
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
		t.Fatalf("final check order: %v", err)
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
	t.Log("all webhook-chain assertions PASS")

	// ── 6. Simulate fin-svc consumer ──────────────────────────────────────────
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
	cashbackOutbox := outbox.NewRepository("wallet_schema.outbox")
	cashbackSvc := cashback.NewService(cashbackRepo, cashbackOutbox, calLoader, coinCurrency)

	payoutRepo := sellerpayout.NewRepository(ledgerPool)
	payoutSvc := sellerpayout.NewService(payoutRepo, calLoader, payoutCurrency)

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

	// ── 7. ASSERT: cashback_schema.plans exists, monthly_amount_minor > 0 ─────
	var planMonthly int64
	if err := ledgerPool.QueryRow(ctx,
		`SELECT monthly_amount_minor FROM cashback_schema.plans WHERE order_id=$1`, orderID,
	).Scan(&planMonthly); err != nil {
		t.Fatalf("cashback plan missing: %v", err)
	}
	if planMonthly <= 0 {
		t.Errorf("cashback monthly_amount_minor: want >0, got %d", planMonthly)
	}
	t.Logf("cashback plan OK: monthly=%d", planMonthly)

	// ── 8. ASSERT: commission_schema.seller_payouts exists, status='scheduled' ─
	var payoutStatus string
	if err := ledgerPool.QueryRow(ctx,
		`SELECT status FROM commission_schema.seller_payouts
		 WHERE order_id=$1 AND seller_id=$2`,
		orderID, sellerID,
	).Scan(&payoutStatus); err != nil {
		t.Fatalf("seller payout missing: %v", err)
	}
	if payoutStatus != "scheduled" {
		t.Errorf("payout status: want scheduled, got %s", payoutStatus)
	}
	t.Logf("seller payout OK: status=%s", payoutStatus)

	t.Logf("e2e PASS: order=%d ship=%d plan_monthly=%d payout=%s",
		orderID, shipmentID, planMonthly, payoutStatus)
}
