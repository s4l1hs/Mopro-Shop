// Package catalog manages product listings, variants, multi-language translations,
// and category commission reads from ref_schema.
// Other modules (cart, order, search) import ONLY the Service interface from this package.
package catalog

import "context"

// Service is the public interface of the catalog module.
// It is the ONLY exported API. Other modules must import this interface, never
// the concrete service or repository types.
type Service interface {
	CreateProduct(ctx context.Context, in CreateProductRequest) (Product, error)
	AddVariant(ctx context.Context, productID int64, in AddVariantRequest) (Variant, error)
	UpdateTranslation(ctx context.Context, productID int64, locale, title, description string) error
	GetByID(ctx context.Context, id int64) (Product, []Variant, []ProductTranslation, error)
	Search(ctx context.Context, query, locale, market string) ([]Product, error)
	GetCommissionForCategory(ctx context.Context, market string, categoryID int64) (CategoryCommission, error)
	GetVariantByID(ctx context.Context, variantID int64) (Variant, error)

	// Discovery endpoints (Phase 4.4a).
	ListCategories(ctx context.Context, locale string) ([]CategoryRow, error)
	ListProductsByCategory(ctx context.Context, categoryID int64, locale, market string, page, perPage int) ([]ProductSummaryRow, int, error)
	SearchSummary(ctx context.Context, query, locale, market string, page, perPage int) ([]ProductSummaryRow, int, error)

	// ListProductsByIDs fetches product summaries for the given IDs (guest favorites, batch hydration).
	ListProductsByIDs(ctx context.Context, ids []int64, locale, market string) ([]ProductSummaryRow, error)

	// HomeRails returns the ordered list of rail keys and their localized titles.
	HomeRails(ctx context.Context, locale string) ([]HomeRailRow, error)

	// HomeBanners returns active banners ordered by sort_order.
	HomeBanners(ctx context.Context) ([]HomeBannerRow, error)

	// HomeMoodStories returns active mood-story tiles ordered by sort_order.
	HomeMoodStories(ctx context.Context) ([]HomeMoodStoryRow, error)

	// ListReviews returns paginated reviews for a product.
	ListReviews(ctx context.Context, productID int64, page, perPage int) ([]ProductReviewRow, int, error)

	// ListAllVariantStocks returns (variantID, stock) for every variant with stock > 0.
	// Used at core-svc startup to seed Redis stock counters.
	ListAllVariantStocks(ctx context.Context) ([]VariantStock, error)
}

// Repository is the storage interface used only by service.go.
// Other modules must not import this; they use the Service interface.
type Repository interface {
	InsertProduct(ctx context.Context, p Product) (Product, error)
	InsertVariant(ctx context.Context, v Variant) (Variant, error)
	UpsertTranslation(ctx context.Context, t ProductTranslation) error
	GetByID(ctx context.Context, id int64) (Product, []Variant, []ProductTranslation, error)
	SearchProducts(ctx context.Context, query, locale, market string) ([]Product, error)
	GetCommission(ctx context.Context, market string, categoryID int64) (CategoryCommission, error)
	IsCurrencyActive(ctx context.Context, code string) (bool, error)
	GetVariantByID(ctx context.Context, variantID int64) (Variant, error)

	// Discovery queries (Phase 4.4a).
	ListCategories(ctx context.Context, locale string) ([]CategoryRow, error)
	ListProductsByCategory(ctx context.Context, categoryID int64, locale string, offset, limit int) ([]ProductSummaryRow, int, error)
	SearchProductsSummary(ctx context.Context, query, locale string, offset, limit int) ([]ProductSummaryRow, int, error)

	ListProductsByIDs(ctx context.Context, ids []int64, locale string) ([]ProductSummaryRow, error)
	HomeRails(ctx context.Context) ([]HomeRailRow, error)
	HomeBanners(ctx context.Context) ([]HomeBannerRow, error)
	HomeMoodStories(ctx context.Context) ([]HomeMoodStoryRow, error)
	ListReviews(ctx context.Context, productID int64, offset, limit int) ([]ProductReviewRow, int, error)

	ListAllVariantStocks(ctx context.Context) ([]VariantStock, error)
}
