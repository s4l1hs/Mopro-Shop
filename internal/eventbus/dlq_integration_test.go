//go:build integration

package eventbus_test

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/mopro/platform/internal/eventbus"
)

// ── DLQ stub ──────────────────────────────────────────────────────────────────

// chanSlack notifies via buffered channel when PostDLQAlert is called,
// allowing integration tests to block until a DLQ insertion fires Slack.
type chanSlack struct {
	mu    sync.Mutex
	calls []string
	ch    chan string
}

func newChanSlack() *chanSlack { return &chanSlack{ch: make(chan string, 20)} }

func (s *chanSlack) PostDLQAlert(_ context.Context, text string) error {
	s.mu.Lock()
	s.calls = append(s.calls, text)
	s.mu.Unlock()
	select {
	case s.ch <- text:
	default:
	}
	return nil
}

// ── helper: seed a DLQ row ────────────────────────────────────────────────────

// seedDLQRow inserts 2 prior error attempt rows then calls InsertIfThreshold
// with a 3rd (current) error to satisfy DLQThreshold and create a DLQ row.
// Returns the new DLQ row ID.
func seedDLQRow(t *testing.T, pool *pgxpool.Pool, topic, group, msgID string) int64 {
	t.Helper()
	ctx := context.Background()
	attemptRepo := eventbus.NewPgxAttemptRepository(pool)
	dlqRepo := eventbus.NewPgxDLQRepository(pool)

	for i := 0; i < 2; i++ {
		if err := attemptRepo.Insert(ctx, eventbus.AttemptRow{
			Stream: topic, MessageID: msgID,
			ConsumerGroup: group, ConsumerName: "seed-consumer",
			Outcome: "error", ErrorMessage: fmt.Sprintf("seed error %d", i+1),
		}); err != nil {
			t.Fatalf("seedDLQRow: insert attempt %d: %v", i, err)
		}
	}

	payload, _ := json.Marshal(map[string]string{"seed": "true"})
	res, id, err := dlqRepo.InsertIfThreshold(ctx, eventbus.DLQRow{
		OriginalTopic:     topic,
		OriginalMessageID: msgID,
		ConsumerGroup:     group,
		IdempotencyKey:    msgID,
		Payload:           payload,
	}, eventbus.AttemptRow{
		Stream: topic, MessageID: msgID,
		ConsumerGroup: group, ConsumerName: "seed-consumer",
		Outcome: "error", ErrorMessage: "final seed error",
	})
	if err != nil {
		t.Fatalf("seedDLQRow: InsertIfThreshold: %v", err)
	}
	if res != eventbus.DLQInserted {
		t.Fatalf("seedDLQRow: expected DLQInserted, got %v (id=%d)", res, id)
	}
	return id
}

// cleanupDLQ deletes test rows from both DLQ and attempts tables.
func cleanupDLQ(pool *pgxpool.Pool, topic string) {
	ctx := context.Background()
	_, _ = pool.Exec(ctx, `DELETE FROM wallet_schema.event_dlq WHERE original_topic = $1`, topic)
	_, _ = pool.Exec(ctx, `DELETE FROM wallet_schema.event_delivery_attempts WHERE stream = $1`, topic)
}

// ── Test 1: Poison message gets DLQ'd and XACKed after ≥ DLQThreshold failures ─

