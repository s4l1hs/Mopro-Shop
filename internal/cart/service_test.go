package cart_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/mopro/platform/internal/cart"
	"github.com/mopro/platform/internal/catalog"
)

// ── catalog mock ─────────────────────────────────────────────────────────────

type mockCatalogSvc struct {
	getVariantByIDFn func(ctx context.Context, id int64) (catalog.Variant, error)
}

func (m *mockCatalogSvc) GetVariantByID(ctx context.Context, id int64) (catalog.Variant, error) {
	if m.getVariantByIDFn != nil {
		return m.getVariantByIDFn(ctx, id)
	}
	return catalog.Variant{ID: id, Stock: 100}, nil
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
func (m *mockCatalogSvc) GetCommissionForCategory(_ context.Context, _ string, id int64) (catalog.CategoryCommission, error) {
	return catalog.CategoryCommission{CategoryID: id}, nil
}
func (m *mockCatalogSvc) ListCategories(_ context.Context, _ string, _ int) ([]catalog.CategoryRow, error) {
	return nil, nil
}
func (m *mockCatalogSvc) ListProductsByCategory(_ context.Context, _ int64, _, _ string, _ catalog.ProductFilter, _, _ int) ([]catalog.ProductSummaryRow, int, error) {
	return nil, 0, nil
}
func (m *mockCatalogSvc) ListProducts(_ context.Context, _, _ string, _ catalog.ProductFilter, _, _ int) ([]catalog.ProductSummaryRow, int, error) {
	return nil, 0, nil
}
func (m *mockCatalogSvc) ListAllVariantStocks(_ context.Context) ([]catalog.VariantStock, error) {
	return nil, nil
}
func (m *mockCatalogSvc) SearchSummary(_ context.Context, _, _, _ string, _ catalog.ProductFilter, _, _ int) ([]catalog.ProductSummaryRow, int, error) {
	return nil, 0, nil
}

// ── repo mock ─────────────────────────────────────────────────────────────────

type mockRepo struct {
	setItemFn            func(ctx context.Context, userID, variantID int64, qty int) error
	removeItemFn         func(ctx context.Context, userID, variantID int64) error
	getItemsFn           func(ctx context.Context, userID int64) ([]cart.CartItem, error)
	tryReserveFn         func(ctx context.Context, variantID int64, qty int, reservationID string, userID int64, ttlSec int64) (bool, int, error)
	setManifestFn        func(ctx context.Context, reservationID string, items []cart.CartItem, ttlSec int64) error
	releaseReservationFn func(ctx context.Context, reservationID string) error
	commitReservationFn  func(ctx context.Context, reservationID string) error
	seedStockFn          func(ctx context.Context, variantID int64, stock int) error
}

func (m *mockRepo) SetItem(ctx context.Context, userID, variantID int64, qty int) error {
	if m.setItemFn != nil {
		return m.setItemFn(ctx, userID, variantID, qty)
	}
	return nil
}
func (m *mockRepo) RemoveItem(ctx context.Context, userID, variantID int64) error {
	if m.removeItemFn != nil {
		return m.removeItemFn(ctx, userID, variantID)
	}
	return nil
}
func (m *mockRepo) GetItems(ctx context.Context, userID int64) ([]cart.CartItem, error) {
	if m.getItemsFn != nil {
		return m.getItemsFn(ctx, userID)
	}
	return nil, nil
}
func (m *mockRepo) TryReserve(ctx context.Context, variantID int64, qty int, reservationID string, userID int64, ttlSec int64) (bool, int, error) {
	if m.tryReserveFn != nil {
		return m.tryReserveFn(ctx, variantID, qty, reservationID, userID, ttlSec)
	}
	return true, 99, nil
}
func (m *mockRepo) SetManifest(ctx context.Context, reservationID string, items []cart.CartItem, ttlSec int64) error {
	if m.setManifestFn != nil {
		return m.setManifestFn(ctx, reservationID, items, ttlSec)
	}
	return nil
}
func (m *mockRepo) ReleaseReservation(ctx context.Context, reservationID string) error {
	if m.releaseReservationFn != nil {
		return m.releaseReservationFn(ctx, reservationID)
	}
	return nil
}
func (m *mockRepo) CommitReservation(ctx context.Context, reservationID string) error {
	if m.commitReservationFn != nil {
		return m.commitReservationFn(ctx, reservationID)
	}
	return nil
}
func (m *mockRepo) SeedStock(ctx context.Context, variantID int64, stock int) error {
	if m.seedStockFn != nil {
		return m.seedStockFn(ctx, variantID, stock)
	}
	return nil
}
func (m *mockRepo) SeedStockIfAbsent(_ context.Context, _ int64, _ int) error { return nil }

// ── helper ────────────────────────────────────────────────────────────────────

func newTestService(repo cart.Repository, cat catalog.Service) cart.Service {
	return cart.NewService(repo, cat)
}

// ── tests ─────────────────────────────────────────────────────────────────────

func TestAddItem_Success(t *testing.T) {
	svc := newTestService(&mockRepo{}, &mockCatalogSvc{})
	if err := svc.AddItem(context.Background(), 1, 10, 2); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestAddItem_VariantNotFound(t *testing.T) {
	cat := &mockCatalogSvc{
		getVariantByIDFn: func(_ context.Context, _ int64) (catalog.Variant, error) {
			return catalog.Variant{}, catalog.ErrNotFound
		},
	}
	err := newTestService(&mockRepo{}, cat).AddItem(context.Background(), 1, 999, 1)
	if !errors.Is(err, cart.ErrVariantNotFound) {
		t.Fatalf("expected ErrVariantNotFound, got %v", err)
	}
}

func TestAddItem_CatalogError(t *testing.T) {
	dbErr := errors.New("redis: connection refused")
	cat := &mockCatalogSvc{
		getVariantByIDFn: func(_ context.Context, _ int64) (catalog.Variant, error) {
			return catalog.Variant{}, dbErr
		},
	}
	err := newTestService(&mockRepo{}, cat).AddItem(context.Background(), 1, 10, 1)
	if err == nil {
		t.Fatal("expected error")
	}
	if errors.Is(err, cart.ErrVariantNotFound) {
		t.Fatal("should not be ErrVariantNotFound for a connection error")
	}
}

func TestRemoveItem(t *testing.T) {
	called := false
	repo := &mockRepo{
		removeItemFn: func(_ context.Context, userID, variantID int64) error {
			called = true
			if userID != 5 || variantID != 20 {
				return errors.New("wrong args")
			}
			return nil
		},
	}
	if err := newTestService(repo, &mockCatalogSvc{}).RemoveItem(context.Background(), 5, 20); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !called {
		t.Fatal("RemoveItem not called on repo")
	}
}

func TestGetCart_Empty(t *testing.T) {
	svc := newTestService(&mockRepo{}, &mockCatalogSvc{})
	c, err := svc.GetCart(context.Background(), 7)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if c.UserID != 7 {
		t.Errorf("expected userID=7, got %d", c.UserID)
	}
	if c.Items == nil {
		t.Error("Items must not be nil for empty cart")
	}
	if len(c.Items) != 0 {
		t.Errorf("expected 0 items, got %d", len(c.Items))
	}
}

func TestGetCart_WithItems(t *testing.T) {
	repo := &mockRepo{
		getItemsFn: func(_ context.Context, _ int64) ([]cart.CartItem, error) {
			return []cart.CartItem{{VariantID: 1, Qty: 3}, {VariantID: 2, Qty: 1}}, nil
		},
	}
	c, err := newTestService(repo, &mockCatalogSvc{}).GetCart(context.Background(), 3)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(c.Items) != 2 {
		t.Errorf("expected 2 items, got %d", len(c.Items))
	}
}

func TestReserve_EmptyCart(t *testing.T) {
	svc := newTestService(&mockRepo{}, &mockCatalogSvc{})
	_, _, err := svc.Reserve(context.Background(), 1)
	if !errors.Is(err, cart.ErrCartEmpty) {
		t.Fatalf("expected ErrCartEmpty, got %v", err)
	}
}

func TestReserve_Success(t *testing.T) {
	repo := &mockRepo{
		getItemsFn: func(_ context.Context, _ int64) ([]cart.CartItem, error) {
			return []cart.CartItem{{VariantID: 1, Qty: 2}}, nil
		},
	}
	svc := newTestService(repo, &mockCatalogSvc{})
	reservationID, expiresAt, err := svc.Reserve(context.Background(), 1)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if reservationID == "" {
		t.Error("reservationID must not be empty")
	}
	if expiresAt.Before(time.Now()) {
		t.Error("expiresAt must be in the future")
	}
}

func TestReserve_OutOfStock_SagaReleases(t *testing.T) {
	releaseCount := 0
	manifestCount := 0

	repo := &mockRepo{
		getItemsFn: func(_ context.Context, _ int64) ([]cart.CartItem, error) {
			return []cart.CartItem{
				{VariantID: 1, Qty: 2},
				{VariantID: 2, Qty: 1},
			}, nil
		},
		tryReserveFn: func(_ context.Context, variantID int64, _ int, _ string, _ int64, _ int64) (bool, int, error) {
			if variantID == 1 {
				return true, 8, nil // first item succeeds
			}
			return false, 0, nil // second item out of stock
		},
		setManifestFn: func(_ context.Context, _ string, _ []cart.CartItem, _ int64) error {
			manifestCount++
			return nil
		},
		releaseReservationFn: func(_ context.Context, _ string) error {
			releaseCount++
			return nil
		},
	}

	svc := newTestService(repo, &mockCatalogSvc{})
	_, _, err := svc.Reserve(context.Background(), 1)

	if !errors.Is(err, cart.ErrOutOfStock) {
		t.Fatalf("expected ErrOutOfStock, got %v", err)
	}
	if releaseCount != 1 {
		t.Errorf("expected 1 saga release, got %d", releaseCount)
	}
	if manifestCount != 1 {
		t.Errorf("expected 1 manifest write for saga, got %d", manifestCount)
	}
}

func TestReserve_OutOfStock_FirstItem_NoRelease(t *testing.T) {
	// If the FIRST item is out of stock, no prior reservations exist — no saga needed.
	releaseCount := 0
	repo := &mockRepo{
		getItemsFn: func(_ context.Context, _ int64) ([]cart.CartItem, error) {
			return []cart.CartItem{{VariantID: 1, Qty: 5}}, nil
		},
		tryReserveFn: func(_ context.Context, _ int64, _ int, _ string, _ int64, _ int64) (bool, int, error) {
			return false, 0, nil // out of stock on first item
		},
		releaseReservationFn: func(_ context.Context, _ string) error {
			releaseCount++
			return nil
		},
	}
	_, _, err := newTestService(repo, &mockCatalogSvc{}).Reserve(context.Background(), 1)
	if !errors.Is(err, cart.ErrOutOfStock) {
		t.Fatalf("expected ErrOutOfStock, got %v", err)
	}
	if releaseCount != 0 {
		t.Errorf("expected 0 releases (nothing to undo), got %d", releaseCount)
	}
}

func TestRelease(t *testing.T) {
	called := false
	repo := &mockRepo{
		releaseReservationFn: func(_ context.Context, reservationID string) error {
			called = true
			if reservationID == "" {
				return errors.New("empty reservationID")
			}
			return nil
		},
	}
	if err := newTestService(repo, &mockCatalogSvc{}).Release(context.Background(), "abc123"); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !called {
		t.Fatal("ReleaseReservation not called on repo")
	}
}

func TestAddItem_RejectsZeroQty(t *testing.T) {
	err := newTestService(&mockRepo{}, &mockCatalogSvc{}).AddItem(context.Background(), 1, 10, 0)
	if !errors.Is(err, cart.ErrInvalidQty) {
		t.Fatalf("expected ErrInvalidQty for qty=0, got %v", err)
	}
}

func TestAddItem_RejectsNegativeQty(t *testing.T) {
	err := newTestService(&mockRepo{}, &mockCatalogSvc{}).AddItem(context.Background(), 1, 10, -5)
	if !errors.Is(err, cart.ErrInvalidQty) {
		t.Fatalf("expected ErrInvalidQty for qty=-5, got %v", err)
	}
}

func TestReserve_RejectsZeroQty(t *testing.T) {
	// Cart contains an item with qty=0 (bypassed AddItem guard, e.g. via direct repo write).
	// Reserve must reject it before calling TryReserve, so no Lua call happens.
	tryReserveCalled := false
	repo := &mockRepo{
		getItemsFn: func(_ context.Context, _ int64) ([]cart.CartItem, error) {
			return []cart.CartItem{{VariantID: 1, Qty: 0}}, nil
		},
		tryReserveFn: func(_ context.Context, _ int64, _ int, _ string, _ int64, _ int64) (bool, int, error) {
			tryReserveCalled = true
			return true, 0, nil
		},
	}
	_, _, err := newTestService(repo, &mockCatalogSvc{}).Reserve(context.Background(), 1)
	if !errors.Is(err, cart.ErrInvalidQty) {
		t.Fatalf("expected ErrInvalidQty for cart item qty=0, got %v", err)
	}
	if tryReserveCalled {
		t.Error("TryReserve must not be called when qty <= 0")
	}
}

func TestCommitReservation(t *testing.T) {
	called := false
	repo := &mockRepo{
		commitReservationFn: func(_ context.Context, reservationID string) error {
			called = true
			if reservationID == "" {
				return errors.New("empty reservationID")
			}
			return nil
		},
	}
	if err := newTestService(repo, &mockCatalogSvc{}).CommitReservation(context.Background(), "abc123"); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !called {
		t.Fatal("CommitReservation not called on repo")
	}
}

func TestSeedStock(t *testing.T) {
	called := false
	repo := &mockRepo{
		seedStockFn: func(_ context.Context, variantID int64, stock int) error {
			called = true
			if variantID != 7 || stock != 50 {
				return errors.New("wrong args")
			}
			return nil
		},
	}
	if err := newTestService(repo, &mockCatalogSvc{}).SeedStock(context.Background(), 7, 50); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !called {
		t.Fatal("SeedStock not called on repo")
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
