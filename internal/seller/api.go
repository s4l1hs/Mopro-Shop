// Package seller manages seller storefront profiles + the seller-user role
// binding (Tranche 5a). It owns seller_schema; product/return/Q&A data stays in
// their own modules and is orchestrated by the HTTP handlers.
package seller

import "context"

// Service is the seller module's public surface.
type Service interface {
	// GetBySlug returns an active seller; ErrSellerNotFound for unknown/suspended.
	GetBySlug(ctx context.Context, slug string) (Seller, error)
	// GetByID returns an active seller by id; ErrSellerNotFound otherwise.
	GetByID(ctx context.Context, id int64) (Seller, error)
	// OfficialSellerIDs returns the subset of ids that are official (verified)
	// active sellers, as a set (PLP-17). §5-safe: a single seller_schema query —
	// the catalog handler app-merges this onto the page's product summaries.
	OfficialSellerIDs(ctx context.Context, ids []int64) (map[int64]bool, error)
	// SellerNamesByIDs returns display names for the given active seller ids
	// (cart read-path enrichment, CT-01). §5-safe: a single seller_schema query —
	// the cart handler app-merges this onto the cart's seller groups.
	SellerNamesByIDs(ctx context.Context, ids []int64) (map[int64]string, error)
	// ResolveSellerForUser returns the seller id a user owns/staffs, if any.
	ResolveSellerForUser(ctx context.Context, userID int64) (sellerID int64, isSeller bool, err error)
	// GetBindingForUser returns the user's seller binding (id+slug+name+role) for
	// the bound active seller, if any. (false, nil) when the user is not a seller.
	GetBindingForUser(ctx context.Context, userID int64) (Binding, bool, error)

	// ── Seller size charts (docs/internal/seller-size-charts.md) ──────────────
	// CreateSizeChart validates + stores a seller chart, returning its id (422 on
	// ErrInvalidChart).
	CreateSizeChart(ctx context.Context, sellerID int64, c SizeChart) (int64, error)
	// UpdateSizeChart replaces a chart the seller owns (ErrChartNotFound if not).
	UpdateSizeChart(ctx context.Context, sellerID, chartID int64, c SizeChart) error
	// ListSizeCharts returns the seller's charts (with rows).
	ListSizeCharts(ctx context.Context, sellerID int64) ([]SizeChart, error)
	// AttachProductChart links a product to one of the seller's charts (chart
	// ownership verified here; product ownership is the caller's responsibility).
	AttachProductChart(ctx context.Context, sellerID, productID, chartID int64) error
	// DetachProductChart removes a product's chart → falls back to the standard.
	DetachProductChart(ctx context.Context, sellerID, productID int64) error
	// SizeChartForProduct resolves a product's attached chart for the match path.
	SizeChartForProduct(ctx context.Context, productID int64) (SizeChart, bool, error)
}

// Repository is the seller_schema persistence boundary.
type Repository interface {
	GetBySlug(ctx context.Context, slug string) (Seller, error)
	GetByID(ctx context.Context, id int64) (Seller, error)
	OfficialSellerIDs(ctx context.Context, ids []int64) (map[int64]bool, error)
	SellerNamesByIDs(ctx context.Context, ids []int64) (map[int64]string, error)
	SellerIDForUser(ctx context.Context, userID int64) (int64, bool, error)
	BindingForUser(ctx context.Context, userID int64) (Binding, bool, error)

	// Seller size charts.
	InsertSizeChart(ctx context.Context, c SizeChart) (int64, error)
	ReplaceSizeChart(ctx context.Context, sellerID, chartID int64, c SizeChart) error
	ListSizeChartsBySeller(ctx context.Context, sellerID int64) ([]SizeChart, error)
	ChartOwnedBy(ctx context.Context, sellerID, chartID int64) (bool, error)
	AttachProductChart(ctx context.Context, productID, chartID, sellerID int64) error
	DetachProductChart(ctx context.Context, productID, sellerID int64) error
	SizeChartForProduct(ctx context.Context, productID int64) (SizeChart, bool, error)
}
