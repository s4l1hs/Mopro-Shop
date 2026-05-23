package order

import "errors"

var (
	ErrOrderNotFound              = errors.New("order: not found")
	ErrInvalidTransition          = errors.New("order: invalid status transition")
	ErrDuplicateIdempotency       = errors.New("order: duplicate idempotency key")
	ErrEmptyCart                  = errors.New("order: cart has no items")
	ErrReservationExpired         = errors.New("order: reservation has expired")
	ErrCheckoutSessionNotFound    = errors.New("order: checkout session not found")
	ErrCheckoutSessionDuplicate   = errors.New("order: checkout session already exists")
)
