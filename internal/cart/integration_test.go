//go:build integration

package cart_test

import (
	"context"
	"errors"
	"fmt"
	"os"
	"strconv"
	"testing"

	"github.com/redis/go-redis/v9"

	"github.com/mopro/platform/internal/cart"
	"github.com/mopro/platform/internal/catalog"
)

var integRedis *redis.Client

func TestMain(m *testing.M) {
	addr := os.Getenv("CART_TEST_REDIS")
	if addr == "" {
		addr = "localhost:6380"
	}
	pw := os.Getenv("REDIS_TEST_PASSWORD")
	integRedis = redis.NewClient(&redis.Options{Addr: addr, Password: pw})
	ctx := context.Background()
	if err := integRedis.Ping(ctx).Err(); err != nil {
		fmt.Fprintf(os.Stderr, "cart integration: Redis not available at %s: %v\n", addr, err)
		os.Exit(1)
	}
	// Clean slate for every test run.
	integRedis.FlushDB(ctx)

	code := m.Run()
	integRedis.Close()
	os.Exit(code)
}

// alwaysValidCatalog is a catalog.Service stub that accepts any variantID.
type alwaysValidCatalog struct{}

func (alwaysValidCatalog) GetVariantByID(_ context.Context, id int64) (catalog.Variant, error) {
	return catalog.Variant{ID: id, Stock: 9999}, nil
}
func (alwaysValidCatalog) CreateProduct(_ context.Context, _ catalog.CreateProductRequest) (catalog.Product, error) {
	return catalog.Product{}, nil
}
func (alwaysValidCatalog) AddVariant(_ context.Context, _ int64, _ catalog.AddVariantRequest) (catalog.Variant, error) {
	return catalog.Variant{}, nil
}
func (alwaysValidCatalog) UpdateTranslation(_ context.Context, _ int64, _, _, _ string) error {
	return nil
}
func (alwaysValidCatalog) GetByID(_ context.Context, id int64) (catalog.Product, []catalog.Variant, []catalog.ProductTranslation, error) {
	return catalog.Product{ID: id}, nil, nil, nil
}
func (alwaysValidCatalog) Search(_ context.Context, _, _, _ string) ([]catalog.Product, error) {
	return nil, nil
}
func (alwaysValidCatalog) GetCommissionForCategory(_ context.Context, _ string, id int64) (catalog.CategoryCommission, error) {
	return catalog.CategoryCommission{CategoryID: id}, nil
}

// REVIVAL_MOCK: catalog.Service grew a discovery/reviews surface (Phase 4.4a+)
// after this stub was written. These no-op methods satisfy the interface; no
// behavior is asserted by the cart scenarios (cart only uses GetVariantByID).
func (alwaysValidCatalog) ListProductsByIDs(_ context.Context, _ []int64, _, _ string) ([]catalog.ProductSummaryRow, error) {
	return nil, nil
}
func (alwaysValidCatalog) HomeRails(_ context.Context, _ string) ([]catalog.HomeRailRow, error) {
	return nil, nil
}
func (alwaysValidCatalog) HomeBanners(_ context.Context) ([]catalog.HomeBannerRow, error) {
	return nil, nil
}
func (alwaysValidCatalog) HomeMoodStories(_ context.Context) ([]catalog.HomeMoodStoryRow, error) {
	return nil, nil
}
func (alwaysValidCatalog) HomeFlashDeals(_ context.Context, _ string, _ *int64) (*catalog.FlashDealsResult, error) {
	return nil, nil
}
func (alwaysValidCatalog) ListReviews(_ context.Context, _ int64, _ catalog.ReviewSort, _, _ int, _ int64) ([]catalog.ProductReviewRow, int, error) {
	return nil, 0, nil
}
func (alwaysValidCatalog) ReviewsSummary(_ context.Context, _ int64) (catalog.ReviewsSummary, error) {
	return catalog.ReviewsSummary{}, nil
}
func (alwaysValidCatalog) ReviewProductID(_ context.Context, _ int64) (int64, error) {
	return 0, nil
}
func (alwaysValidCatalog) ToggleHelpfulVote(_ context.Context, _, _ int64) (catalog.HelpfulVoteResult, error) {
	return catalog.HelpfulVoteResult{}, nil
}
func (alwaysValidCatalog) ListAllVariantStocks(_ context.Context) ([]catalog.VariantStock, error) {
	return nil, nil
}

// newIntegService builds a real repo + service backed by the test Redis.
func newIntegService(t *testing.T) cart.Service {
	t.Helper()
	repo, err := cart.NewRepository(context.Background(), integRedis)
	if err != nil {
		t.Fatalf("NewRepository: %v", err)
	}
	return cart.NewService(repo, alwaysValidCatalog{})
}

func checkStock(t *testing.T, ctx context.Context, variantID int64, want int) {
	t.Helper()
	key := "mopro:stock:" + strconv.FormatInt(variantID, 10)
	val, err := integRedis.Get(ctx, key).Result()
	if err != nil {
		t.Fatalf("GET stock %d: %v", variantID, err)
	}
	got, _ := strconv.Atoi(val)
	if got != want {
		t.Errorf("variant %d: expected stock=%d, got %d", variantID, want, got)
	}
}

