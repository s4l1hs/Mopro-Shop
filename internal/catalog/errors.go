package catalog

import "errors"

var (
	// ErrNotFound is returned when a product does not exist.
	ErrNotFound = errors.New("catalog: product not found")

	// ErrInvalidCurrency is returned when the requested currency is unknown or
	// not active in ref_schema.currencies.
	ErrInvalidCurrency = errors.New("catalog: invalid or inactive currency")

	// ErrDuplicateSKU is returned when a variant SKU already exists for the product.
	ErrDuplicateSKU = errors.New("catalog: duplicate SKU within product")

	// ErrCommissionNotFound is returned when no active commission rule exists.
	ErrCommissionNotFound = errors.New("catalog: commission rule not found for market/category")

	// ErrReviewNotFound is returned when a review id does not exist (or does not
	// belong to the requested product).
	ErrReviewNotFound = errors.New("catalog: review not found")

	// ErrAlreadyVoted is returned by InsertHelpfulVote when the (review_id, user_id)
	// row already exists — a 23505 unique violation. It is the EXPECTED concurrent /
	// already-voted path (the storage-layer PRIMARY KEY is authoritative), so callers
	// treat it as "toggle off" rather than an error. Mirrors the cashback layer's
	// sentinel-error convention. Do NOT error-log this.
	ErrAlreadyVoted = errors.New("catalog: helpful vote already exists for this review/user")
)
