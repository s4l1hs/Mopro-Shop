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

	// ErrInvalidInstallments is returned when the requested card-installment count
	// (PD-05, taksit) is not one of the supported values. 0 is tolerated as
	// "unset" and normalized to 1 (single charge) by the adapter.
	ErrInvalidInstallments = errors.New("payment: installments must be one of 1, 3, 6, 9, 12")

	// ErrProviderRequired is returned by NewService when the provider name is empty
	// (A-001: construction is now caller-injected + error-returning, not log.Fatal).
	ErrProviderRequired = errors.New("payment: provider required (sipay|craftgate|iyzico)")

	// ErrUnknownProvider is returned by NewService for an unrecognised provider name.
	ErrUnknownProvider = errors.New("payment: unknown provider")

	// ErrProviderNotRegistered is returned when a known provider (sipay) needs an
	// init()-registered factory but the sub-package wasn't imported (blank import in main.go).
	ErrProviderNotRegistered = errors.New("payment: provider factory not registered (missing blank import)")
)
