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
	"errors"
	"fmt"
	"log/slog"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/trace"

	"github.com/mopro/platform/internal/eventbus"
	"github.com/mopro/platform/pkg/metrics"
)

const (
	minBatchSize         = 100
	maxBatchSize         = 500
	initialBackoff       = time.Second
	maxBackoff           = 60 * time.Second
	lagAlertThreshold    = 60 * time.Second
	gracefulDrainTimeout = 30 * time.Second
	idlePollInterval     = 5 * time.Second
)

// Option configures a Publisher.
type Option func(*Publisher)

// WithServiceName sets the service identifier used in metric labels.
// Example: WithServiceName("fin") → service label on all emitted metrics.
// Default is "mopro" when not set.
func WithServiceName(name string) Option {
	return func(p *Publisher) { p.svcName = name }
}

// WithLagTable sets the schema-qualified outbox table for lag metric queries.
// When not set, the lag metric is not emitted.
func WithLagTable(table string) Option {
	return func(p *Publisher) { p.lagTable = table }
}

// WithOutboxMetrics wires Prometheus metrics for outbox publish throughput and lag.
func WithOutboxMetrics(m *metrics.OutboxMetrics) Option {
	return func(p *Publisher) { p.outboxM = m }
}

// Publisher is the outbox relay worker. It drains unpublished rows from the outbox
// table to Redis Streams via eventbus.Publisher in at-least-once delivery order.
// Batch size grows adaptively on clean cycles (100 → 500) and falls back to
// minBatchSize on Redis errors. Redis errors trigger exponential backoff
// (1s → 2s → 4s → … capped at 60s) before the next cycle.
type Publisher struct {
	pool     *pgxpool.Pool
	repo     Repository
	bus      eventbus.Publisher
	log      *slog.Logger
	svcName  string
	lagTable string

	// adaptive batch state — updated by RunBatch, read by Run (single-goroutine)
	batchSize     int
	redisErrCount int // Redis XADD failures in the last RunBatch call

	// backoff state — managed exclusively by Run loop
	backoff time.Duration

	lagEnabled bool
	outboxM    *metrics.OutboxMetrics // nil when metrics not wired; all calls are nil-safe
}

// NewPublisher constructs a Publisher.
// Use WithOutboxMetrics to wire Prometheus metrics (optional; nil-safe if absent).
func NewPublisher(pool *pgxpool.Pool, repo Repository, bus eventbus.Publisher, log *slog.Logger, opts ...Option) (*Publisher, error) {
	p := &Publisher{
		pool:      pool,
		repo:      repo,
		bus:       bus,
		log:       log,
		svcName:   "mopro",
		batchSize: minBatchSize,
	}
	for _, o := range opts {
		o(p)
	}
	if p.lagTable != "" {
		p.lagEnabled = true
	}
	return p, nil
}

// Run starts the adaptive drain loop. Blocks until ctx is cancelled.
// On cancellation, attempts one graceful drain batch (up to gracefulDrainTimeout)
// to flush rows queued just before shutdown, then returns nil.
func (p *Publisher) Run(ctx context.Context) error {
	for {
		if ctx.Err() != nil {
			return p.drainGraceful()
		}

		n, err := p.RunBatch(ctx)
		if err != nil {
			p.log.Error("outbox.batch_error", slog.String("err", err.Error()))
			select {
			case <-ctx.Done():
				return p.drainGraceful()
			case <-time.After(idlePollInterval):
			}
			continue
		}

		p.updateBatchSize()
		p.updateBackoff()
		p.recordLag(ctx)

		if n == 0 {
			// Idle: wait, honouring any active backoff.
			delay := idlePollInterval
			if p.backoff > delay {
				delay = p.backoff
			}
			select {
			case <-ctx.Done():
				return p.drainGraceful()
			case <-time.After(delay):
			}
		} else if p.backoff > 0 {
			// Non-empty batch but Redis errors — throttle before next cycle.
			select {
			case <-ctx.Done():
				return p.drainGraceful()
			case <-time.After(p.backoff):
			}
		}
		// Non-empty, error-free batch: loop immediately.
	}
}

// drainGraceful runs one final RunBatch with a short-lived background context
// to flush rows that arrived or were stranded just before shutdown.
func (p *Publisher) drainGraceful() error {
	drainCtx, cancel := context.WithTimeout(context.Background(), gracefulDrainTimeout)
	defer cancel()
	n, err := p.RunBatch(drainCtx)
	if err != nil {
		p.log.Warn("outbox.drain_error", slog.String("err", err.Error()))
		return nil
	}
	if n > 0 {
		p.log.Info("outbox.drain_completed", slog.Int("published", n))
	}
	return nil
}

