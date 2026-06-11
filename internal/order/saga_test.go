package order_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/mopro/platform/internal/cart"
	"github.com/mopro/platform/internal/catalog"
	"github.com/mopro/platform/internal/order"
	"github.com/mopro/platform/internal/outbox"
	"github.com/mopro/platform/internal/payment"
)

// ── mock PSP ──────────────────────────────────────────────────────────────────

type mockPSP struct {
	initiatePaymentFn func(ctx context.Context, req payment.InitiatePaymentRequest) (payment.InitiatePaymentResponse, error)
}

func (m *mockPSP) InitiatePayment(ctx context.Context, req payment.InitiatePaymentRequest) (payment.InitiatePaymentResponse, error) {
	if m.initiatePaymentFn != nil {
		return m.initiatePaymentFn(ctx, req)
	}
	return payment.InitiatePaymentResponse{
		ProviderRef: req.IdempotencyKey,
		ThreeDSHTML: "<form>3DS</form>",
		ExpiresAt:   time.Now().Add(30 * time.Minute),
	}, nil
}

func (m *mockPSP) ConfirmWebhook(_ context.Context, _ []byte, _ string) (payment.PaymentEvent, error) {
	return payment.PaymentEvent{}, nil
}
func (m *mockPSP) Refund(_ context.Context, _ payment.RefundRequest) (payment.RefundResponse, error) {
	return payment.RefundResponse{}, nil
}
func (m *mockPSP) CheckStatus(_ context.Context, _ string) (payment.PaymentStatus, error) {
	return payment.PaymentStatusUnknown, nil
}
func (m *mockPSP) RegisterSubMerchant(_ context.Context, _ payment.RegisterSubMerchantRequest) (payment.SubMerchantRef, error) {
	return payment.SubMerchantRef{}, nil
}
func (m *mockPSP) TransferToSeller(_ context.Context, _ payment.TransferToSellerRequest) (payment.TransferRef, error) {
	return payment.TransferRef{}, nil
}

// ── mock checkout session repo ─────────────────────────────────────────────────

type mockSessionRepo struct {
	insertFn func(ctx context.Context, tx pgx.Tx, s order.CheckoutSession) (order.CheckoutSession, error)
	findFn   func(ctx context.Context, id string) (order.CheckoutSession, error)
	updateFn func(ctx context.Context, id string, status order.CheckoutSessionStatus, providerRef string) error
}

func (m *mockSessionRepo) InsertCheckoutSession(ctx context.Context, tx pgx.Tx, s order.CheckoutSession) (order.CheckoutSession, error) {
	if m.insertFn != nil {
		return m.insertFn(ctx, tx, s)
	}
	s.CreatedAt = time.Now()
	s.UpdatedAt = s.CreatedAt
	return s, nil
}
func (m *mockSessionRepo) FindCheckoutSessionByID(ctx context.Context, id string) (order.CheckoutSession, error) {
	if m.findFn != nil {
		return m.findFn(ctx, id)
	}
	return order.CheckoutSession{}, order.ErrCheckoutSessionNotFound
}
func (m *mockSessionRepo) UpdateCheckoutSession(ctx context.Context, id string, status order.CheckoutSessionStatus, providerRef string) error {
	if m.updateFn != nil {
		return m.updateFn(ctx, id, status, providerRef)
	}
	return nil
}

// ── helper ────────────────────────────────────────────────────────────────────

func newSagaService(
	repo order.Repository,
	sessionRepo order.CheckoutSessionRepository,
	cartSvc cart.Service,
	catSvc catalog.Service,
	ob outbox.Repository,
	psp payment.Service,
) order.Service {
	return order.NewServiceFull(repo, sessionRepo, cartSvc, catSvc, ob, "TR", "TRY_COIN", psp, nil, nil)
}

// ── tests ─────────────────────────────────────────────────────────────────────

