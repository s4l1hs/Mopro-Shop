package eventbus

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"
)

// AttemptRow records one dispatch outcome for a Redis Streams message.
type AttemptRow struct {
	Stream        string
	MessageID     string
	ConsumerGroup string
	ConsumerName  string
	Outcome       string // "success" | "error" | "panic"
	ErrorMessage  string // empty on success
	DurationMs    int
}

// AttemptRepository persists dispatch attempt records.
// Phase 3.1: used to detect DLQ candidates (>= 3 failures on same message).
// Phase 3.2: will drive actual DLQ insertion and XACK to break the retry loop.
type AttemptRepository interface {
	Insert(ctx context.Context, row AttemptRow) error
	// CountFailures returns the number of error/panic outcomes recorded for this
	// (stream, messageID, group) triple across ALL consumer names. Surviving a
	// consumer name change (process restart) is intentional — the group-level
	// count is what matters for DLQ candidacy.
	CountFailures(ctx context.Context, stream, messageID, group string) (int, error)
}

// pgxAttemptRepository writes to wallet_schema.event_delivery_attempts.
type pgxAttemptRepository struct {
	pool *pgxpool.Pool
}

// NewPgxAttemptRepository returns a postgres-backed AttemptRepository.
func NewPgxAttemptRepository(pool *pgxpool.Pool) AttemptRepository {
	return &pgxAttemptRepository{pool: pool}
}

func (r *pgxAttemptRepository) Insert(ctx context.Context, row AttemptRow) error {
	var errMsg *string
	if row.ErrorMessage != "" {
		s := row.ErrorMessage
		errMsg = &s
	}
	_, err := r.pool.Exec(ctx, `
		INSERT INTO wallet_schema.event_delivery_attempts
		    (stream, message_id, consumer_group, consumer_name, outcome, error_message, duration_ms)
		VALUES ($1, $2, $3, $4, $5, $6, $7)`,
		row.Stream, row.MessageID, row.ConsumerGroup, row.ConsumerName,
		row.Outcome, errMsg, row.DurationMs,
	)
	return err
}

func (r *pgxAttemptRepository) CountFailures(ctx context.Context, stream, messageID, group string) (int, error) {
	var n int
	err := r.pool.QueryRow(ctx, `
		SELECT COUNT(*) FROM wallet_schema.event_delivery_attempts
		WHERE stream = $1 AND message_id = $2 AND consumer_group = $3
		  AND outcome IN ('error', 'panic')`,
		stream, messageID, group,
	).Scan(&n)
	return n, err
}

// noopAttemptRepository discards all records; used in tests and when no DB is configured.
type noopAttemptRepository struct{}

// NewNoopAttemptRepository returns an AttemptRepository that does nothing.
func NewNoopAttemptRepository() AttemptRepository { return noopAttemptRepository{} }

func (noopAttemptRepository) Insert(_ context.Context, _ AttemptRow) error { return nil }
func (noopAttemptRepository) CountFailures(_ context.Context, _, _, _ string) (int, error) {
	return 0, nil
}
