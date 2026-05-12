// Package payment manages PSP adapter integration (Sipay, Craftgate, Stripe, etc.).
// The Service interface is provider-agnostic; the active provider is selected via
// PSP_PROVIDER env at startup. CLAUDE.md § 9.
package payment

import (
	"context"

	"github.com/jackc/pgx/v5"
)

// Service is the provider-agnostic payment interface.
// All methods must be safe to call concurrently.
type Service interface {
	// InitiatePayment creates a 3D-Secure payment session.
	// Returns the HTML fragment the mobile WebView renders for card entry.
	// Card data NEVER passes through Mopro (SAQ-A scope).
	InitiatePayment(ctx context.Context, req InitiatePaymentRequest) (InitiatePaymentResponse, error)

	// ConfirmWebhook validates the provider signature on an incoming webhook body,
	// then returns a normalised PaymentEvent. Returns ErrInvalidSignature on failure.
	ConfirmWebhook(ctx context.Context, rawBody []byte, sig string) (PaymentEvent, error)

	// Refund issues a full or partial refund for a captured payment.
	// RefundRequest.AmountMinor == 0 means full refund.
	Refund(ctx context.Context, req RefundRequest) (RefundResponse, error)

	// CheckStatus polls the provider for the current payment lifecycle status.
	// Used as fallback when a webhook is missed or delayed.
	CheckStatus(ctx context.Context, providerRef string) (PaymentStatus, error)

	// RegisterSubMerchant creates a sub-merchant account for a seller at the PSP.
	// TODO(seller-module): the seller approval flow will call this method when the
	// seller module is implemented. For Phase 1.4 it is exercised only by integration
	// tests; no production HTTP caller exists yet.
	RegisterSubMerchant(ctx context.Context, req RegisterSubMerchantRequest) (SubMerchantRef, error)

	// TransferToSeller sends the seller's net payout amount to their registered bank.
	// Called by the seller-payout daily cron (sellerpayout.Service) when unlock_at <= now.
	TransferToSeller(ctx context.Context, req TransferToSellerRequest) (TransferRef, error)
}

// Repository persists payment intents in order_schema.payments (CLAUDE.md § 4.4).
// All write methods MUST be called within the same DB transaction as surrounding
// order state updates to satisfy the outbox pattern (CLAUDE.md § 4.5).
type Repository interface {
	// InsertPaymentIntent writes a new pending payment intent within tx.
	InsertPaymentIntent(ctx context.Context, tx pgx.Tx, p PaymentIntent) (PaymentIntent, error)

	// FindPaymentIntentByIdempotencyKey returns a PaymentIntent by idempotency key.
	// Returns ErrPaymentNotFound if not found.
	FindPaymentIntentByIdempotencyKey(ctx context.Context, key string) (PaymentIntent, error)

	// UpdatePaymentStatus updates the status and relevant timestamp fields within tx.
	UpdatePaymentStatus(ctx context.Context, tx pgx.Tx, providerRef string, status PaymentStatus,
		capturedAt, failedAt, refundedAt *string, failureReason, refundRef string,
		refundAmountMinor int64) error

	// WithTx begins a transaction and calls fn within it, committing on nil return.
	WithTx(ctx context.Context, fn func(pgx.Tx) error) error
}
