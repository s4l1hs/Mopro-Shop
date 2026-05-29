// Package orderledger consumes ecom.order.paid.v1 and posts the balanced
// ledger entry (DR psp_receivable / CR seller_payable + commission +
// kdv_payable [+ shipping_payable]) to wallet_schema for each paid order.
//
// One commission.CapturePosting audit row per order is written atomically
// in the same SERIALIZABLE transaction as the wallet PostInTx call. The
// audit row is persisted through the commission.CaptureRecorder seam
// (injected via NewService) — orderledger does not reach into
// commission_schema directly. See internal/commission/capture_recorder.go
// for the schema-owning implementation.
package orderledger

import (
	"context"

	"github.com/jackc/pgx/v5"

	"github.com/mopro/platform/internal/ledger"
)

// Service is the public interface of the orderledger module.
type Service interface {
	// PostCapture posts the balanced ledger entry for a paid order.
	// Idempotent: returns nil if the order has already been posted.
	PostCapture(ctx context.Context, ev OrderPaidEvent) error
}

// WalletPoster is the subset of wallet.Service used by the orderledger service.
// wallet.Service satisfies this interface via Go structural typing;
// no orderledger→wallet package import is introduced.
type WalletPoster interface {
	PostInTx(ctx context.Context, tx pgx.Tx, in ledger.PostInput) (int64, error)
	FindAccount(ctx context.Context, accountType, currency string) (int64, error)
	FindOrOpenSellerPayable(ctx context.Context, sellerID int64, currency string) (int64, error)
}