// TestDLQIntegration_PoisonMessage_DLQAndXACK publishes a poison message,
// verifies that the bus inserts a DLQ row and XACKs the message out of PEL.
func TestDLQIntegration_PoisonMessage_DLQAndXACK(t *testing.T) {
	t.Setenv("EVENTBUS_AUTOCLAIM_IDLE_MS", "100")
	t.Setenv("EVENTBUS_AUTOCLAIM_TICK_MS", "200")

	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	rc := newTestRedis(t)
	pool := newTestLedgerPool(t)

	stream := fmt.Sprintf("test.dlq.poison.v1.%d", time.Now().UnixNano())
	group := "test-dlq-poison-grp"

	t.Cleanup(func() {
		rc.Del(context.Background(), stream) //nolint:errcheck
		cleanupDLQ(pool, stream)
	})

	if err := rc.XGroupCreateMkStream(ctx, stream, group, "0").Err(); err != nil {
		t.Fatalf("XGroupCreateMkStream: %v", err)
	}

	msgID := publishMinimalEvent(t, rc, stream)
	t.Logf("published poison message id=%s", msgID)

	sl := newChanSlack()
	attemptRepo := eventbus.NewPgxAttemptRepository(pool)
	dlqRepo := eventbus.NewPgxDLQRepository(pool)

	bus := eventbus.NewRedisBus(rc, slog.Default(),
		eventbus.WithAttemptRepo(attemptRepo),
		eventbus.WithDLQRepo(dlqRepo),
		eventbus.WithSlackPoster(sl),
	)

	var callCount atomic.Int32
	handler := func(_ context.Context, _ eventbus.Event) error {
		callCount.Add(1)
		return fmt.Errorf("permanent failure #%d", callCount.Load())
	}

	consumerCtx, cancelConsumer := context.WithCancel(ctx)
	defer cancelConsumer()
	go func() { _ = bus.Subscribe(consumerCtx, group, stream, handler) }()

	// Block until Slack fires — that is the DLQ-inserted signal.
	select {
	case msg := <-sl.ch:
		t.Logf("Slack notified (callCount=%d): %q", callCount.Load(), msg)
	case <-ctx.Done():
		t.Fatalf("timeout waiting for DLQ Slack notification (callCount=%d)", callCount.Load())
	}

	cancelConsumer()
	time.Sleep(200 * time.Millisecond)

	// PEL must be empty — message was XACKed after DLQ insertion.
	pending, err := rc.XPending(ctx, stream, group).Result()
	if err != nil {
		t.Fatalf("XPending: %v", err)
	}
	if pending.Count != 0 {
		t.Errorf("PEL should be empty after DLQ+XACK; got count=%d", pending.Count)
	}

	// DLQ row must exist in DB.
	rows, err := dlqRepo.List(context.Background(), eventbus.DLQFilter{Topic: stream})
	if err != nil {
		t.Fatalf("List: %v", err)
	}
	if len(rows) != 1 {
		t.Fatalf("expected 1 DLQ row, got %d", len(rows))
	}
	dlqRow := rows[0]
	if dlqRow.OriginalMessageID != msgID {
		t.Errorf("DLQ row msgID mismatch: want %s got %s", msgID, dlqRow.OriginalMessageID)
	}
	if dlqRow.Status != "open" {
		t.Errorf("DLQ row status: want 'open', got %q", dlqRow.Status)
	}
	if dlqRow.AttemptCount < eventbus.DLQThreshold {
		t.Errorf("DLQ attempt_count want >= %d, got %d", eventbus.DLQThreshold, dlqRow.AttemptCount)
	}
	t.Logf("DLQ row id=%d status=%s attempt_count=%d", dlqRow.ID, dlqRow.Status, dlqRow.AttemptCount)
}

// ── Test 2: InsertIfThreshold is idempotent — second call returns DLQAlreadyExists ─

// TestDLQIntegration_Idempotent_OnSecondInsert verifies that a second
// InsertIfThreshold call for the same (consumer_group, original_message_id)
// returns DLQAlreadyExists with the original row's ID rather than inserting again.
func TestDLQIntegration_Idempotent_OnSecondInsert(t *testing.T) {
	ctx := context.Background()
	pool := newTestLedgerPool(t)

	topic := fmt.Sprintf("test.dlq.idem.v1.%d", time.Now().UnixNano())
	group := "test-dlq-idem-grp"
	msgID := fmt.Sprintf("1-%d", time.Now().UnixNano())

	t.Cleanup(func() { cleanupDLQ(pool, topic) })

	firstID := seedDLQRow(t, pool, topic, group, msgID)
	t.Logf("first insert id=%d", firstID)

	// Second insert with same (group, msgID) → must return DLQAlreadyExists.
	dlqRepo := eventbus.NewPgxDLQRepository(pool)
	payload, _ := json.Marshal(map[string]string{"retry": "true"})
	res, existingID, err := dlqRepo.InsertIfThreshold(ctx, eventbus.DLQRow{
		OriginalTopic:     topic,
		OriginalMessageID: msgID,
		ConsumerGroup:     group,
		IdempotencyKey:    msgID,
		Payload:           payload,
	}, eventbus.AttemptRow{
		Stream: topic, MessageID: msgID,
		ConsumerGroup: group, ConsumerName: "retry-consumer",
		Outcome: "error", ErrorMessage: "retry",
	})
	if err != nil {
		t.Fatalf("second InsertIfThreshold: %v", err)
	}
	if res != eventbus.DLQAlreadyExists {
		t.Errorf("want DLQAlreadyExists, got %v", res)
	}
	if existingID != firstID {
		t.Errorf("existingID want %d, got %d", firstID, existingID)
	}
}

// ── Test 3: CountInWindow returns accurate count for SEV2 storm detection ──────

