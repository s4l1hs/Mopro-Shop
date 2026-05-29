package orderledger

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Repository handles DB operations for the orderledger module.
//
// After the commission-owns-capture-postings refactor this is only the
// transaction wrapper — the capture_postings audit table is owned by
// internal/commission via commission.CaptureRecorder. The Repository
// interface is kept (rather than collapsed into the service) so the
// service stays testable with a fake tx wrapper independent of the
// recorder mock.
type Repository interface {
	// WithTx starts a transaction at level and calls fn. Retries up to 3
	// times on serialization failure (pgError 40001).
	WithTx(ctx context.Context, level pgx.TxIsoLevel, fn func(pgx.Tx) error) error
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

func isSerializationFailure(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "40001"
}