func TestInitiateCheckout_HappyPath(t *testing.T) {
	svc := newSagaService(
		&mockRepo{},
		&mockSessionRepo{},
		&mockCartSvc{},
		&mockCatalogSvc{},
		&mockOutbox{},
		&mockPSP{},
	)

	resp, err := svc.InitiateCheckout(context.Background(), order.InitiateCheckoutRequest{
		UserID:        1,
		ReservationID: "res-001",
		SessionID:     "session-001",
		BuyerName:     "Ali",
		BuyerSurname:  "Veli",
		BuyerEmail:    "ali@example.com",
	})
	if err != nil {
		t.Fatalf("InitiateCheckout: unexpected error: %v", err)
	}
	if resp.SessionID != "session-001" {
		t.Errorf("SessionID: want session-001, got %q", resp.SessionID)
	}
	if resp.ThreeDSHTML == "" {
		t.Error("ThreeDSHTML must not be empty")
	}
	if len(resp.Orders) == 0 {
		t.Error("Orders must not be empty")
	}
}

// TestInitiateCheckout_ChargesDiscountedTotal is the CT-09 asymmetry guard for the
// PSP path: the saga must charge the basket-discounted total, not the list total.
// Default cart = variant 1 × qty 2; price 10000, pct 15 → 8500×2 = 17000.
func TestInitiateCheckout_ChargesDiscountedTotal(t *testing.T) {
	pct := 15
	cat := &mockCatalogSvc{
		getVariantByIDFn: func(_ context.Context, id int64) (catalog.Variant, error) {
			return catalog.Variant{
				ID: id, ProductID: 1, CategoryID: 30, SellerID: 99,
				PriceMinor: 10000, PriceCurrency: "TRY", Stock: 100,
				BasketDiscountPct: &pct,
			}, nil
		},
	}
	var charged int64
	psp := &mockPSP{
		initiatePaymentFn: func(_ context.Context, req payment.InitiatePaymentRequest) (payment.InitiatePaymentResponse, error) {
			charged = req.AmountMinor
			return payment.InitiatePaymentResponse{ProviderRef: req.IdempotencyKey, ThreeDSHTML: "<form/>"}, nil
		},
	}
	var capturedOrder order.Order
	repo := &mockRepo{
		insertOrderFn: func(_ context.Context, _ pgx.Tx, o order.Order) (order.Order, error) {
			capturedOrder = o
			o.ID = 1
			return o, nil
		},
	}
	resp, err := newSagaService(repo, &mockSessionRepo{}, &mockCartSvc{}, cat, &mockOutbox{}, psp).
		InitiateCheckout(context.Background(), order.InitiateCheckoutRequest{
			UserID: 1, SessionID: "sess-disc", BuyerEmail: "a@b.c",
		})
	if err != nil {
		t.Fatalf("InitiateCheckout: %v", err)
	}
	if charged != 17000 {
		t.Errorf("PSP charged: want 17000 (discounted), got %d", charged)
	}
	if capturedOrder.TotalMinor != 17000 || capturedOrder.SubtotalMinor != 20000 || capturedOrder.DiscountMinor != 3000 {
		t.Errorf("order totals: want subtotal=20000 discount=3000 total=17000, got %d/%d/%d",
			capturedOrder.SubtotalMinor, capturedOrder.DiscountMinor, capturedOrder.TotalMinor)
	}
	if len(resp.Orders) == 0 {
		t.Error("Orders must not be empty")
	}
}

func TestInitiateCheckout_EmptyCart(t *testing.T) {
	cartSvc := &mockCartSvc{
		getCartFn: func(_ context.Context, _ int64) (cart.Cart, error) {
			return cart.Cart{Items: []cart.CartItem{}}, nil
		},
	}
	svc := newSagaService(&mockRepo{}, &mockSessionRepo{}, cartSvc, &mockCatalogSvc{}, &mockOutbox{}, &mockPSP{})

	_, err := svc.InitiateCheckout(context.Background(), order.InitiateCheckoutRequest{
		UserID: 1, SessionID: "s-empty",
	})
	if !errors.Is(err, order.ErrEmptyCart) {
		t.Fatalf("want ErrEmptyCart, got %v", err)
	}
}