// TestDLQIntegration_SEV2_CountInWindow inserts N DLQ rows for a single topic
// and verifies that CountInWindow returns exactly N within the 10-min window.
func TestDLQIntegration_SEV2_CountInWindow(t *testing.T) {
	ctx := context.Background()
	pool := newTestLedgerPool(t)

	topic := fmt.Sprintf("test.dlq.sev2.v1.%d", time.Now().UnixNano())
	group := "test-dlq-sev2-grp"

	t.Cleanup(func() { cleanupDLQ(pool, topic) })

	const insertCount = 3
	for i := 0; i < insertCount; i++ {
		msgID := fmt.Sprintf("sev2-msg-%d-%d", time.Now().UnixNano(), i)
		seedDLQRow(t, pool, topic, group, msgID)
	}

	dlqRepo := eventbus.NewPgxDLQRepository(pool)
	count, err := dlqRepo.CountInWindow(ctx, topic, 10)
	if err != nil {
		t.Fatalf("CountInWindow: %v", err)
	}
	if count != insertCount {
		t.Errorf("CountInWindow want %d, got %d", insertCount, count)
	}
}

// ── Test 4: MarkReplayed transitions status to 'replayed' ────────────────────

// TestDLQIntegration_Replay_ClearsStatus verifies that MarkReplayed sets
// status='replayed' with replayed_at/by/message_id and rejects a second call.
func TestDLQIntegration_Replay_ClearsStatus(t *testing.T) {
	ctx := context.Background()
	pool := newTestLedgerPool(t)

	topic := fmt.Sprintf("test.dlq.replay.v1.%d", time.Now().UnixNano())
	group := "test-dlq-replay-grp"
	msgID := fmt.Sprintf("replay-msg-%d", time.Now().UnixNano())

	t.Cleanup(func() { cleanupDLQ(pool, topic) })

	dlqRepo := eventbus.NewPgxDLQRepository(pool)
	id := seedDLQRow(t, pool, topic, group, msgID)

	replayedMsgID := fmt.Sprintf("replayed-%d", time.Now().UnixNano())
	if err := dlqRepo.MarkReplayed(ctx, id, "test-user", replayedMsgID); err != nil {
		t.Fatalf("MarkReplayed: %v", err)
	}

	row, err := dlqRepo.GetByID(ctx, id)
	if err != nil {
		t.Fatalf("GetByID: %v", err)
	}
	if row.Status != "replayed" {
		t.Errorf("status want 'replayed', got %q", row.Status)
	}
	if row.ReplayedBy == nil || *row.ReplayedBy != "test-user" {
		t.Errorf("replayed_by want 'test-user', got %v", row.ReplayedBy)
	}
	if row.ReplayedMessageID == nil || *row.ReplayedMessageID != replayedMsgID {
		t.Errorf("replayed_message_id mismatch: got %v", row.ReplayedMessageID)
	}
	if row.ReplayedAt == nil {
		t.Error("replayed_at must not be nil")
	}

	if err := dlqRepo.MarkReplayed(ctx, id, "test-user", "another"); err != eventbus.ErrDLQNotOpen {
		t.Errorf("second MarkReplayed: want ErrDLQNotOpen, got %v", err)
	}
}

// ── Test 5: MarkDismissed transitions status to 'dismissed' ──────────────────

// TestDLQIntegration_Dismiss_ClearsStatus verifies that MarkDismissed sets
// status='dismissed' with dismissed_at/by/reason and rejects a second call.
func TestDLQIntegration_Dismiss_ClearsStatus(t *testing.T) {
	ctx := context.Background()
	pool := newTestLedgerPool(t)

	topic := fmt.Sprintf("test.dlq.dismiss.v1.%d", time.Now().UnixNano())
	group := "test-dlq-dismiss-grp"
	msgID := fmt.Sprintf("dismiss-msg-%d", time.Now().UnixNano())

	t.Cleanup(func() { cleanupDLQ(pool, topic) })

	dlqRepo := eventbus.NewPgxDLQRepository(pool)
	id := seedDLQRow(t, pool, topic, group, msgID)

	if err := dlqRepo.MarkDismissed(ctx, id, "ops-user", "known flaky event"); err != nil {
		t.Fatalf("MarkDismissed: %v", err)
	}

	row, err := dlqRepo.GetByID(ctx, id)
	if err != nil {
		t.Fatalf("GetByID: %v", err)
	}
	if row.Status != "dismissed" {
		t.Errorf("status want 'dismissed', got %q", row.Status)
	}
	if row.DismissedBy == nil || *row.DismissedBy != "ops-user" {
		t.Errorf("dismissed_by want 'ops-user', got %v", row.DismissedBy)
	}
	if row.DismissalReason == nil || *row.DismissalReason != "known flaky event" {
		t.Errorf("dismissal_reason mismatch: got %v", row.DismissalReason)
	}
	if row.DismissedAt == nil {
		t.Error("dismissed_at must not be nil")
	}

	if err := dlqRepo.MarkDismissed(ctx, id, "ops-user2", "again"); err != eventbus.ErrDLQNotOpen {
		t.Errorf("second MarkDismissed: want ErrDLQNotOpen, got %v", err)
	}
}
