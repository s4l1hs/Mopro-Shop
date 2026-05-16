package notification

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

// DedupStore prevents duplicate Slack messages for the same idempotency key.
type DedupStore interface {
	// MarkSent inserts idempotencyKey + topic. Returns alreadySent=true and nil error
	// when the key already exists. Returns false + nil on first insertion.
	// Returns false + non-nil on unexpected DB errors.
	MarkSent(ctx context.Context, idempotencyKey, topic string) (alreadySent bool, err error)
}

type pgxDedupStore struct {
	pool *pgxpool.Pool
}

// NewPgxDedupStore constructs a DedupStore backed by notification_schema.slack_sent.
func NewPgxDedupStore(pool *pgxpool.Pool) DedupStore {
	return &pgxDedupStore{pool: pool}
}

func (s *pgxDedupStore) MarkSent(ctx context.Context, idempotencyKey, topic string) (bool, error) {
	tag, err := s.pool.Exec(ctx,
		`INSERT INTO notification_schema.slack_sent (idempotency_key, topic)
		 VALUES ($1, $2)
		 ON CONFLICT (idempotency_key) DO NOTHING`,
		idempotencyKey, topic,
	)
	if err != nil {
		// Distinguish unique-violation from other errors defensively (pool.Exec path).
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			return true, nil
		}
		return false, fmt.Errorf("notification: dedup mark_sent: %w", err)
	}
	if tag.RowsAffected() == 0 {
		// ON CONFLICT DO NOTHING path — key already existed.
		return true, nil
	}
	return false, nil
}

// noopDedupStore never suppresses a message — useful when no DB is wired.
type noopDedupStore struct{}

func (noopDedupStore) MarkSent(_ context.Context, _, _ string) (bool, error) { return false, nil }

// NewNoopDedupStore returns a DedupStore that never deduplicates.
func NewNoopDedupStore() DedupStore { return noopDedupStore{} }

// inTxDedupStore uses an existing pgx.Tx instead of a pool — used in tests.
type inTxDedupStore struct {
	tx pgx.Tx
}

// NewInTxDedupStore is exposed for integration tests that manage their own transaction.
func NewInTxDedupStore(tx pgx.Tx) DedupStore { return &inTxDedupStore{tx: tx} }

func (s *inTxDedupStore) MarkSent(ctx context.Context, idempotencyKey, topic string) (bool, error) {
	tag, err := s.tx.Exec(ctx,
		`INSERT INTO notification_schema.slack_sent (idempotency_key, topic)
		 VALUES ($1, $2)
		 ON CONFLICT (idempotency_key) DO NOTHING`,
		idempotencyKey, topic,
	)
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			return true, nil
		}
		return false, fmt.Errorf("notification: dedup (tx) mark_sent: %w", err)
	}
	return tag.RowsAffected() == 0, nil
}
