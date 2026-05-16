package sellerpayout

import (
	"context"
	"errors"

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

func (r *pgxPayoutRepository) InsertPayout(ctx context.Context, tx pgx.Tx, p Payout) (Payout, error) {
	const q = `
		INSERT INTO commission_schema.seller_payouts
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
		       delivered_at, unlock_at, status, market, idempotency_key,
		       created_at, updated_at
		FROM commission_schema.seller_payouts
		WHERE idempotency_key = $1`

	var p Payout
	var statusStr string

	err := r.pool.QueryRow(ctx, q, idempotencyKey).Scan(
		&p.ID, &p.OrderID, &p.SellerID, &p.AmountMinor, &p.Currency,
		&p.DeliveredAt, &p.UnlockAt, &statusStr, &p.Market, &p.IdempotencyKey,
		&p.CreatedAt, &p.UpdatedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return Payout{}, ErrPayoutNotFound
		}
		return Payout{}, err
	}
	p.Status = PayoutStatus(statusStr)
	return p, nil
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
