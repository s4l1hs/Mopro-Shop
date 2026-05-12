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
)
