package order

import "errors"

var (
	ErrOrderNotFound            = errors.New("order: not found")
	ErrInvalidTransition        = errors.New("order: invalid status transition")
	ErrDuplicateIdempotency     = errors.New("order: duplicate idempotency key")
	ErrEmptyCart                = errors.New("order: cart has no items")
	ErrReservationExpired       = errors.New("order: reservation has expired")
	ErrCheckoutSessionNotFound  = errors.New("order: checkout session not found")
	ErrCheckoutSessionDuplicate = errors.New("order: checkout session already exists")
	ErrCouponNotFound           = errors.New("order: coupon not found")
	// ErrInvalidInstallments rejects a card-installment count outside the
	// supported set (PD-05). Validated before any persistence in the saga.
	ErrInvalidInstallments = errors.New("order: installments must be one of 1, 3, 6, 9, 12")
)
