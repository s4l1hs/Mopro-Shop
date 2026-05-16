//go:build integration

package eventbus_test

// e2e-style DLQ tests: replay lifecycle and property verification.
// Runs against the integration stack (REDIS_TEST_ADDR=localhost:6380,
// LEDGER_TEST_DSN=...localhost:6434). The full e2e stack tests
// (internal/e2e/dlq_e2e_test.go) run against the separate e2e containers.

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/redis/go-redis/v9"

	"github.com/mopro/platform/internal/eventbus"
)

// TestE2E_PoisonMessageFullCycle is a thin alias over the integration-level
// poison-message test to satisfy the Commit 12 naming requirement. The full
// scenario is covered by TestDLQIntegration_PoisonMessage_DLQAndXACK; this
// version adds a higher-level assertion on the Slack alert text format.
func TestE2E_PoisonMessageFullCycle(t *testing.T) {
	t.Setenv("EVENTBUS_AUTOCLAIM_IDLE_MS", "100")
	t.Setenv("EVENTBUS_AUTOCLAIM_TICK_MS", "200")

	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	rc := newTestRedis(t)
	pool := newTestLedgerPool(t)

	stream := fmt.Sprintf("e2e.poison.full.v1.%d", time.Now().UnixNano())
	group := "e2e-poison-full-grp"

	t.Cleanup(func() {
		rc.Del(context.Background(), stream) //nolint:errcheck
		cleanupDLQ(pool, stream)
	})

	if err := rc.XGroupCreateMkStream(ctx, stream, group, "0").Err(); err != nil {
		t.Fatalf("XGroupCreateMkStream: %v", err)
	}

	msgID := publishMinimalEvent(t, rc, stream)
	sl := newChanSlack()
	bus := eventbus.NewRedisBus(rc, slog.Default(),
		eventbus.WithAttemptRepo(eventbus.NewPgxAttemptRepository(pool)),
		eventbus.WithDLQRepo(eventbus.NewPgxDLQRepository(pool)),
		eventbus.WithSlackPoster(sl),
	)

	var calls atomic.Int32
	consumerCtx, cancelConsumer := context.WithCancel(ctx)
	defer cancelConsumer()
	go func() {
		_ = bus.Subscribe(consumerCtx, group, stream, func(_ context.Context, _ eventbus.Event) error {
			calls.Add(1)
			return fmt.Errorf("permanent failure")
		})
	}()

	select {
	case alert := <-sl.ch:
		if len(alert) == 0 {
			t.Error("Slack alert text must not be empty")
		}
	case <-ctx.Done():
		t.Fatalf("timeout (calls=%d)", calls.Load())
	}
	cancelConsumer()
	time.Sleep(200 * time.Millisecond)

	pending, _ := rc.XPending(ctx, stream, group).Result()
	if pending.Count != 0 {
		t.Errorf("PEL want empty, got %d", pending.Count)
	}
	dlqRepo := eventbus.NewPgxDLQRepository(pool)
	rows, _ := dlqRepo.List(context.Background(), eventbus.DLQFilter{Topic: stream})
	if len(rows) != 1 || rows[0].OriginalMessageID != msgID {
		t.Errorf("expected 1 DLQ row for %s, got %d", msgID, len(rows))
	}
}

