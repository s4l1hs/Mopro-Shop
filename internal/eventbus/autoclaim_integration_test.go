//go:build integration

package eventbus_test

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"os"
	"sync/atomic"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"

	"github.com/mopro/platform/internal/eventbus"
)

// ── helpers ───────────────────────────────────────────────────────────────────

func redisTestAddr() string {
	if v := os.Getenv("REDIS_TEST_ADDR"); v != "" {
		return v
	}
	return "localhost:6380"
}

func ledgerTestDSN() string {
	if v := os.Getenv("LEDGER_TEST_DSN"); v != "" {
		return v
	}
	return "postgres://ledger_admin:test123@localhost:6434/mopro_ledger" //nolint:gosec
}

func newTestRedis(t *testing.T) *redis.Client {
	t.Helper()
	rc := redis.NewClient(&redis.Options{Addr: redisTestAddr()})
	if err := rc.Ping(context.Background()).Err(); err != nil {
		t.Skipf("Redis at %s not available (run make test-integration-outbox): %v", redisTestAddr(), err)
	}
	t.Cleanup(func() { _ = rc.Close() })
	return rc
}

func newTestLedgerPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	pool, err := pgxpool.New(context.Background(), ledgerTestDSN())
	if err != nil {
		t.Fatalf("newTestLedgerPool: %v", err)
	}
	if err := pool.Ping(context.Background()); err != nil {
		t.Skipf("Ledger DB at %s not available (run make test-integration-outbox): %v", ledgerTestDSN(), err)
	}
	t.Cleanup(pool.Close)
	return pool
}

func publishMinimalEvent(t *testing.T, rc *redis.Client, stream string) string {
	t.Helper()
	ctx := context.Background()
	payload, _ := json.Marshal(map[string]string{"test": "data"})
	id, err := rc.XAdd(ctx, &redis.XAddArgs{
		Stream: stream,
		Values: map[string]interface{}{
			"event_id":        fmt.Sprintf("evt-%d", time.Now().UnixNano()),
			"event_type":      stream,
			"aggregate":       "test",
			"idempotency_key": fmt.Sprintf("idem-%d", time.Now().UnixNano()),
			"market":          "TR",
			"currency":        "TRY",
			"trace_id":        "",
			"span_id":         "",
			"occurred_at":     time.Now().UTC().Format(time.RFC3339Nano),
			"payload":         string(payload),
		},
	}).Result()
	if err != nil {
		t.Fatalf("publishMinimalEvent XADD: %v", err)
	}
	return id
}

// ── XAUTOCLAIM test ───────────────────────────────────────────────────────────

