package catalog_test

import (
	"context"
	"errors"
	"testing"

	"github.com/mopro/platform/internal/catalog"
)

// mockRepo implements catalog.Repository for unit testing.
type mockRepo struct {
	insertProductFn     func(ctx context.Context, p catalog.Product) (catalog.Product, error)
	insertVariantFn     func(ctx context.Context, v catalog.Variant) (catalog.Variant, error)
	upsertTranslationFn func(ctx context.Context, t catalog.ProductTranslation) error
	getByIDFn           func(ctx context.Context, id int64) (catalog.Product, []catalog.Variant, []catalog.ProductTranslation, error)
	searchProductsFn    func(ctx context.Context, query, locale, market string) ([]catalog.Product, error)
	getCommissionFn     func(ctx context.Context, market string, categoryID int64) (catalog.CategoryCommission, error)
	isCurrencyActiveFn  func(ctx context.Context, code string) (bool, error)
}

func (m *mockRepo) InsertProduct(ctx context.Context, p catalog.Product) (catalog.Product, error) {
	if m.insertProductFn != nil {
		return m.insertProductFn(ctx, p)
	}
	p.ID = 1
	return p, nil
}

func (m *mockRepo) InsertVariant(ctx context.Context, v catalog.Variant) (catalog.Variant, error) {
	if m.insertVariantFn != nil {
		return m.insertVariantFn(ctx, v)
	}
	v.ID = 1
	return v, nil
}

func (m *mockRepo) UpsertTranslation(ctx context.Context, t catalog.ProductTranslation) error {
	if m.upsertTranslationFn != nil {
		return m.upsertTranslationFn(ctx, t)
	}
	return nil
}

func (m *mockRepo) GetByID(ctx context.Context, id int64) (catalog.Product, []catalog.Variant, []catalog.ProductTranslation, error) {
	if m.getByIDFn != nil {
		return m.getByIDFn(ctx, id)
	}
	return catalog.Product{ID: id}, nil, nil, nil
}

func (m *mockRepo) SearchProducts(ctx context.Context, query, locale, market string) ([]catalog.Product, error) {
	if m.searchProductsFn != nil {
		return m.searchProductsFn(ctx, query, locale, market)
	}
	return nil, nil
}

func (m *mockRepo) GetCommission(ctx context.Context, market string, categoryID int64) (catalog.CategoryCommission, error) {
	if m.getCommissionFn != nil {
		return m.getCommissionFn(ctx, market, categoryID)
	}
	return catalog.CategoryCommission{CategoryID: categoryID, Market: market, CommissionPctBps: 700, KdvPctBps: 2000}, nil
}

func (m *mockRepo) IsCurrencyActive(ctx context.Context, code string) (bool, error) {
	if m.isCurrencyActiveFn != nil {
		return m.isCurrencyActiveFn(ctx, code)
	}
	return true, nil
}

// newTestService returns a service wired to the given mock repo.
func newTestService(repo catalog.Repository) catalog.Service {
	return catalog.NewService(repo, "TRY", "tr-TR")
}

