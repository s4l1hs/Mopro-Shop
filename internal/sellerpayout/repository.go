package sellerpayout

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

type pgxPayoutRepository struct {
	pool *pgxpool.Pool
}

// NewRepository constructs a Repository backed by pool.
func NewRepository(pool *pgxpool.Pool) Repository {
	return &pgxPayoutRepository{pool: pool}
}

func (r *pgxPayoutRepository) WithTx(ctx context.Context, level pgx.TxIsoLevel, fn func(pgx.Tx) error) error {
	tx, err := r.pool.BeginTx(ctx, pgx.TxOptions{IsoLevel: level})
	if err != nil {
		return err
	}
	if err := fn(tx); err != nil {
		_ = tx.Rollback(ctx)
		return err
	}
	return tx.Commit(ctx)
}

// ── scheduling path ────────────────────────────────────────────────────────────

func (r *pgxPayoutRepository) InsertPayout(ctx context.Context, tx pgx.Tx, p Payout) (Payout, error) {
	const q = `
		INSERT INTO sellerpayout_schema.seller_payouts
			(order_id, seller_id, amount_minor, currency,
			 delivered_at, unlock_at, status, market, idempotency_key)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
		RETURNING id, created_at, updated_at`

	err := tx.QueryRow(ctx, q,
		p.OrderID, p.SellerID, p.AmountMinor, p.Currency,
		p.DeliveredAt.UTC(), p.UnlockAt,
		string(p.Status), p.Market, p.IdempotencyKey,
	).Scan(&p.ID, &p.CreatedAt, &p.UpdatedAt)
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			return Payout{}, ErrPayoutAlreadyExists
		}
		return Payout{}, err
	}
	return p, nil
}

func (r *pgxPayoutRepository) FindPayoutByKey(ctx context.Context, idempotencyKey string) (Payout, error) {
	const q = `
		SELECT id, order_id, seller_id, amount_minor, currency,
		       delivered_at, unlock_at, paid_at, psp_transfer_id, status,
		       market, ledger_transaction_id, idempotency_key, batch_id,
		       attempt_count, last_attempt_at, last_error,
		       created_at, updated_at
		FROM sellerpayout_schema.seller_payouts
		WHERE idempotency_key = $1`

	return r.scanPayout(r.pool.QueryRow(ctx, q, idempotencyKey))
}

func (r *pgxPayoutRepository) FetchScheduledPayouts(ctx context.Context, payoutDate time.Time, currency string, batchSize int) ([]Payout, error) {
	const q = `
		SELECT id, order_id, seller_id, amount_minor, currency,
		       delivered_at, unlock_at, paid_at, psp_transfer_id, status,
		       market, ledger_transaction_id, idempotency_key, batch_id,
		       attempt_count, last_attempt_at, last_error,
		       created_at, updated_at
		FROM sellerpayout_schema.seller_payouts
		WHERE status = 'scheduled'
		  AND currency = $1
		  AND unlock_at <= $2
		ORDER BY seller_id, id
		LIMIT $3
		FOR UPDATE SKIP LOCKED`

	rows, err := r.pool.Query(ctx, q, currency, payoutDate, batchSize)
	if err != nil {
		return nil, fmt.Errorf("sellerpayout: FetchScheduledPayouts: %w", err)
	}
	defer rows.Close()

	var payouts []Payout
	for rows.Next() {
		p, err := r.scanPayout(rows)
		if err != nil {
			return nil, err
		}
		payouts = append(payouts, p)
	}
	return payouts, rows.Err()
}

func (r *pgxPayoutRepository) UpdatePayoutBatchID(ctx context.Context, tx pgx.Tx, payoutID, batchID int64) error {
	_, err := tx.Exec(ctx,
		`UPDATE sellerpayout_schema.seller_payouts SET batch_id=$1, updated_at=now() WHERE id=$2`,
		batchID, payoutID,
	)
	return err
}

// ── batch path ─────────────────────────────────────────────────────────────────

