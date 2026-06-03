package payment

import (
	"encoding/json"
	"time"
)

// InitiatePaymentRequest carries all non-card fields needed to start a 3DS session.
// Card data is NEVER present — Mopro is SAQ-A; the PSP hosts the card entry form.
type InitiatePaymentRequest struct {
	OrderID        int64
	AmountMinor    int64
	Currency       string // fiat currency code; never hardcoded — read from order
	IdempotencyKey string // from Idempotency-Key HTTP header
	BuyerName      string // PII; decrypted transiently by caller
	BuyerSurname   string
	BuyerEmail     string
	BuyerPhone     string
	Market         string
	ReturnURL      string // 3DS redirect on success
	CancelURL      string // 3DS redirect on cancel
}

// InitiatePaymentResponse is the payload returned to the caller.
type InitiatePaymentResponse struct {
	ProviderRef string    // Sipay invoice_id = IdempotencyKey from request
	ThreeDSHTML string    // raw HTML fragment the mobile renders in a WebView
	ThreeDSURL  string    // 3DS redirect URL for web clients (extracted from ThreeDSHTML form action)
	ExpiresAt   time.Time // payment session expiry (~30 min from now)
}

// PaymentEventType classifies a normalised webhook event.
type PaymentEventType string

const (
	PaymentEventCaptured PaymentEventType = "captured"
	PaymentEventFailed   PaymentEventType = "failed"
	PaymentEventRefunded PaymentEventType = "refunded"
)

// PaymentEvent is the provider-agnostic representation of a PSP webhook.
// Produced by ConfirmWebhook after signature validation.
type PaymentEvent struct {
	Type              PaymentEventType
	OrderID           int64  // resolved from ProviderRef via payment repository
	ProviderRef       string // our invoice_id / idempotency_key
	ProviderOrderNo   string // PSP's internal reference (for support)
	AmountMinor       int64
	Currency          string
	OccurredAt        time.Time
	FailureReason     string // set when Type == PaymentEventFailed
	RefundRef         string // set when Type == PaymentEventRefunded
	RefundAmountMinor int64  // set when Type == PaymentEventRefunded
	IsFullRefund      bool   // set when Type == PaymentEventRefunded
}

// PaymentStatus is the lifecycle state of a payment.
type PaymentStatus string

const (
	PaymentStatusPending  PaymentStatus = "pending"
	PaymentStatusCaptured PaymentStatus = "captured"
	PaymentStatusFailed   PaymentStatus = "failed"
	PaymentStatusRefunded PaymentStatus = "refunded"
	PaymentStatusUnknown  PaymentStatus = "unknown"
)

// RefundRequest initiates a full or partial refund.
// AmountMinor == 0 means full refund (adapter converts to provider convention).
type RefundRequest struct {
	ProviderRef    string
	AmountMinor    int64
	IdempotencyKey string
	OrderID        int64
}

// RefundResponse is the provider's acknowledgement of a refund.
type RefundResponse struct {
	RefundRef   string
	RefundedAt  time.Time
	AmountMinor int64
}

// RegisterSubMerchantRequest carries seller banking details for PSP onboarding.
// All PII fields must be decrypted transiently by the caller; they are not stored
// in this struct beyond the duration of the API call.
type RegisterSubMerchantRequest struct {
	SellerID  int64
	Name      string // business name
	TaxNumber string // TR: vergi kimlik numarası (PII)
	IBAN      string // bank IBAN (PII)
	Address   string
	Market    string
}

// SubMerchantRef is the PSP's persistent handle for a sub-merchant.
// The ProviderMemberID must be stored in seller_schema.sellers.sipay_member_id.
type SubMerchantRef struct {
	ProviderMemberID string
	RegisteredAt     time.Time
}

// TransferToSellerRequest triggers a bank settlement to a registered sub-merchant.
// Called by the seller-payout daily cron when unlock_at <= now.
type TransferToSellerRequest struct {
	SellerID         int64
	ProviderMemberID string // from seller_schema.sellers.sipay_member_id
	PayoutID         int64
	AmountMinor      int64
	Currency         string
	IdempotencyKey   string // "payout:<payout_id>"
	Market           string
}

// TransferRef is the PSP's acknowledgement of a sub-merchant settlement.
type TransferRef struct {
	ProviderTransferID string
	TransferredAt      time.Time
}

// PaymentIntent is the persistent record for a payment initiation.
// Stored in order_schema.payments (migration 70-payments.sql).
type PaymentIntent struct {
	ID                int64
	OrderID           int64
	IdempotencyKey    string
	Provider          string
	ProviderRef       string
	ProviderOrderNo   string
	Status            PaymentStatus
	AmountMinor       int64
	Currency          string
	CapturedAt        *time.Time
	FailedAt          *time.Time
	FailureReason     string
	RefundedAt        *time.Time
	RefundRef         string
	RefundAmountMinor int64
	RawResponse       json.RawMessage // PCI-SAFE: no card data — see 70-payments.sql
	CreatedAt         time.Time
	UpdatedAt         time.Time
}

// SipayConfig holds all Sipay-specific configuration.
// Values come from env vars and are injected at startup.
type SipayConfig struct {
	BaseURL     string // SIPAY_BASE_URL
	MerchantKey string // SIPAY_MERCHANT_KEY
	AppID       string // SIPAY_APP_ID
	AppSecret   string // SIPAY_APP_SECRET
	MerchantID  string // SIPAY_MERCHANT_ID
	ReturnURL   string // SIPAY_RETURN_URL
	CancelURL   string // SIPAY_CANCEL_URL
	Environment string // GO_ENV — "production" triggers the prod-safety guard (A-003: was os.Getenv in validateConfig)
}
