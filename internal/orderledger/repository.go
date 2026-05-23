package orderledger

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ErrAlreadyPosted is returned by InsertPosting when a capture_postings row
// already exists for the order (UNIQUE order_id constraint).
var ErrAlreadyPosted = errors.New("orderledger: order capture already posted")

// Repository handles DB operations for the orderledger module.
type Repository interface {
	// WithTx starts a transaction at level and calls fn. Retries up to 3
	// times on serialization failure (pgError 40001).
	WithTx(ctx context.Context, level pgx.TxIsoLevel, fn func(pgx.Tx) error) error

	// InsertPosting writes a capture_postings audit row within tx.
	// Returns ErrAlreadyPosted on UNIQUE(order_id) conflict (idempotent re-delivery).
	InsertPosting(ctx context.Context, tx pgx.Tx, p CapturePosting) error

	// FindPostingByOrderID checks whether an order has already been posted.
	// Returns (nil, nil) when no row exists.
	FindPostingByOrderID(ctx context.Context, orderID int64) (*CapturePosting, error)
}

type pgxRepository struct {
	pool *pgxpool.Pool
}

// NewRepository constructs a Repository backed by pool.
func NewRepository(pool *pgxpool.Pool) Repository {
	return &pgxRepository{pool: pool}
}

func (r *pgxRepository) WithTx(ctx context.Context, level pgx.TxIsoLevel, fn func(pgx.Tx) error) error {
	const maxRetries = 3
	for attempt := 0; attempt < maxRetries; attempt++ {
		tx, err := r.pool.BeginTx(ctx, pgx.TxOptions{IsoLevel: level})
		if err != nil {
			return err
		}
		if err := fn(tx); err != nil {
			_ = tx.Rollback(ctx)
			if isSerializationFailure(err) && attempt < maxRetries-1 {
				continue
			}
			return err
		}
		return tx.Commit(ctx)
	}
	return errors.New("orderledger: transaction retry limit exceeded")
}

func (r *pgxRepository) InsertPosting(ctx context.Context, tx pgx.Tx, p CapturePosting) error {
	const q = `
		INSERT INTO commission_schema.capture_postings
			(order_id, transaction_id, idempotency_key,
			 gross_minor, seller_net_minor, commission_minor, kdv_minor, shipping_minor,
			 currency, market, status)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,'posted')`
	_, err := tx.Exec(ctx, q,
		p.OrderID, p.TransactionID, p.IdempotencyKey,
		p.GrossMinor, p.SellerNetMinor, p.CommissionMinor, p.KdvMinor, p.ShippingMinor,
		p.Currency, p.Market,
	)
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			return ErrAlreadyPosted
		}
		return err
	}
	return nil
}

func (r *pgxRepository) FindPostingByOrderID(ctx context.Context, orderID int64) (*CapturePosting, error) {
	const q = `
		SELECT id, order_id, transaction_id, idempotency_key,
		       gross_minor, seller_net_minor, commission_minor, kdv_minor, shipping_minor,
		       currency, market, status, created_at
		FROM commission_schema.capture_postings
		WHERE order_id = $1`
	p := &CapturePosting{}
	err := r.pool.QueryRow(ctx, q, orderID).Scan(
		&p.ID, &p.OrderID, &p.TransactionID, &p.IdempotencyKey,
		&p.GrossMinor, &p.SellerNetMinor, &p.CommissionMinor, &p.KdvMinor, &p.ShippingMinor,
		&p.Currency, &p.Market, &p.Status, &p.CreatedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return p, nil
}

func isSerializationFailure(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "40001"
}
