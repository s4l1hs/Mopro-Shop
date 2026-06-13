package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/mopro/platform/internal/order"
	"github.com/mopro/platform/internal/outbox"
	"github.com/mopro/platform/internal/payment"
)

// ── order.Service mock ────────────────────────────────────────────────────────

type stubOrderSvc struct {
	getOrderFn     func(ctx context.Context, id int64) (order.Order, []order.OrderItem, error)
	cancelOrderFn  func(ctx context.Context, id int64, reason string) error
	updateStatusFn func(ctx context.Context, id int64, status order.OrderStatus) error
}

func (s *stubOrderSvc) Checkout(_ context.Context, _ order.CheckoutRequest) (order.Order, []order.OrderItem, error) {
	return order.Order{}, nil, nil
}
func (s *stubOrderSvc) GetOrder(ctx context.Context, id int64) (order.Order, []order.OrderItem, error) {
	if s.getOrderFn != nil {
		return s.getOrderFn(ctx, id)
	}
	return order.Order{ID: id, Status: order.StatusPaid, Currency: "TRY"}, nil, nil
}
func (s *stubOrderSvc) ListOrders(_ context.Context, _ int64) ([]order.Order, error) { return nil, nil }
func (s *stubOrderSvc) UpdateStatus(ctx context.Context, id int64, status order.OrderStatus) error {
	if s.updateStatusFn != nil {
		return s.updateStatusFn(ctx, id, status)
	}
	return nil
}
func (s *stubOrderSvc) MarkDelivered(_ context.Context, _ int64, _ time.Time) error { return nil }
func (s *stubOrderSvc) CancelOrder(ctx context.Context, id int64, reason string) error {
	if s.cancelOrderFn != nil {
		return s.cancelOrderFn(ctx, id, reason)
	}
	return nil
}
func (s *stubOrderSvc) InitiateCheckout(_ context.Context, _ order.InitiateCheckoutRequest) (order.InitiateCheckoutResponse, error) {
	return order.InitiateCheckoutResponse{}, nil
}
func (s *stubOrderSvc) MarkPaid(_ context.Context, _ int64) error { return nil }
func (s *stubOrderSvc) ValidateCoupon(_ context.Context, _ string, _ int64, _ string, _ int64) (order.CouponValidation, error) {
	return order.CouponValidation{}, nil
}

// ── payment.Service mock ──────────────────────────────────────────────────────

type stubPaymentSvc struct {
	refundFn func(ctx context.Context, req payment.RefundRequest) (payment.RefundResponse, error)
}

func (s *stubPaymentSvc) InitiatePayment(_ context.Context, _ payment.InitiatePaymentRequest) (payment.InitiatePaymentResponse, error) {
	return payment.InitiatePaymentResponse{}, nil
}
func (s *stubPaymentSvc) ConfirmWebhook(_ context.Context, _ []byte, _ string) (payment.PaymentEvent, error) {
	return payment.PaymentEvent{}, nil
}
func (s *stubPaymentSvc) Refund(ctx context.Context, req payment.RefundRequest) (payment.RefundResponse, error) {
	if s.refundFn != nil {
		return s.refundFn(ctx, req)
	}
	return payment.RefundResponse{RefundRef: "ref-001", RefundedAt: time.Now(), AmountMinor: 5000}, nil
}
func (s *stubPaymentSvc) CheckStatus(_ context.Context, _ string) (payment.PaymentStatus, error) {
	return payment.PaymentStatusCaptured, nil
}
func (s *stubPaymentSvc) RegisterSubMerchant(_ context.Context, _ payment.RegisterSubMerchantRequest) (payment.SubMerchantRef, error) {
	return payment.SubMerchantRef{}, nil
}
func (s *stubPaymentSvc) TransferToSeller(_ context.Context, _ payment.TransferToSellerRequest) (payment.TransferRef, error) {
	return payment.TransferRef{}, nil
}

// ── payment.Repository mock ───────────────────────────────────────────────────

type stubPaymentRepo struct {
	findByOrderIDFn func(ctx context.Context, orderID int64) (payment.PaymentIntent, error)
	updateStatusFn  func(ctx context.Context, tx pgx.Tx, providerRef string, status payment.PaymentStatus, capturedAt, failedAt, refundedAt *string, failureReason, refundRef string, refundAmountMinor int64) error
}

