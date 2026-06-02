package notification

import (
	"context"
	"errors"
	"fmt"

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
