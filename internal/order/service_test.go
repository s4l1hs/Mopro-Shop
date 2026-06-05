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
)

// ── catalog mock ─────────────────────────────────────────────────────────────

type mockCatalogSvc struct {
	getVariantByIDFn           func(ctx context.Context, id int64) (catalog.Variant, error)
	getCommissionForCategoryFn func(ctx context.Context, market string, catID int64) (catalog.CategoryCommission, error)
}

func (m *mockCatalogSvc) GetVariantByID(ctx context.Context, id int64) (catalog.Variant, error) {
	if m.getVariantByIDFn != nil {
		return m.getVariantByIDFn(ctx, id)
	}
	return catalog.Variant{
		ID: id, ProductID: 1, CategoryID: 30, SellerID: 99,
		PriceMinor: 10000, PriceCurrency: "TRY", Stock: 100,
	}, nil
}
func (m *mockCatalogSvc) GetCommissionForCategory(ctx context.Context, market string, catID int64) (catalog.CategoryCommission, error) {
	if m.getCommissionForCategoryFn != nil {
		return m.getCommissionForCategoryFn(ctx, market, catID)
	}
	return catalog.CategoryCommission{CategoryID: catID, Market: market, CommissionPctBps: 700, KdvPctBps: 2000}, nil
}
func (m *mockCatalogSvc) CreateProduct(_ context.Context, _ catalog.CreateProductRequest) (catalog.Product, error) {
	return catalog.Product{}, nil
}
func (m *mockCatalogSvc) AddVariant(_ context.Context, _ int64, _ catalog.AddVariantRequest) (catalog.Variant, error) {
	return catalog.Variant{}, nil
}

func (m *mockCatalogSvc) UpdateVariantPrice(_ context.Context, _ int64, _ catalog.UpdateVariantPriceRequest) error {
	return nil
}
func (m *mockCatalogSvc) UpdateTranslation(_ context.Context, _ int64, _, _, _ string) error {
	return nil
}
func (m *mockCatalogSvc) GetByID(_ context.Context, id int64) (catalog.Product, []catalog.Variant, []catalog.ProductTranslation, error) {
	return catalog.Product{ID: id}, nil, nil, nil
}
func (m *mockCatalogSvc) Search(_ context.Context, _, _, _ string) ([]catalog.Product, error) {
	return nil, nil
}
func (m *mockCatalogSvc) ListCategories(_ context.Context, _ string, _ int) ([]catalog.CategoryRow, error) {
	return nil, nil
}
func (m *mockCatalogSvc) ListProductsByCategory(_ context.Context, _ int64, _, _ string, _ catalog.ProductFilter, _, _ int) ([]catalog.ProductSummaryRow, int, error) {
	return nil, 0, nil
}
func (m *mockCatalogSvc) ListAllVariantStocks(_ context.Context) ([]catalog.VariantStock, error) {
	return nil, nil
}
func (m *mockCatalogSvc) SearchSummary(_ context.Context, _, _, _ string, _ catalog.ProductFilter, _, _ int) ([]catalog.ProductSummaryRow, int, error) {
	return nil, 0, nil
}

// ── cart mock ─────────────────────────────────────────────────────────────────

type mockCartSvc struct {
	getCartFn           func(ctx context.Context, userID int64) (cart.Cart, error)
	commitReservationFn func(ctx context.Context, reservationID string) error
}

func (m *mockCartSvc) GetCart(ctx context.Context, userID int64) (cart.Cart, error) {
	if m.getCartFn != nil {
		return m.getCartFn(ctx, userID)
	}
	return cart.Cart{UserID: userID, Items: []cart.CartItem{{VariantID: 1, Qty: 2}}}, nil
}
func (m *mockCartSvc) CommitReservation(ctx context.Context, resID string) error {
	if m.commitReservationFn != nil {
		return m.commitReservationFn(ctx, resID)
	}
	return nil
}
func (m *mockCartSvc) AddItem(_ context.Context, _, _ int64, _ int) error { return nil }
func (m *mockCartSvc) RemoveItem(_ context.Context, _, _ int64) error     { return nil }
func (m *mockCartSvc) Reserve(_ context.Context, _ int64) (string, time.Time, error) {
	return "res-id", time.Now().Add(15 * time.Minute), nil
}
func (m *mockCartSvc) Release(_ context.Context, _ string) error                 { return nil }
func (m *mockCartSvc) SeedStock(_ context.Context, _ int64, _ int) error         { return nil }
func (m *mockCartSvc) SeedStockIfAbsent(_ context.Context, _ int64, _ int) error { return nil }

