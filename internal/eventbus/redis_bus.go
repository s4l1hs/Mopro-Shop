// CONSUMER GROUP CREATION POLICY (Phase 0.4, ADR-0003):
// First-creation uses XGROUP CREATE $ MKSTREAM — new groups skip historical
// events (greenfield deployment assumption). Consumer group names are stable
// identifiers; renaming requires an explicit migration procedure
// (re-create group at 0, replay via "mopro outbox replay --since <deployment-time>").
// DO NOT rename groups casually.

package eventbus

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/redis/go-redis/v9"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/trace"
	"golang.org/x/sync/semaphore"

	"github.com/mopro/platform/pkg/logx"
	"github.com/mopro/platform/pkg/metrics"
	"github.com/mopro/platform/pkg/slack"
)

const (
	workerPoolSize = 8   // concurrent handler goroutines per Subscribe call (PROMPTS.md § 0.4)
	xreadCount     = 100 // messages per XREADGROUP batch (PROMPTS.md § 1237)
	xreadBlockMS   = 5000 * time.Millisecond
	defaultMaxLen  = 10000
	attemptWorkers = 4   // worker goroutines draining the attempt-log channel
	attemptChanBuf = 512 // buffered channel capacity for attempt-log rows
	sev2Window     = 10  // minutes: window for SEV2 storm rate check
	sev2Threshold  = 10  // DLQ count > sev2Threshold in window → SEV2 alert
)

// Option configures a RedisBus at construction time.
type Option func(*busOptions)

type busOptions struct {
	attemptRepo AttemptRepository
	dlqRepo     DLQRepository
	slackPoster SlackPoster
	ebMetrics   *metrics.EventBusMetrics
	svcName     string
}

// WithAttemptRepo wires an AttemptRepository into the bus for dispatch attempt logging.
// If not set (or nil), attempt logging is silently skipped.
func WithAttemptRepo(r AttemptRepository) Option {
	return func(o *busOptions) { o.attemptRepo = r }
}

// WithDLQRepo wires a DLQRepository into the bus for DLQ insertion after 3 failures.
// Requires WithAttemptRepo to also be set; if not, DLQ check is skipped.
func WithDLQRepo(r DLQRepository) Option {
	return func(o *busOptions) { o.dlqRepo = r }
}

// WithSlackPoster wires a SlackPoster for DLQ alert messages.
// SEV3 on first DLQ insertion; SEV2 when > 10 DLQ rows for same topic in 10 min.
// Use eventbus.NewSlackPosterAdapter(*slack.Client) to adapt the production client.
func WithSlackPoster(p SlackPoster) Option {
	return func(o *busOptions) { o.slackPoster = p }
}

// WithMetrics wires a *metrics.EventBusMetrics for consumer throughput tracking.
// svcName is the service label on all emitted metrics (e.g. "fin-svc").
func WithMetrics(m *metrics.EventBusMetrics, svcName string) Option {
	return func(o *busOptions) {
		o.ebMetrics = m
		o.svcName = svcName
	}
}

// xackClient wraps the Redis XAck call so it can be replaced in unit tests.
// *redis.Client satisfies this interface.
type xackClient interface {
	XAck(ctx context.Context, stream, group string, ids ...string) *redis.IntCmd
}

// RedisBus is the Redis Streams implementation of both Publisher and Consumer.
type RedisBus struct {
	client      *redis.Client
	xack        xackClient // seam for testable DLQ XACK path; set to client in NewRedisBus
	tracer      trace.Tracer
	log         *slog.Logger
	attemptRepo AttemptRepository
	dlqRepo     DLQRepository
	slackPoster SlackPoster
	sev2Sent    sync.Map                 // key: string (topic) → time.Time of last SEV2 alert
	ebMetrics   *metrics.EventBusMetrics // nil when metrics not wired
	svcName     string                   // for metric labels; empty when metrics not wired

	// Attempt-log worker pool: buffered channel drained by attemptWorkers goroutines.
	// Started lazily (once) on the first Subscribe call.
	attemptCh        chan AttemptRow
	startWorkersOnce sync.Once
}

