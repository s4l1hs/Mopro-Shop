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
	// ResolveSellerForUser returns the seller id a user owns/staffs, if any.
	ResolveSellerForUser(ctx context.Context, userID int64) (sellerID int64, isSeller bool, err error)
}

// Repository is the seller_schema persistence boundary.
type Repository interface {
	GetBySlug(ctx context.Context, slug string) (Seller, error)
	GetByID(ctx context.Context, id int64) (Seller, error)
	SellerIDForUser(ctx context.Context, userID int64) (int64, bool, error)
}