// ── repo mock ─────────────────────────────────────────────────────────────────

type mockRepo struct {
	insertOrderFn          func(ctx context.Context, tx pgx.Tx, o order.Order) (order.Order, error)
	insertOrderItemFn      func(ctx context.Context, tx pgx.Tx, item order.OrderItem) (order.OrderItem, error)
	getOrderFn             func(ctx context.Context, orderID int64) (order.Order, []order.OrderItem, error)
	getOrderItemsFn        func(ctx context.Context, orderID int64) ([]order.OrderItem, error)
	findByIdempotencyKeyFn func(ctx context.Context, key string) (order.Order, error)
	listOrdersFn           func(ctx context.Context, userID int64) ([]order.Order, error)
	updateStatusFn         func(ctx context.Context, tx pgx.Tx, orderID int64, status order.OrderStatus, updatedAt time.Time) error
	setDeliveredFn         func(ctx context.Context, tx pgx.Tx, orderID int64, deliveredAt time.Time) error
	withTxFn               func(ctx context.Context, fn func(pgx.Tx) error) error
}

func (m *mockRepo) InsertOrder(ctx context.Context, tx pgx.Tx, o order.Order) (order.Order, error) {
	if m.insertOrderFn != nil {
		return m.insertOrderFn(ctx, tx, o)
	}
	o.ID = 42
	o.CreatedAt = time.Now()
	o.UpdatedAt = o.CreatedAt
	return o, nil
}
func (m *mockRepo) InsertOrderItem(ctx context.Context, tx pgx.Tx, item order.OrderItem) (order.OrderItem, error) {
	if m.insertOrderItemFn != nil {
		return m.insertOrderItemFn(ctx, tx, item)
	}
	item.ID = 1
	return item, nil
}
func (m *mockRepo) GetOrder(ctx context.Context, orderID int64) (order.Order, []order.OrderItem, error) {
	if m.getOrderFn != nil {
		return m.getOrderFn(ctx, orderID)
	}
	return order.Order{ID: orderID, Status: order.StatusPendingPayment}, nil, nil
}
func (m *mockRepo) GetOrderItems(ctx context.Context, orderID int64) ([]order.OrderItem, error) {
	if m.getOrderItemsFn != nil {
		return m.getOrderItemsFn(ctx, orderID)
	}
	return nil, nil
}
func (m *mockRepo) FindByIdempotencyKey(ctx context.Context, key string) (order.Order, error) {
	if m.findByIdempotencyKeyFn != nil {
		return m.findByIdempotencyKeyFn(ctx, key)
	}
	return order.Order{}, order.ErrOrderNotFound
}
func (m *mockRepo) ListOrders(ctx context.Context, userID int64) ([]order.Order, error) {
	if m.listOrdersFn != nil {
		return m.listOrdersFn(ctx, userID)
	}
	return nil, nil
}
func (m *mockRepo) UpdateStatus(ctx context.Context, tx pgx.Tx, orderID int64, status order.OrderStatus, updatedAt time.Time) error {
	if m.updateStatusFn != nil {
		return m.updateStatusFn(ctx, tx, orderID, status, updatedAt)
	}
	return nil
}
func (m *mockRepo) SetDelivered(ctx context.Context, tx pgx.Tx, orderID int64, deliveredAt time.Time) error {
	if m.setDeliveredFn != nil {
		return m.setDeliveredFn(ctx, tx, orderID, deliveredAt)
	}
	return nil
}
func (m *mockRepo) WithTx(ctx context.Context, fn func(pgx.Tx) error) error {
	if m.withTxFn != nil {
		return m.withTxFn(ctx, fn)
	}
	return fn(nil) // nil tx — mocks don't use it
}

// ── outbox mock ───────────────────────────────────────────────────────────────

type mockOutbox struct {
	insertFn func(ctx context.Context, tx pgx.Tx, row outbox.Row) error
}

func (m *mockOutbox) Insert(ctx context.Context, tx pgx.Tx, row outbox.Row) error {
	if m.insertFn != nil {
		return m.insertFn(ctx, tx, row)
	}
	return nil
}
func (m *mockOutbox) FetchUnpublished(_ context.Context, _ pgx.Tx, _ int) ([]outbox.Row, error) {
	return nil, nil
}
func (m *mockOutbox) MarkPublished(_ context.Context, _ pgx.Tx, _ int64) error { return nil }

// ── helper ────────────────────────────────────────────────────────────────────

