// Package reconcile implements the weekly ledger invariant verification cron (Phase 2.4).
//
// CROSS-SCHEMA EXCEPTION (CLAUDE.md §5): This module is the sole approved location
// for SQL queries that span wallet_schema and cashback_schema in a single statement.
// All other cross-schema reads must go through the owning module's interface or the
// event/outbox pattern.
//
// IN-TX EXCEPTION: This module calls wallet.Repository methods directly (not
// wallet.Service) when in-tx coordination is required (OQ4 resolution, approved
// in Phase 2.4 dry run).
package reconcile

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5"
)

// Service orchestrates the weekly reconcile run.
type Service interface {
	RunWeekly(ctx context.Context, asOf time.Time) (WeeklyResult, error)
}

// Repository is the storage interface for the reconcile module.
// Implemented by pgxReconcileRepository which connects as reconcile_user.
type Repository interface {
	// Check1DCBalance returns the net D-C balance per currency across ALL ledger_entries.
	// Returns map[currency]deltaMinor; entries with delta==0 are omitted.
	Check1DCBalance(ctx context.Context) (map[string]int64, error)

	// Check2CashbackBackward returns (payments_total, ledger_total, error) for a given
	// period_yyyymm. Cross-schema SQL approved under CLAUDE.md §5 exception.
	Check2CashbackBackward(ctx context.Context, periodYYYYMM int) (paymentsTotal, ledgerTotal int64, err error)

	// HasUnacknowledgedAlert returns true if an unacknowledged alert exists for the
	// given alert_type and dedup_key (stored in context->>'dedup_key').
	HasUnacknowledgedAlert(ctx context.Context, alertType, dedupKey string) (bool, error)

	// InsertAlertWithOutboxAndState atomically within tx:
	//   1. INSERTs a ledger_alerts row; returns the new alert ID.
	//   2. INSERTs a wallet_schema.outbox row for fin.reconciliation.drift_critical.v1.
	//   3. UPDATEs wallet_schema.system_state SET read_only=TRUE.
	// Called inside reconcileService.handleFailedCheck's WithTx callback.
	InsertAlertWithOutboxAndState(ctx context.Context, tx pgx.Tx, alert ReconcileAlert, reason string) (alertID int64, err error)

	// WithTx starts a READ COMMITTED transaction and calls fn.
	WithTx(ctx context.Context, fn func(pgx.Tx) error) error
}

// PDClient is the pagerduty.Client interface as seen by reconcile.
// pkg/pagerduty.Client satisfies this via structural typing.
type PDClient interface {
	Trigger(ctx context.Context, summary, dedupKey string, details map[string]any) error
	Resolve(ctx context.Context, dedupKey string) error
}

// SystemStateSetter allows reconcile to invalidate the wallet cache post-commit.
// wallet.Service satisfies this via structural typing.
type SystemStateSetter interface {
	InvalidateReadOnlyCache()
}