func TestInitiateCheckout_NoPSP(t *testing.T) {
	// NewService (not NewServiceFull) → psp == nil.
	svc := order.NewService(&mockRepo{}, &mockCartSvc{}, &mockCatalogSvc{}, &mockOutbox{}, "TR", "TRY_COIN")

	_, err := svc.InitiateCheckout(context.Background(), order.InitiateCheckoutRequest{
		UserID: 1, SessionID: "s-nopsp",
	})
	if !errors.Is(err, order.ErrPSPNotConfigured) {
		t.Fatalf("want ErrPSPNotConfigured, got %v", err)
	}
}

func TestInitiateCheckout_Idempotent(t *testing.T) {
	existingSession := order.CheckoutSession{
		ID:       "session-idem",
		UserID:   1,
		OrderIDs: []int64{42},
		Status:   order.CheckoutSessionPSPInitiated,
	}
	sessionRepo := &mockSessionRepo{
		findFn: func(_ context.Context, id string) (order.CheckoutSession, error) {
			return existingSession, nil // already exists
		},
	}
	repo := &mockRepo{
		getOrderFn: func(_ context.Context, id int64) (order.Order, []order.OrderItem, error) {
			return order.Order{ID: id, Status: order.StatusPendingPayment}, nil, nil
		},
	}

	svc := newSagaService(repo, sessionRepo, &mockCartSvc{}, &mockCatalogSvc{}, &mockOutbox{}, &mockPSP{})

	resp, err := svc.InitiateCheckout(context.Background(), order.InitiateCheckoutRequest{
		UserID: 1, SessionID: "session-idem",
	})
	if err != nil {
		t.Fatalf("idempotent InitiateCheckout: unexpected error: %v", err)
	}
	if resp.SessionID != "session-idem" {
		t.Errorf("SessionID: want session-idem, got %q", resp.SessionID)
	}
}

func TestInitiateCheckout_PSPFails_CancelsOrders(t *testing.T) {
	pspErr := errors.New("PSP unavailable")
	psp := &mockPSP{
		initiatePaymentFn: func(_ context.Context, _ payment.InitiatePaymentRequest) (payment.InitiatePaymentResponse, error) {
			return payment.InitiatePaymentResponse{}, pspErr
		},
	}

	var cancelledOrderIDs []int64
	repo := &mockRepo{
		updateStatusFn: func(_ context.Context, _ pgx.Tx, id int64, status order.OrderStatus, _ time.Time) error {
			if status == order.StatusCancelled {
				cancelledOrderIDs = append(cancelledOrderIDs, id)
			}
			return nil
		},
	}

	sessionUpdates := map[string]order.CheckoutSessionStatus{}
	sessionRepo := &mockSessionRepo{
		updateFn: func(_ context.Context, id string, status order.CheckoutSessionStatus, _ string) error {
			sessionUpdates[id] = status
			return nil
		},
	}

	svc := newSagaService(repo, sessionRepo, &mockCartSvc{}, &mockCatalogSvc{}, &mockOutbox{}, psp)

	_, err := svc.InitiateCheckout(context.Background(), order.InitiateCheckoutRequest{
		UserID: 1, SessionID: "session-pspfail",
	})
	if err == nil {
		t.Fatal("expected error when PSP fails")
	}
	if len(cancelledOrderIDs) == 0 {
		t.Error("saga compensation: no orders were cancelled after PSP failure")
	}
	if sessionUpdates["session-pspfail"] != order.CheckoutSessionFailed {
		t.Errorf("session status: want failed, got %q", sessionUpdates["session-pspfail"])
	}
}

