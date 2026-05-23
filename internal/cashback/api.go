// Package cashback owns the v8 accelerated amortization cashback engine (fin-svc).
// v8 MODEL: fixed-term plans where T = CashbackK/commission_bps months, monthly payout
// = (price × commission_bps)/CashbackK, with a balloon last payment so the sum equals
// exactly the gross order price. See calculator.go for the formula and PROMPTS.md §2.2.
package cashback

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/mopro/platform/internal/ledger"
)

// OrderDeliveredEvent is the decoded payload from ecom.order.delivered.v1.
type OrderDeliveredEvent struct {
	OrderID     int64
	UserID      int64
	DeliveredAt time.Time
	Market      string
	Currency    string // fiat currency; service converts to coin currency
	// v8 direct fields — populated by the consumer from the event payload.
	PriceMinor    int64
	CommissionBps int
	// Items retains the per-line snapshot for the commission_snapshot audit column.
	Items []CommissionSnapshotItem
	// Product snapshot (Phase 4.4a additive). Zero for pre-4.4a events.
	ProductID       int64
	ProductTitle    string
	ProductImageURL string
}

// Service is the public interface of the cashback engine (fin-svc only).
type Service interface {
	// CreatePlanFromDelivery creates a v8 fixed-term cashback plan for the delivered order.
	// Idempotent: returns the existing plan if one already exists for ev.OrderID.
	CreatePlanFromDelivery(ctx context.Context, ev OrderDeliveredEvent) (Plan, error)

	// PayMonthlyInstallments processes all active plans whose next installment is due by runDate.
	// Designed to be called by the monthly cron on the 1st of each month.
	// Idempotent: re-running for an already-processed period is safe.
	PayMonthlyInstallments(ctx context.Context, runDate time.Time) (PaymentSummary, error)

	// GetPlan returns a single plan scoped to userID (IDOR-safe: 404 on cross-user access).
	GetPlan(ctx context.Context, userID, planID int64) (Plan, error)

	// ListPlans returns cursor-paginated plans for userID, ordered by id DESC.
	ListPlans(ctx context.Context, userID int64, cursor int64, limit int, status *PlanStatus) ([]Plan, error)
}

// WalletPoster is the subset of wallet.Service that cashback needs.
// Defined as an interface to keep the packages independently testable.
type WalletPoster interface {
	PostInTx(ctx context.Context, tx pgx.Tx, in ledger.PostInput) (int64, error)
	FindAccount(ctx context.Context, accountType, currency string) (int64, error)
	OpenOrFindUserWallet(ctx context.Context, userID int64, currency string) (int64, error)
	FindAccountByOwnerAnyStatus(ctx context.Context, ownerType string, ownerID int64, currency string) (int64, string, error)
}

// Repository is the storage interface of the cashback engine (fin-svc only).
type Repository interface {
	// Plan creation — idempotent via UNIQUE INDEX on order_id.
	// Returns (plan, true, nil) when newly inserted; (plan, false, nil) when already existed.
	InsertPlanIfAbsent(ctx context.Context, tx pgx.Tx, p Plan) (Plan, bool, error)

	// Payout cron: select active plans whose next installment is due by runDate.
	// Uses start_date + payments_made*interval'1 month' <= runDate to determine due date.
	// Caller holds the result for the duration of per-plan processing.
	ListDuePlans(ctx context.Context, runDate time.Time, limit int) ([]Plan, error)

	// Payout cron: within a SERIALIZABLE tx, increment payments_made by 1.
	// Returns the new payments_made counter and whether the plan is now completed.
	IncrPaymentsMade(ctx context.Context, tx pgx.Tx, planID int64) (newCount int, completed bool, err error)

	// HTTP read path — safe for direct repository calls per CLAUDE.md §3.1 exception.
	GetPlan(ctx context.Context, userID, planID int64) (Plan, error)
	ListPlansByUser(ctx context.Context, userID int64, limit int, beforeID int64, status *PlanStatus) ([]Plan, error)
	// ListPaymentsByPlanID is kept for backward compat with the fin HTTP API (v6 plans only).
	ListPaymentsByPlanID(ctx context.Context, planID int64, limit int, beforeID int64) ([]Payment, error)

	// Transaction control.
	// level must be pgx.Serializable for cron per-plan tx; pgx.ReadCommitted for plan creation.
	WithTx(ctx context.Context, level pgx.TxIsoLevel, fn func(pgx.Tx) error) error
}
