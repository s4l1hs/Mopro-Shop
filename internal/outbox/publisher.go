// AT-LEAST-ONCE DELIVERY CONTRACT (Phase 0.4, dry-run § 12 R1):
// The publisher loop XADDs to Redis BEFORE writing published_at to the outbox
// row. If the worker crashes after a successful XADD but before MarkPublished
// (or before tx.Commit), the row stays with published_at IS NULL and is
// re-fetched on the next cycle, producing a duplicate Redis stream entry.
// This is intentional: it guarantees no event is ever lost.
//
// Consumer handlers MUST be idempotent (LEDGER_GUIDE.md § 7.1, § 8.1):
// they check for existing records (FindPlanByOrderID, FindPayoutByKey, wallet
// UNIQUE(idempotency_key), etc.) before any side effect. Combined with the
// outbox UNIQUE(idempotency_key) constraint this gives end-to-end exactly-once
// semantics over an at-least-once transport.

package outbox

import (
	"context"
	"fmt"
	"log/slog"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/metric"

	"github.com/mopro/platform/internal/eventbus"
)

const (
	defaultBatchSize = 100
	idlePollInterval = 5 * time.Second
)

// Publisher is the outbox relay worker. It drains unpublished rows from the outbox
// table to Redis Streams via eventbus.Publisher in at-least-once delivery order.
type Publisher struct {
	pool           *pgxpool.Pool
	repo           Repository
	bus            eventbus.Publisher
	log            *slog.Logger
	publishCounter metric.Int64Counter
}

// NewPublisher constructs a Publisher.
// Uses the global OTel MeterProvider for the publish counter — safe in tests
// (global no-op meter when OTel is uninitialised).
func NewPublisher(pool *pgxpool.Pool, repo Repository, bus eventbus.Publisher, log *slog.Logger) (*Publisher, error) {
	meter := otel.GetMeterProvider().Meter("github.com/mopro/platform/internal/outbox")
	counter, err := meter.Int64Counter(
		"mopro.outbox.publish.total",
		metric.WithDescription("Total outbox events published to Redis Streams"),
		metric.WithUnit("{events}"),
	)
	if err != nil {
		return nil, fmt.Errorf("outbox: create publish counter: %w", err)
	}
	return &Publisher{
		pool:           pool,
		repo:           repo,
		bus:            bus,
		log:            log,
		publishCounter: counter,
	}, nil
}

// Run starts the infinite drain loop. Blocks until ctx is cancelled; returns nil.
// Intended to be called in a goroutine as a background worker.
func (p *Publisher) Run(ctx context.Context) error {
	for {
		if ctx.Err() != nil {
			return nil
		}

		published, err := p.RunBatch(ctx)
		if err != nil {
			p.log.Error("outbox.batch_error", slog.String("err", err.Error()))
			select {
			case <-ctx.Done():
				return nil
			case <-time.After(idlePollInterval):
			}
			continue
		}

		if published == 0 {
			p.log.Debug("outbox.idle",
				slog.Float64("next_poll_seconds", idlePollInterval.Seconds()),
			)
			select {
			case <-ctx.Done():
				return nil
			case <-time.After(idlePollInterval):
			}
			// Non-empty batch: immediately start next cycle (no sleep).
		}
	}
}

// RunBatch executes one drain cycle: claims up to defaultBatchSize rows from the outbox
// table (SELECT FOR UPDATE SKIP LOCKED), publishes each to Redis Streams, then marks
// them published. Returns the number of rows successfully published.
//
// Exported for testing: integration tests call RunBatch directly to drive individual cycles
// without the infinite loop.
//
// If MarkPublished fails (rare DB error), the entire batch transaction is rolled back. Any
// rows already XADDed in this cycle will be re-published on the next RunBatch call.
// This is the at-least-once guarantee — consumer handlers handle the duplicate via
// idempotency checks.
func (p *Publisher) RunBatch(ctx context.Context) (int, error) {
	tx, err := p.pool.Begin(ctx)
	if err != nil {
		return 0, fmt.Errorf("outbox: begin batch tx: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }() // no-op after Commit; cleans up on all error paths

	rows, err := p.repo.FetchUnpublished(ctx, tx, defaultBatchSize)
	if err != nil {
		return 0, fmt.Errorf("outbox: fetch unpublished: %w", err)
	}
	if len(rows) == 0 {
		return 0, nil
	}

	p.log.Info("outbox.batch_fetched", slog.Int("count", len(rows)))

	published := 0
	for _, row := range rows {
		ev := rowToEvent(row)

		if err := p.bus.Publish(ctx, ev); err != nil {
			// XADD failed: log, skip row, leave it unpublished for next cycle.
			// The PG transaction remains healthy — only the Redis call failed.
			p.log.Error("outbox.publish_failed",
				slog.Int64("id", row.ID),
				slog.String("event_type", row.EventType),
				slog.String("market", row.Market),
				slog.String("currency", row.Currency),
				slog.String("idempotency_key", row.IdempotencyKey),
				slog.String("err", err.Error()),
			)
			p.emitMetric(ctx, row, "error")
			continue
		}

		if err := p.repo.MarkPublished(ctx, tx, row.ID); err != nil {
			// DB error post-XADD: abort the batch transaction. Previously XADDed rows
			// in this cycle will be re-delivered on the next RunBatch (at-least-once).
			p.log.Error("outbox.mark_published_failed",
				slog.Int64("id", row.ID),
				slog.String("err", err.Error()),
				slog.String("warning", "tx rolled back — rows will republish on next cycle"),
			)
			p.emitMetric(ctx, row, "error")
			return published, fmt.Errorf("outbox: MarkPublished id=%d: %w (tx rolled back)", row.ID, err)
		}

		p.log.Info("outbox.published",
			slog.Int64("id", row.ID),
			slog.String("event_type", row.EventType),
			slog.String("market", row.Market),
			slog.String("currency", row.Currency),
			slog.String("idempotency_key", row.IdempotencyKey),
			slog.String("trace_id", row.TraceID),
		)
		p.emitMetric(ctx, row, "ok")
		published++
	}

	if err := tx.Commit(ctx); err != nil {
		// Rare: PG network error at commit time. All XADDed rows will be re-delivered.
		return 0, fmt.Errorf("outbox: commit batch tx: %w", err)
	}
	return published, nil
}

// rowToEvent maps an outbox.Row to an eventbus.Event.
// EventID = IdempotencyKey: deterministic so re-published rows produce the same EventID,
// allowing consumers to recognise duplicates via the idempotency_key field.
func rowToEvent(row Row) eventbus.Event {
	return eventbus.Event{
		EventID:        row.IdempotencyKey,
		EventType:      row.EventType,
		Aggregate:      row.Aggregate,
		IdempotencyKey: row.IdempotencyKey,
		Market:         row.Market,
		Currency:       row.Currency,
		TraceID:        row.TraceID,
		SpanID:         row.SpanID,
		OccurredAt:     row.CreatedAt,
		Payload:        row.Payload,
	}
}

func (p *Publisher) emitMetric(ctx context.Context, row Row, result string) {
	p.publishCounter.Add(ctx, 1,
		metric.WithAttributes(
			attribute.String("market", row.Market),
			attribute.String("currency", row.Currency),
			attribute.String("event_type", row.EventType),
			attribute.String("result", result),
		),
	)
}
