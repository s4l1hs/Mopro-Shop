// Package outbox implements the transactional outbox pattern for reliable event publishing.
// Financial and e-commerce events MUST be written to the outbox table within the SAME
// database transaction as the surrounding ledger/order write (CLAUDE.md § 4.5).
// A separate Publisher worker drains rows to Redis Streams via internal/eventbus.
package outbox

import (
	"context"
	"encoding/json"
	"time"

	"github.com/jackc/pgx/v5"
)

// Row is the in-memory representation of a wallet_schema.outbox or order_schema.outbox row.
// CreatedAt is zero until populated by FetchUnpublished; Insert callers leave it zero.
type Row struct {
	ID             int64
	Aggregate      string
	EventType      string
	Payload        json.RawMessage
	IdempotencyKey string
	TraceID        string
	SpanID         string
	Market         string
	Currency       string
	CreatedAt      time.Time // populated by FetchUnpublished; used as Event.OccurredAt
}

// Repository methods all accept an explicit pgx.Tx so callers control the
// transaction lifecycle. Insert MUST run inside the caller's outer
// transaction (ACID guarantee with the surrounding ledger/order write).
// FetchUnpublished + MarkPublished are called by the publisher worker
// inside its own short-lived batch transaction (so SELECT FOR UPDATE
// SKIP LOCKED locks are held across the XADD calls and released by
// tx.Commit).
type Repository interface {
	Insert(ctx context.Context, tx pgx.Tx, row Row) error
	FetchUnpublished(ctx context.Context, tx pgx.Tx, limit int) ([]Row, error)
	MarkPublished(ctx context.Context, tx pgx.Tx, id int64) error
}
