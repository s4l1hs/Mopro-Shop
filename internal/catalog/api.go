// Package catalog manages product listings, variants, multi-language translations,
// and category commission reads from ref_schema.
// Other modules (cart, order, search) import ONLY the Service interface from this package.
package catalog

import (
	"context"

	"github.com/jackc/pgx/v5"
)

// Service is the public interface of the catalog module.
// It is the ONLY exported API. Other modules must import this interface, never
// the concrete service or repository types.
type Service interface {
	CreateProduct(ctx context.Context, in CreateProductRequest) (Product, error)
	AddVariant(ctx context.Context, productID int64, in AddVariantRequest) (Variant, error)
	// UpdateVariantPrice updates the price of a variant the seller owns (P-032).
	// Returns ErrVariantNotFound when the variant is missing or not owned, and
	// ErrInvalidPrice on a bad price. The #92 trigger records history.
	UpdateVariantPrice(ctx context.Context, sellerID int64, in UpdateVariantPriceRequest) error
	UpdateTranslation(ctx context.Context, productID int64, locale, title, description string) error
	GetByID(ctx context.Context, id int64) (Product, []Variant, []ProductTranslation, error)
	Search(ctx context.Context, query, locale, market string) ([]Product, error)
	GetCommissionForCategory(ctx context.Context, market string, categoryID int64) (CategoryCommission, error)
	GetVariantByID(ctx context.Context, variantID int64) (Variant, error)

	// Discovery endpoints (Phase 4.4a).
	//
	// `maxDepth` (Session 4c §3) filters to categories whose chain length to
	// a root parent is at most `maxDepth` (root=0, direct children=1, …).
	// Pass 0 for "no limit" — preserves the historical behavior.
	ListCategories(ctx context.Context, locale string, maxDepth int) ([]CategoryRow, error)
	ListProductsByCategory(ctx context.Context, categoryID int64, locale, market string, filter ProductFilter, page, perPage int) ([]ProductSummaryRow, int, error)
	// ListProducts is the global (catalog-wide) listing — the no-category variant
	// backing the server-driven Home rails (recommended / bestseller / newest).
	ListProducts(ctx context.Context, locale, market string, filter ProductFilter, page, perPage int) ([]ProductSummaryRow, int, error)
	SearchSummary(ctx context.Context, query, locale, market string, filter ProductFilter, page, perPage int) ([]ProductSummaryRow, int, error)

	// Suggest returns structured autocomplete data (SE-06): up to brandLimit
	// brand rows + up to productLimit product summaries matching query, all from
	// catalog_schema (§5-safe). An empty/blank query yields an empty result.
	Suggest(ctx context.Context, query, locale string, brandLimit, productLimit int) (SuggestResult, error)

	// FacetsByCategory aggregates the facetable attributes over a category's
	// subtree into (value, count) buckets (PLP-13).
	FacetsByCategory(ctx context.Context, categoryID int64, locale string) ([]Facet, error)
	// ProductAttributes returns a product's normalized attributes for the PDP
	// specs tab (PLP-13 / PD-01).
	ProductAttributes(ctx context.Context, productID int64, locale string) ([]ProductAttribute, error)

	// ListProductsByIDs fetches product summaries for the given IDs (guest favorites, batch hydration).
	ListProductsByIDs(ctx context.Context, ids []int64, locale, market string) ([]ProductSummaryRow, error)

	// HomeRails returns the ordered list of rail keys and their localized titles.
	HomeRails(ctx context.Context, locale string) ([]HomeRailRow, error)

	// HomeBanners returns active banners ordered by sort_order.
	HomeBanners(ctx context.Context) ([]HomeBannerRow, error)

	// HomeMoodStories returns active mood-story tiles ordered by sort_order.
	HomeMoodStories(ctx context.Context) ([]HomeMoodStoryRow, error)

	// HomeFlashDeals returns the active flash-deals collection (or the one with
	// collectionID when non-nil) with products hydrated. Returns (nil, nil) when
	// there is no active collection / the id doesn't exist.
	HomeFlashDeals(ctx context.Context, locale string, collectionID *int64) (*FlashDealsResult, error)

	// ListReviews returns one page of reviews for a product, ordered by sort.
	// viewerUserID computes ProductReviewRow.VotedByCurrentUser (pass 0 for guest).
	ListReviews(ctx context.Context, productID int64, sort ReviewSort, page, pageSize int, viewerUserID int64) ([]ProductReviewRow, int, error)

	// ReviewsSummary returns the product-level rating aggregate (average,
	// distribution, totalCount) that drives the histogram. Identical across pages.
	ReviewsSummary(ctx context.Context, productID int64) (ReviewsSummary, error)

	// ReviewProductID returns the product a review belongs to (for URL validation),
	// or ErrReviewNotFound. Used by the helpful-vote endpoint to 404 mismatches.
	ReviewProductID(ctx context.Context, reviewID int64) (int64, error)

	// ToggleHelpfulVote flips the (reviewID, userID) helpful vote inside a
	// SERIALIZABLE transaction and returns the new vote state plus refreshed count.
	// Authoritative source: catalog_schema.review_helpful_votes.
	ToggleHelpfulVote(ctx context.Context, reviewID, userID int64) (HelpfulVoteResult, error)

	// ListAllVariantStocks returns (variantID, stock) for every variant with stock > 0.
	// Used at core-svc startup to seed Redis stock counters.
	ListAllVariantStocks(ctx context.Context) ([]VariantStock, error)
}