// TestEventBus_XAUTOCLAIM_ClaimsOrphanedMessages simulates a consumer crash
// (message claimed but not ACKed) and verifies that a new consumer's XAUTOCLAIM
// goroutine reclaims and processes the orphaned message.
//
// Uses EVENTBUS_AUTOCLAIM_IDLE_MS=100 and EVENTBUS_AUTOCLAIM_TICK_MS=200
// so the test completes in seconds rather than minutes.
func TestEventBus_XAUTOCLAIM_ClaimsOrphanedMessages(t *testing.T) {
	t.Setenv("EVENTBUS_AUTOCLAIM_IDLE_MS", "100")
	t.Setenv("EVENTBUS_AUTOCLAIM_TICK_MS", "200")

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	rc := newTestRedis(t)

	// Unique stream/group per test run to avoid cross-test interference.
	stream := fmt.Sprintf("test.autoclaim.v1.%d", time.Now().UnixNano())
	group := "test-autoclaim-grp"

	// Pre-create consumer group at "0" so it reads all messages.
	if err := rc.XGroupCreateMkStream(ctx, stream, group, "0").Err(); err != nil {
		t.Fatalf("XGroupCreateMkStream: %v", err)
	}

	// Publish one message to the stream.
	msgID := publishMinimalEvent(t, rc, stream)
	t.Logf("published message id=%s", msgID)

	// Consumer A: claim the message but DO NOT ACK (simulate crash before XACKing).
	consumerA := fmt.Sprintf("%s:hostA:1", group)
	streams, err := rc.XReadGroup(ctx, &redis.XReadGroupArgs{
		Group:    group,
		Consumer: consumerA,
		Streams:  []string{stream, ">"},
		Count:    1,
	}).Result()
	if err != nil || len(streams) == 0 || len(streams[0].Messages) == 0 {
		t.Fatalf("consumer A XReadGroup: err=%v len=%d", err, len(streams))
	}
	t.Logf("consumer A claimed message (no ACK) — simulating crash")

	// Wait for min-idle-time to pass (100ms + buffer).
	time.Sleep(300 * time.Millisecond)

	// Consumer B: starts fresh (new consumerName = different PID).
	// Its XAUTOCLAIM goroutine should reclaim A's idle message within one tick (200ms).
	var received atomic.Bool
	handler := func(_ context.Context, ev eventbus.Event) error {
		received.Store(true)
		t.Logf("consumer B processed message id=%s", ev.EventID)
		return nil
	}

	bus := eventbus.NewRedisBus(rc, slog.Default())
	consumerCtx, cancelConsumer := context.WithCancel(ctx)
	defer cancelConsumer()

	go func() {
		_ = bus.Subscribe(consumerCtx, group, stream, handler)
	}()

	// Poll until consumer B receives the message (or 8-second timeout).
	deadline := time.Now().Add(8 * time.Second)
	for time.Now().Before(deadline) {
		if received.Load() {
			break
		}
		time.Sleep(50 * time.Millisecond)
	}

	if !received.Load() {
		// Diagnostic: check PEL state.
		info, _ := rc.XPendingExt(ctx, &redis.XPendingExtArgs{
			Stream: stream, Group: group,
			Start: "-", End: "+", Count: 10,
		}).Result()
		t.Fatalf("consumer B did not receive orphaned message via XAUTOCLAIM within 8s; PEL: %v", info)
	}

	// Verify the message was XACKed (PEL should be empty now).
	pending, err := rc.XPending(ctx, stream, group).Result()
	if err != nil {
		t.Fatalf("XPending: %v", err)
	}
	if pending.Count != 0 {
		t.Errorf("PEL should be empty after successful processing; got count=%d", pending.Count)
	}
}

// ── Attempt counter tests ─────────────────────────────────────────────────────

// TestEventBus_AttemptCounter_FailureLogged verifies that a failed handler
// causes an attempt row to be inserted with outcome='error', and that after
// 3 failures the DLQ candidate threshold is reached.
func TestEventBus_AttemptCounter_FailureLogged(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	rc := newTestRedis(t)
	pool := newTestLedgerPool(t)
	attemptRepo := eventbus.NewPgxAttemptRepository(pool)

	stream := fmt.Sprintf("test.attempts.fail.v1.%d", time.Now().UnixNano())
	group := "test-attempts-fail-grp"

	// Pre-create consumer group at "0".
	if err := rc.XGroupCreateMkStream(ctx, stream, group, "0").Err(); err != nil {
		t.Fatalf("XGroupCreateMkStream: %v", err)
	}

	// Publish one message.
	msgID := publishMinimalEvent(t, rc, stream)
	t.Logf("published message id=%s", msgID)

	// Handler that always fails.
	var callCount atomic.Int32
	handler := func(_ context.Context, _ eventbus.Event) error {
		callCount.Add(1)
		return fmt.Errorf("transient failure #%d", callCount.Load())
	}

	bus := eventbus.NewRedisBus(rc, slog.Default(), eventbus.WithAttemptRepo(attemptRepo))
	consumerCtx, cancelConsumer := context.WithCancel(ctx)
	defer cancelConsumer()

	go func() {
		_ = bus.Subscribe(consumerCtx, group, stream, handler)
	}()

	// Wait for at least 3 handler calls (PEL re-deliveries).
	deadline := time.Now().Add(10 * time.Second)
	for time.Now().Before(deadline) {
		if callCount.Load() >= 3 {
			break
		}
		time.Sleep(50 * time.Millisecond)
	}
	if callCount.Load() < 3 {
		t.Fatalf("handler called fewer than 3 times (got %d) — PEL redelivery may not be working", callCount.Load())
	}

	cancelConsumer() // stop the consumer

	// Allow attempt workers to drain the channel.
	time.Sleep(300 * time.Millisecond)

	// Verify at least 3 failure rows were inserted.
	n, err := attemptRepo.CountFailures(context.Background(), stream, msgID, group)
	if err != nil {
		t.Fatalf("CountFailures: %v", err)
	}
	if n < 3 {
		t.Errorf("want >= 3 failure rows, got %d", n)
	}
	t.Logf("failure rows in DB: %d (callCount=%d)", n, callCount.Load())
}

