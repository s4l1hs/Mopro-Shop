package shipping

import "errors"

var (
	ErrShipmentNotFound   = errors.New("shipping: shipment not found")
	ErrInvalidCarrier     = errors.New("shipping: invalid or unconfigured carrier")
	ErrInvalidSignature   = errors.New("shipping: invalid webhook signature")
	ErrCarrierUnavailable = errors.New("shipping: carrier API unavailable")
)