func (s *stubPaymentRepo) InsertPaymentIntent(_ context.Context, _ pgx.Tx, p payment.PaymentIntent) (payment.PaymentIntent, error) {
	return p, nil
}
func (s *stubPaymentRepo) FindPaymentIntentByIdempotencyKey(_ context.Context, _ string) (payment.PaymentIntent, error) {
	return payment.PaymentIntent{}, nil
}
func (s *stubPaymentRepo) FindPaymentByOrderID(ctx context.Context, orderID int64) (payment.PaymentIntent, error) {
	if s.findByOrderIDFn != nil {
		return s.findByOrderIDFn(ctx, orderID)
	}
	return payment.PaymentIntent{
		ID: 1, OrderID: orderID, ProviderRef: "inv-001",
		Status: payment.PaymentStatusCaptured, AmountMinor: 5000, Currency: "TRY",
	}, nil
}
func (s *stubPaymentRepo) UpdatePaymentStatus(ctx context.Context, tx pgx.Tx, providerRef string, status payment.PaymentStatus, capturedAt, failedAt, refundedAt *string, failureReason, refundRef string, refundAmountMinor int64) error {
	if s.updateStatusFn != nil {
		return s.updateStatusFn(ctx, tx, providerRef, status, capturedAt, failedAt, refundedAt, failureReason, refundRef, refundAmountMinor)
	}
	return nil
}
func (s *stubPaymentRepo) FindExpiredPendingPayments(_ context.Context, _ int) ([]payment.PaymentIntent, error) {
	return nil, nil
}
func (s *stubPaymentRepo) WithTx(_ context.Context, fn func(pgx.Tx) error) error {
	return fn(nil)
}

// ── outbox.Repository mock ────────────────────────────────────────────────────

type stubOutbox struct{}

func (s *stubOutbox) Insert(_ context.Context, _ pgx.Tx, _ outbox.Row) error { return nil }
func (s *stubOutbox) FetchUnpublished(_ context.Context, _ pgx.Tx, _ int) ([]outbox.Row, error) {
	return nil, nil
}
func (s *stubOutbox) MarkPublished(_ context.Context, _ pgx.Tx, _ int64) error { return nil }

// ── helpers ───────────────────────────────────────────────────────────────────

func newRequest(method, path, body string) *http.Request {
	var b *strings.Reader
	if body != "" {
		b = strings.NewReader(body)
	} else {
		b = strings.NewReader("{}")
	}
	r := httptest.NewRequest(method, path, b)
	r.Header.Set("Content-Type", "application/json")
	return r
}

// ── handleCancelOrder tests ───────────────────────────────────────────────────

func TestHandleCancelOrder_Success(t *testing.T) {
	svc := &stubOrderSvc{}
	r := newRequest("POST", "/orders/1/cancel", `{"reason":"changed mind"}`)
	r.SetPathValue("id", "1")
	w := httptest.NewRecorder()
	handleCancelOrder(svc)(w, r)
	if w.Code != http.StatusNoContent {
		t.Errorf("want 204, got %d: %s", w.Code, w.Body.String())
	}
}

func TestHandleCancelOrder_InvalidTransition(t *testing.T) {
	svc := &stubOrderSvc{
		cancelOrderFn: func(_ context.Context, _ int64, _ string) error {
			return fmt.Errorf("%w: cannot cancel shipped order", order.ErrInvalidTransition)
		},
	}
	r := newRequest("POST", "/orders/1/cancel", `{"reason":"test"}`)
	r.SetPathValue("id", "1")
	w := httptest.NewRecorder()
	handleCancelOrder(svc)(w, r)
	if w.Code != http.StatusConflict {
		t.Errorf("want 409, got %d", w.Code)
	}
}

func TestHandleCancelOrder_NotFound(t *testing.T) {
	svc := &stubOrderSvc{
		cancelOrderFn: func(_ context.Context, _ int64, _ string) error {
			return order.ErrOrderNotFound
		},
	}
	r := newRequest("POST", "/orders/9999/cancel", `{}`)
	r.SetPathValue("id", "9999")
	w := httptest.NewRecorder()
	handleCancelOrder(svc)(w, r)
	if w.Code != http.StatusNotFound {
		t.Errorf("want 404, got %d", w.Code)
	}
}

// ── handleRefundOrder tests ───────────────────────────────────────────────────

func TestHandleRefundOrder_Success(t *testing.T) {
	orderSvc := &stubOrderSvc{
		getOrderFn: func(_ context.Context, id int64) (order.Order, []order.OrderItem, error) {
			return order.Order{ID: id, Status: order.StatusPaid, Currency: "TRY"}, nil, nil
		},
	}
	paymentSvc := &stubPaymentSvc{}
	paymentRepo := &stubPaymentRepo{}
	ob := &stubOutbox{}

	r := newRequest("POST", "/orders/1/refund", `{}`)
	r.SetPathValue("id", "1")
	r.Header.Set("Idempotency-Key", "refund-test-001")
	w := httptest.NewRecorder()
	handleRefundOrder(orderSvc, paymentSvc, paymentRepo, ob, "TR", "TRY")(w, r)
	if w.Code != http.StatusOK {
		t.Errorf("want 200, got %d: %s", w.Code, w.Body.String())
	}
	var resp map[string]any
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if resp["refund_ref"] == "" {
		t.Error("refund_ref must be set in response")
	}
}

func TestHandleRefundOrder_WrongStatus(t *testing.T) {
	orderSvc := &stubOrderSvc{
		getOrderFn: func(_ context.Context, id int64) (order.Order, []order.OrderItem, error) {
			return order.Order{ID: id, Status: order.StatusPendingPayment}, nil, nil
		},
	}
	r := newRequest("POST", "/orders/1/refund", `{}`)
	r.SetPathValue("id", "1")
	r.Header.Set("Idempotency-Key", "refund-test-002")
	w := httptest.NewRecorder()
	handleRefundOrder(orderSvc, &stubPaymentSvc{}, &stubPaymentRepo{}, &stubOutbox{}, "TR", "TRY")(w, r)
	if w.Code != http.StatusConflict {
		t.Errorf("want 409, got %d: %s", w.Code, w.Body.String())
	}
}

