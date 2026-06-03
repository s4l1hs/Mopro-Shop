package payment

import (
	"context"
	"fmt"
)

// ProviderFactory is a constructor registered by each PSP sub-package via init().
// The sipay sub-package calls RegisterProvider("sipay", ...) from its init().
// NewService looks up the factory when PSP_PROVIDER=sipay.
// import _ "github.com/mopro/platform/internal/payment/sipay" in main.go triggers init().
type ProviderFactory func(cfg SipayConfig, repo Repository) Service

var providerRegistry = map[string]ProviderFactory{}

// RegisterProvider registers a PSP factory under name.
// Called from PSP sub-package init() functions.
func RegisterProvider(name string, fn ProviderFactory) {
	providerRegistry[name] = fn
}

// NewService constructs the PSP adapter for the given provider name.
//
// A-001 (was T-016): provider selection is **caller-injected and error-returning**
// — no os.Getenv, no log.Fatal, no panic — so construction is testable without
// process-global env or os/exec subprocess tests. The caller (cmd/core-svc/main.go)
// reads PSP_PROVIDER and fails fast on the returned error (log.Fatal at main is the
// correct place for a startup invariant). Sipay requires cfg + repo and its
// sub-package to be blank-imported in main.go (its init() calls RegisterProvider);
// the stub adapters ignore cfg/repo.
func NewService(provider string, cfg SipayConfig, repo Repository) (Service, error) {
	switch provider {
	case "sipay":
		fn, ok := providerRegistry["sipay"]
		if !ok {
			return nil, ErrProviderNotRegistered
		}
		return fn(cfg, repo), nil
	case "craftgate":
		return &craftgateStub{}, nil
	case "iyzico":
		return &iyzicoStub{}, nil
	case "":
		return nil, ErrProviderRequired
	default:
		return nil, fmt.Errorf("%w: %q (valid: sipay|craftgate|iyzico)", ErrUnknownProvider, provider)
	}
}

// Compile-time checks: the stub adapters satisfy Service.
var (
	_ Service = (*craftgateStub)(nil)
	_ Service = (*iyzicoStub)(nil)
)

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
