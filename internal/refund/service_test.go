package refund

import (
	"context"
	"errors"
	"testing"

	"github.com/mopro/platform/internal/ledger"
)

type fakeWallet struct {
	posts          []ledger.PostInput
	equityID       int64
	userID         int64
	findErr        error
	openErr        error
	postErr        error
	openedUser     int64
	openedCurrency string
}

func (f *fakeWallet) FindAccount(_ context.Context, _ string, _ string) (int64, error) {
	return f.equityID, f.findErr
}
func (f *fakeWallet) OpenOrFindUserWallet(_ context.Context, userID int64, currency string) (int64, error) {
	f.openedUser, f.openedCurrency = userID, currency
	return f.userID, f.openErr
}
func (f *fakeWallet) Post(_ context.Context, in ledger.PostInput) (int64, error) {
	if f.postErr != nil {
		return 0, f.postErr
	}
	f.posts = append(f.posts, in)
	return int64(len(f.posts)), nil
}

func TestSettleRefund_PostsBalancedCoinCredit(t *testing.T) {
	w := &fakeWallet{equityID: 90, userID: 42}
	s := NewService(w, "TRY_COIN", nil)

	err := s.SettleRefund(context.Background(), RefundEvent{
		ReturnID: 5, OrderID: 1, UserID: 7, RefundAmountMinor: 8000, Market: "TR",
	})
	if err != nil {
		t.Fatalf("SettleRefund: %v", err)
	}
	if w.openedUser != 7 || w.openedCurrency != "TRY_COIN" {
		t.Errorf("user wallet resolved for (%d,%q), want (7,TRY_COIN)", w.openedUser, w.openedCurrency)
	}
	if len(w.posts) != 1 {
		t.Fatalf("want 1 post, got %d", len(w.posts))
	}
	p := w.posts[0]
	if p.IdempotencyKey != "refund:5" {
		t.Errorf("idempotency key=%q want refund:5", p.IdempotencyKey)
	}
	if p.Currency != "TRY_COIN" || p.Type != "refund_settlement" || p.EventType != "fin.refund.coin.credited.v1" {
		t.Errorf("post header mismatch: %+v", p)
	}
	// Balanced: D equity:90 8000, C user:42 8000.
	debit := entry(t, p.Entries, ledger.Debit)
	credit := entry(t, p.Entries, ledger.Credit)
	if debit.AccountID != 90 || debit.AmountMinor != 8000 {
		t.Errorf("debit leg = %+v, want {acct 90, 8000}", debit)
	}
	if credit.AccountID != 42 || credit.AmountMinor != 8000 {
		t.Errorf("credit leg = %+v, want {acct 42, 8000}", credit)
	}
}

// entry returns the single entry with the given direction, failing otherwise.
func entry(t *testing.T, entries []ledger.Entry, dir ledger.EntryDirection) ledger.Entry {
	t.Helper()
	var found []ledger.Entry
	for _, e := range entries {
		if e.Direction == dir {
			found = append(found, e)
		}
	}
	if len(found) != 1 {
		t.Fatalf("want exactly 1 %q entry, got %d (entries=%+v)", dir, len(found), entries)
	}
	return found[0]
}

func TestSettleRefund_ZeroAmountSkips(t *testing.T) {
	w := &fakeWallet{equityID: 90, userID: 42}
	s := NewService(w, "TRY_COIN", nil)
	if err := s.SettleRefund(context.Background(), RefundEvent{ReturnID: 5, RefundAmountMinor: 0}); err != nil {
		t.Fatalf("zero amount should ack without error, got %v", err)
	}
	if len(w.posts) != 0 {
		t.Errorf("zero amount must not post, got %d posts", len(w.posts))
	}
}

func TestSettleRefund_PropagatesPostError(t *testing.T) {
	w := &fakeWallet{equityID: 90, userID: 42, postErr: errors.New("boom")}
	s := NewService(w, "TRY_COIN", nil)
	// A post failure must propagate (→ message stays in PEL for idempotent redelivery).
	if err := s.SettleRefund(context.Background(), RefundEvent{ReturnID: 5, RefundAmountMinor: 8000}); err == nil {
		t.Fatal("want error propagated, got nil")
	}
}
