package payment

import (
	"context"
	"log"
	"os"
)

// NewService constructs the active PSP adapter from PSP_PROVIDER env.
// Calls log.Fatal for unknown or missing PSP_PROVIDER (startup invariant; Q1).
// Sipay requires cfg and repo; stub adapters ignore them.
// The sipay sub-package is registered by Commit 6 (Track A); until then
// PSP_PROVIDER=sipay panics with a clear message.
func NewService(cfg SipayConfig, repo Repository) Service {
	switch v := os.Getenv("PSP_PROVIDER"); v {
	case "sipay":
		// Wired in Commit 6 (Track A). Panics here until sipay package is added.
		// TODO(sipay): replace with sipay.NewAdapter(cfg, repo)
		panic("payment: sipay adapter not yet wired — see Track A Commit 6")
	case "craftgate":
		return &craftgateStub{}
	case "iyzico":
		return &iyzicoStub{}
	case "":
		log.Fatal("payment: PSP_PROVIDER env required (sipay|craftgate|iyzico)")
	default:
		log.Fatalf("payment: PSP_PROVIDER=%q unknown; valid: sipay|craftgate|iyzico", v)
	}
	panic("unreachable") // log.Fatal exits; compiler requires this
}

// craftgateStub is a placeholder adapter; PSP_PROVIDER=craftgate is not implemented in v1.
type craftgateStub struct{}

func (craftgateStub) InitiatePayment(_ context.Context, _ InitiatePaymentRequest) (InitiatePaymentResponse, error) {
	return InitiatePaymentResponse{}, ErrProviderNotImplemented
}
func (craftgateStub) ConfirmWebhook(_ context.Context, _ []byte, _ string) (PaymentEvent, error) {
	return PaymentEvent{}, ErrProviderNotImplemented
}
func (craftgateStub) Refund(_ context.Context, _ RefundRequest) (RefundResponse, error) {
	return RefundResponse{}, ErrProviderNotImplemented
}
func (craftgateStub) CheckStatus(_ context.Context, _ string) (PaymentStatus, error) {
	return PaymentStatusUnknown, ErrProviderNotImplemented
}
func (craftgateStub) RegisterSubMerchant(_ context.Context, _ RegisterSubMerchantRequest) (SubMerchantRef, error) {
	return SubMerchantRef{}, ErrProviderNotImplemented
}
func (craftgateStub) TransferToSeller(_ context.Context, _ TransferToSellerRequest) (TransferRef, error) {
	return TransferRef{}, ErrProviderNotImplemented
}

// iyzicoStub is a placeholder adapter; PSP_PROVIDER=iyzico is not implemented in v1.
type iyzicoStub struct{}

func (iyzicoStub) InitiatePayment(_ context.Context, _ InitiatePaymentRequest) (InitiatePaymentResponse, error) {
	return InitiatePaymentResponse{}, ErrProviderNotImplemented
}
func (iyzicoStub) ConfirmWebhook(_ context.Context, _ []byte, _ string) (PaymentEvent, error) {
	return PaymentEvent{}, ErrProviderNotImplemented
}
func (iyzicoStub) Refund(_ context.Context, _ RefundRequest) (RefundResponse, error) {
	return RefundResponse{}, ErrProviderNotImplemented
}
func (iyzicoStub) CheckStatus(_ context.Context, _ string) (PaymentStatus, error) {
	return PaymentStatusUnknown, ErrProviderNotImplemented
}
func (iyzicoStub) RegisterSubMerchant(_ context.Context, _ RegisterSubMerchantRequest) (SubMerchantRef, error) {
	return SubMerchantRef{}, ErrProviderNotImplemented
}
func (iyzicoStub) TransferToSeller(_ context.Context, _ TransferToSellerRequest) (TransferRef, error) {
	return TransferRef{}, ErrProviderNotImplemented
}
