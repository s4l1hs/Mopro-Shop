package payment

// Unit tests for the PSP provider registry/factory.
//
// A-001 (was T-016): NewService is now caller-injected + error-returning (no
// PSP_PROVIDER env, no log.Fatal), so every case is a plain error-return assertion.
// The os/exec subprocess test that the old log.Fatal path required is GONE — that
// ugliness was the finding. White-box; pure logic, no DB. Reuses fakeSvc
// (reconciler_test.go, same package) as the registered adapter double.

import (
	"context"
	"errors"
	"testing"
)

// withCleanRegistry saves + clears providerRegistry, restoring it on cleanup.
func withCleanRegistry(t *testing.T) {
	t.Helper()
	saved := providerRegistry
	providerRegistry = map[string]ProviderFactory{}
	t.Cleanup(func() { providerRegistry = saved })
}

// sipay path: the registered factory is invoked with the cfg and its Service returned.
func TestNewService_Sipay_UsesRegisteredFactory(t *testing.T) {
	withCleanRegistry(t)
	want := &fakeSvc{}
	var gotCfg SipayConfig
	RegisterProvider("sipay", func(cfg SipayConfig, _ Repository) Service {
		gotCfg = cfg
		return want
	})

	got, err := NewService("sipay", SipayConfig{BaseURL: "https://psp.example"}, nil)
	if err != nil {
		t.Fatalf("NewService(sipay) unexpected err: %v", err)
	}
	if got != want {
		t.Errorf("NewService(sipay) must return the registered factory's Service")
	}
	if gotCfg.BaseURL != "https://psp.example" {
		t.Errorf("factory must receive the cfg; got BaseURL=%q", gotCfg.BaseURL)
	}
}

// sipay with no registered factory → ErrProviderNotRegistered (was: panic).
func TestNewService_Sipay_NotRegistered_ReturnsError(t *testing.T) {
	withCleanRegistry(t) // empty → "sipay" not registered
	_, err := NewService("sipay", SipayConfig{}, nil)
	if !errors.Is(err, ErrProviderNotRegistered) {
		t.Errorf("want ErrProviderNotRegistered, got %v", err)
	}
}

// craftgate/iyzico return a stub whose every method yields ErrProviderNotImplemented.
func TestNewService_StubAdapters_NotImplemented(t *testing.T) {
	for _, provider := range []string{"craftgate", "iyzico"} {
		t.Run(provider, func(t *testing.T) {
			svc, err := NewService(provider, SipayConfig{}, nil)
			if err != nil {
				t.Fatalf("NewService(%s) unexpected err: %v", provider, err)
			}
			ctx := context.Background()
			checks := []func() error{
				func() error { _, e := svc.InitiatePayment(ctx, InitiatePaymentRequest{}); return e },
				func() error { _, e := svc.ConfirmWebhook(ctx, nil, ""); return e },
				func() error { _, e := svc.Refund(ctx, RefundRequest{}); return e },
				func() error { _, e := svc.CheckStatus(ctx, ""); return e },
				func() error { _, e := svc.RegisterSubMerchant(ctx, RegisterSubMerchantRequest{}); return e },
				func() error { _, e := svc.TransferToSeller(ctx, TransferToSellerRequest{}); return e },
			}
			for i, check := range checks {
				if err := check(); !errors.Is(err, ErrProviderNotImplemented) {
					t.Errorf("%s method[%d]: want ErrProviderNotImplemented, got %v", provider, i, err)
				}
			}
		})
	}
}

// Empty provider → ErrProviderRequired (was: log.Fatal, only testable via os/exec).
func TestNewService_EmptyProvider_ReturnsErrProviderRequired(t *testing.T) {
	_, err := NewService("", SipayConfig{}, nil)
	if !errors.Is(err, ErrProviderRequired) {
		t.Errorf("want ErrProviderRequired, got %v", err)
	}
}

// Unknown provider → ErrUnknownProvider (was: log.Fatalf).
func TestNewService_UnknownProvider_ReturnsErrUnknownProvider(t *testing.T) {
	_, err := NewService("bogus", SipayConfig{}, nil)
	if !errors.Is(err, ErrUnknownProvider) {
		t.Errorf("want ErrUnknownProvider, got %v", err)
	}
}

// RegisterProvider stores the factory under its name (independent of NewService).
func TestRegisterProvider_StoresUnderName(t *testing.T) {
	withCleanRegistry(t)
	RegisterProvider("sipay", func(SipayConfig, Repository) Service { return &fakeSvc{} })
	if _, ok := providerRegistry["sipay"]; !ok {
		t.Errorf("RegisterProvider must store the factory under its name")
	}
}