// NewRedisBus constructs a RedisBus backed by client.
// The OTel tracer is obtained from the global TracerProvider (no-op if uninitialised).
func NewRedisBus(client *redis.Client, log *slog.Logger, opts ...Option) *RedisBus {
	o := &busOptions{}
	for _, opt := range opts {
		opt(o)
	}
	b := &RedisBus{
		client:      client,
		xack:        client,
		tracer:      otel.GetTracerProvider().Tracer("github.com/mopro/platform/internal/eventbus"),
		log:         log,
		attemptRepo: o.attemptRepo,
		dlqRepo:     o.dlqRepo,
		slackPoster: o.slackPoster,
		ebMetrics:   o.ebMetrics,
		svcName:     o.svcName,
	}
	if o.attemptRepo != nil {
		b.attemptCh = make(chan AttemptRow, attemptChanBuf)
	}
	return b
}

// Publish XADDs ev to a Redis Stream keyed by ev.EventType.
// Market and Currency are stored as explicit top-level stream entry fields
// so consumers can filter/route without deserialising Payload.
// MAXLEN is approximate (~ operator) for O(1) trim performance.
func (b *RedisBus) Publish(ctx context.Context, ev Event) error {
	values := map[string]interface{}{
		"event_id":        ev.EventID,
		"event_type":      ev.EventType,
		"aggregate":       ev.Aggregate,
		"idempotency_key": ev.IdempotencyKey,
		"market":          ev.Market,
		"currency":        ev.Currency,
		"trace_id":        ev.TraceID,
		"span_id":         ev.SpanID,
		"occurred_at":     ev.OccurredAt.UTC().Format(time.RFC3339Nano),
		"payload":         string(ev.Payload),
	}

	err := b.client.XAdd(ctx, &redis.XAddArgs{
		Stream: ev.EventType,
		MaxLen: b.maxLenFor(ev.EventType),
		Approx: true,
		Values: values,
	}).Err()
	if err != nil {
		return fmt.Errorf("eventbus: XADD stream=%s: %w", ev.EventType, err)
	}
	return nil
}

// Subscribe starts a blocking XREADGROUP loop on topic.
// Messages are dispatched to handler in goroutines bounded by workerPoolSize (8).
// Blocks until ctx is cancelled; returns nil on cancellation.
// PEL (pending/unacked messages from previous cycles) is drained before each new-message fetch.
// An XAUTOCLAIM goroutine runs every EVENTBUS_AUTOCLAIM_TICK_MS (default 60 000 ms) and
// reclaims messages idle > EVENTBUS_AUTOCLAIM_IDLE_MS (default 300 000 ms) from other
// consumers in the group (e.g., a previous process that crashed before XACKing).
func (b *RedisBus) Subscribe(ctx context.Context, group, topic string, handler func(context.Context, Event) error) error {
	if err := b.ensureGroup(ctx, topic, group); err != nil {
		return err
	}

	consumerName := fmt.Sprintf("%s:%s:%d", group, hostname(), os.Getpid())
	sem := semaphore.NewWeighted(workerPoolSize)

	// Start attempt-log worker pool once across all Subscribe calls on this bus.
	if b.attemptRepo != nil {
		b.startWorkersOnce.Do(func() { b.launchAttemptWorkers(ctx) })
	}

	// XAUTOCLAIM goroutine — reclaims orphaned PEL entries from crashed/restarted consumers.
	go b.runXAutoClaim(ctx, group, topic, consumerName, sem, handler)

	for {
		if ctx.Err() != nil {
			return nil
		}

		// Phase 1: re-deliver PEL (unacked messages from previous cycles / crash recovery).
		b.consumeBatch(ctx, topic, group, consumerName, "0", false, sem, handler)

		// Phase 2: fetch new messages with a 5-second block.
		b.consumeBatch(ctx, topic, group, consumerName, ">", true, sem, handler)
	}
}

