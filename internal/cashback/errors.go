package cashback

import "errors"

var (
	ErrPlanNotFound      = errors.New("cashback: plan not found")
	ErrPlanAlreadyExists = errors.New("cashback: plan already exists for this order")
)
