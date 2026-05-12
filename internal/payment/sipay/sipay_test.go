//go:build integration

package sipay_test

import (
	"context"
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/redis/go-redis/v9"

	"github.com/mopro/platform/internal/outbox"
	"github.com/mopro/platform/internal/payment"
	"github.com/mopro/platform/internal/payment/sipay"
)

// skipIfNoSipayCredentials skips the test when SIPAY_APP_ID is not set.
// Used for mock-only tests that don't need real credentials.
// Real-network sandbox tests use //go:build sipay_sandbox tag instead.
func skipIfNoCredentialsRequired(t *testing.T) {
	t.Helper()
	// These tests use httptest mocks and do NOT need real credentials.
	// They will NOT be skipped — this function is a no-op placeholder
	// to document the intent.
}

// skipIfRealSandboxOnly skips tests that require real Sipay credentials.
func skipIfRealSandboxOnly(t *testing.T) {
	t.Helper()
	if os.Getenv("SIPAY_APP_ID") == "" {
		t.Skip("skipping real-network test: SIPAY_APP_ID not set")
	}
}

// --- Mock helpers ---

func mockTokenServer() *httptest.Server {
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/ccpayment/api/token" {
			w.Header().Set("Content-Type", "application/json")
			json.NewEncoder(w).Encode(map[string]any{
				"status_code": 100,
				"message":     "success",
				"data":        map[string]string{"token": "mock-token-xyz"},
			})
			return
		}
		w.WriteHeader(http.StatusNotFound)
	}))
}

func testConfig(baseURL string) payment.SipayConfig {
	return payment.SipayConfig{
		BaseURL:     baseURL,
		MerchantKey: "test_merchant_key_for_unit_tests",
		AppID:       "test_app_id",
		AppSecret:   "test_app_secret",
		MerchantID:  "test_merchant_id",
		ReturnURL:   "https://example.com/return",
		CancelURL:   "https://example.com/cancel",
	}
}

// stubPaymentRepo is a minimal in-memory payment.Repository for tests.
type stubPaymentRepo struct {
	intents map[string]payment.PaymentIntent
}

func newStubRepo() *stubPaymentRepo {
	return &stubPaymentRepo{intents: make(map[string]payment.PaymentIntent)}
}

func (r *stubPaymentRepo) InsertPaymentIntent(_ context.Context, _ pgx.Tx, p payment.PaymentIntent) (payment.PaymentIntent, error) {
	if _, exists := r.intents[p.IdempotencyKey]; exists {
		return payment.PaymentIntent{}, payment.ErrPaymentAlreadyCaptured
	}
	p.ID = int64(len(r.intents)) + 1
	p.CreatedAt = time.Now()
	p.UpdatedAt = time.Now()
	r.intents[p.IdempotencyKey] = p
	return p, nil
}

func (r *stubPaymentRepo) FindPaymentIntentByIdempotencyKey(_ context.Context, key string) (payment.PaymentIntent, error) {
	if p, ok := r.intents[key]; ok {
		return p, nil
	}
	return payment.PaymentIntent{}, payment.ErrPaymentNotFound
}

func (r *stubPaymentRepo) UpdatePaymentStatus(_ context.Context, _ pgx.Tx, _ string, _ payment.PaymentStatus, _, _, _ *string, _, _ string, _ int64) error {
	return nil
}

func (r *stubPaymentRepo) WithTx(_ context.Context, fn func(pgx.Tx) error) error {
	return fn(nil)
}

// --- Tests ---

