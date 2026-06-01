package main

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"testing"

	"github.com/mopro/platform/internal/seller"
)

func newAuthHandlersForBinding(fn func(ctx context.Context, userID int64) (*seller.Binding, error)) *authHandlers {
	return &authHandlers{
		log:           slog.New(slog.NewTextHandler(io.Discard, nil)),
		sellerBinding: fn,
	}
}

func TestResolveSellerBinding_NilHookYieldsNull(t *testing.T) {
	a := &authHandlers{log: slog.New(slog.NewTextHandler(io.Discard, nil))}
	if b := a.resolveSellerBinding(context.Background(), 1); b != nil {
		t.Errorf("nil hook: want nil, got %#v", b)
	}
}

func TestResolveSellerBinding_BoundUser(t *testing.T) {
	want := &seller.Binding{SellerID: 1, Slug: "acme-store", Name: "Acme Store", Role: "owner"}
	a := newAuthHandlersForBinding(func(_ context.Context, userID int64) (*seller.Binding, error) {
		if userID != 7 {
			t.Fatalf("userID: want 7 got %d", userID)
		}
		return want, nil
	})
	got := a.resolveSellerBinding(context.Background(), 7)
	if got == nil || got.SellerID != 1 || got.Slug != "acme-store" || got.Role != "owner" {
		t.Errorf("binding mismatch: %#v", got)
	}
}

func TestResolveSellerBinding_NonSellerAndErrorYieldNull(t *testing.T) {
	// Unbound → (nil, nil) → null.
	a := newAuthHandlersForBinding(func(context.Context, int64) (*seller.Binding, error) {
		return nil, nil
	})
	if b := a.resolveSellerBinding(context.Background(), 9); b != nil {
		t.Errorf("unbound: want nil, got %#v", b)
	}
	// Lookup error → null (logged, not surfaced).
	aErr := newAuthHandlersForBinding(func(context.Context, int64) (*seller.Binding, error) {
		return nil, errors.New("db down")
	})
	if b := aErr.resolveSellerBinding(context.Background(), 9); b != nil {
		t.Errorf("error path: want nil, got %#v", b)
	}
}
