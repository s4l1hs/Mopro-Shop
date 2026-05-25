package payment

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

const pgUniqueViolation = "23505"

type pgxPaymentRepository struct {
	pool *pgxpool.Pool
}

// NewRepository returns a Repository backed by a pgx connection pool.
func NewRepository(pool *pgxpool.Pool) Repository {
	return &pgxPaymentRepository{pool: pool}
}

func (r *pgxPaymentRepository) WithTx(ctx context.Context, fn func(pgx.Tx) error) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("payment.repo: begin tx: %w", err)
	}
	defer tx.Rollback(ctx) //nolint:errcheck
	if err := fn(tx); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func (r *pgxPaymentRepository) InsertPaymentIntent(ctx context.Context, tx pgx.Tx, p PaymentIntent) (PaymentIntent, error) {
	err := tx.QueryRow(ctx,
		`INSERT INTO order_schema.payments
			(order_id, idempotency_key, provider, provider_ref, provider_order_no,
			 status, amount_minor, currency, raw_response)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
		RETURNING id, created_at, updated_at`,
		p.OrderID, p.IdempotencyKey, p.Provider, p.ProviderRef, p.ProviderOrderNo,
		string(p.Status), p.AmountMinor, p.Currency, p.RawResponse,
	).Scan(&p.ID, &p.CreatedAt, &p.UpdatedAt)
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == pgUniqueViolation {
			return PaymentIntent{}, ErrPaymentAlreadyCaptured
		}
		return PaymentIntent{}, fmt.Errorf("payment.repo: InsertPaymentIntent: %w", err)
	}
	return p, nil
}

func (r *pgxPaymentRepository) FindPaymentIntentByIdempotencyKey(ctx context.Context, key string) (PaymentIntent, error) {
	var p PaymentIntent
	err := r.pool.QueryRow(ctx,
		`SELECT id, order_id, idempotency_key, provider, provider_ref, provider_order_no,
		        status, amount_minor, currency,
		        captured_at, failed_at, failure_reason, refunded_at, refund_ref,
		        refund_amount_minor, raw_response, created_at, updated_at
		   FROM order_schema.payments
		  WHERE idempotency_key = $1`,
		key,
	).Scan(
		&p.ID, &p.OrderID, &p.IdempotencyKey, &p.Provider, &p.ProviderRef, &p.ProviderOrderNo,
		&p.Status, &p.AmountMinor, &p.Currency,
		&p.CapturedAt, &p.FailedAt, &p.FailureReason, &p.RefundedAt, &p.RefundRef,
		&p.RefundAmountMinor, &p.RawResponse, &p.CreatedAt, &p.UpdatedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return PaymentIntent{}, ErrPaymentNotFound
	}
	if err != nil {
		return PaymentIntent{}, fmt.Errorf("payment.repo: FindPaymentIntentByIdempotencyKey: %w", err)
	}
	return p, nil
}

func (r *pgxPaymentRepository) FindPaymentByOrderID(ctx context.Context, orderID int64) (PaymentIntent, error) {
	var p PaymentIntent
	err := r.pool.QueryRow(ctx,
		`SELECT id, order_id, idempotency_key, provider, provider_ref, provider_order_no,
		        status, amount_minor, currency,
		        captured_at, failed_at, failure_reason, refunded_at, refund_ref,
		        refund_amount_minor, raw_response, created_at, updated_at
		   FROM order_schema.payments
		  WHERE order_id = $1
		  ORDER BY created_at DESC
		  LIMIT 1`,
		orderID,
	).Scan(
		&p.ID, &p.OrderID, &p.IdempotencyKey, &p.Provider, &p.ProviderRef, &p.ProviderOrderNo,
		&p.Status, &p.AmountMinor, &p.Currency,
		&p.CapturedAt, &p.FailedAt, &p.FailureReason, &p.RefundedAt, &p.RefundRef,
		&p.RefundAmountMinor, &p.RawResponse, &p.CreatedAt, &p.UpdatedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return PaymentIntent{}, ErrPaymentNotFound
	}
	if err != nil {
		return PaymentIntent{}, fmt.Errorf("payment.repo: FindPaymentByOrderID: %w", err)
	}
	return p, nil
}

func (r *pgxPaymentRepository) FindExpiredPendingPayments(ctx context.Context, limit int) ([]PaymentIntent, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT id, order_id, idempotency_key, provider, provider_ref, provider_order_no,
		        status, amount_minor, currency,
		        captured_at, failed_at, failure_reason, refunded_at, refund_ref,
		        refund_amount_minor, raw_response, created_at, updated_at
		   FROM order_schema.payments
		  WHERE status = 'pending'
		    AND expires_at IS NOT NULL
		    AND expires_at < NOW() - INTERVAL '2 minutes'
		  ORDER BY expires_at ASC
		  LIMIT $1
		  FOR UPDATE SKIP LOCKED`,
		limit,
	)
	if err != nil {
		return nil, fmt.Errorf("payment.repo: FindExpiredPendingPayments: %w", err)
	}
	defer rows.Close()

	var results []PaymentIntent
	for rows.Next() {
		var p PaymentIntent
		if err := rows.Scan(
			&p.ID, &p.OrderID, &p.IdempotencyKey, &p.Provider, &p.ProviderRef, &p.ProviderOrderNo,
			&p.Status, &p.AmountMinor, &p.Currency,
			&p.CapturedAt, &p.FailedAt, &p.FailureReason, &p.RefundedAt, &p.RefundRef,
			&p.RefundAmountMinor, &p.RawResponse, &p.CreatedAt, &p.UpdatedAt,
		); err != nil {
			return nil, fmt.Errorf("payment.repo: FindExpiredPendingPayments scan: %w", err)
		}
		results = append(results, p)
	}
	return results, rows.Err()
}

func (r *pgxPaymentRepository) UpdatePaymentStatus(
	ctx context.Context, tx pgx.Tx, providerRef string, status PaymentStatus,
	capturedAt, failedAt, refundedAt *string, failureReason, refundRef string,
	refundAmountMinor int64,
) error {
	_, err := tx.Exec(ctx,
		`UPDATE order_schema.payments
		    SET status             = $1,
		        captured_at        = $2::timestamptz,
		        failed_at          = $3::timestamptz,
		        failure_reason     = $4,
		        refunded_at        = $5::timestamptz,
		        refund_ref         = $6,
		        refund_amount_minor= $7,
		        updated_at         = now()
		  WHERE provider_ref = $8`,
		string(status), capturedAt, failedAt, failureReason,
		refundedAt, refundRef, refundAmountMinor, providerRef,
	)
	if err != nil {
		return fmt.Errorf("payment.repo: UpdatePaymentStatus: %w", err)
	}
	return nil
}