func TestCreateProduct_Success(t *testing.T) {
	svc := newTestService(&mockRepo{})
	p, err := svc.CreateProduct(context.Background(), catalog.CreateProductRequest{
		SellerID:   42,
		CategoryID: 30,
		Brand:      "Acme",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if p.ID == 0 {
		t.Fatal("expected non-zero product ID")
	}
	if p.DefaultCurrency != "TRY" {
		t.Errorf("expected defaultCurrency=TRY, got %q", p.DefaultCurrency)
	}
	if p.DefaultLocale != "tr-TR" {
		t.Errorf("expected defaultLocale=tr-TR, got %q", p.DefaultLocale)
	}
	if p.Status != "draft" {
		t.Errorf("expected status=draft, got %q", p.Status)
	}
}

func TestCreateProduct_ExplicitCurrency(t *testing.T) {
	svc := newTestService(&mockRepo{})
	p, err := svc.CreateProduct(context.Background(), catalog.CreateProductRequest{
		SellerID:        1,
		CategoryID:      1,
		DefaultCurrency: "USD",
		DefaultLocale:   "en-US",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if p.DefaultCurrency != "USD" {
		t.Errorf("expected USD, got %q", p.DefaultCurrency)
	}
}

func TestCreateProduct_InvalidCurrency(t *testing.T) {
	repo := &mockRepo{
		isCurrencyActiveFn: func(_ context.Context, code string) (bool, error) {
			return false, nil
		},
	}
	_, err := newTestService(repo).CreateProduct(context.Background(), catalog.CreateProductRequest{
		SellerID:        1,
		CategoryID:      1,
		DefaultCurrency: "FAKE",
	})
	if !errors.Is(err, catalog.ErrInvalidCurrency) {
		t.Fatalf("expected ErrInvalidCurrency, got %v", err)
	}
}

func TestCreateProduct_RepoError(t *testing.T) {
	repoErr := errors.New("db error")
	repo := &mockRepo{
		isCurrencyActiveFn: func(_ context.Context, _ string) (bool, error) {
			return false, repoErr
		},
	}
	_, err := newTestService(repo).CreateProduct(context.Background(), catalog.CreateProductRequest{
		SellerID: 1, CategoryID: 1,
	})
	if err == nil {
		t.Fatal("expected error")
	}
	if errors.Is(err, catalog.ErrInvalidCurrency) {
		t.Fatal("should not be ErrInvalidCurrency; repo returned DB error")
	}
}

func TestAddVariant_Success(t *testing.T) {
	svc := newTestService(&mockRepo{})
	v, err := svc.AddVariant(context.Background(), 1, catalog.AddVariantRequest{
		SKU:        "SKU-001",
		PriceMinor: 100_00,
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if v.ID == 0 {
		t.Fatal("expected non-zero variant ID")
	}
	if v.PriceCurrency != "TRY" {
		t.Errorf("expected TRY, got %q", v.PriceCurrency)
	}
	if v.ImageKeys == nil {
		t.Error("ImageKeys must not be nil (should be empty slice)")
	}
}

func TestAddVariant_InvalidCurrency(t *testing.T) {
	repo := &mockRepo{
		isCurrencyActiveFn: func(_ context.Context, _ string) (bool, error) {
			return false, nil
		},
	}
	_, err := newTestService(repo).AddVariant(context.Background(), 1, catalog.AddVariantRequest{
		SKU:           "SKU-X",
		PriceCurrency: "FAKE",
		PriceMinor:    50_00,
	})
	if !errors.Is(err, catalog.ErrInvalidCurrency) {
		t.Fatalf("expected ErrInvalidCurrency, got %v", err)
	}
}

func TestAddVariant_DuplicateSKU(t *testing.T) {
	repo := &mockRepo{
		insertVariantFn: func(_ context.Context, _ catalog.Variant) (catalog.Variant, error) {
			return catalog.Variant{}, catalog.ErrDuplicateSKU
		},
	}
	_, err := newTestService(repo).AddVariant(context.Background(), 1, catalog.AddVariantRequest{
		SKU:        "SKU-DUP",
		PriceMinor: 100,
	})
	if !errors.Is(err, catalog.ErrDuplicateSKU) {
		t.Fatalf("expected ErrDuplicateSKU, got %v", err)
	}
}

func TestUpdateTranslation(t *testing.T) {
	called := false
	repo := &mockRepo{
		upsertTranslationFn: func(_ context.Context, t catalog.ProductTranslation) error {
			called = true
			if t.Locale != "tr-TR" {
				return errors.New("wrong locale")
			}
			return nil
		},
	}
	err := newTestService(repo).UpdateTranslation(context.Background(), 1, "tr-TR", "Başlık", "Açıklama")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !called {
		t.Fatal("UpsertTranslation not called")
	}
}

func TestGetByID_Found(t *testing.T) {
	repo := &mockRepo{
		getByIDFn: func(_ context.Context, id int64) (catalog.Product, []catalog.Variant, []catalog.ProductTranslation, error) {
			return catalog.Product{ID: id, Status: "active"},
				[]catalog.Variant{{ID: 1, SKU: "A"}},
				[]catalog.ProductTranslation{{Locale: "tr-TR", Title: "T"}},
				nil
		},
	}
	p, variants, translations, err := newTestService(repo).GetByID(context.Background(), 5)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if p.ID != 5 {
		t.Errorf("expected ID=5, got %d", p.ID)
	}
	if len(variants) != 1 {
		t.Errorf("expected 1 variant, got %d", len(variants))
	}
	if len(translations) != 1 {
		t.Errorf("expected 1 translation, got %d", len(translations))
	}
}

func TestGetByID_NotFound(t *testing.T) {
	repo := &mockRepo{
		getByIDFn: func(_ context.Context, _ int64) (catalog.Product, []catalog.Variant, []catalog.ProductTranslation, error) {
			return catalog.Product{}, nil, nil, catalog.ErrNotFound
		},
	}
	_, _, _, err := newTestService(repo).GetByID(context.Background(), 999)
	if !errors.Is(err, catalog.ErrNotFound) {
		t.Fatalf("expected ErrNotFound, got %v", err)
	}
}

func TestSearch_EmptyLocale(t *testing.T) {
	var capturedLocale string
	repo := &mockRepo{
		searchProductsFn: func(_ context.Context, _, locale, _ string) ([]catalog.Product, error) {
			capturedLocale = locale
			return nil, nil
		},
	}
	// Empty locale should fall back to service default.
	_, _ = newTestService(repo).Search(context.Background(), "test", "", "TR")
	if capturedLocale != "tr-TR" {
		t.Errorf("expected tr-TR fallback, got %q", capturedLocale)
	}
}

func TestSearch_ExplicitLocale(t *testing.T) {
	var capturedLocale string
	repo := &mockRepo{
		searchProductsFn: func(_ context.Context, _, locale, _ string) ([]catalog.Product, error) {
			capturedLocale = locale
			return nil, nil
		},
	}
	_, _ = newTestService(repo).Search(context.Background(), "phone", "en-US", "TR")
	if capturedLocale != "en-US" {
		t.Errorf("expected en-US, got %q", capturedLocale)
	}
}

func TestAddVariant_CurrencyCheckError(t *testing.T) {
	dbErr := errors.New("pg: connection error")
	repo := &mockRepo{
		isCurrencyActiveFn: func(_ context.Context, _ string) (bool, error) {
			return false, dbErr
		},
	}
	_, err := newTestService(repo).AddVariant(context.Background(), 1, catalog.AddVariantRequest{
		SKU:        "ERR-SKU",
		PriceMinor: 1000,
	})
	if err == nil {
		t.Fatal("expected error from currency check")
	}
	if errors.Is(err, catalog.ErrInvalidCurrency) {
		t.Fatal("should not be ErrInvalidCurrency; this is a DB error")
	}
}

func TestGetCommissionForCategory(t *testing.T) {
	repo := &mockRepo{
		getCommissionFn: func(_ context.Context, market string, categoryID int64) (catalog.CategoryCommission, error) {
			return catalog.CategoryCommission{
				CategoryID:       categoryID,
				Market:           market,
				CommissionPctBps: 700,
				KdvPctBps:        2000,
			}, nil
		},
	}
	cc, err := newTestService(repo).GetCommissionForCategory(context.Background(), "TR", 30)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if cc.CommissionPctBps != 700 {
		t.Errorf("expected 700, got %d", cc.CommissionPctBps)
	}
	if cc.KdvPctBps != 2000 {
		t.Errorf("expected 2000, got %d", cc.KdvPctBps)
	}
}

func TestGetCommissionForCategory_NotFound(t *testing.T) {
	repo := &mockRepo{
		getCommissionFn: func(_ context.Context, _ string, _ int64) (catalog.CategoryCommission, error) {
			return catalog.CategoryCommission{}, catalog.ErrCommissionNotFound
		},
	}
	_, err := newTestService(repo).GetCommissionForCategory(context.Background(), "TR", 999)
	if !errors.Is(err, catalog.ErrCommissionNotFound) {
		t.Fatalf("expected ErrCommissionNotFound, got %v", err)
	}
}
