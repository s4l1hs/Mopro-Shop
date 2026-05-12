package sellerpayout

import "errors"

var (
	ErrPayoutNotFound      = errors.New("sellerpayout: payout not found")
	ErrPayoutAlreadyExists = errors.New("sellerpayout: payout already exists for this order/seller")
)
