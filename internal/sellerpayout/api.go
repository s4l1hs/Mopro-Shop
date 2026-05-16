// Package sellerpayout owns the seller net payout engine: scheduling, unlock, and daily cron (fin-svc).
// unlock_at = delivered_at + 3 business days via pkg/timex.AddBusinessDays.
// Net amount = gross - commission - KDV; all amounts frozen at order completion (CLAUDE.md § 4.8).
package sellerpayout

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/mopro/platform/internal/ledger"
)

// OrderDeliveredEvent is the decoded payload from ecom.order.delivered.v1.
// Consumed by SchedulePayoutsForOrder to create per-seller payout rows.
type OrderDeliveredEvent struct {
	OrderID     int64
	DeliveredAt time.Time
	Market      string
	Currency    string
	Items       []DeliveredItem
}

// DeliveredItem holds the per-item commission snapshot from the delivered order event.
type DeliveredItem struct {
	SellerID       int64
	SellerNetMinor int64
}

// Service is the public interface of the seller payout engine (fin-svc only).
type Service interface {
	// SchedulePayoutsForOrder creates one payout row per seller for the delivered order.
	// Payouts are aggregated by seller (one row per seller regardless of item count).
	// Idempotent: returns nil if payouts already exist for this order.
	SchedulePayoutsForOrder(ctx context.Context, ev OrderDeliveredEvent) error

	// RunDailyPayouts groups all scheduled payouts due on payoutDate into per-seller
	// batches and processes each via the 3-phase sandwich (Tx1 → PSP → Tx2).
	// Returns a summary of the run without returning per-batch errors to the cron caller.
	RunDailyPayouts(ctx context.Context, payoutDate time.Time, market, currency string) (RunDailyResult, error)

	// ReconcileProcessing finds payout_batches stuck in 'processing' (crashed between
	// PSP call and Tx2) and retries the Tx2 phase, or marks them ambiguous.
	ReconcileProcessing(ctx context.Context) error

	// HandlePspOnboarded persists a seller's PSP registration on the ledger side.
	// Called by the psp_event_handler consumer (ecom.seller.psp_onboarded.v1).
	HandlePspOnboarded(ctx context.Context, ev PspOnboardedEvent) error

	// HandleFraudHoldSet inserts a ledger_alerts row linking the alert to any in-flight
	// payout batch for the affected seller. The batch is left in 'processing'; ReconcileProcessing
	// will detect the open alert and skip Tx2 until the alert is acknowledged.
	HandleFraudHoldSet(ctx context.Context, ev FraudHoldSetEvent) error
}

// WalletPoster is the subset of wallet.Service used by the payout engine.
// wallet.Service satisfies this interface via Go structural typing;
// no sellerpayout→wallet package import is introduced.
type WalletPoster interface {
	PostInTx(ctx context.Context, tx pgx.Tx, in ledger.PostInput) (int64, error)
	FindAccount(ctx context.Context, accountType, currency string) (int64, error)
	FindOrOpenSellerPayable(ctx context.Context, sellerID int64, currency string) (int64, error)
}

// PspTransferer is the PSP transfer abstraction; sipay.Client satisfies it.
type PspTransferer interface {
	Transfer(ctx context.Context, req TransferRequest) (TransferResponse, error)
	GetTransferStatus(ctx context.Context, transferID string) (TransferResponse, error)
}

// Repository is the storage interface of the seller payout engine (fin-svc only).
type Repository interface {
	// ─── scheduling path ───────────────────────────────────────────────────────
	InsertPayout(ctx context.Context, tx pgx.Tx, p Payout) (Payout, error)
	FindPayoutByKey(ctx context.Context, idempotencyKey string) (Payout, error)

	// FetchScheduledPayouts returns up to batchSize payout rows with status='scheduled'
	// and unlock_at <= payoutDate for the given currency, using FOR UPDATE SKIP LOCKED.
	FetchScheduledPayouts(ctx context.Context, payoutDate time.Time, currency string, batchSize int) ([]Payout, error)

	// UpdatePayoutBatchID links a payout row to its aggregation batch (within Tx1).
	UpdatePayoutBatchID(ctx context.Context, tx pgx.Tx, payoutID, batchID int64) error

	// ─── batch path ────────────────────────────────────────────────────────────
	InsertBatch(ctx context.Context, tx pgx.Tx, b PayoutBatch) (PayoutBatch, error)
	FindBatchByKey(ctx context.Context, idempotencyKey string) (PayoutBatch, error)

	// UpdateBatchPspTransferID persists the PSP transfer_id immediately after the
	// PSP call, outside any transaction (best-effort; enables reconcile).
	UpdateBatchPspTransferID(ctx context.Context, batchID int64, pspTransferID string) error

	// UpdateBatchPaid atomically marks the batch paid + records the ledger tx ID (Tx2).
	UpdateBatchPaid(ctx context.Context, tx pgx.Tx, batchID, ledgerTxnID int64, pspTransferID string, paidAt time.Time) error

	// UpdateBatchStatus marks the batch with a terminal or escalation status.
	UpdateBatchStatus(ctx context.Context, batchID int64, status BatchStatus, lastError string) error

	// FetchProcessingBatches returns batches stuck in 'processing' older than 10 min.
	FetchProcessingBatches(ctx context.Context) ([]PayoutBatch, error)

	// ─── PSP account path ──────────────────────────────────────────────────────
	UpsertSellerPspAccount(ctx context.Context, acc SellerPspAccount) error
	FindSellerPspAccount(ctx context.Context, sellerID int64) (SellerPspAccount, error)

	// ─── alert path ────────────────────────────────────────────────────────────
	InsertLedgerAlert(ctx context.Context, alert LedgerAlert) error
	HasOpenAlertForBatch(ctx context.Context, batchID int64) (bool, error)

	// ─── transaction control ───────────────────────────────────────────────────
	WithTx(ctx context.Context, level pgx.TxIsoLevel, fn func(pgx.Tx) error) error
}
