// Package paymenttest provides a configurable fake payment.Service for tests
// (ARCHITECTURE_AUDIT A-001). Like net/http/httptest: importable by any test that
// needs to exercise a payment.Service consumer without a real PSP gateway. The
// always-error stub adapters (craftgateStub/iyzicoStub) can't model happy paths;
// this fake can.
package paymenttest

import (
	"context"

	"github.com/mopro/platform/internal/payment"
)

// Fake is a configurable payment.Service. Set the *Result / *Err fields to control
// each method's return; read the Last* fields + Calls to assert. The zero value is
// a usable no-op (returns zero values, nil errors). Not safe for concurrent
// configuration, but the recorded fields are fine to read after calls complete.
type Fake struct {
	InitiateResult payment.InitiatePaymentResponse
	InitiateErr    error
	ConfirmResult  payment.PaymentEvent
	ConfirmErr     error
	RefundResult   payment.RefundResponse
	RefundErr      error
	StatusResult   payment.PaymentStatus
	StatusErr      error
	SubMerchResult payment.SubMerchantRef
	SubMerchErr    error
	TransferResult payment.TransferRef
	TransferErr    error

	// Recording — last request per method (nil pointer / zero = not called).
	LastInitiate   *payment.InitiatePaymentRequest
	LastWebhook    []byte
	LastWebhookSig string
	LastRefund     *payment.RefundRequest
	LastStatusRef  string
	LastSubMerch   *payment.RegisterSubMerchantRequest
	LastTransfer   *payment.TransferToSellerRequest
	Calls          int
}

// Compile-time check: Fake satisfies the production payment.Service interface.
var _ payment.Service = (*Fake)(nil)

func (f *Fake) InitiatePayment(_ context.Context, req payment.InitiatePaymentRequest) (payment.InitiatePaymentResponse, error) {
	f.Calls++
	f.LastInitiate = &req
	return f.InitiateResult, f.InitiateErr
}

func (f *Fake) ConfirmWebhook(_ context.Context, rawBody []byte, sig string) (payment.PaymentEvent, error) {
	f.Calls++
	f.LastWebhook = rawBody
	f.LastWebhookSig = sig
	return f.ConfirmResult, f.ConfirmErr
}

func (f *Fake) Refund(_ context.Context, req payment.RefundRequest) (payment.RefundResponse, error) {
	f.Calls++
	f.LastRefund = &req
	return f.RefundResult, f.RefundErr
}

func (f *Fake) CheckStatus(_ context.Context, providerRef string) (payment.PaymentStatus, error) {
	f.Calls++
	f.LastStatusRef = providerRef
	return f.StatusResult, f.StatusErr
}

func (f *Fake) RegisterSubMerchant(_ context.Context, req payment.RegisterSubMerchantRequest) (payment.SubMerchantRef, error) {
	f.Calls++
	f.LastSubMerch = &req
	return f.SubMerchResult, f.SubMerchErr
}

func (f *Fake) TransferToSeller(_ context.Context, req payment.TransferToSellerRequest) (payment.TransferRef, error) {
	f.Calls++
	f.LastTransfer = &req
	return f.TransferResult, f.TransferErr
}
