// CONSUMER GROUP CREATION POLICY (Phase 0.4, ADR-0003):
// First-creation uses XGROUP CREATE $ MKSTREAM — new groups skip historical
// events (greenfield deployment assumption). Consumer group names are stable
// identifiers; renaming requires an explicit migration procedure
// (re-create group at 0, replay via "mopro outbox replay --since <deployment-time>").
// DO NOT rename groups casually.

package eventbus

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/redis/go-redis/v9"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/trace"
	"golang.org/x/sync/semaphore"
)

const (
	workerPoolSize = 8   // concurrent handler goroutines per Subscribe call (PROMPTS.md § 0.4)
	xreadCount     = 100 // messages per XREADGROUP batch (PROMPTS.md § 1237)
	xreadBlockMS   = 5000 * time.Millisecond
	defaultMaxLen  = 10000
)

// RedisBus is the Redis Streams implementation of both Publisher and Consumer.
type RedisBus struct {
	client *redis.Client
	tracer trace.Tracer
	log    *slog.Logger
}

// NewRedisBus constructs a RedisBus backed by client.
// The OTel tracer is obtained from the global TracerProvider (no-op if uninitialised).
func NewRedisBus(client *redis.Client, log *slog.Logger) *RedisBus {
	return &RedisBus{
		client: client,
		tracer: otel.GetTracerProvider().Tracer("github.com/mopro/platform/internal/eventbus"),
		log:    log,
	}
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
func (b *RedisBus) Subscribe(ctx context.Context, group, topic string, handler func(context.Context, Event) error) error {
	if err := b.ensureGroup(ctx, topic, group); err != nil {
		return err
	}

	consumerName := fmt.Sprintf("%s:%s:%d", group, hostname(), os.Getpid())
	sem := semaphore.NewWeighted(workerPoolSize)

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

	streams, err := b.client.XReadGroup(ctx, args).Result()
	if err != nil {
		if err == redis.Nil || ctx.Err() != nil {
			return // BLOCK timeout or context cancellation — both normal
		}
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
				b.dispatchMessage(ctx, topic, group, msgCopy, handler)
			}()
		}
	}
}

// dispatchMessage parses one stream entry, injects the remote OTel span (OQ3),
// runs handler, and XACKs on success.
func (b *RedisBus) dispatchMessage(
	ctx context.Context,
	topic, group string,
	msg redis.XMessage,
	handler func(context.Context, Event) error,
) {
	ev, err := parseStreamEntry(msg)
	if err != nil {
		b.log.Error("eventbus.parse_failed",
			slog.String("stream", topic),
			slog.String("msg_id", msg.ID),
			slog.String("err", err.Error()),
		)
		return
	}

	// Inject remote span context: links the consumer span to the producer span in Grafana Tempo.
	handlerCtx := injectRemoteSpan(ctx, ev)
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

	if handlerErr := handler(handlerCtx, ev); handlerErr != nil {
		span.RecordError(handlerErr)
		span.SetStatus(codes.Error, handlerErr.Error())
		b.log.Error("eventbus.handler_failed",
			slog.String("stream", topic),
			slog.String("event_id", ev.EventID),
			slog.String("idempotency_key", ev.IdempotencyKey),
			slog.String("err", handlerErr.Error()),
			slog.String("note", "NOT acked — Redis will redeliver"),
		)
		return // do NOT XACK
	}

	if ackErr := b.client.XAck(ctx, topic, group, msg.ID).Err(); ackErr != nil {
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