// outboxTracer is used for batch-level spans in RunBatch.
var outboxTracer = otel.GetTracerProvider().Tracer("github.com/mopro/platform/internal/outbox")

// RunBatch executes one drain cycle: claims up to p.batchSize rows from the outbox
// table (SELECT FOR UPDATE SKIP LOCKED), publishes each to Redis Streams, then marks
// them published. Returns the number of rows successfully published.
//
// Exported for testing: integration tests call RunBatch directly to drive individual cycles
// without the infinite loop.
//
// Redis XADD failures are counted in p.redisErrCount (read by Run for backoff and
// batch-size adjustment) and logged; the row is skipped and retried on the next cycle.
//
// If MarkPublished fails (rare DB error), the entire batch transaction is rolled back. Any
// rows already XADDed in this cycle will be re-published on the next RunBatch call.
// This is the at-least-once guarantee — consumer handlers handle the duplicate via
// idempotency checks.
func (p *Publisher) RunBatch(ctx context.Context) (int, error) {
	p.redisErrCount = 0
	batchStart := time.Now()

	ctx, span := outboxTracer.Start(ctx, "outbox.run_batch",
		trace.WithSpanKind(trace.SpanKindProducer),
	)
	defer func() {
		span.End()
		if p.outboxM != nil {
			p.outboxM.RecordBatch(p.svcName, time.Since(batchStart))
		}
	}()

	tx, err := p.pool.Begin(ctx)
	if err != nil {
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
		return 0, fmt.Errorf("outbox: begin batch tx: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }() // no-op after Commit; cleans up on all error paths

	rows, err := p.repo.FetchUnpublished(ctx, tx, p.batchSize)
	if err != nil {
		return 0, fmt.Errorf("outbox: fetch unpublished: %w", err)
	}
	if len(rows) == 0 {
		return 0, nil
	}

	p.log.Info("outbox.batch_fetched", slog.Int("count", len(rows)), slog.Int("batch_size", p.batchSize))

	published := 0
	for _, row := range rows {
		ev := rowToEvent(row)

		if err := p.bus.Publish(ctx, ev); err != nil {
			p.redisErrCount++
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
		span.RecordError(err)
		span.SetStatus(codes.Error, err.Error())
		return 0, fmt.Errorf("outbox: commit batch tx: %w", err)
	}
	span.SetAttributes(attribute.Int("outbox.published", published))
	return published, nil
}

// updateBatchSize scales the batch size up by 50% on error-free cycles,
// and resets to minBatchSize when Redis errors were detected.
func (p *Publisher) updateBatchSize() {
	if p.redisErrCount > 0 {
		p.batchSize = minBatchSize
		return
	}
	next := p.batchSize + p.batchSize/2
	if next > maxBatchSize {
		next = maxBatchSize
	}
	p.batchSize = next
}

// updateBackoff doubles the backoff delay on Redis errors (capped at maxBackoff),
// and resets it to zero when a cycle completes without errors.
func (p *Publisher) updateBackoff() {
	if p.redisErrCount > 0 {
		if p.backoff == 0 {
			p.backoff = initialBackoff
		} else {
			p.backoff *= 2
			if p.backoff > maxBackoff {
				p.backoff = maxBackoff
			}
		}
		return
	}
	p.backoff = 0
}

// recordLag queries the oldest unpublished outbox row, records the lag metric,
// and logs a warning when lag exceeds lagAlertThreshold.
func (p *Publisher) recordLag(ctx context.Context) {
	if !p.lagEnabled {
		return
	}
	var createdAt time.Time
	// lagTable is operator-controlled (never user input); interpolation is safe.
	err := p.pool.QueryRow(ctx, `
		SELECT created_at FROM `+p.lagTable+`
		WHERE published_at IS NULL ORDER BY id ASC LIMIT 1
	`).Scan(&createdAt)
	if errors.Is(err, pgx.ErrNoRows) {
		if p.outboxM != nil {
			p.outboxM.SetLag(p.svcName, 0)
		}
		return
	}
	if err != nil {
		return // transient DB error: skip this cycle's metric update
	}
	lag := time.Since(createdAt).Seconds()
	if p.outboxM != nil {
		p.outboxM.SetLag(p.svcName, lag)
	}
	if lag > lagAlertThreshold.Seconds() {
		p.log.Warn("outbox.lag_alert",
			slog.Float64("lag_seconds", lag),
			slog.String("table", p.lagTable),
		)
	}
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

func (p *Publisher) emitMetric(_ context.Context, row Row, result string) {
	if p.outboxM != nil {
		p.outboxM.RecordPublish(p.svcName, row.EventType, result)
	}
}