// consumeBatch issues one XREADGROUP call and dispatches each message to a goroutine.
// id="0" → PEL re-deliveries (non-blocking); id=">" → new messages (blocking when blocking=true).
func (b *RedisBus) consumeBatch(
	ctx context.Context,
	topic, group, consumerName, id string,
	blocking bool,
	sem *semaphore.Weighted,
	handler func(context.Context, Event) error,
) {
	args := &redis.XReadGroupArgs{
		Group:    group,
		Consumer: consumerName,
		Streams:  []string{topic, id},
		Count:    xreadCount,
	}
	if blocking {
		args.Block = xreadBlockMS
	}

	batchCtx, batchSpan := b.tracer.Start(ctx, "eventbus.xreadgroup:"+topic,
		trace.WithSpanKind(trace.SpanKindConsumer),
		trace.WithAttributes(
			attribute.String("messaging.system", "redis"),
			attribute.String("messaging.destination", topic),
			attribute.String("messaging.consumer_group", group),
		),
	)
	defer batchSpan.End()

	streams, err := b.client.XReadGroup(batchCtx, args).Result()
	if err != nil {
		if err == redis.Nil || ctx.Err() != nil {
			return // BLOCK timeout or context cancellation — both normal
		}
		batchSpan.RecordError(err)
		b.log.Error("eventbus.xreadgroup_failed",
			slog.String("stream", topic),
			slog.String("group", group),
			slog.String("id", id),
			slog.String("err", err.Error()),
		)
		time.Sleep(5 * time.Second) // simple backoff; Phase 3.3 adds exponential
		return
	}

	for _, stream := range streams {
		batchSpan.SetAttributes(attribute.Int("messaging.batch.message_count", len(stream.Messages)))
		b.log.Info("eventbus.batch_received",
			slog.String("stream", topic),
			slog.String("group", group),
			slog.Int("count", len(stream.Messages)),
		)
		for _, msg := range stream.Messages {
			if ctx.Err() != nil {
				return
			}
			if err := sem.Acquire(ctx, 1); err != nil {
				return // context cancelled
			}
			msgCopy := msg
			go func() {
				defer sem.Release(1)
				b.dispatchMessage(ctx, topic, group, consumerName, msgCopy, handler)
			}()
		}
	}
}

