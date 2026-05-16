package cashback

import "errors"

var (
	ErrPlanNotFound          = errors.New("cashback: plan not found")
	ErrPlanAlreadyExists     = errors.New("cashback: plan already exists for this order")
	ErrPaymentAlreadyExists  = errors.New("cashback: payment already exists for this period")
	ErrWalletNotActive       = errors.New("cashback: user wallet account is not active")
	ErrMaxRetriesExceeded    = errors.New("cashback: max serialization retries exceeded")
)
