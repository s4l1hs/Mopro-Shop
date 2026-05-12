package cart

import "errors"

var (
	ErrOutOfStock          = errors.New("cart: out of stock")
	ErrCartEmpty           = errors.New("cart: cart is empty")
	ErrReservationNotFound = errors.New("cart: reservation not found")
	ErrVariantNotFound     = errors.New("cart: variant not found")
	ErrInvalidQty          = errors.New("cart: qty must be positive")
)
