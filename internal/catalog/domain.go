package catalog

import "time"

// VariantStock is a minimal projection used to sync Redis stock counters at startup.
type VariantStock struct {
	VariantID int64
	Stock     int
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
type CategoryRow struct {
	ID               int64
	Slug             string
	Name             string // locale-resolved (name_tr or name_en)
	ParentID         *int64
	CommissionPctBps int
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
type ProductReviewRow struct {
	ID           int64
	ProductID    int64
	UserID       int64
	Rating       int
	Title        string
	Body         string
	HelpfulCount int
	CreatedAt    string
}
