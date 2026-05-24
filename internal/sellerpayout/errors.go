package sellerpayout

import "errors"

var (
	ErrPayoutNotFound           = errors.New("sellerpayout: payout not found")
	ErrPayoutAlreadyExists      = errors.New("sellerpayout: payout already exists for this order/seller")
	ErrBatchNotFound            = errors.New("sellerpayout: batch not found")
	ErrBatchAlreadyExists       = errors.New("sellerpayout: batch already exists")
	ErrSellerPspAccountNotFound = errors.New("sellerpayout: seller psp account not found")
	ErrMaxRetriesExceeded       = errors.New("sellerpayout: max retries exceeded")
	ErrAmbiguousTransfer        = errors.New("sellerpayout: ambiguous PSP transfer state; manual review required")
)
