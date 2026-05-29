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

// ClaimPaymentInput is the per-installment payload for ClaimPaymentPeriod.
type ClaimPaymentInput struct {
	PlanID         int64
	PeriodYYYYMM   int       // derived from the cron's runDate, not the installment's scheduled month
	ScheduledDate  time.Time // start_date + (installmentN-1) months — audit value only
	AmountMinor    int64
	IdempotencyKey string // 'cashback:plan_<id>:period_<yyyymm>'
}

// Repository is the storage interface of the cashback engine (fin-svc only).
type Repository interface {
	// Plan creation — idempotent via UNIQUE INDEX on order_id.
	// Returns (plan, true, nil) when newly inserted; (plan, false, nil) when already existed.
	InsertPlanIfAbsent(ctx context.Context, tx pgx.Tx, p Plan) (Plan, bool, error)

	// Payout cron: select active plans whose next installment is due by runDate
	// AND have NO payment row for runPeriodYYYYMM yet. The period filter (via
	// NOT EXISTS against cashback_schema.payments) is what keeps the cron's
	// per-call cost bounded when many plans exist — without it, every active
	// plan re-enters the SERIALIZABLE tx loop and is rejected by ClaimPaymentPeriod's
	// UNIQUE, which is correct but quadratic.
	ListDuePlans(ctx context.Context, runDate time.Time, runPeriodYYYYMM int, limit int) ([]Plan, error)

	// PaymentExistsForPeriod is a cheap (pool-read) pre-check the cron uses
	// to skip plans already paid for the current run period without entering a
	// SERIALIZABLE tx. Correctness still flows from ClaimPaymentPeriod's
	// UNIQUE(plan_id, period_yyyymm) — this is purely an optimization to keep
	// the hot path fast as the payments table grows.
	PaymentExistsForPeriod(ctx context.Context, planID int64, periodYYYYMM int) (bool, error)

	// ClaimPaymentPeriod INSERTs a 'scheduled' payment row inside tx as the
	// first step of an installment payment. The UNIQUE(plan_id, period_yyyymm)
	// constraint is the v6 storage-layer idempotency guard: concurrent racers
	// for the same plan+period both attempt to INSERT, one succeeds and the
	// others skip the rest of the payment flow.
	// Returns (paymentID, true, nil) when the caller won the race; the caller
	// MUST proceed to PostInTx and MarkPaymentPaid inside the same tx.
	// Returns (0, false, nil) when another worker already claimed this period;
	// the caller MUST NOT call PostInTx or RefreshPaymentsMadeCache.
	ClaimPaymentPeriod(ctx context.Context, tx pgx.Tx, in ClaimPaymentInput) (int64, bool, error)

	// MarkPaymentPaid flips the row inserted by ClaimPaymentPeriod from
	// 'scheduled' to 'paid' and records the ledger transaction id + paid_date.
	// Called inside the same tx after PostInTx returns successfully.
	MarkPaymentPaid(ctx context.Context, tx pgx.Tx, paymentID int64, ledgerTxnID int64, paidDate time.Time) error

	// IncrPaymentsMade atomically increments payments_made by 1 within tx.
	// Returns the new counter and whether the plan is now completed (>= total_months).
	// NOTE (commit 2 of this PR will replace this with a COUNT-derived
	// RefreshPaymentsMadeCache; for commit 1 the counter still wins because
	// ClaimPaymentPeriod above ensures at most one winner per (plan, period)).
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