func (r *pgxPayoutRepository) InsertBatch(ctx context.Context, tx pgx.Tx, b PayoutBatch) (PayoutBatch, error) {
	const q = `
		INSERT INTO sellerpayout_schema.payout_batches
			(seller_id, currency, payout_date, total_amount_minor, status,
			 idempotency_key, market, attempt_count, last_attempt_at)
		VALUES ($1,$2,$3,$4,'processing',$5,$6,1,now())
		RETURNING id, created_at, updated_at`

	err := tx.QueryRow(ctx, q,
		b.SellerID, b.Currency, b.PayoutDate.UTC(), b.TotalAmountMinor,
		b.IdempotencyKey, b.Market,
	).Scan(&b.ID, &b.CreatedAt, &b.UpdatedAt)
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			return PayoutBatch{}, ErrBatchAlreadyExists
		}
		return PayoutBatch{}, fmt.Errorf("sellerpayout: InsertBatch: %w", err)
	}
	b.Status = BatchStatusProcessing
	return b, nil
}

func (r *pgxPayoutRepository) FindBatchByKey(ctx context.Context, idempotencyKey string) (PayoutBatch, error) {
	const q = `
		SELECT id, seller_id, currency, payout_date, total_amount_minor,
		       psp_transfer_id, status, ledger_transaction_id, paid_at,
		       idempotency_key, attempt_count, last_attempt_at, last_error,
		       market, created_at, updated_at
		FROM sellerpayout_schema.payout_batches
		WHERE idempotency_key = $1`

	return r.scanBatch(r.pool.QueryRow(ctx, q, idempotencyKey))
}

func (r *pgxPayoutRepository) UpdateBatchPspTransferID(ctx context.Context, batchID int64, pspTransferID string) error {
	_, err := r.pool.Exec(ctx,
		`UPDATE sellerpayout_schema.payout_batches
		 SET psp_transfer_id=$1, updated_at=now()
		 WHERE id=$2`,
		pspTransferID, batchID,
	)
	return err
}

func (r *pgxPayoutRepository) UpdateBatchPaid(ctx context.Context, tx pgx.Tx, batchID, ledgerTxnID int64, pspTransferID string, paidAt time.Time) error {
	_, err := tx.Exec(ctx,
		`UPDATE sellerpayout_schema.payout_batches
		 SET status='paid', psp_transfer_id=$1, ledger_transaction_id=$2,
		     paid_at=$3, updated_at=now()
		 WHERE id=$4`,
		pspTransferID, ledgerTxnID, paidAt.UTC(), batchID,
	)
	return err
}

func (r *pgxPayoutRepository) MarkPayoutsPaidByBatch(ctx context.Context, tx pgx.Tx, batchID int64) error {
	_, err := tx.Exec(ctx,
		`UPDATE sellerpayout_schema.seller_payouts
		 SET status='paid', updated_at=now()
		 WHERE batch_id=$1 AND status='scheduled'`,
		batchID,
	)
	return err
}

func (r *pgxPayoutRepository) UpdateBatchStatus(ctx context.Context, batchID int64, status BatchStatus, lastError string) error {
	_, err := r.pool.Exec(ctx,
		`UPDATE sellerpayout_schema.payout_batches
		 SET status=$1, last_error=$2, last_attempt_at=now(),
		     attempt_count=attempt_count+1, updated_at=now()
		 WHERE id=$3`,
		string(status), lastError, batchID,
	)
	return err
}

func (r *pgxPayoutRepository) FetchProcessingBatches(ctx context.Context) ([]PayoutBatch, error) {
	// Batches stuck in 'processing' for more than 10 minutes are eligible for reconcile.
	const q = `
		SELECT id, seller_id, currency, payout_date, total_amount_minor,
		       psp_transfer_id, status, ledger_transaction_id, paid_at,
		       idempotency_key, attempt_count, last_attempt_at, last_error,
		       market, created_at, updated_at
		FROM sellerpayout_schema.payout_batches
		WHERE status = 'processing'
		  AND (last_attempt_at IS NULL OR last_attempt_at < now() - interval '10 minutes')
		FOR UPDATE SKIP LOCKED`

	rows, err := r.pool.Query(ctx, q)
	if err != nil {
		return nil, fmt.Errorf("sellerpayout: FetchProcessingBatches: %w", err)
	}
	defer rows.Close()

	var batches []PayoutBatch
	for rows.Next() {
		b, err := r.scanBatch(rows)
		if err != nil {
			return nil, err
		}
		batches = append(batches, b)
	}
	return batches, rows.Err()
}

// ── PSP account path ───────────────────────────────────────────────────────────