// dispatchMessage parses one stream entry, injects the remote OTel span,
// runs handler, and XACKs on success. Panics are recovered and counted as errors.
// On failure, attempt outcome is logged; when failure count >= DLQThreshold the
// message is synchronously written to the DLQ and XACKed to break the retry loop.
func (b *RedisBus) dispatchMessage(
	ctx context.Context,
	topic, group, consumerName string,
	msg redis.XMessage,
	handler func(context.Context, Event) error,
) {
	start := time.Now()
	outcome := "success"
	var handlerErr error
	// ev is declared before defer so the DLQ insertion path can use its idempotency_key.
	var ev Event

	defer func() {
		dur := time.Since(start)
		// Recover from handler panics — convert to error, keep message in PEL.
		if r := recover(); r != nil {
			outcome = "panic"
			handlerErr = fmt.Errorf("panic: %v", r)
			b.log.Error("eventbus.handler_panicked",
				slog.String("stream", topic),
				slog.String("msg_id", msg.ID),
				slog.Any("panic", r),
			)
		}
		if b.ebMetrics != nil {
			b.ebMetrics.RecordDispatch(b.svcName, group, ev.EventType, outcome, dur)
		}
		row := AttemptRow{
			Stream:        topic,
			MessageID:     msg.ID,
			ConsumerGroup: group,
			ConsumerName:  consumerName,
			Outcome:       outcome,
			ErrorMessage:  errString(handlerErr),
			DurationMs:    int(dur.Milliseconds()),
		}
		if b.attemptRepo != nil {
			b.sendAttempt(row) // async, buffered
		}
		if outcome != "success" && b.dlqRepo != nil {
			// Synchronous: may XACK if DLQ threshold is reached.
			// Runs BEFORE returning from dispatchMessage — must complete before
			// the semaphore slot is released so the caller's loop stays coherent.
			b.insertDLQIfThreshold(ctx, topic, group, consumerName, msg, row, ev)
		}
	}()

	var parseErr error
	ev, parseErr = parseStreamEntry(msg)
	if parseErr != nil {
		b.log.Error("eventbus.parse_failed",
			slog.String("stream", topic),
			slog.String("msg_id", msg.ID),
			slog.String("err", parseErr.Error()),
		)
		outcome = "error"
		handlerErr = parseErr
		return // no XACK — malformed message stays in PEL (DLQ path fires via defer)
	}

	// Inject remote span context: links consumer span to producer span in Grafana Tempo.
	handlerCtx := injectRemoteSpan(ctx, ev)
	handlerCtx = logx.With(handlerCtx,
		slog.String("event_type", ev.EventType),
		slog.String("idempotency_key", ev.IdempotencyKey),
		slog.String("market", ev.Market),
		slog.String("trace_id", ev.TraceID),
	)
	handlerCtx, span := b.tracer.Start(handlerCtx,
		"eventbus.handle:"+ev.EventType,
		trace.WithSpanKind(trace.SpanKindConsumer),
	)
	defer span.End()

	b.log.Info("eventbus.dispatch",
		slog.String("stream", topic),
		slog.String("event_id", ev.EventID),
		slog.String("idempotency_key", ev.IdempotencyKey),
		slog.String("market", ev.Market),
		slog.String("currency", ev.Currency),
		slog.String("trace_id", ev.TraceID),
	)

	if handlerErr = handler(handlerCtx, ev); handlerErr != nil {
		outcome = "error"
		span.RecordError(handlerErr)
		span.SetStatus(codes.Error, handlerErr.Error())
		b.log.Error("eventbus.handler_failed",
			slog.String("stream", topic),
			slog.String("event_id", ev.EventID),
			slog.String("idempotency_key", ev.IdempotencyKey),
			slog.String("err", handlerErr.Error()),
			slog.String("note", "NOT acked — DLQ path will check threshold"),
		)
		return // do NOT XACK here — defer handles DLQ path
	}

	// Success: XACK to remove from PEL.
	if ackErr := b.xack.XAck(ctx, topic, group, msg.ID).Err(); ackErr != nil {
		b.log.Error("eventbus.xack_failed",
			slog.String("stream", topic),
			slog.String("msg_id", msg.ID),
			slog.String("err", ackErr.Error()),
		)
		return
	}

	b.log.Info("eventbus.acked",
		slog.String("stream", topic),
		slog.String("event_id", ev.EventID),
		slog.String("idempotency_key", ev.IdempotencyKey),
	)
}

// insertDLQIfThreshold is called synchronously from the dispatchMessage defer block
// when outcome != "success". It writes the DLQ row and XACKs the message when the
// failure count crosses DLQThreshold. If the DB insert fails, XACK is NOT called
// so the message stays in PEL for the next XAUTOCLAIM cycle.
func (b *RedisBus) insertDLQIfThreshold(
	ctx context.Context,
	topic, group, consumerName string,
	msg redis.XMessage,
	current AttemptRow,
	ev Event,
) {
	// Build DLQ payload from raw stream entry values — always available even when
	// ev parse failed (ev.IdempotencyKey will be empty in that case).
	payloadJSON, _ := json.Marshal(msg.Values)
	idemKey := ev.IdempotencyKey
	if idemKey == "" {
		idemKey = msg.ID // fallback for malformed events
	}

	dlqRow := DLQRow{
		OriginalTopic:     topic,
		OriginalMessageID: msg.ID,
		ConsumerGroup:     group,
		IdempotencyKey:    idemKey,
		Payload:           payloadJSON,
	}

	res, dlqID, err := b.dlqRepo.InsertIfThreshold(ctx, dlqRow, current)
	if err != nil {
		b.log.Error("eventbus.dlq_insert_failed",
			slog.String("stream", topic),
			slog.String("msg_id", msg.ID),
			slog.String("err", err.Error()),
			slog.String("note", "NOT acked — message stays in PEL"),
		)
		return // do NOT XACK — message stays in PEL for retry
	}

	switch res {
	case DLQBelowThreshold:
		return // failure count not reached; message stays in PEL

	case DLQAlreadyExists:
		// Row already exists from a prior cycle where XACK failed.
		// Retry the XACK to stop the delivery storm.
		if ackErr := b.xack.XAck(ctx, topic, group, msg.ID).Err(); ackErr != nil {
			b.log.Error("eventbus.xack_retry_failed",
				slog.String("stream", topic),
				slog.String("msg_id", msg.ID),
				slog.Int64("existing_dlq_id", dlqID),
				slog.String("err", ackErr.Error()),
			)
		}

	case DLQInserted:
		// First insertion. XACK to break the retry loop.
		if ackErr := b.xack.XAck(ctx, topic, group, msg.ID).Err(); ackErr != nil {
			b.log.Error("eventbus.xack_failed_after_dlq",
				slog.String("stream", topic),
				slog.String("msg_id", msg.ID),
				slog.Int64("dlq_id", dlqID),
				slog.String("err", ackErr.Error()),
				slog.String("note", "DLQ row exists; next redelivery will retry XACK via DLQAlreadyExists path"),
			)
			// Fall through: still log and alert even if XACK failed.
		}
		b.log.Info("eventbus.dlq_inserted",
			slog.String("stream", topic),
			slog.String("msg_id", msg.ID),
			slog.String("group", group),
			slog.Int64("dlq_id", dlqID),
			slog.String("idempotency_key", idemKey),
		)
		if b.ebMetrics != nil {
			b.ebMetrics.RecordDLQ(b.svcName, group, topic)
		}
		b.sendDLQAlert(ctx, topic, group, idemKey, current, dlqID)
	}
}