func TestIntegration_CartFlow(t *testing.T) {
	ctx := context.Background()
	svc := newIntegService(t)
	userID := int64(1001)

	if err := svc.AddItem(ctx, userID, 101, 2); err != nil {
		t.Fatalf("AddItem 101: %v", err)
	}
	if err := svc.AddItem(ctx, userID, 102, 3); err != nil {
		t.Fatalf("AddItem 102: %v", err)
	}

	c, err := svc.GetCart(ctx, userID)
	if err != nil {
		t.Fatalf("GetCart: %v", err)
	}
	if len(c.Items) != 2 {
		t.Fatalf("expected 2 cart items, got %d", len(c.Items))
	}

	if err := svc.SeedStock(ctx, 101, 20); err != nil {
		t.Fatalf("SeedStock 101: %v", err)
	}
	if err := svc.SeedStock(ctx, 102, 20); err != nil {
		t.Fatalf("SeedStock 102: %v", err)
	}

	reservationID, expiresAt, err := svc.Reserve(ctx, userID)
	if err != nil {
		t.Fatalf("Reserve: %v", err)
	}
	if reservationID == "" {
		t.Fatal("empty reservationID")
	}
	if expiresAt.IsZero() {
		t.Fatal("zero expiresAt")
	}

	// Stock must be decremented: 20-2=18, 20-3=17.
	checkStock(t, ctx, 101, 18)
	checkStock(t, ctx, 102, 17)

	// Release must restore stock.
	if err := svc.Release(ctx, reservationID); err != nil {
		t.Fatalf("Release: %v", err)
	}
	checkStock(t, ctx, 101, 20)
	checkStock(t, ctx, 102, 20)
}

func TestIntegration_RemoveItem(t *testing.T) {
	ctx := context.Background()
	svc := newIntegService(t)
	userID := int64(1002)

	if err := svc.AddItem(ctx, userID, 201, 1); err != nil {
		t.Fatalf("AddItem: %v", err)
	}
	if err := svc.RemoveItem(ctx, userID, 201); err != nil {
		t.Fatalf("RemoveItem: %v", err)
	}
	c, err := svc.GetCart(ctx, userID)
	if err != nil {
		t.Fatalf("GetCart: %v", err)
	}
	if len(c.Items) != 0 {
		t.Errorf("expected empty cart after remove, got %d items", len(c.Items))
	}
}

func TestIntegration_Reserve_OutOfStock(t *testing.T) {
	ctx := context.Background()
	svc := newIntegService(t)
	userID := int64(1003)

	if err := svc.AddItem(ctx, userID, 301, 10); err != nil {
		t.Fatalf("AddItem: %v", err)
	}
	// Seed only 3 units, but cart wants 10.
	if err := svc.SeedStock(ctx, 301, 3); err != nil {
		t.Fatalf("SeedStock: %v", err)
	}

	_, _, err := svc.Reserve(ctx, userID)
	if !errors.Is(err, cart.ErrOutOfStock) {
		t.Fatalf("expected ErrOutOfStock, got %v", err)
	}

	// Stock must be unchanged — Lua atomically rejected.
	checkStock(t, ctx, 301, 3)
}

func TestIntegration_Release_NotFound(t *testing.T) {
	ctx := context.Background()
	svc := newIntegService(t)
	err := svc.Release(ctx, "nonexistent-reservation-xyz")
	if !errors.Is(err, cart.ErrReservationNotFound) {
		t.Fatalf("expected ErrReservationNotFound, got %v", err)
	}
}

func TestIntegration_CommitReservation(t *testing.T) {
	ctx := context.Background()
	svc := newIntegService(t)
	userID := int64(2001)
	variantID := int64(501)

	if err := svc.AddItem(ctx, userID, variantID, 5); err != nil {
		t.Fatalf("AddItem: %v", err)
	}
	if err := svc.SeedStock(ctx, variantID, 20); err != nil {
		t.Fatalf("SeedStock: %v", err)
	}

	reservationID, _, err := svc.Reserve(ctx, userID)
	if err != nil {
		t.Fatalf("Reserve: %v", err)
	}
	checkStock(t, ctx, variantID, 15) // 20-5=15

	// Commit: must delete manifest but NOT restore stock.
	if err := svc.CommitReservation(ctx, reservationID); err != nil {
		t.Fatalf("CommitReservation: %v", err)
	}

	// Stock must remain at 15 — purchase consumed the units.
	checkStock(t, ctx, variantID, 15)

	// Manifest key must be gone.
	mKey := "mopro:reservation:" + reservationID
	exists, err := integRedis.Exists(ctx, mKey).Result()
	if err != nil {
		t.Fatalf("EXISTS manifest: %v", err)
	}
	if exists != 0 {
		t.Error("manifest key must be deleted after CommitReservation")
	}

	// Double-commit must be a no-op (idempotent).
	if err := svc.CommitReservation(ctx, reservationID); err != nil {
		t.Fatalf("second CommitReservation must be no-op: %v", err)
	}
}

func (alwaysValidCatalog) ListCategories(_ context.Context, _ string, _ int) ([]catalog.CategoryRow, error) {
	return nil, nil
}

func (alwaysValidCatalog) ListProductsByCategory(_ context.Context, _ int64, _, _ string, _ catalog.ProductFilter, _, _ int) ([]catalog.ProductSummaryRow, int, error) {
	return nil, 0, nil
}

func (alwaysValidCatalog) SearchSummary(_ context.Context, _, _, _ string, _ catalog.ProductFilter, _, _ int) ([]catalog.ProductSummaryRow, int, error) {
	return nil, 0, nil
}
