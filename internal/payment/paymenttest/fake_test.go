package paymenttest_test

import (
	"context"
	"errors"
	"testing"

	"github.com/mopro/platform/internal/payment"
	"github.com/mopro/platform/internal/payment/paymenttest"
)

// The fake must satisfy the production interface (also asserted in fake.go).
var _ payment.Service = (*paymenttest.Fake)(nil)

func TestFake_Refund_RecordsArgsAndReturnsConfigured(t *testing.T) {
	wantErr := errors.New("declined")
	f := &paymenttest.Fake{RefundErr: wantErr}
	req := payment.RefundRequest{AmountMinor: 1500}

	_, err := f.Refund(context.Background(), req)

	if !errors.Is(err, wantErr) {
		t.Fatalf("Refund err = %v, want %v", err, wantErr)
	}
	if f.LastRefund == nil || f.LastRefund.AmountMinor != 1500 {
		t.Fatalf("LastRefund not recorded: %+v", f.LastRefund)
	}
	if f.Calls != 1 {
		t.Fatalf("Calls = %d, want 1", f.Calls)
	}
}

func TestFake_ZeroValue_IsUsableNoOp(t *testing.T) {
	f := &paymenttest.Fake{}
	if _, err := f.CheckStatus(context.Background(), "psp-ref-1"); err != nil {
		t.Fatalf("zero-value fake CheckStatus err = %v, want nil", err)
	}
	if f.LastStatusRef != "psp-ref-1" {
		t.Fatalf("LastStatusRef = %q, want psp-ref-1", f.LastStatusRef)
	}
	if f.Calls != 1 {
		t.Fatalf("Calls = %d, want 1", f.Calls)
	}
}

func TestFake_Webhook_RecordsBodyAndSig(t *testing.T) {
	f := &paymenttest.Fake{}
	_, _ = f.ConfirmWebhook(context.Background(), []byte(`{"x":1}`), "sig-abc")
	if string(f.LastWebhook) != `{"x":1}` || f.LastWebhookSig != "sig-abc" {
		t.Fatalf("webhook not recorded: body=%q sig=%q", f.LastWebhook, f.LastWebhookSig)
	}
}