// Repository is the storage interface used only by service.go.
// Other modules must not import this; they use the Service interface.
type Repository interface {
	InsertProduct(ctx context.Context, p Product) (Product, error)
	InsertVariant(ctx context.Context, v Variant) (Variant, error)
	// UpdateVariantPrice sets a variant's price (+ optional strikethrough original)
	// when it belongs to sellerID; returns whether a row was updated (P-032).
	UpdateVariantPrice(ctx context.Context, sellerID, variantID, priceMinor int64, originalPriceMinor *int64) (bool, error)
	UpsertTranslation(ctx context.Context, t ProductTranslation) error
	GetByID(ctx context.Context, id int64) (Product, []Variant, []ProductTranslation, error)
	SearchProducts(ctx context.Context, query, locale, market string) ([]Product, error)
	GetCommission(ctx context.Context, market string, categoryID int64) (CategoryCommission, error)
	IsCurrencyActive(ctx context.Context, code string) (bool, error)
	GetVariantByID(ctx context.Context, variantID int64) (Variant, error)

	// Discovery queries (Phase 4.4a).
	ListCategories(ctx context.Context, locale string, maxDepth int) ([]CategoryRow, error)
	ListProductsByCategory(ctx context.Context, categoryID int64, locale string, filter ProductFilter, offset, limit int) ([]ProductSummaryRow, int, error)
	ListProducts(ctx context.Context, locale string, filter ProductFilter, offset, limit int) ([]ProductSummaryRow, int, error)
	SearchProductsSummary(ctx context.Context, query, locale string, filter ProductFilter, offset, limit int) ([]ProductSummaryRow, int, error)
	// SuggestBrands returns up to limit distinct active-product brands whose name
	// prefix-matches query (case-insensitive), ordered by product count desc.
	// Single-schema (catalog_schema.products) — §5-safe.
	SuggestBrands(ctx context.Context, query string, limit int) ([]BrandSuggestion, error)

	FacetsByCategory(ctx context.Context, categoryID int64, locale string) ([]Facet, error)
	ProductAttributes(ctx context.Context, productID int64, locale string) ([]ProductAttribute, error)

	ListProductsByIDs(ctx context.Context, ids []int64, locale string) ([]ProductSummaryRow, error)
	HomeRails(ctx context.Context) ([]HomeRailRow, error)
	HomeBanners(ctx context.Context) ([]HomeBannerRow, error)
	HomeMoodStories(ctx context.Context) ([]HomeMoodStoryRow, error)
	HomeFlashDeals(ctx context.Context, collectionID *int64) (*FlashDealsCollectionRow, error)

	// ListReviews returns one page (offset/limit) ordered by sort, with
	// VotedByCurrentUser computed against viewerUserID (0 = guest).
	ListReviews(ctx context.Context, productID int64, sort ReviewSort, offset, limit int, viewerUserID int64) ([]ProductReviewRow, int, error)
	// ReviewsSummary returns the rating aggregate for the histogram.
	ReviewsSummary(ctx context.Context, productID int64) (ReviewsSummary, error)
	// ReviewProductID returns the owning product id or ErrReviewNotFound.
	ReviewProductID(ctx context.Context, reviewID int64) (int64, error)

	// ── Helpful-vote primitives (authoritative table: review_helpful_votes) ──
	// All three run inside a caller-provided tx (see WithTx) so the vote mutation
	// and the helpful_count cache refresh commit atomically.
	//
	// InsertHelpfulVote returns ErrAlreadyVoted on a 23505 PK conflict (expected
	// concurrent / already-voted path; not logged). It is savepoint-guarded so the
	// outer tx survives the conflict and can toggle off instead.
	InsertHelpfulVote(ctx context.Context, tx pgx.Tx, reviewID, userID int64) error
	// DeleteHelpfulVote removes the vote; bool reports whether a row was deleted.
	DeleteHelpfulVote(ctx context.Context, tx pgx.Tx, reviewID, userID int64) (bool, error)
	// RefreshHelpfulCountCache recomputes product_reviews.helpful_count from the
	// authoritative review_helpful_votes rows. helpful_count is a denormalized
	// cache, never the source of truth.
	RefreshHelpfulCountCache(ctx context.Context, tx pgx.Tx, reviewID int64) error
	// HelpfulCount reads the (just-refreshed) cached count within the tx.
	HelpfulCount(ctx context.Context, tx pgx.Tx, reviewID int64) (int, error)

	// WithTx runs fn inside a transaction at the given isolation level, retrying
	// on serialization failures (40001) and deadlocks (40P01).
	WithTx(ctx context.Context, iso pgx.TxIsoLevel, fn func(pgx.Tx) error) error

	ListAllVariantStocks(ctx context.Context) ([]VariantStock, error)
}
