// Package refund (fin-svc) settles approved returns by minting the refund as Mopro
// Coin to the buyer's wallet (RT-01, refund-as-coin). It consumes
// ecom.return.refunded.v1 (emitted by core-svc on seller approval) and posts a
// balanced coin move: D equity:refund_distribution:<COIN> ↔ C the user wallet.
// It owns no schema — all ledger I/O goes through wallet.Service (§4.1/§5).
package refund

import (
	"context"

	"github.com/mopro/platform/internal/ledger"
)

// Wallet is the subset of wallet.Service the refund engine needs. wallet.Service
// satisfies it. Post starts its own SERIALIZABLE tx + outbox row and is idempotent
// on PostInput.IdempotencyKey (returns the original txn id on replay).
type Wallet interface {
	Post(ctx context.Context, in ledger.PostInput) (txnID int64, err error)
	FindAccount(ctx context.Context, accountType, currency string) (int64, error)
	OpenOrFindUserWallet(ctx context.Context, userID int64, currency string) (int64, error)
}

// RefundEvent is the decoded ecom.return.refunded.v1 payload.
type RefundEvent struct {
	ReturnID          int64
	OrderID           int64
	UserID            int64
	RefundAmountMinor int64
	Market            string
}

// Service settles a refund into the buyer's coin wallet.
type Service interface {
	// SettleRefund mints RefundAmountMinor as coin to the buyer. Idempotent via the
	// ledger key refund:<return_id> (a redelivered event posts once).
	SettleRefund(ctx context.Context, ev RefundEvent) error
}