func (r *pgxPayoutRepository) UpsertSellerPspAccount(ctx context.Context, acc SellerPspAccount) error {
	_, err := r.pool.Exec(ctx,
		`INSERT INTO sellerpayout_schema.seller_psp_accounts (seller_id, psp_member_id, market, status)
		 VALUES ($1, $2, $3, 'active')
		 ON CONFLICT (seller_id) DO UPDATE
		   SET psp_member_id = EXCLUDED.psp_member_id,
		       market        = EXCLUDED.market,
		       status        = 'active',
		       updated_at    = now()`,
		acc.SellerID, acc.PspMemberID, acc.Market,
	)
	return err
}

func (r *pgxPayoutRepository) FindSellerPspAccount(ctx context.Context, sellerID int64) (SellerPspAccount, error) {
	const q = `
		SELECT id, seller_id, psp_member_id, market, status, created_at, updated_at
		FROM sellerpayout_schema.seller_psp_accounts
		WHERE seller_id = $1`

	var acc SellerPspAccount
	err := r.pool.QueryRow(ctx, q, sellerID).Scan(
		&acc.ID, &acc.SellerID, &acc.PspMemberID, &acc.Market,
		&acc.Status, &acc.CreatedAt, &acc.UpdatedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return SellerPspAccount{}, ErrSellerPspAccountNotFound
		}
		return SellerPspAccount{}, err
	}
	return acc, nil
}

// ── alert path ─────────────────────────────────────────────────────────────────

func (r *pgxPayoutRepository) InsertLedgerAlert(ctx context.Context, alert LedgerAlert) error {
	_, err := r.pool.Exec(ctx,
		`INSERT INTO wallet_schema.ledger_alerts (severity, currency, batch_id, alert_type, message)
		 VALUES ($1, $2, $3, $4, $5)`,
		alert.Severity, alert.Currency, alert.BatchID, alert.AlertType, alert.Message,
	)
	return err
}

func (r *pgxPayoutRepository) HasOpenAlertForBatch(ctx context.Context, batchID int64) (bool, error) {
	var exists bool
	err := r.pool.QueryRow(ctx,
		`SELECT EXISTS(
		   SELECT 1 FROM wallet_schema.ledger_alerts
		   WHERE batch_id = $1 AND acknowledged_at IS NULL
		 )`,
		batchID,
	).Scan(&exists)
	return exists, err
}

// ── scan helpers ───────────────────────────────────────────────────────────────

type pgxScanner interface {
	Scan(dest ...any) error
}

func (r *pgxPayoutRepository) scanPayout(row pgxScanner) (Payout, error) {
	var p Payout
	var statusStr string
	var pspTransferID, lastError *string
	err := row.Scan(
		&p.ID, &p.OrderID, &p.SellerID, &p.AmountMinor, &p.Currency,
		&p.DeliveredAt, &p.UnlockAt, &p.PaidAt, &pspTransferID, &statusStr,
		&p.Market, &p.LedgerTransactionID, &p.IdempotencyKey, &p.BatchID,
		&p.AttemptCount, &p.LastAttemptAt, &lastError,
		&p.CreatedAt, &p.UpdatedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return Payout{}, ErrPayoutNotFound
		}
		return Payout{}, err
	}
	p.Status = PayoutStatus(statusStr)
	if pspTransferID != nil {
		p.PspTransferID = *pspTransferID
	}
	if lastError != nil {
		p.LastError = *lastError
	}
	return p, nil
}

func (r *pgxPayoutRepository) scanBatch(row pgxScanner) (PayoutBatch, error) {
	var b PayoutBatch
	var statusStr string
	var pspTransferID, lastError *string
	err := row.Scan(
		&b.ID, &b.SellerID, &b.Currency, &b.PayoutDate, &b.TotalAmountMinor,
		&pspTransferID, &statusStr, &b.LedgerTransactionID, &b.PaidAt,
		&b.IdempotencyKey, &b.AttemptCount, &b.LastAttemptAt, &lastError,
		&b.Market, &b.CreatedAt, &b.UpdatedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return PayoutBatch{}, ErrBatchNotFound
		}
		return PayoutBatch{}, err
	}
	b.Status = BatchStatus(statusStr)
	if pspTransferID != nil {
		b.PspTransferID = *pspTransferID
	}
	if lastError != nil {
		b.LastError = *lastError
	}
	return b, nil
}