func TestHandleRefundOrder_NoPaymentFound(t *testing.T) {
	paymentRepo := &stubPaymentRepo{
		findByOrderIDFn: func(_ context.Context, _ int64) (payment.PaymentIntent, error) {
			return payment.PaymentIntent{}, payment.ErrPaymentNotFound
		},
	}
	r := newRequest("POST", "/orders/1/refund", `{}`)
	r.SetPathValue("id", "1")
	r.Header.Set("Idempotency-Key", "refund-test-003")
	w := httptest.NewRecorder()
	handleRefundOrder(&stubOrderSvc{}, &stubPaymentSvc{}, paymentRepo, &stubOutbox{}, "TR", "TRY")(w, r)
	if w.Code != http.StatusNotFound {
		t.Errorf("want 404, got %d: %s", w.Code, w.Body.String())
	}
}

func TestHandleRefundOrder_MissingIdempotencyKey(t *testing.T) {
	r := newRequest("POST", "/orders/1/refund", `{}`)
	r.SetPathValue("id", "1")
	// No Idempotency-Key header
	w := httptest.NewRecorder()
	handleRefundOrder(&stubOrderSvc{}, &stubPaymentSvc{}, &stubPaymentRepo{}, &stubOutbox{}, "TR", "TRY")(w, r)
	if w.Code != http.StatusUnprocessableEntity {
		t.Errorf("want 422, got %d", w.Code)
	}
}

// ── handleSellerBreakdown tests ───────────────────────────────────────────────

func TestHandleSellerBreakdown_Success(t *testing.T) {
	svc := &stubOrderSvc{
		getOrderFn: func(_ context.Context, id int64) (order.Order, []order.OrderItem, error) {
			return order.Order{ID: id, Status: order.StatusDelivered}, []order.OrderItem{
				{
					VariantID: 10, SellerID: 42, Qty: 2,
					UnitPriceMinor: 5000, UnitPriceCurrency: "TRY",
					CommissionPctBps: 700, KdvPctBps: 2000,
					CommissionAmountMinor: 700, KdvAmountMinor: 140, SellerNetMinor: 9160,
				},
			}, nil
		},
	}
	r := httptest.NewRequest("GET", "/seller/orders/1/breakdown", nil)
	r.SetPathValue("id", "1")
	r.Header.Set("X-Mopro-Seller-Id", "42")
	w := httptest.NewRecorder()
	handleSellerBreakdown(svc)(w, r)
	if w.Code != http.StatusOK {
		t.Errorf("want 200, got %d: %s", w.Code, w.Body.String())
	}
	var resp map[string]any
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	items, ok := resp["items"].([]any)
	if !ok || len(items) != 1 {
		t.Fatalf("expected 1 item in breakdown, got %v", resp["items"])
	}
}

func TestHandleSellerBreakdown_WrongSeller(t *testing.T) {
	svc := &stubOrderSvc{
		getOrderFn: func(_ context.Context, id int64) (order.Order, []order.OrderItem, error) {
			return order.Order{ID: id, Status: order.StatusDelivered}, []order.OrderItem{
				{VariantID: 10, SellerID: 99, Qty: 1, UnitPriceMinor: 5000, UnitPriceCurrency: "TRY"},
			}, nil
		},
	}
	r := httptest.NewRequest("GET", "/seller/orders/1/breakdown", nil)
	r.SetPathValue("id", "1")
	r.Header.Set("X-Mopro-Seller-Id", "42") // seller 42 has no items in this order
	w := httptest.NewRecorder()
	handleSellerBreakdown(svc)(w, r)
	if w.Code != http.StatusNotFound {
		t.Errorf("want 404, got %d", w.Code)
	}
}

func TestHandleSellerBreakdown_MissingSellerHeader(t *testing.T) {
	r := httptest.NewRequest("GET", "/seller/orders/1/breakdown", nil)
	r.SetPathValue("id", "1")
	w := httptest.NewRecorder()
	handleSellerBreakdown(&stubOrderSvc{})(w, r)
	if w.Code != http.StatusUnauthorized {
		t.Errorf("want 401, got %d", w.Code)
	}
}

func TestHandleSellerBreakdown_OrderNotFound(t *testing.T) {
	svc := &stubOrderSvc{
		getOrderFn: func(_ context.Context, _ int64) (order.Order, []order.OrderItem, error) {
			return order.Order{}, nil, order.ErrOrderNotFound
		},
	}
	r := httptest.NewRequest("GET", "/seller/orders/9999/breakdown", nil)
	r.SetPathValue("id", "9999")
	r.Header.Set("X-Mopro-Seller-Id", "42")
	w := httptest.NewRecorder()
	handleSellerBreakdown(svc)(w, r)
	if w.Code != http.StatusNotFound {
		t.Errorf("want 404, got %d", w.Code)
	}
}