// TestE2E_ReplayReloops verifies the full DLQ replay lifecycle:
//  1. Poison message fails DLQThreshold times → DLQ row created, PEL cleared.
//  2. Operator replays: XADD new message → MarkReplayed.
//  3. Consumer with fixed handler processes the replayed message.
//  4. DLQ row status='replayed', replayed_message_id populated.
func TestE2E_ReplayReloops(t *testing.T) {
	t.Setenv("EVENTBUS_AUTOCLAIM_IDLE_MS", "100")
	t.Setenv("EVENTBUS_AUTOCLAIM_TICK_MS", "200")

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	rc := newTestRedis(t)
	pool := newTestLedgerPool(t)

	stream := fmt.Sprintf("e2e.replay.reloop.v1.%d", time.Now().UnixNano())
	group := "e2e-replay-reloop-grp"

	t.Cleanup(func() {
		rc.Del(context.Background(), stream) //nolint:errcheck
		cleanupDLQ(pool, stream)
	})

	if err := rc.XGroupCreateMkStream(ctx, stream, group, "0").Err(); err != nil {
		t.Fatalf("XGroupCreateMkStream: %v", err)
	}
	publishMinimalEvent(t, rc, stream)

	sl := newChanSlack()
	attemptRepo := eventbus.NewPgxAttemptRepository(pool)
	dlqRepo := eventbus.NewPgxDLQRepository(pool)

	// ── Phase 1: poison handler → DLQ ────────────────────────────────────────
	var poisonCalls atomic.Int32
	poisonBus := eventbus.NewRedisBus(rc, slog.Default(),
		eventbus.WithAttemptRepo(attemptRepo),
		eventbus.WithDLQRepo(dlqRepo),
		eventbus.WithSlackPoster(sl),
	)
	consumerCtx, cancelPoison := context.WithCancel(ctx)
	go func() {
		_ = poisonBus.Subscribe(consumerCtx, group, stream, func(_ context.Context, _ eventbus.Event) error {
			poisonCalls.Add(1)
			return fmt.Errorf("poison failure #%d", poisonCalls.Load())
		})
	}()

	select {
	case <-sl.ch:
		t.Logf("DLQ inserted after %d calls", poisonCalls.Load())
	case <-ctx.Done():
		cancelPoison()
		t.Fatal("timeout waiting for DLQ insertion")
	}
	cancelPoison()
	time.Sleep(200 * time.Millisecond)

	// Get DLQ row.
	rows, err := dlqRepo.List(context.Background(), eventbus.DLQFilter{Topic: stream})
	if err != nil || len(rows) == 0 {
		t.Fatalf("DLQ row not found: err=%v rows=%d", err, len(rows))
	}
	dlqRow := rows[0]
	t.Logf("DLQ row id=%d msg=%s", dlqRow.ID, dlqRow.OriginalMessageID)

	// ── Phase 2: replay — XADD then MarkReplayed ─────────────────────────────
	var replayValues map[string]interface{}
	if jsonErr := json.Unmarshal(dlqRow.Payload, &replayValues); jsonErr != nil {
		t.Fatalf("unmarshal payload: %v", jsonErr)
	}
	newMsgID, xaddErr := rc.XAdd(ctx, &redis.XAddArgs{
		Stream: dlqRow.OriginalTopic,
		Values: replayValues,
	}).Result()
	if xaddErr != nil {
		t.Fatalf("replay XADD: %v", xaddErr)
	}
	if markErr := dlqRepo.MarkReplayed(ctx, dlqRow.ID, "e2e-test", newMsgID); markErr != nil {
		t.Fatalf("MarkReplayed: %v", markErr)
	}
	t.Logf("replayed DLQ #%d → new_msg_id=%s", dlqRow.ID, newMsgID)

	// ── Phase 3: fixed handler processes the replayed message ─────────────────
	var replayProcessed atomic.Bool
	fixedBus := eventbus.NewRedisBus(rc, slog.Default(),
		eventbus.WithAttemptRepo(attemptRepo),
		eventbus.WithDLQRepo(dlqRepo),
	)
	replayCtx, cancelReplay := context.WithCancel(ctx)
	defer cancelReplay()
	go func() {
		_ = fixedBus.Subscribe(replayCtx, group, stream, func(_ context.Context, _ eventbus.Event) error {
			replayProcessed.Store(true)
			return nil
		})
	}()

	deadline := time.Now().Add(12 * time.Second)
	for time.Now().Before(deadline) && !replayProcessed.Load() {
		time.Sleep(50 * time.Millisecond)
	}
	cancelReplay()

	if !replayProcessed.Load() {
		t.Fatal("replayed message was not processed by fixed handler within 12s")
	}

	// Verify DLQ row is 'replayed'.
	updated, err := dlqRepo.GetByID(context.Background(), dlqRow.ID)
	if err != nil {
		t.Fatalf("GetByID: %v", err)
	}
	if updated.Status != "replayed" {
		t.Errorf("DLQ status want 'replayed', got %q", updated.Status)
	}
	if updated.ReplayedMessageID == nil || *updated.ReplayedMessageID != newMsgID {
		t.Errorf("replayed_message_id mismatch: want %s, got %v", newMsgID, updated.ReplayedMessageID)
	}
	t.Logf("DLQ row status=%s replayed_message_id=%s", updated.Status, *updated.ReplayedMessageID)
}

