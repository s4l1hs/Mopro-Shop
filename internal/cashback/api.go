// Package cashback owns the perpetual cashback engine: plan creation and monthly payments (fin-svc).
// v6 LOCKED PERPETUAL MODEL: monthly_coin = (commission_minor × ref_rate_bps) / 10000 / 12
// Reference interest rate is frozen at 5000 bps (50%) per plan at creation; NEVER changed for existing plans.
package cashback

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/mopro/platform/internal/ledger"
)

// OrderDeliveredEvent is the decoded payload from ecom.order.delivered.v1.
// Consumed by CreatePlanForOrder to create a v6 perpetual cashback plan.
type OrderDeliveredEvent struct {
	OrderID     int64
	UserID      int64
	DeliveredAt time.Time
	Market      string
	Currency    string // fiat currency from the order event; service converts to coin currency
	Items       []CommissionSnapshotItem
}

// Service is the public interface of the cashback engine (fin-svc only).
type Service interface {
	// CreatePlanForOrder creates a v6 perpetual cashback plan for the delivered order.
	// Idempotent: returns nil if a plan already exists for ev.OrderID.
	CreatePlanForOrder(ctx context.Context, ev OrderDeliveredEvent) error

	// RunMonth processes all active plans due for period (YYYYMM) as of asOf for the
	// given currency. Designed to be called by the monthly cron on the 1st of each month.
	// The currency parameter selects which coin currency to process (e.g. "TRY_COIN").
	// Idempotent: re-running for an already-processed period is safe.
	RunMonth(ctx context.Context, period int, asOf time.Time, currency string) (RunMonthResult, error)
}

// WalletPoster is the subset of wallet.Service that cashback needs.
// Using an interface instead of importing the wallet package keeps the packages
// independently testable. Go structural typing means wallet.Service satisfies
// this interface without any code change in the wallet package.
type WalletPoster interface {
	PostInTx(ctx context.Context, tx pgx.Tx, in ledger.PostInput) (int64, error)
	FindAccount(ctx context.Context, accountType, currency string) (int64, error)
	OpenOrFindUserWallet(ctx context.Context, userID int64, currency string) (int64, error)
}

// Repository is the storage interface of the cashback engine (fin-svc only).
type Repository interface {
	// Plan creation path.
	InsertPlan(ctx context.Context, tx pgx.Tx, p Plan) (Plan, error)
	FindPlanByOrderID(ctx context.Context, orderID int64) (Plan, error)

	// Cron path: batch cursor SELECT.
	FetchPlansBatch(ctx context.Context, period int, asOf time.Time, currency string, batchSize int) ([]Plan, error)

	// Cron path: payment write.
	InsertPayment(ctx context.Context, tx pgx.Tx, pay Payment) (Payment, error)
	MarkPaymentPaid(ctx context.Context, tx pgx.Tx, paymentID int64, ledgerTxnID int64, paidDate time.Time) error
	MarkPaymentFailed(ctx context.Context, tx pgx.Tx, paymentID int64, errMsg string) error

	// Cron path: post-payment plan stamp.
	UpdateLastDistributedPeriod(ctx context.Context, tx pgx.Tx, planID int64, period int) error

	// Cron path: wallet account status check.
	GetWalletAccountStatus(ctx context.Context, accountID int64) (string, error)

	// Transaction control.
	// level must be pgx.Serializable for cron per-plan tx; pgx.ReadCommitted for plan creation.
	WithTx(ctx context.Context, level pgx.TxIsoLevel, fn func(pgx.Tx) error) error
}
