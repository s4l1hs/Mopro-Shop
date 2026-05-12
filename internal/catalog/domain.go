package catalog

import "time"

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
