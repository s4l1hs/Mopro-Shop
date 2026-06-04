package catalog

import "time"

// VariantStock is a minimal projection used to sync Redis stock counters at startup.
type VariantStock struct {
	VariantID int64
	Stock     int
}

// FlashDealsCollectionRow is a flash-deals collection's metadata + its item
// references (product id + flash price), as stored. The service hydrates the
// products via ListProductsByIDs.
type FlashDealsCollectionRow struct {
	ID     int64
	Title  string
	EndsAt time.Time
	Items  []FlashDealItemRow
}

// FlashDealItemRow links a product to a collection at a flash price.
type FlashDealItemRow struct {
	ProductID       int64
	FlashPriceMinor int64
	SortOrder       int
}

// FlashDealsResult is the assembled flash-deals collection returned by the
// service: metadata + hydrated product summaries, each carrying its flash price.
type FlashDealsResult struct {
	ID       int64
	Title    string
	EndsAt   time.Time
	Products []FlashDealProduct
}

// FlashDealProduct is a product summary plus its flash price within a collection.
type FlashDealProduct struct {
	Summary         ProductSummaryRow
	FlashPriceMinor int64
}

// Product is the aggregate root for a seller listing.
type Product struct {
	ID              int64     `json:"id"`
	SellerID        int64     `json:"seller_id"`
	CategoryID      int64     `json:"category_id"`
	Brand           string    `json:"brand"`
	DefaultCurrency string    `json:"default_currency"`
	DefaultLocale   string    `json:"default_locale"`
	Status          string    `json:"status"`
	CreatedAt       time.Time `json:"created_at"`
	UpdatedAt       time.Time `json:"updated_at"`
}

// Variant is a single SKU within a product (color/size/price combination).
type Variant struct {
	ID            int64    `json:"id"`
	ProductID     int64    `json:"product_id"`
	CategoryID    int64    `json:"category_id"`
	SellerID      int64    `json:"seller_id"`
	SKU           string   `json:"sku"`
	Color         string   `json:"color"`
	Size          string   `json:"size"`
	PriceMinor    int64    `json:"price_minor"`
	PriceCurrency string   `json:"price_currency"`
	Stock         int      `json:"stock"`
	ImageKeys     []string `json:"image_keys"`
}

// ProductTranslation holds locale-specific title and description.
type ProductTranslation struct {
	ProductID   int64  `json:"product_id"`
	Locale      string `json:"locale"`
	Title       string `json:"title"`
	Description string `json:"description"`
}

// CategoryRow is a category with its locale-resolved name and commission rate.
// Used by ListCategories for the buyer-facing GET /categories endpoint.
//
// PromoSlot (Session 4d §2) is surfaced only on top-level rows (ParentID == nil).
// Repository normalizes malformed JSON to nil + warning log; the API contract
// is "absent or null for everything except seeded top-level categories."
type CategoryRow struct {
	ID               int64
	Slug             string
	Name             string // locale-resolved (name_tr or name_en)
	ParentID         *int64
	CommissionPctBps int
	PromoSlot        *PromoSlot
}

// PromoSlot is the optional 16:9 card + title + CTA shown in the desktop
// mega menu's 3+1 layout. Persisted as JSONB in ref_schema.categories.promo_slot;
// always null on subcategories and leaves.
type PromoSlot struct {
	ImageURL string `json:"imageUrl"`
	Title    string `json:"title"`
	DeepLink string `json:"deepLink"`
}

// ProductSummaryRow is a lightweight product record for list / search results.
// Includes the lowest-priced variant's price, cover image key, and commission rate.
type ProductSummaryRow struct {
	ID                 int64
	SellerID           int64
	CategoryID         int64
	Brand              string
	Status             string
	Title              string // locale-resolved
	PriceMinor         int64
	PriceCurrency      string
	CoverImageKey      string // raw storage key; handler calls mediaurl.CDNUrl()
	CommissionPctBps   int
	OriginalPriceMinor *int64   // null when no discount; render strikethrough on UI
	RatingAvg          *float64 // null when no reviews
	RatingCount        int
	FreeShipping       bool // products.free_shipping flag (P-028 column) — P-009 badge
	FavoritesCount     int  // count of user_favorites rows for this product (P-004)
}

// ProductFilter holds the optional filter + sort knobs for product listing and
// search (P-028). The zero value applies no constraints. Nil pointers / empty
// slices mean "unset"; an unknown Sort token falls back to recommended (see
// repository.orderByClause). Price filters match the displayed (lowest-variant)
// price. Brands is an ANY-match. FreeShipping/InStock constrain only when true.
type ProductFilter struct {
	CategoryID    *int64   // search-only; PLP passes its dedicated categoryID arg
	MinPriceMinor *int64   // v.price_minor >= MinPriceMinor
	MaxPriceMinor *int64   // v.price_minor <= MaxPriceMinor
	Brands        []string // p.brand = ANY(Brands)
	MinRating     *int     // p.rating_avg >= MinRating (1..5)
	FreeShipping  *bool    // true => only free-shipping products
	InStock       *bool    // true => only products with an in-stock variant
	Sort          string   // PlpSort token; "" or unknown => recommended
}

