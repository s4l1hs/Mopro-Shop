package payment

// Unit tests for the PSP provider registry/factory (TESTING_AUDIT F-002 slice).
// White-box: NewService dispatches on PSP_PROVIDER over the package-global
// providerRegistry. Pure logic, no DB. See docs/internal/payment-service.md.
//
// Reuses fakeSvc (reconciler_test.go, same package, default tags) as the registered
// adapter double. providerRegistry is saved/restored around tests that mutate it.

import (
	"context"
	"errors"
	"os"
	"os/exec"
	"testing"
)

// withCleanRegistry saves + clears providerRegistry, restoring it on cleanup.
func withCleanRegistry(t *testing.T) {
	t.Helper()
	saved := providerRegistry
	providerRegistry = map[string]ProviderFactory{}
	t.Cleanup(func() { providerRegistry = saved })
}

// Exercises the sipay path: a registered factory is invoked and its Service returned.
func TestNewService_Sipay_UsesRegisteredFactory(t *testing.T) {
	withCleanRegistry(t)
	want := &fakeSvc{}
	var gotCfg SipayConfig
	RegisterProvider("sipay", func(cfg SipayConfig, _ Repository) Service {
		gotCfg = cfg
		return want
	})
	t.Setenv("PSP_PROVIDER", "sipay")

	got := NewService(SipayConfig{BaseURL: "https://psp.example"}, nil)
	if got != want {
		t.Errorf("NewService(sipay) must return the registered factory's Service")
	}
	if gotCfg.BaseURL != "https://psp.example" {
		t.Errorf("factory must receive the cfg; got BaseURL=%q", gotCfg.BaseURL)
	}
}

// Exercises the wiring-error path: PSP_PROVIDER=sipay with no registered factory panics
// (the "forgot the blank import" startup guard).
func TestNewService_Sipay_NotRegistered_Panics(t *testing.T) {
	withCleanRegistry(t) // empty → "sipay" not registered
	t.Setenv("PSP_PROVIDER", "sipay")
	defer func() {
		if r := recover(); r == nil {
			t.Errorf("NewService(sipay) must panic when the adapter is not registered")
		}
	}()
	_ = NewService(SipayConfig{}, nil)
}

// Exercises the stub adapters: craftgate/iyzico return a stub whose every method yields
// ErrProviderNotImplemented (the v1 "sipay only" contract).
func TestNewService_StubAdapters_NotImplemented(t *testing.T) {
	for _, provider := range []string{"craftgate", "iyzico"} {
		t.Run(provider, func(t *testing.T) {
			t.Setenv("PSP_PROVIDER", provider)
			svc := NewService(SipayConfig{}, nil)
			if svc == nil {
				t.Fatal("stub adapter must be non-nil")
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

// RegisterProvider stores the factory under its name (independent of NewService).
func TestRegisterProvider_StoresUnderName(t *testing.T) {
	withCleanRegistry(t)
	RegisterProvider("sipay", func(SipayConfig, Repository) Service { return &fakeSvc{} })
	if _, ok := providerRegistry["sipay"]; !ok {
		t.Errorf("RegisterProvider must store the factory under its name")
	}
}

// Exercises the startup invariant: PSP_PROVIDER unset → log.Fatal (process exit).
// Standard re-exec idiom — the child runs the same test with BE_FATAL=1 and must exit non-zero.
func TestNewService_MissingProvider_FatalExit(t *testing.T) {
	if os.Getenv("BE_FATAL") == "1" {
		os.Unsetenv("PSP_PROVIDER")
		NewService(SipayConfig{}, nil) // log.Fatal → os.Exit(1)
		return                         // unreachable if Fatal fired
	}
	cmd := exec.Command(os.Args[0], "-test.run=^TestNewService_MissingProvider_FatalExit$")
	cmd.Env = append(os.Environ(), "BE_FATAL=1")
	err := cmd.Run()
	var exitErr *exec.ExitError
	if !errors.As(err, &exitErr) || exitErr.Success() {
		t.Fatalf("missing PSP_PROVIDER must exit non-zero (log.Fatal); got %v", err)
	}
}
