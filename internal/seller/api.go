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
	// ResolveSellerForUser returns the seller id a user owns/staffs, if any.
	ResolveSellerForUser(ctx context.Context, userID int64) (sellerID int64, isSeller bool, err error)
	// GetBindingForUser returns the user's seller binding (id+slug+name+role) for
	// the bound active seller, if any. (false, nil) when the user is not a seller.
	GetBindingForUser(ctx context.Context, userID int64) (Binding, bool, error)
}

// Repository is the seller_schema persistence boundary.
type Repository interface {
	GetBySlug(ctx context.Context, slug string) (Seller, error)
	GetByID(ctx context.Context, id int64) (Seller, error)
	OfficialSellerIDs(ctx context.Context, ids []int64) (map[int64]bool, error)
	SellerIDForUser(ctx context.Context, userID int64) (int64, bool, error)
	BindingForUser(ctx context.Context, userID int64) (Binding, bool, error)
}
