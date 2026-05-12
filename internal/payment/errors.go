package payment

import "errors"

var (
	// ErrProviderNotImplemented is returned by stub adapters (craftgate, iyzico).
	ErrProviderNotImplemented = errors.New("payment: provider not implemented in v1; PSP_PROVIDER=sipay only")

	// ErrInvalidSignature is returned by ConfirmWebhook when the PSP signature fails.
	ErrInvalidSignature = errors.New("payment: invalid webhook signature")

	// ErrPaymentNotFound is returned when a PaymentIntent lookup finds no row.
	ErrPaymentNotFound = errors.New("payment: payment intent not found")

	// ErrPaymentAlreadyCaptured is returned by InitiatePayment when a second
	// initiation attempt targets an already-captured payment.
	ErrPaymentAlreadyCaptured = errors.New("payment: payment already captured")

	// ErrSubMerchantNotFound is returned when a sub-merchant lookup finds no row.
	ErrSubMerchantNotFound = errors.New("payment: sub-merchant not found")

	// ErrInvalidAmount is returned when an amount is zero or negative.
	ErrInvalidAmount = errors.New("payment: amount must be positive")
)