// sendDLQAlert posts a Slack alert for the newly-inserted DLQ row.
// SEV3 on first insertion; SEV2 if count in last 10 min exceeds sev2Threshold.
// Slack failures are logged but do not affect the DLQ insertion outcome.
func (b *RedisBus) sendDLQAlert(
	ctx context.Context,
	topic, group, idemKey string,
	current AttemptRow,
	dlqID int64,
) {
	if b.slackPoster == nil {
		return
	}

	// SEV2 storm check: count DLQ rows in last sev2Window minutes for this topic.
	count, countErr := b.dlqRepo.CountInWindow(ctx, topic, sev2Window)
	if countErr != nil {
		b.log.Warn("eventbus.dlq_count_window_failed", slog.String("err", countErr.Error()))
	}

	var text string
	if count > sev2Threshold && b.shouldSendSEV2(topic) {
		text = fmt.Sprintf(
			":rotating_light: *[SEV2] DLQ Storm — fin-svc* — %d messages in %d min | Topic: `%s` | Run: `mopro dlq list --topic %s --since %dm`",
			count, sev2Window, topic, topic, sev2Window,
		)
	} else {
		errSnip := current.ErrorMessage
		if len(errSnip) > 120 {
			errSnip = errSnip[:120] + "…"
		}
		text = fmt.Sprintf(
			":warning: *[SEV3] DLQ Insertion — fin-svc* | DLQ ID: %d | Topic: `%s` | Group: `%s` | Key: `%s` | Error: %s | Run: `mopro dlq inspect %d`",
			dlqID, topic, group, idemKey, errSnip, dlqID,
		)
	}

	if err := b.slackPoster.PostDLQAlert(ctx, text); err != nil {
		b.log.Error("eventbus.dlq_slack_alert_failed",
			slog.Int64("dlq_id", dlqID),
			slog.String("err", err.Error()),
		)
	}
}

// shouldSendSEV2 returns true if we have NOT sent a SEV2 alert for this topic
// within the last sev2Window minutes. Uses an in-memory sync.Map to suppress
// duplicate SEV2 pages during a sustained storm.
func (b *RedisBus) shouldSendSEV2(topic string) bool {
	now := time.Now()
	if t, ok := b.sev2Sent.Load(topic); ok {
		if ts, isTime := t.(time.Time); isTime && now.Sub(ts) < time.Duration(sev2Window)*time.Minute {
			return false
		}
	}
	b.sev2Sent.Store(topic, now)
	return true
}

// NewSlackPosterAdapter wraps a *slack.Client to satisfy SlackPoster.
// Pass the result to WithSlackPoster when constructing RedisBus.
func NewSlackPosterAdapter(c *slack.Client) SlackPoster {
	return &slackPosterAdapter{c: c}
}

type slackPosterAdapter struct{ c *slack.Client }

