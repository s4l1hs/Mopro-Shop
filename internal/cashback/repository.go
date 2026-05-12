package cashback

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

type pgxCashbackRepository struct {
	pool *pgxpool.Pool
}

// NewRepository constructs a Repository backed by pool.
func NewRepository(pool *pgxpool.Pool) Repository {
	return &pgxCashbackRepository{pool: pool}
}

func (r *pgxCashbackRepository) InsertPlan(ctx context.Context, tx pgx.Tx, p Plan) (Plan, error) {
	const q = `
		INSERT INTO cashback_schema.plans
			(order_id, user_id, monthly_amount_minor, currency,
			 reference_interest_rate_bps, start_date, status,
			 delivered_at, market, commission_snapshot, idempotency_key)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
		RETURNING id, created_at, updated_at`

	err := tx.QueryRow(ctx, q,
		p.OrderID, p.UserID, p.MonthlyAmountMinor, p.Currency,
		p.ReferenceInterestRateBps, p.StartDate,
		string(p.Status), p.DeliveredAt.UTC(), p.Market,
		[]byte(p.CommissionSnapshot), p.IdempotencyKey,
	).Scan(&p.ID, &p.CreatedAt, &p.UpdatedAt)
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			return Plan{}, ErrPlanAlreadyExists
		}
		return Plan{}, err
	}
	return p, nil
}

func (r *pgxCashbackRepository) FindPlanByOrderID(ctx context.Context, orderID int64) (Plan, error) {
	const q = `
		SELECT id, order_id, user_id, monthly_amount_minor, currency,
		       reference_interest_rate_bps, start_date, status,
		       delivered_at, market, commission_snapshot, idempotency_key,
		       created_at, updated_at
		FROM cashback_schema.plans
		WHERE order_id = $1
		LIMIT 1`

	var p Plan
	var statusStr string
	var snapshot []byte

	err := r.pool.QueryRow(ctx, q, orderID).Scan(
		&p.ID, &p.OrderID, &p.UserID, &p.MonthlyAmountMinor, &p.Currency,
		&p.ReferenceInterestRateBps, &p.StartDate, &statusStr,
		&p.DeliveredAt, &p.Market, &snapshot, &p.IdempotencyKey,
		&p.CreatedAt, &p.UpdatedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return Plan{}, ErrPlanNotFound
		}
		return Plan{}, err
	}
	p.Status = PlanStatus(statusStr)
	p.CommissionSnapshot = snapshot
	return p, nil
}

func (r *pgxCashbackRepository) WithTx(ctx context.Context, fn func(pgx.Tx) error) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	if err := fn(tx); err != nil {
		_ = tx.Rollback(ctx)
		return err
	}
	return tx.Commit(ctx)
}
