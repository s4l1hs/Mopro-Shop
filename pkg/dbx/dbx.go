// Package dbx provides pgx helpers and transaction patterns for Postgres access.
// All DB connections MUST go through PgBouncer; never connect directly to Postgres.
package dbx

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Pool is the shared pgx connection pool type.
type Pool = pgxpool.Pool

// Connect opens a pgxpool connection to the given DSN.
// DSN must point to PgBouncer, not directly to Postgres.
// TODO(mopro:placeholder): add connection retry with exponential backoff and health-check
// Unblocked by: Phase 1 (config loader providing DSN)
func Connect(ctx context.Context, dsn string) (*pgxpool.Pool, error) {
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		return nil, fmt.Errorf("dbx.Connect: %w", err)
	}
	return pool, nil
}