func (a *slackPosterAdapter) PostDLQAlert(ctx context.Context, text string) error {
	return a.c.Post(ctx, slack.Message{Text: text})
}

// runXAutoClaim runs XAUTOCLAIM in a ticker loop for the duration of ctx.
// It reclaims messages that have been in another consumer's PEL for longer than
// EVENTBUS_AUTOCLAIM_IDLE_MS (default 300 000 ms = 5 min) and dispatches them
// through the same handler. Runs every EVENTBUS_AUTOCLAIM_TICK_MS (default 60 000 ms).
func (b *RedisBus) runXAutoClaim(
	ctx context.Context,
	group, topic, consumerName string,
	sem *semaphore.Weighted,
	handler func(context.Context, Event) error,
) {
	idleMS := envInt("EVENTBUS_AUTOCLAIM_IDLE_MS", 300_000)
	tickMS := envInt("EVENTBUS_AUTOCLAIM_TICK_MS", 60_000)
	minIdle := time.Duration(idleMS) * time.Millisecond

	ticker := time.NewTicker(time.Duration(tickMS) * time.Millisecond)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			b.claimOrphaned(ctx, group, topic, consumerName, minIdle, sem, handler)
		}
	}
}

// claimOrphaned runs one full XAUTOCLAIM sweep (may span multiple batches via cursor).
func (b *RedisBus) claimOrphaned(
	ctx context.Context,
	group, topic, consumerName string,
	minIdle time.Duration,
	sem *semaphore.Weighted,
	handler func(context.Context, Event) error,
) {
	start := "0-0"
	for {
		if ctx.Err() != nil {
			return
		}
		msgs, nextStart, err := b.client.XAutoClaim(ctx, &redis.XAutoClaimArgs{
			Stream:   topic,
			Group:    group,
			Consumer: consumerName,
			MinIdle:  minIdle,
			Start:    start,
			Count:    xreadCount,
		}).Result()
		if err != nil {
			if ctx.Err() != nil {
				return
			}
			b.log.Error("eventbus.xautoclaim_failed",
				slog.String("stream", topic),
				slog.String("group", group),
				slog.String("err", err.Error()),
			)
			return
		}
		if len(msgs) > 0 {
			b.log.Info("eventbus.xautoclaim_claimed",
				slog.String("stream", topic),
				slog.String("group", group),
				slog.Int("count", len(msgs)),
			)
		}
		for _, msg := range msgs {
			if ctx.Err() != nil {
				return
			}
			if err := sem.Acquire(ctx, 1); err != nil {
				return
			}
			msgCopy := msg
			go func() {
				defer sem.Release(1)
				b.dispatchMessage(ctx, topic, group, consumerName, msgCopy, handler)
			}()
		}
		// nextStart == "0-0" means no more messages to claim in this sweep.
		if nextStart == "0-0" || len(msgs) == 0 {
			return
		}
		start = nextStart
	}
}

// launchAttemptWorkers starts attemptWorkers goroutines that drain b.attemptCh.
// Workers use context.Background() so inserts are not cancelled by the subscriber ctx.
func (b *RedisBus) launchAttemptWorkers(ctx context.Context) {
	for i := 0; i < attemptWorkers; i++ {
		go func() { //nolint:gosec // workers intentionally use context.Background() for inserts to outlive subscriber ctx
			for {
				select {
				case <-ctx.Done():
					// Drain remaining rows before exiting.
					for {
						select {
						case row := <-b.attemptCh:
							if err := b.attemptRepo.Insert(context.Background(), row); err != nil {
								b.log.Warn("eventbus: attempt-log insert failed", "err", err)
							}
						default:
							return
						}
					}
				case row := <-b.attemptCh:
					if err := b.attemptRepo.Insert(context.Background(), row); err != nil {
						b.log.Warn("eventbus: attempt-log insert failed", "err", err)
					}
				}
			}
		}()
	}
}

// sendAttempt queues an attempt row for async insertion. Non-blocking: drops the row
// with a WARN if the channel is full.
func (b *RedisBus) sendAttempt(row AttemptRow) {
	select {
	case b.attemptCh <- row:
	default:
		b.log.Warn("eventbus: attempt channel full, dropping record",
			slog.String("stream", row.Stream),
			slog.String("msg_id", row.MessageID),
		)
	}
}

