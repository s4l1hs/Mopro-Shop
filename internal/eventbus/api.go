// Package eventbus defines the Redis Streams event bus interface for cross-binary communication.
// core-svc → fin-svc and fin-svc → core-svc communicate ONLY via this interface
// (CLAUDE.md § 3, ARCHITECTURE.md § 5). Direct HTTP between binaries is FORBIDDEN.
package eventbus

import (
	"context"
	"encoding/json"
	"errors"
	"time"
)

// Event is the canonical envelope for all cross-binary async messages.
// Every field is mandatory; zero-value fields indicate a programming error.
// Market and Currency are first-class fields (not buried in Payload) so
// consumers can route/filter without deserialising the payload.
type Event struct {
	EventID        string          // deterministic: set to IdempotencyKey by outbox publisher
	EventType      string          // topic format: <domain>.<entity>.<action>.v<n>
	Aggregate      string          // e.g. "order" | "cashback" | "sellerpayout"
	IdempotencyKey string          // end-to-end dedup key; matches outbox.idempotency_key
	Market         string          // "TR" | "DE" | … — always propagated from originating tx
	Currency       string          // "TRY" | "TRY_COIN" | … — account currency from originating tx
	TraceID        string          // OTel trace ID, hex-encoded
	SpanID         string          // OTel span ID, hex-encoded
	OccurredAt     time.Time       // when the triggering DB row committed (outbox.created_at)
	Payload        json.RawMessage // opaque domain body; consumers decode into their own types
}

// Publisher publishes a single event to the Redis Streams event bus.
type Publisher interface {
	Publish(ctx context.Context, ev Event) error
}

// Consumer subscribes to a Redis Streams topic via a named consumer group.
// The handler receives a context carrying the remote OTel span from the event's
// TraceID/SpanID so Grafana Tempo can link the full async call chain
// (e.g., core-svc order.delivered → fin-svc cashback.plan.created).
// XACK is issued only on a nil handler return; errors leave the message in the PEL
// for redelivery.
type Consumer interface {
	Subscribe(ctx context.Context, group, topic string, handler func(context.Context, Event) error) error
}

// ErrTransient marks a publisher-side error as eligible for backoff retry.
// Phase 0.4: reserved, not used. Phase 3.3 will use this in the publisher loop
// to distinguish recoverable Redis errors (CLUSTERDOWN, LOADING, …) from
// permanent serialisation errors (unknown event_type, nil Payload, …).
var ErrTransient = errors.New("eventbus: transient error (Phase 3.3 reserved)")
