package outbox

import (
	"context"
	"encoding/json"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

// pgxRepository implements Repository against a named outbox table.
// table is injected at construction time and is an operator-controlled constant
// (e.g., "wallet_schema.outbox" or "order_schema.outbox"). It is NEVER derived
// from user input, so direct interpolation into SQL is safe.
type pgxRepository struct {
	table string
}

// NewRepository constructs a Repository for the given schema-qualified table name.
func NewRepository(table string) Repository {
	return &pgxRepository{table: table}
}

// Insert writes row to the outbox table within tx. The INSERT participates in the
// caller's outer transaction — if that transaction rolls back, the outbox row is
// never visible to the publisher (ACID guarantee for the outbox pattern).
// Returns ErrDuplicateIdempotency on UNIQUE(idempotency_key) violation (SQLSTATE 23505).
func (r *pgxRepository) Insert(ctx context.Context, tx pgx.Tx, row Row) error {
	_, err := tx.Exec(ctx, `
		INSERT INTO `+r.table+`
			(aggregate, event_type, payload, idempotency_key, trace_id, span_id, market, currency)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
		row.Aggregate, row.EventType, row.Payload, row.IdempotencyKey,
		row.TraceID, row.SpanID, row.Market, row.Currency,
	)
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			return ErrDuplicateIdempotency
		}
		return err
	}
	return nil
}

// FetchUnpublished selects up to limit rows with published_at IS NULL, ordered by id ASC,
// locking them with FOR UPDATE SKIP LOCKED so concurrent publisher workers do not
// double-claim the same rows.
func (r *pgxRepository) FetchUnpublished(ctx context.Context, tx pgx.Tx, limit int) ([]Row, error) {
	pgRows, err := tx.Query(ctx, `
		SELECT id, aggregate, event_type, payload, idempotency_key,
		       COALESCE(trace_id, ''), COALESCE(span_id, ''),
		       market, currency, created_at
		FROM `+r.table+`
		WHERE published_at IS NULL
		ORDER BY id ASC
		FOR UPDATE SKIP LOCKED
		LIMIT $1`,
		limit,
	)
	if err != nil {
		return nil, err
	}
	defer pgRows.Close()

	var result []Row
	for pgRows.Next() {
		var row Row
		var rawPayload []byte
		if err := pgRows.Scan(
			&row.ID, &row.Aggregate, &row.EventType, &rawPayload, &row.IdempotencyKey,
			&row.TraceID, &row.SpanID, &row.Market, &row.Currency, &row.CreatedAt,
		); err != nil {
			return nil, err
		}
		row.Payload = json.RawMessage(rawPayload)
		result = append(result, row)
	}
	return result, pgRows.Err()
}

// MarkPublished sets published_at = now() for the row with the given id within tx.
func (r *pgxRepository) MarkPublished(ctx context.Context, tx pgx.Tx, id int64) error {
	_, err := tx.Exec(ctx, `UPDATE `+r.table+` SET published_at = now() WHERE id = $1`, id)
	return err
}