// maxLenFor returns the MAXLEN for a stream, reading a per-stream env override first.
//
// Override env key: REDIS_STREAM_MAXLEN_<STREAM_UPPER_DOTS_TO_UNDERSCORES>
// Example: REDIS_STREAM_MAXLEN_ECOM_ORDER_DELIVERED_V1=25000
// Default: 10000 (≈1.6 hours buffer at 100 events/min).
// See ADR-0003 and .env.example for production recommendations.
func (b *RedisBus) maxLenFor(topic string) int64 {
	envKey := "REDIS_STREAM_MAXLEN_" + strings.ReplaceAll(strings.ToUpper(topic), ".", "_")
	if v := os.Getenv(envKey); v != "" {
		if n, err := strconv.ParseInt(v, 10, 64); err == nil && n > 0 {
			return n
		}
	}
	return defaultMaxLen
}

// ensureGroup creates the consumer group (with MKSTREAM) if it does not yet exist.
// BUSYGROUP error means the group already exists — treated as a no-op success.
func (b *RedisBus) ensureGroup(ctx context.Context, topic, group string) error {
	err := b.client.XGroupCreateMkStream(ctx, topic, group, "$").Err()
	if err != nil && !strings.HasPrefix(err.Error(), "BUSYGROUP") {
		return fmt.Errorf("eventbus: XGROUP CREATE stream=%s group=%s: %w", topic, group, err)
	}
	return nil
}

// parseStreamEntry converts a Redis stream message back to an Event.
func parseStreamEntry(msg redis.XMessage) (Event, error) {
	get := func(key string) string {
		if v, ok := msg.Values[key]; ok {
			if s, ok := v.(string); ok {
				return s
			}
		}
		return ""
	}

	occurredAtStr := get("occurred_at")
	if occurredAtStr == "" {
		return Event{}, fmt.Errorf("eventbus: missing occurred_at in stream entry %s", msg.ID)
	}
	occurredAt, err := time.Parse(time.RFC3339Nano, occurredAtStr)
	if err != nil {
		return Event{}, fmt.Errorf("eventbus: parse occurred_at %q: %w", occurredAtStr, err)
	}

	payload := get("payload")
	if payload == "" {
		payload = "{}"
	}

	return Event{
		EventID:        get("event_id"),
		EventType:      get("event_type"),
		Aggregate:      get("aggregate"),
		IdempotencyKey: get("idempotency_key"),
		Market:         get("market"),
		Currency:       get("currency"),
		TraceID:        get("trace_id"),
		SpanID:         get("span_id"),
		OccurredAt:     occurredAt,
		Payload:        []byte(payload),
	}, nil
}

// injectRemoteSpan builds a context with the event's TraceID/SpanID as the remote parent.
// Enables end-to-end distributed tracing across the Redis Streams async boundary.
func injectRemoteSpan(ctx context.Context, ev Event) context.Context {
	if ev.TraceID == "" || ev.SpanID == "" {
		return ctx
	}
	traceID, err1 := trace.TraceIDFromHex(ev.TraceID)
	spanID, err2 := trace.SpanIDFromHex(ev.SpanID)
	if err1 != nil || err2 != nil {
		return ctx
	}
	spanCtx := trace.NewSpanContext(trace.SpanContextConfig{
		TraceID:    traceID,
		SpanID:     spanID,
		TraceFlags: trace.FlagsSampled,
		Remote:     true,
	})
	return trace.ContextWithRemoteSpanContext(ctx, spanCtx)
}

// hostname returns the machine hostname, falling back to "unknown".
func hostname() string {
	h, err := os.Hostname()
	if err != nil {
		return "unknown"
	}
	return h
}

// errString returns err.Error() or "" if err is nil.
func errString(err error) string {
	if err == nil {
		return ""
	}
	return err.Error()
}

// envInt reads an integer from an environment variable.
// Returns defaultVal if the key is unset or cannot be parsed.
func envInt(key string, defaultVal int) int {
	if v := os.Getenv(key); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			return n
		}
	}
	return defaultVal
}