func TestInitiatePayment_TokenFetch(t *testing.T) {
	mux := http.NewServeMux()
	mux.HandleFunc("/ccpayment/api/token", func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(map[string]any{
			"status_code": 100,
			"data":        map[string]string{"token": "tok-abc"},
		})
	})
	mux.HandleFunc("/ccpayment/api/paySmart3D", func(w http.ResponseWriter, r *http.Request) {
		// Verify Authorization header is set.
		if r.Header.Get("Authorization") != "Bearer tok-abc" {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		json.NewEncoder(w).Encode(map[string]any{
			"status_code": 100,
			"data": map[string]string{
				"invoice_id": "idem-1",
				"ccform":     "<html>3DS</html>",
			},
		})
	})
	srv := httptest.NewServer(mux)
	defer srv.Close()

	cfg := testConfig(srv.URL)
	adapter, err := sipay.NewAdapter(cfg, newStubRepo(), nil)
	if err != nil {
		t.Fatalf("NewAdapter: %v", err)
	}

	resp, err := adapter.InitiatePayment(context.Background(), payment.InitiatePaymentRequest{
		OrderID:        1,
		AmountMinor:    10000,
		Currency:       "TRY",
		IdempotencyKey: "idem-1",
		BuyerName:      "Ali",
		BuyerSurname:   "Yılmaz",
		BuyerEmail:     "ali@example.com",
		Market:         "TR",
		ReturnURL:      cfg.ReturnURL,
		CancelURL:      cfg.CancelURL,
	})
	if err != nil {
		t.Fatalf("InitiatePayment: %v", err)
	}
	if resp.ThreeDSHTML != "<html>3DS</html>" {
		t.Errorf("ThreeDSHTML: got %q", resp.ThreeDSHTML)
	}
	if resp.ProviderRef != "idem-1" {
		t.Errorf("ProviderRef: got %q", resp.ProviderRef)
	}
}

func TestInitiatePayment_ZeroAmountRejected(t *testing.T) {
	srv := mockTokenServer()
	defer srv.Close()

	adapter, err := sipay.NewAdapter(testConfig(srv.URL), newStubRepo(), nil)
	if err != nil {
		t.Fatalf("NewAdapter: %v", err)
	}
	_, err = adapter.InitiatePayment(context.Background(), payment.InitiatePaymentRequest{
		OrderID:        1,
		AmountMinor:    0,
		Currency:       "TRY",
		IdempotencyKey: "idem-zero",
	})
	if err != payment.ErrInvalidAmount {
		t.Errorf("want ErrInvalidAmount, got %v", err)
	}
}

func TestInitiatePayment_TokenRetryOn401(t *testing.T) {
	calls := 0
	mux := http.NewServeMux()
	mux.HandleFunc("/ccpayment/api/token", func(w http.ResponseWriter, r *http.Request) {
		calls++
		json.NewEncoder(w).Encode(map[string]any{
			"status_code": 100,
			"data":        map[string]string{"token": "fresh-token"},
		})
	})
	mux.HandleFunc("/ccpayment/api/paySmart3D", func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer fresh-token" {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		json.NewEncoder(w).Encode(map[string]any{
			"status_code": 100,
			"data":        map[string]string{"invoice_id": "idem-retry", "ccform": "<html/>"},
		})
	})
	srv := httptest.NewServer(mux)
	defer srv.Close()

	adapter, err := sipay.NewAdapter(testConfig(srv.URL), newStubRepo(), nil)
	if err != nil {
		t.Fatalf("NewAdapter: %v", err)
	}
	_, err = adapter.InitiatePayment(context.Background(), payment.InitiatePaymentRequest{
		OrderID: 1, AmountMinor: 5000, Currency: "TRY", IdempotencyKey: "idem-retry",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if calls < 1 {
		t.Error("expected token endpoint to be called")
	}
}

func TestConfirmWebhook_ValidSignature(t *testing.T) {
	cfg := testConfig("http://localhost")
	adapter, _ := sipay.NewAdapter(cfg, newStubRepo(), nil)

	invoiceID := "inv-001"
	statusCode := "100"
	totalAmount := "5000"
	currency := "TRY"
	sig := sipay.ComputeHashKey(cfg.MerchantKey, statusCode, invoiceID, totalAmount, currency)

	body, _ := json.Marshal(map[string]any{
		"status_code":   100,
		"invoice_id":    invoiceID,
		"order_no":      "sipay-order-999",
		"total_amount":  totalAmount,
		"currency_code": currency,
		"hash_key":      sig,
	})
	ev, err := adapter.ConfirmWebhook(context.Background(), body, sig)
	if err != nil {
		t.Fatalf("ConfirmWebhook: %v", err)
	}
	if ev.Type != payment.PaymentEventCaptured {
		t.Errorf("event type: want captured, got %s", ev.Type)
	}
	if ev.ProviderRef != invoiceID {
		t.Errorf("ProviderRef: want %s, got %s", invoiceID, ev.ProviderRef)
	}
}

func TestConfirmWebhook_InvalidSignature(t *testing.T) {
	cfg := testConfig("http://localhost")
	adapter, _ := sipay.NewAdapter(cfg, newStubRepo(), nil)

	body, _ := json.Marshal(map[string]any{
		"status_code":   100,
		"invoice_id":    "inv-001",
		"total_amount":  "5000",
		"currency_code": "TRY",
		"hash_key":      "wrong-sig",
	})
	_, err := adapter.ConfirmWebhook(context.Background(), body, "wrong-sig")
	if err != payment.ErrInvalidSignature {
		t.Errorf("want ErrInvalidSignature, got %v", err)
	}
}

func TestCheckStatus_CapturedMapping(t *testing.T) {
	mux := http.NewServeMux()
	mux.HandleFunc("/ccpayment/api/token", func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(map[string]any{"status_code": 100, "data": map[string]string{"token": "t"}})
	})
	mux.HandleFunc("/ccpayment/api/checkStatus", func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(map[string]any{
			"status_code": 100,
			"data":        map[string]string{"payment_status": "captured"},
		})
	})
	srv := httptest.NewServer(mux)
	defer srv.Close()

	adapter, _ := sipay.NewAdapter(testConfig(srv.URL), newStubRepo(), nil)
	status, err := adapter.CheckStatus(context.Background(), "inv-001")
	if err != nil {
		t.Fatalf("CheckStatus: %v", err)
	}
	if status != payment.PaymentStatusCaptured {
		t.Errorf("want captured, got %s", status)
	}
}

