package catalog

import (
	"context"
	"fmt"
)

type catalogService struct {
	repo            Repository
	defaultCurrency string
	defaultLocale   string
}

// NewService constructs a catalog Service backed by the given Repository.
// defaultCurrency and defaultLocale are read from env (DEFAULT_CURRENCY, DEFAULT_LOCALE)
// and used when the caller omits those fields.
func NewService(repo Repository, defaultCurrency, defaultLocale string) Service {
	return &catalogService{
		repo:            repo,
		defaultCurrency: defaultCurrency,
		defaultLocale:   defaultLocale,
	}
}

func (s *catalogService) CreateProduct(ctx context.Context, in CreateProductRequest) (Product, error) {
	if in.DefaultCurrency == "" {
		in.DefaultCurrency = s.defaultCurrency
	}
	if in.DefaultLocale == "" {
		in.DefaultLocale = s.defaultLocale
	}

	ok, err := s.repo.IsCurrencyActive(ctx, in.DefaultCurrency)
	if err != nil {
		return Product{}, fmt.Errorf("catalog: validate currency: %w", err)
	}
	if !ok {
		return Product{}, ErrInvalidCurrency
	}

	return s.repo.InsertProduct(ctx, Product{
		SellerID:        in.SellerID,
		CategoryID:      in.CategoryID,
		Brand:           in.Brand,
		DefaultCurrency: in.DefaultCurrency,
		DefaultLocale:   in.DefaultLocale,
		Status:          "draft",
	})
}

func (s *catalogService) AddVariant(ctx context.Context, productID int64, in AddVariantRequest) (Variant, error) {
	if in.PriceCurrency == "" {
		in.PriceCurrency = s.defaultCurrency
	}

	ok, err := s.repo.IsCurrencyActive(ctx, in.PriceCurrency)
	if err != nil {
		return Variant{}, fmt.Errorf("catalog: validate currency: %w", err)
	}
	if !ok {
		return Variant{}, ErrInvalidCurrency
	}

	keys := in.ImageKeys
	if keys == nil {
		keys = []string{}
	}

	return s.repo.InsertVariant(ctx, Variant{
		ProductID:     productID,
		SKU:           in.SKU,
		Color:         in.Color,
		Size:          in.Size,
		PriceMinor:    in.PriceMinor,
		PriceCurrency: in.PriceCurrency,
		Stock:         in.Stock,
		ImageKeys:     keys,
	})
}

func (s *catalogService) UpdateTranslation(ctx context.Context, productID int64, locale, title, description string) error {
	return s.repo.UpsertTranslation(ctx, ProductTranslation{
		ProductID:   productID,
		Locale:      locale,
		Title:       title,
		Description: description,
	})
}

func (s *catalogService) GetByID(ctx context.Context, id int64) (Product, []Variant, []ProductTranslation, error) {
	return s.repo.GetByID(ctx, id)
}

func (s *catalogService) Search(ctx context.Context, query, locale, market string) ([]Product, error) {
	if locale == "" {
		locale = s.defaultLocale
	}
	return s.repo.SearchProducts(ctx, query, locale, market)
}

func (s *catalogService) GetCommissionForCategory(ctx context.Context, market string, categoryID int64) (CategoryCommission, error) {
	return s.repo.GetCommission(ctx, market, categoryID)
}

func (s *catalogService) GetVariantByID(ctx context.Context, variantID int64) (Variant, error) {
	return s.repo.GetVariantByID(ctx, variantID)
}

func (s *catalogService) ListCategories(ctx context.Context, locale string, maxDepth int) ([]CategoryRow, error) {
	if locale == "" {
		locale = s.defaultLocale
	}
	return s.repo.ListCategories(ctx, locale, maxDepth)
}

func (s *catalogService) ListProductsByCategory(ctx context.Context, categoryID int64, locale, market string, page, perPage int) ([]ProductSummaryRow, int, error) {
	if locale == "" {
		locale = s.defaultLocale
	}
	if page < 1 {
		page = 1
	}
	if perPage < 1 || perPage > 50 {
		perPage = 20
	}
	offset := (page - 1) * perPage
	return s.repo.ListProductsByCategory(ctx, categoryID, locale, offset, perPage)
}

func (s *catalogService) SearchSummary(ctx context.Context, query, locale, market string, page, perPage int) ([]ProductSummaryRow, int, error) {
	if locale == "" {
		locale = s.defaultLocale
	}
	if page < 1 {
		page = 1
	}
	if perPage < 1 || perPage > 50 {
		perPage = 20
	}
	offset := (page - 1) * perPage
	return s.repo.SearchProductsSummary(ctx, query, locale, offset, perPage)
}

func (s *catalogService) ListAllVariantStocks(ctx context.Context) ([]VariantStock, error) {
	return s.repo.ListAllVariantStocks(ctx)
}

func (s *catalogService) ListProductsByIDs(ctx context.Context, ids []int64, locale, _ string) ([]ProductSummaryRow, error) {
	if locale == "" {
		locale = s.defaultLocale
	}
	return s.repo.ListProductsByIDs(ctx, ids, locale)
}

func (s *catalogService) HomeRails(ctx context.Context, locale string) ([]HomeRailRow, error) {
	return s.repo.HomeRails(ctx)
}

func (s *catalogService) HomeBanners(ctx context.Context) ([]HomeBannerRow, error) {
	return s.repo.HomeBanners(ctx)
}

func (s *catalogService) HomeMoodStories(ctx context.Context) ([]HomeMoodStoryRow, error) {
	return s.repo.HomeMoodStories(ctx)
}

func (s *catalogService) HomeFlashDeals(ctx context.Context, locale string, collectionID *int64) (*FlashDealsResult, error) {
	col, err := s.repo.HomeFlashDeals(ctx, collectionID)
	if err != nil {
		return nil, err
	}
	if col == nil {
		return nil, nil
	}
	ids := make([]int64, 0, len(col.Items))
	flashByID := make(map[int64]int64, len(col.Items))
	for _, it := range col.Items {
		ids = append(ids, it.ProductID)
		flashByID[it.ProductID] = it.FlashPriceMinor
	}
	var rows []ProductSummaryRow
	if len(ids) > 0 {
		rows, err = s.repo.ListProductsByIDs(ctx, ids, locale)
		if err != nil {
			return nil, err
		}
	}
	byID := make(map[int64]ProductSummaryRow, len(rows))
	for _, r := range rows {
		byID[r.ID] = r
	}
	// Assemble in the collection's item order, skipping any product that no
	// longer resolves (deleted/inactive).
	products := make([]FlashDealProduct, 0, len(col.Items))
	for _, it := range col.Items {
		if row, ok := byID[it.ProductID]; ok {
			products = append(products, FlashDealProduct{
				Summary:         row,
				FlashPriceMinor: flashByID[it.ProductID],
			})
		}
	}
	return &FlashDealsResult{
		ID:       col.ID,
		Title:    col.Title,
		EndsAt:   col.EndsAt,
		Products: products,
	}, nil
}

func (s *catalogService) ListReviews(ctx context.Context, productID int64, page, perPage int) ([]ProductReviewRow, int, error) {
	if perPage <= 0 {
		perPage = 20
	}
	offset := (page - 1) * perPage
	return s.repo.ListReviews(ctx, productID, offset, perPage)
}