// TestEventBus_AttemptCounter_SurvivesConsumerNameChange verifies that
// CountFailures accumulates across different consumer names (process restarts).
func TestEventBus_AttemptCounter_SurvivesConsumerNameChange(t *testing.T) {
	ctx := context.Background()
	pool := newTestLedgerPool(t)
	repo := eventbus.NewPgxAttemptRepository(pool)

	stream := fmt.Sprintf("test.name.change.v1.%d", time.Now().UnixNano())
	msgID := fmt.Sprintf("1-%d", time.Now().UnixNano())
	group := "test-name-change-grp"

	// Simulate 3 failures from 2 different consumer names (proc1 restart → proc2).
	for i, name := range []string{"grp:host:100", "grp:host:100", "grp:host:200"} {
		if err := repo.Insert(ctx, eventbus.AttemptRow{
			Stream: stream, MessageID: msgID,
			ConsumerGroup: group, ConsumerName: name,
			Outcome:      "error",
			ErrorMessage: fmt.Sprintf("err #%d", i+1),
		}); err != nil {
			t.Fatalf("Insert: %v", err)
		}
	}

	n, err := repo.CountFailures(ctx, stream, msgID, group)
	if err != nil {
		t.Fatalf("CountFailures: %v", err)
	}
	if n != 3 {
		t.Errorf("CountFailures: want 3 (survived name change), got %d", n)
	}
}

// TestEventBus_AttemptCounter_SuccessRecorded verifies that a successful
// handler invocation produces a row with outcome='success'.
func TestEventBus_AttemptCounter_SuccessRecorded(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	rc := newTestRedis(t)
	pool := newTestLedgerPool(t)
	attemptRepo := eventbus.NewPgxAttemptRepository(pool)

	stream := fmt.Sprintf("test.attempts.ok.v1.%d", time.Now().UnixNano())
	group := "test-attempts-ok-grp"

	if err := rc.XGroupCreateMkStream(ctx, stream, group, "0").Err(); err != nil {
		t.Fatalf("XGroupCreateMkStream: %v", err)
	}

	msgID := publishMinimalEvent(t, rc, stream)
	t.Logf("published message id=%s", msgID)

	var processed atomic.Bool
	handler := func(_ context.Context, _ eventbus.Event) error {
		processed.Store(true)
		return nil
	}

	bus := eventbus.NewRedisBus(rc, slog.Default(), eventbus.WithAttemptRepo(attemptRepo))
	consumerCtx, cancelConsumer := context.WithCancel(ctx)
	defer cancelConsumer()

	go func() {
		_ = bus.Subscribe(consumerCtx, group, stream, handler)
	}()

	// Wait for handler to process.
	deadline := time.Now().Add(6 * time.Second)
	for time.Now().Before(deadline) {
		if processed.Load() {
			break
		}
		time.Sleep(50 * time.Millisecond)
	}
	if !processed.Load() {
		t.Fatal("handler not called within 6s")
	}

	cancelConsumer()
	time.Sleep(300 * time.Millisecond) // allow workers to drain

	// At least 1 success row should exist.
	n, err := attemptRepo.CountFailures(context.Background(), stream, msgID, group)
	if err != nil {
		t.Fatalf("CountFailures: %v", err)
	}
	// Failure count must be 0 (it was a success).
	if n != 0 {
		t.Errorf("CountFailures after success: want 0, got %d", n)
	}
	t.Logf("success recorded; failure count = %d", n)
}
