package outbox

import "errors"

// ErrDuplicateIdempotency is returned by Insert when the outbox table already
// contains a row with the same idempotency_key (UNIQUE constraint: SQLSTATE 23505).
// Callers MUST treat this as a no-op success — the event was already queued.
var ErrDuplicateIdempotency = errors.New("outbox: duplicate idempotency_key")
