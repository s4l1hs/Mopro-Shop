package reconcile

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/mopro/platform/internal/outbox"
)

type pgxReconcileRepository struct {
	pool       *pgxpool.Pool
	outboxRepo outbox.Repository
}

// NewRepository constructs a Repository backed by pool (should use reconcile_user credentials).
func NewRepository(pool *pgxpool.Pool) Repository {
	return &pgxReconcileRepository{
		pool:       pool,
		outboxRepo: outbox.NewRepository("wallet_schema.outbox"),
	}
}

func (r *pgxReconcileRepository) WithTx(ctx context.Context, fn func(pgx.Tx) error) error {
	tx, err := r.pool.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.ReadCommitted})
	if err != nil {
		return fmt.Errorf("reconcile: begin tx: %w", err)
	}
	if err := fn(tx); err != nil {
		_ = tx.Rollback(ctx)
		return err
	}
	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("reconcile: commit tx: %w", err)
	}
	return nil
}

// Check1DCBalance queries the total D-C balance per currency across all ledger entries.
// CROSS-SCHEMA: no cross-schema join here; purely within wallet_schema.
func (r *pgxReconcileRepository) Check1DCBalance(ctx context.Context) (map[string]int64, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT a.currency,
		       COALESCE(SUM(CASE WHEN le.direction='D' THEN le.amount_minor
		                         ELSE -le.amount_minor END), 0) AS delta
		FROM wallet_schema.ledger_entries le
		JOIN wallet_schema.accounts a ON a.id = le.account_id
		GROUP BY a.currency
		HAVING COALESCE(SUM(CASE WHEN le.direction='D' THEN le.amount_minor
		                         ELSE -le.amount_minor END), 0) != 0
	`)
	if err != nil {
		return nil, fmt.Errorf("reconcile: check1 query: %w", err)
	}
	defer rows.Close()
	result := make(map[string]int64)
	for rows.Next() {
		var currency string
		var delta int64
		if err := rows.Scan(&currency, &delta); err != nil {
			return nil, fmt.Errorf("reconcile: check1 scan: %w", err)
		}
		result[currency] = delta
	}
	return result, rows.Err()
}

// Check2CashbackBackward compares paid cashback payments total against ledger C entries
// linked via ledger_transaction_id.
// CROSS-SCHEMA EXCEPTION: queries cashback_schema.payments + wallet_schema.ledger_entries
// in a single statement. Approved under CLAUDE.md §5 exception for internal/reconcile.
func (r *pgxReconcileRepository) Check2CashbackBackward(ctx context.Context, periodYYYYMM int) (int64, int64, error) {
	var paymentsTotal, ledgerTotal int64
	err := r.pool.QueryRow(ctx, `
		SELECT
		    COALESCE(SUM(p.amount_minor), 0)   AS payments_total,
		    COALESCE(SUM(le.amount_minor), 0)  AS ledger_total
		FROM cashback_schema.payments p
		LEFT JOIN wallet_schema.ledger_entries le
		       ON le.transaction_id = p.ledger_transaction_id
		      AND le.direction = 'C'
		WHERE p.status = 'paid'
		  AND p.period_yyyymm = $1
		  AND p.ledger_transaction_id IS NOT NULL
	`, periodYYYYMM).Scan(&paymentsTotal, &ledgerTotal)
	if err != nil {
		return 0, 0, fmt.Errorf("reconcile: check2 period=%d: %w", periodYYYYMM, err)
	}
	return paymentsTotal, ledgerTotal, nil
}

func (r *pgxReconcileRepository) HasUnacknowledgedAlert(ctx context.Context, alertType, dedupKey string) (bool, error) {
	var exists bool
	err := r.pool.QueryRow(ctx, `
		SELECT EXISTS (
		    SELECT 1 FROM wallet_schema.ledger_alerts
		    WHERE alert_type = $1
		      AND context->>'dedup_key' = $2
		      AND acknowledged_at IS NULL
		)
	`, alertType, dedupKey).Scan(&exists)
	if err != nil {
		return false, fmt.Errorf("reconcile: HasUnacknowledgedAlert: %w", err)
	}
	return exists, nil
}

func (r *pgxReconcileRepository) InsertAlertWithOutboxAndState(ctx context.Context, tx pgx.Tx, alert ReconcileAlert, reason string) (int64, error) {
	// 1. Build context JSONB.
	ctxJSON, err := json.Marshal(map[string]any{
		"check_name":         alert.CheckName,
		"currency_or_period": alert.CurrencyOrPeriod,
		"expected":           alert.Expected,
		"observed":           alert.Observed,
		"drift_minor":        alert.DriftMinor,
		"dedup_key":          alert.DedupKey,
	})
	if err != nil {
		return 0, fmt.Errorf("reconcile: marshal context: %w", err)
	}

	// 2. Insert ledger_alerts row.
	var alertID int64
	err = tx.QueryRow(ctx, `
		INSERT INTO wallet_schema.ledger_alerts
		    (severity, currency, delta_amount_minor, message, alert_type, context)
		VALUES ('CRITICAL', $1, $2, $3, 'reconciliation_drift', $4)
		RETURNING id
	`,
		alert.CurrencyOrPeriod,
		alert.DriftMinor,
		fmt.Sprintf("reconcile drift: check=%s currency_or_period=%s expected=%d observed=%d drift=%d",
			alert.CheckName, alert.CurrencyOrPeriod, alert.Expected, alert.Observed, alert.DriftMinor),
		ctxJSON,
	).Scan(&alertID)
	if err != nil {
		return 0, fmt.Errorf("reconcile: insert alert: %w", err)
	}

	// 3. Insert outbox row for fin.reconciliation.drift_critical.v1.
	payload, _ := json.Marshal(map[string]any{
		"alert_id":           alertID,
		"check_name":         alert.CheckName,
		"currency_or_period": alert.CurrencyOrPeriod,
		"drift_minor":        alert.DriftMinor,
	})
	outboxRow := outbox.Row{
		Aggregate:      "reconcile",
		EventType:      "fin.reconciliation.drift_critical.v1",
		Payload:        payload,
		IdempotencyKey: fmt.Sprintf("reconcile:drift:%s:%s:%d", alert.CheckName, alert.CurrencyOrPeriod, time.Now().UnixNano()),
		Market:         "global",
		Currency:       "",
	}
	if err := r.outboxRepo.Insert(ctx, tx, outboxRow); err != nil {
		return 0, fmt.Errorf("reconcile: insert outbox: %w", err)
	}

	// 4. Update system_state: read_only=TRUE.
	reasonStr := fmt.Sprintf("reconciliation_drift_critical_alert_%d", alertID)
	if reason != "" {
		reasonStr = reason
	}
	_, err = tx.Exec(ctx, `
		UPDATE wallet_schema.system_state
		SET read_only        = TRUE,
		    read_only_reason = $1,
		    read_only_since  = now(),
		    updated_at       = now()
		WHERE id = 1
	`, reasonStr)
	if err != nil {
		return 0, fmt.Errorf("reconcile: set system_state read_only: %w", err)
	}

	return alertID, nil
}