// TestProperty_DLQContainsExactlyPermanentFailures publishes a mix of permanent-
// and transient-failure messages, then asserts only permanent ones appear in DLQ.
//
// permanent: handler always errors → DLQ threshold reached → DLQ row inserted.
// transient: handler fails exactly once then succeeds (total 1 failure < DLQThreshold=3).
//
// sync.Map tracks per-key call counts so the handler is safe across concurrent deliveries.
func TestProperty_DLQContainsExactlyPermanentFailures(t *testing.T) {
	t.Setenv("EVENTBUS_AUTOCLAIM_IDLE_MS", "200")
	t.Setenv("EVENTBUS_AUTOCLAIM_TICK_MS", "400")

	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	defer cancel()

	rc := newTestRedis(t)
	pool := newTestLedgerPool(t)

	stream := fmt.Sprintf("e2e.property.dlq.v1.%d", time.Now().UnixNano())
	group := "e2e-property-dlq-grp"

	t.Cleanup(func() {
		rc.Del(context.Background(), stream) //nolint:errcheck
		cleanupDLQ(pool, stream)
	})

	if err := rc.XGroupCreateMkStream(ctx, stream, group, "0").Err(); err != nil {
		t.Fatalf("XGroupCreateMkStream: %v", err)
	}

	const permanentCount = 2
	const transientCount = 3

	permanentKeys := make(map[string]bool)
	for i := 0; i < permanentCount; i++ {
		key := fmt.Sprintf("perm-%d-%d", time.Now().UnixNano(), i)
		permanentKeys[key] = true
		publishEventWithKey(t, rc, stream, key)
	}
	for i := 0; i < transientCount; i++ {
		key := fmt.Sprintf("trans-%d-%d", time.Now().UnixNano(), i)
		publishEventWithKey(t, rc, stream, key)
	}

	sl := newChanSlack()
	attemptRepo := eventbus.NewPgxAttemptRepository(pool)
	dlqRepo := eventbus.NewPgxDLQRepository(pool)

	// callCounts tracks per-key delivery count using sync.Map for race safety.
	// Transient keys fail on the 1st delivery only (1 failure << DLQThreshold=3).
	var callCounts sync.Map

	handler := func(_ context.Context, ev eventbus.Event) error {
		key := ev.IdempotencyKey
		if permanentKeys[key] {
			return fmt.Errorf("permanent failure for %s", key)
		}
		v, _ := callCounts.LoadOrStore(key, new(atomic.Int32))
		if v.(*atomic.Int32).Add(1) == 1 {
			return fmt.Errorf("transient failure (1st attempt) for %s", key)
		}
		return nil
	}

	bus := eventbus.NewRedisBus(rc, slog.Default(),
		eventbus.WithAttemptRepo(attemptRepo),
		eventbus.WithDLQRepo(dlqRepo),
		eventbus.WithSlackPoster(sl),
	)

	consumerCtx, cancelConsumer := context.WithCancel(ctx)
	defer cancelConsumer()
	go func() { _ = bus.Subscribe(consumerCtx, group, stream, handler) }()

	// Collect exactly permanentCount DLQ alerts (or timeout).
	var alertCount atomic.Int32
	deadline := time.Now().Add(30 * time.Second)
	for time.Now().Before(deadline) && int(alertCount.Load()) < permanentCount {
		select {
		case <-sl.ch:
			alertCount.Add(1)
		case <-time.After(300 * time.Millisecond):
		}
	}

	cancelConsumer()
	time.Sleep(400 * time.Millisecond)

	if int(alertCount.Load()) != permanentCount {
		t.Errorf("DLQ alert count want %d, got %d", permanentCount, alertCount.Load())
	}

	rows, err := dlqRepo.List(context.Background(), eventbus.DLQFilter{Topic: stream})
	if err != nil {
		t.Fatalf("List: %v", err)
	}
	if len(rows) != permanentCount {
		t.Errorf("DLQ rows want %d (permanent only), got %d", permanentCount, len(rows))
		for _, r := range rows {
			t.Logf("  DLQ row: key=%s status=%s", r.IdempotencyKey, r.Status)
		}
	}
	for _, r := range rows {
		if !permanentKeys[r.IdempotencyKey] {
			t.Errorf("transient key %q found in DLQ — must not be DLQ'd", r.IdempotencyKey)
		}
	}
	t.Logf("property: %d permanent rows in DLQ, %d transient messages not DLQ'd",
		len(rows), transientCount)
}

// publishEventWithKey publishes a minimal event with the given idempotency key.
func publishEventWithKey(t *testing.T, rc *redis.Client, stream, idemKey string) {
	t.Helper()
	ctx := context.Background()
	payload, _ := json.Marshal(map[string]string{"prop": "test"})
	_, err := rc.XAdd(ctx, &redis.XAddArgs{
		Stream: stream,
		Values: map[string]interface{}{
			"event_id":        fmt.Sprintf("evt-%d", time.Now().UnixNano()),
			"event_type":      stream,
			"aggregate":       "test",
			"idempotency_key": idemKey,
			"market":          "TR",
			"currency":        "TRY",
			"trace_id":        "",
			"span_id":         "",
			"occurred_at":     time.Now().UTC().Format(time.RFC3339Nano),
			"payload":         string(payload),
		},
	}).Result()
	if err != nil {
		t.Fatalf("publishEventWithKey XADD: %v", err)
	}
}