// CategoryCommission holds the currently active commission + KDV rates for a
// market/category pair, read from ref_schema.commission_rules.
type CategoryCommission struct {
	CategoryID       int64  `json:"category_id"`
	Market           string `json:"market"`
	CommissionPctBps int    `json:"commission_pct_bps"`
	KdvPctBps        int    `json:"kdv_pct_bps"`
}

// CreateProductRequest is the input for Service.CreateProduct.
type CreateProductRequest struct {
	SellerID        int64  `json:"seller_id"`
	CategoryID      int64  `json:"category_id"`
	Brand           string `json:"brand"`
	DefaultCurrency string `json:"default_currency"` // left empty to fall back to service defaultCurrency
	DefaultLocale   string `json:"default_locale"`   // left empty to fall back to service defaultLocale
}

// AddVariantRequest is the input for Service.AddVariant.
type AddVariantRequest struct {
	SKU           string   `json:"sku"`
	Color         string   `json:"color"`
	Size          string   `json:"size"`
	PriceMinor    int64    `json:"price_minor"`
	PriceCurrency string   `json:"price_currency"` // left empty to fall back to service defaultCurrency
	Stock         int      `json:"stock"`
	ImageKeys     []string `json:"image_keys"`
}

// HomeRailRow is a named product rail for server-driven home composition.
type HomeRailRow struct {
	RailKey   string
	TitleTR   string
	TitleEN   string
	SortOrder int
}

// HomeBannerRow is a single banner in the home carousel.
type HomeBannerRow struct {
	ID        int64
	ImageURL  string
	DeepLink  string
	SortOrder int
}

// HomeMoodStoryRow is one circular tile in the home-screen "mood stories"
// strip. Each tile carries a localized title and a deep-link target.
type HomeMoodStoryRow struct {
	ID        int64
	TitleTR   string
	TitleEN   string
	ImageURL  string
	DeepLink  string
	SortOrder int
}

// ProductReviewRow is a single user review on a product.
//
// HelpfulCount is the denormalized cache from product_reviews.helpful_count; the
// authoritative source is catalog_schema.review_helpful_votes (see
// RefreshHelpfulCountCache). VotedByCurrentUser is true only when the viewing
// user has a row in review_helpful_votes for this review (always false for guests,
// who are passed viewerUserID == 0).
type ProductReviewRow struct {
	ID                 int64
	ProductID          int64
	UserID             int64
	Rating             int
	Title              string
	Body               string
	HelpfulCount       int
	VotedByCurrentUser bool
	CreatedAt          string
}

// ReviewSort enumerates the allowed sort orders for the reviews list endpoint.
type ReviewSort string

const (
	ReviewSortNewest  ReviewSort = "newest"  // created_at DESC
	ReviewSortHighest ReviewSort = "highest" // rating DESC, created_at DESC
	ReviewSortLowest  ReviewSort = "lowest"  // rating ASC, created_at DESC
	ReviewSortHelpful ReviewSort = "helpful" // helpful_count DESC, created_at DESC
)

// ParseReviewSort validates a raw sort string. ok is false for unknown values so
// the HTTP layer can return 400.
func ParseReviewSort(s string) (ReviewSort, bool) {
	switch ReviewSort(s) {
	case ReviewSortNewest, ReviewSortHighest, ReviewSortLowest, ReviewSortHelpful:
		return ReviewSort(s), true
	}
	return "", false
}

// orderByClause returns the trusted, whitelisted SQL ORDER BY for this sort.
// A stable final tiebreaker (id DESC) guarantees pagination has no overlaps or
// gaps even when created_at ties.
func (s ReviewSort) orderByClause() string {
	switch s {
	case ReviewSortHighest:
		return "r.rating DESC, r.created_at DESC, r.id DESC"
	case ReviewSortLowest:
		return "r.rating ASC, r.created_at DESC, r.id DESC"
	case ReviewSortHelpful:
		return "r.helpful_count DESC, r.created_at DESC, r.id DESC"
	case ReviewSortNewest:
		fallthrough
	default:
		return "r.created_at DESC, r.id DESC"
	}
}

// ReviewsSummary is the product-level rating aggregate that drives the histogram.
// It is identical across every page request for the same product. Distribution is
// keyed by rating (1..5); ratings with no reviews are present with a zero count.
type ReviewsSummary struct {
	Average      float64
	Distribution map[int]int
	TotalCount   int
}

// HelpfulVoteResult is the outcome of a helpful-vote toggle: the new vote state for
// the calling user plus the refreshed authoritative count.
type HelpfulVoteResult struct {
	Voted        bool
	HelpfulCount int
}