func TestInitiateCheckout_SessionIDRequired(t *testing.T) {
	svc := newSagaService(&mockRepo{}, &mockSessionRepo{}, &mockCartSvc{}, &mockCatalogSvc{}, &mockOutbox{}, &mockPSP{})

	_, err := svc.InitiateCheckout(context.Background(), order.InitiateCheckoutRequest{
		UserID:    1,
		SessionID: "", // missing
	})
	if !errors.Is(err, order.ErrCheckoutSessionRequired) {
		t.Fatalf("want ErrCheckoutSessionRequired, got %v", err)
	}
}

// ── MarkPaid tests ────────────────────────────────────────────────────────────

func TestMarkPaid_HappyPath(t *testing.T) {
	var updatedStatus order.OrderStatus
	repo := &mockRepo{
		getOrderFn: func(_ context.Context, id int64) (order.Order, []order.OrderItem, error) {
			return order.Order{ID: id, Status: order.StatusPendingPayment, Market: "TR", Currency: "TRY"}, nil, nil
		},
		updateStatusFn: func(_ context.Context, _ pgx.Tx, _ int64, status order.OrderStatus, _ time.Time) error {
			updatedStatus = status
			return nil
		},
	}
	svc := order.NewService(repo, &mockCartSvc{}, &mockCatalogSvc{}, &mockOutbox{}, "TR", "TRY_COIN")

	if err := svc.MarkPaid(context.Background(), 1); err != nil {
		t.Fatalf("MarkPaid: unexpected error: %v", err)
	}
	if updatedStatus != order.StatusPaid {
		t.Errorf("status: want paid, got %q", updatedStatus)
	}
}

func TestMarkPaid_Idempotent(t *testing.T) {
	callCount := 0
	repo := &mockRepo{
		getOrderFn: func(_ context.Context, id int64) (order.Order, []order.OrderItem, error) {
			return order.Order{ID: id, Status: order.StatusPaid}, nil, nil // already paid
		},
		updateStatusFn: func(_ context.Context, _ pgx.Tx, _ int64, _ order.OrderStatus, _ time.Time) error {
			callCount++
			return nil
		},
	}
	svc := order.NewService(repo, &mockCartSvc{}, &mockCatalogSvc{}, &mockOutbox{}, "TR", "TRY_COIN")

	if err := svc.MarkPaid(context.Background(), 1); err != nil {
		t.Fatalf("MarkPaid idempotent: unexpected error: %v", err)
	}
	if callCount != 0 {
		t.Error("UpdateStatus must not be called for already-paid order")
	}
}

func TestMarkPaid_InvalidTransition_FromShipped(t *testing.T) {
	repo := &mockRepo{
		getOrderFn: func(_ context.Context, id int64) (order.Order, []order.OrderItem, error) {
			return order.Order{ID: id, Status: order.StatusShipped}, nil, nil
		},
	}
	svc := order.NewService(repo, &mockCartSvc{}, &mockCatalogSvc{}, &mockOutbox{}, "TR", "TRY_COIN")

	err := svc.MarkPaid(context.Background(), 1)
	if !errors.Is(err, order.ErrInvalidTransition) {
		t.Fatalf("want ErrInvalidTransition, got %v", err)
	}
}

func TestMarkPaid_WritesOutbox(t *testing.T) {
	var capturedRow outbox.Row
	ob := &mockOutbox{
		insertFn: func(_ context.Context, _ pgx.Tx, row outbox.Row) error {
			capturedRow = row
			return nil
		},
	}
	repo := &mockRepo{
		getOrderFn: func(_ context.Context, id int64) (order.Order, []order.OrderItem, error) {
			return order.Order{ID: id, Status: order.StatusPendingPayment, Market: "TR", Currency: "TRY"}, nil, nil
		},
	}
	svc := order.NewService(repo, &mockCartSvc{}, &mockCatalogSvc{}, ob, "TR", "TRY_COIN")

	if err := svc.MarkPaid(context.Background(), 5); err != nil {
		t.Fatalf("MarkPaid: %v", err)
	}
	if capturedRow.EventType != "ecom.order.paid.v1" {
		t.Errorf("event type: want ecom.order.paid.v1, got %q", capturedRow.EventType)
	}
}