func newTestService(repo order.Repository, cartSvc cart.Service, catSvc catalog.Service, ob outbox.Repository) order.Service {
	return order.NewService(repo, cartSvc, catSvc, ob, "TR", "TRY_COIN")
}

// ── tests ─────────────────────────────────────────────────────────────────────

func TestCheckout_Success(t *testing.T) {
	svc := newTestService(&mockRepo{}, &mockCartSvc{}, &mockCatalogSvc{}, &mockOutbox{})
	o, items, err := svc.Checkout(context.Background(), order.CheckoutRequest{
		UserID: 1, IdempotencyKey: "test-checkout-1",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if o.ID == 0 {
		t.Error("order ID must be set")
	}
	if o.Status != order.StatusPendingPayment {
		t.Errorf("status: want pending_payment, got %s", o.Status)
	}
	if len(items) == 0 {
		t.Error("items must not be empty")
	}
}

func TestCheckout_EmptyCart(t *testing.T) {
	cartSvc := &mockCartSvc{
		getCartFn: func(_ context.Context, _ int64) (cart.Cart, error) {
			return cart.Cart{Items: []cart.CartItem{}}, nil
		},
	}
	_, _, err := newTestService(&mockRepo{}, cartSvc, &mockCatalogSvc{}, &mockOutbox{}).
		Checkout(context.Background(), order.CheckoutRequest{UserID: 1, IdempotencyKey: "empty"})
	if !errors.Is(err, order.ErrEmptyCart) {
		t.Fatalf("expected ErrEmptyCart, got %v", err)
	}
}

func TestCheckout_Idempotent(t *testing.T) {
	existing := order.Order{ID: 99, Status: order.StatusPaid, IdempotencyKey: "dup-key"}
	repo := &mockRepo{
		findByIdempotencyKeyFn: func(_ context.Context, key string) (order.Order, error) {
			return existing, nil // already exists
		},
	}
	o, _, err := newTestService(repo, &mockCartSvc{}, &mockCatalogSvc{}, &mockOutbox{}).
		Checkout(context.Background(), order.CheckoutRequest{UserID: 1, IdempotencyKey: "dup-key"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if o.ID != 99 {
		t.Errorf("expected existing order id=99, got %d", o.ID)
	}
}

func TestCheckout_CommissionSnapshot(t *testing.T) {
	// price=10000, qty=2, commissionPctBps=700, kdvPctBps=2000
	// gross = 20000
	// commission = 20000 * 700 / 10000 = 1400
	// kdv = 1400 * 2000 / 10000 = 280
	// sellerNet = 20000 - 1400 - 280 = 18320
	var captured order.OrderItem
	repo := &mockRepo{
		insertOrderItemFn: func(_ context.Context, _ pgx.Tx, item order.OrderItem) (order.OrderItem, error) {
			captured = item
			item.ID = 1
			return item, nil
		},
	}
	_, _, err := newTestService(repo, &mockCartSvc{}, &mockCatalogSvc{}, &mockOutbox{}).
		Checkout(context.Background(), order.CheckoutRequest{UserID: 1, IdempotencyKey: "snap-test"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if captured.CommissionAmountMinor != 1400 {
		t.Errorf("commission: want 1400, got %d", captured.CommissionAmountMinor)
	}
	if captured.KdvAmountMinor != 280 {
		t.Errorf("kdv: want 280, got %d", captured.KdvAmountMinor)
	}
	if captured.SellerNetMinor != 18320 {
		t.Errorf("seller_net: want 18320, got %d", captured.SellerNetMinor)
	}
}

func TestGetOrder_Success(t *testing.T) {
	repo := &mockRepo{
		getOrderFn: func(_ context.Context, orderID int64) (order.Order, []order.OrderItem, error) {
			return order.Order{ID: orderID, Status: order.StatusShipped}, []order.OrderItem{{ID: 1}}, nil
		},
	}
	o, items, err := newTestService(repo, &mockCartSvc{}, &mockCatalogSvc{}, &mockOutbox{}).
		GetOrder(context.Background(), 7)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if o.ID != 7 {
		t.Errorf("order ID: want 7, got %d", o.ID)
	}
	if len(items) != 1 {
		t.Errorf("items: want 1, got %d", len(items))
	}
}

func TestGetOrder_NotFound(t *testing.T) {
	repo := &mockRepo{
		getOrderFn: func(_ context.Context, _ int64) (order.Order, []order.OrderItem, error) {
			return order.Order{}, nil, order.ErrOrderNotFound
		},
	}
	_, _, err := newTestService(repo, &mockCartSvc{}, &mockCatalogSvc{}, &mockOutbox{}).
		GetOrder(context.Background(), 9999)
	if !errors.Is(err, order.ErrOrderNotFound) {
		t.Fatalf("expected ErrOrderNotFound, got %v", err)
	}
}

func TestUpdateStatus_Success(t *testing.T) {
	called := false
	repo := &mockRepo{
		updateStatusFn: func(_ context.Context, _ pgx.Tx, _ int64, status order.OrderStatus, _ time.Time) error {
			called = true
			if status != order.StatusPaid {
				return errors.New("wrong status")
			}
			return nil
		},
	}
	if err := newTestService(repo, &mockCartSvc{}, &mockCatalogSvc{}, &mockOutbox{}).
		UpdateStatus(context.Background(), 1, order.StatusPaid); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !called {
		t.Fatal("UpdateStatus not called on repo")
	}
}

func TestMarkDelivered_WritesOutbox(t *testing.T) {
	deliveredAt := time.Date(2026, 5, 12, 10, 0, 0, 0, time.UTC)
	var capturedRow outbox.Row
	ob := &mockOutbox{
		insertFn: func(_ context.Context, _ pgx.Tx, row outbox.Row) error {
			capturedRow = row
			return nil
		},
	}
	repo := &mockRepo{
		getOrderFn: func(_ context.Context, id int64) (order.Order, []order.OrderItem, error) {
			return order.Order{
				ID: id, UserID: 5, Status: order.StatusShipped,
				Market: "TR", Currency: "TRY",
			}, []order.OrderItem{{ID: 1, VariantID: 10, Qty: 1, CommissionAmountMinor: 700}}, nil
		},
	}
	if err := newTestService(repo, &mockCartSvc{}, &mockCatalogSvc{}, ob).
		MarkDelivered(context.Background(), 1, deliveredAt); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if capturedRow.EventType != "ecom.order.delivered.v1" {
		t.Errorf("event type: want ecom.order.delivered.v1, got %q", capturedRow.EventType)
	}
	if capturedRow.Market != "TR" {
		t.Errorf("market: want TR, got %q", capturedRow.Market)
	}
}

func TestMarkDelivered_Idempotent(t *testing.T) {
	outboxCallCount := 0
	ob := &mockOutbox{
		insertFn: func(_ context.Context, _ pgx.Tx, _ outbox.Row) error {
			outboxCallCount++
			return nil
		},
	}
	repo := &mockRepo{
		getOrderFn: func(_ context.Context, id int64) (order.Order, []order.OrderItem, error) {
			// Already delivered
			return order.Order{ID: id, Status: order.StatusDelivered}, nil, nil
		},
	}
	if err := newTestService(repo, &mockCartSvc{}, &mockCatalogSvc{}, ob).
		MarkDelivered(context.Background(), 1, time.Now()); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if outboxCallCount != 0 {
		t.Errorf("outbox must not be called for already-delivered order, called %d times", outboxCallCount)
	}
}

func TestListOrders(t *testing.T) {
	repo := &mockRepo{
		listOrdersFn: func(_ context.Context, userID int64) ([]order.Order, error) {
			return []order.Order{{ID: 1, UserID: userID}, {ID: 2, UserID: userID}}, nil
		},
	}
	orders, err := newTestService(repo, &mockCartSvc{}, &mockCatalogSvc{}, &mockOutbox{}).
		ListOrders(context.Background(), 10)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(orders) != 2 {
		t.Errorf("expected 2 orders, got %d", len(orders))
	}
}

func TestCancelOrder_Success(t *testing.T) {
	repo := &mockRepo{
		getOrderFn: func(_ context.Context, id int64) (order.Order, []order.OrderItem, error) {
			return order.Order{ID: id, Status: order.StatusPendingPayment}, nil, nil
		},
	}
	if err := newTestService(repo, &mockCartSvc{}, &mockCatalogSvc{}, &mockOutbox{}).
		CancelOrder(context.Background(), 1, "customer request"); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestCancelOrder_FromPaid(t *testing.T) {
	repo := &mockRepo{
		getOrderFn: func(_ context.Context, id int64) (order.Order, []order.OrderItem, error) {
			return order.Order{ID: id, Status: order.StatusPaid}, nil, nil
		},
	}
	if err := newTestService(repo, &mockCartSvc{}, &mockCatalogSvc{}, &mockOutbox{}).
		CancelOrder(context.Background(), 1, "changed mind"); err != nil {
		t.Fatalf("cancel from paid must succeed, got %v", err)
	}
}

func TestCancelOrder_InvalidTransition(t *testing.T) {
	// Post-shipment states cannot be cancelled.
	for _, status := range []order.OrderStatus{
		order.StatusShipped, order.StatusDelivered, order.StatusRefunded,
	} {
		st := status
		repo := &mockRepo{
			getOrderFn: func(_ context.Context, id int64) (order.Order, []order.OrderItem, error) {
				return order.Order{ID: id, Status: st}, nil, nil
			},
		}
		err := newTestService(repo, &mockCartSvc{}, &mockCatalogSvc{}, &mockOutbox{}).
			CancelOrder(context.Background(), 1, "test")
		if !errors.Is(err, order.ErrInvalidTransition) {
			t.Errorf("status %q: expected ErrInvalidTransition, got %v", st, err)
		}
	}
}

// Re-cancelling an already-cancelled order is idempotent (§3.2): no error.
func TestCancelOrder_IdempotentWhenAlreadyCancelled(t *testing.T) {
	repo := &mockRepo{
		getOrderFn: func(_ context.Context, id int64) (order.Order, []order.OrderItem, error) {
			return order.Order{ID: id, Status: order.StatusCancelled}, nil, nil
		},
	}
	if err := newTestService(repo, &mockCartSvc{}, &mockCatalogSvc{}, &mockOutbox{}).
		CancelOrder(context.Background(), 1, "test"); err != nil {
		t.Fatalf("re-cancel must be a no-op success, got %v", err)
	}
}

func TestCancelOrder_NotFound(t *testing.T) {
	repo := &mockRepo{
		getOrderFn: func(_ context.Context, _ int64) (order.Order, []order.OrderItem, error) {
			return order.Order{}, nil, order.ErrOrderNotFound
		},
	}
	err := newTestService(repo, &mockCartSvc{}, &mockCatalogSvc{}, &mockOutbox{}).
		CancelOrder(context.Background(), 999, "test")
	if !errors.Is(err, order.ErrOrderNotFound) {
		t.Fatalf("expected ErrOrderNotFound, got %v", err)
	}
}

func TestCheckout_CommitReservationCalledBestEffort(t *testing.T) {
	commitCalled := false
	commitErr := errors.New("redis timeout")
	cartSvc := &mockCartSvc{
		commitReservationFn: func(_ context.Context, _ string) error {
			commitCalled = true
			return commitErr
		},
	}
	// Even when CommitReservation fails, Checkout succeeds (best-effort).
	_, _, err := newTestService(&mockRepo{}, cartSvc, &mockCatalogSvc{}, &mockOutbox{}).
		Checkout(context.Background(), order.CheckoutRequest{
			UserID: 1, ReservationID: "res-abc", IdempotencyKey: "commit-test",
		})
	if err != nil {
		t.Fatalf("checkout must succeed even if CommitReservation fails: %v", err)
	}
	if !commitCalled {
		t.Error("CommitReservation must be called when ReservationID is set")
	}
}

// ── Stubs for new catalog.Service methods (Trendyol home work) ──────────────

func (m *mockCatalogSvc) ListProductsByIDs(_ context.Context, _ []int64, _, _ string) ([]catalog.ProductSummaryRow, error) {
	return nil, nil
}
func (m *mockCatalogSvc) HomeRails(_ context.Context, _ string) ([]catalog.HomeRailRow, error) {
	return nil, nil
}
func (m *mockCatalogSvc) HomeBanners(_ context.Context) ([]catalog.HomeBannerRow, error) {
	return nil, nil
}
func (m *mockCatalogSvc) HomeMoodStories(_ context.Context) ([]catalog.HomeMoodStoryRow, error) {
	return nil, nil
}

func (m *mockCatalogSvc) HomeFlashDeals(_ context.Context, _ string, _ *int64) (*catalog.FlashDealsResult, error) {
	return nil, nil
}
func (m *mockCatalogSvc) ListReviews(_ context.Context, _ int64, _ catalog.ReviewSort, _, _ int, _ int64) ([]catalog.ProductReviewRow, int, error) {
	return nil, 0, nil
}
func (m *mockCatalogSvc) ReviewsSummary(_ context.Context, _ int64) (catalog.ReviewsSummary, error) {
	return catalog.ReviewsSummary{}, nil
}
func (m *mockCatalogSvc) ReviewProductID(_ context.Context, _ int64) (int64, error) {
	return 0, nil
}
func (m *mockCatalogSvc) ToggleHelpfulVote(_ context.Context, _, _ int64) (catalog.HelpfulVoteResult, error) {
	return catalog.HelpfulVoteResult{}, nil
}