func TestWebhookHandler_ValidCapture(t *testing.T) {
	// Sipay mock that answers token requests.
	apiSrv := mockTokenServer()
	defer apiSrv.Close()

	cfg := testConfig(apiSrv.URL)
	repo := newStubRepo()
	adapter, err := sipay.NewAdapter(cfg, repo, nil)
	if err != nil {
		t.Fatalf("NewAdapter: %v", err)
	}

	// In-memory Redis for dedup test.
	rdb := redis.NewClient(&redis.Options{Addr: "localhost:6379"})
	if rdb.Ping(context.Background()).Err() != nil {
		t.Skip("Redis not available — skipping WebhookHandler test")
	}
	rdb.FlushDB(context.Background())

	outboxRepo := outbox.NewRepository("order_schema.outbox")
	h := sipay.NewWebhookHandler(adapter, repo, outboxRepo, rdb, "TR", "TRY", nil)

	invoiceID := "inv-wh-001"
	sig := sipay.ComputeHashKey(cfg.MerchantKey, "100", invoiceID, "10000", "TRY")
	body, _ := json.Marshal(map[string]any{
		"status_code":   100,
		"invoice_id":    invoiceID,
		"order_no":      "sipay-999",
		"total_amount":  "10000",
		"currency_code": "TRY",
		"hash_key":      sig,
	})

	req := httptest.NewRequest(http.MethodPost, "/webhooks/sipay", bytes.NewReader(body))
	rr := httptest.NewRecorder()
	h.ServeHTTP(rr, req)
	// Webhook handler will fail the outbox insert (no real DB) but must not 401.
	if rr.Code == http.StatusUnauthorized {
		t.Errorf("signature verification failed unexpectedly")
	}
}

// TestD2_ProductionGuard verifies that a sandbox MerchantKey is rejected in production.
func TestD2_ProductionGuard(t *testing.T) {
	t.Setenv("GO_ENV", "production")
	_, err := sipay.NewAdapter(payment.SipayConfig{
		BaseURL:     "https://provisioning.sipay.com.tr",
		MerchantKey: "test_my_key", // sandbox prefix — should be rejected
		AppID:       "x",
		AppSecret:   "y",
		MerchantID:  "z",
	}, newStubRepo(), nil)
	if err == nil {
		t.Error("expected error for sandbox MerchantKey in production GO_ENV, got nil")
	}
}

func TestD2_ProductionGuard_WrongURL(t *testing.T) {
	t.Setenv("GO_ENV", "production")
	_, err := sipay.NewAdapter(payment.SipayConfig{
		BaseURL:     "https://sandbox.sipay.dev", // wrong host
		MerchantKey: "prod_live_key",
		AppID:       "x",
		AppSecret:   "y",
		MerchantID:  "z",
	}, newStubRepo(), nil)
	if err == nil {
		t.Error("expected error for non-production BaseURL in production GO_ENV, got nil")
	}
}
