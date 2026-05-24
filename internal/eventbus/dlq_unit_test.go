package eventbus

// White-box unit tests for DLQ insertion logic.
// Uses in-package access so we can set unexported fields (xack, dlqRepo, slackPoster)
// without needing miniredis. No containers required.

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"sync"
	"testing"
	"time"

	"github.com/redis/go-redis/v9"
)

// ── Stubs ─────────────────────────────────────────────────────────────────────

type stubDLQRepo struct {
	mu           sync.Mutex
	insertResult DLQInsertResult
	insertID     int64
	insertErr    error
	countResult  int
	insertCalls  int
	countCalls   int
}

func (s *stubDLQRepo) InsertIfThreshold(_ context.Context, _ DLQRow, _ AttemptRow) (DLQInsertResult, int64, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.insertCalls++
	return s.insertResult, s.insertID, s.insertErr
}
func (s *stubDLQRepo) CountInWindow(_ context.Context, _ string, _ int) (int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.countCalls++
	return s.countResult, nil
}
func (s *stubDLQRepo) List(_ context.Context, _ DLQFilter) ([]DLQRow, error)       { return nil, nil }
func (s *stubDLQRepo) GetByID(_ context.Context, _ int64) (DLQRow, error)          { return DLQRow{}, nil }
func (s *stubDLQRepo) MarkReplayed(_ context.Context, _ int64, _, _ string) error  { return nil }
func (s *stubDLQRepo) MarkDismissed(_ context.Context, _ int64, _, _ string) error { return nil }

type stubSlack struct {
	mu    sync.Mutex
	calls []string
	err   error
}

func (s *stubSlack) PostDLQAlert(_ context.Context, text string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.calls = append(s.calls, text)
	return s.err
}

type stubXAcker struct {
	mu    sync.Mutex
	calls []string
	err   error
}

func (s *stubXAcker) XAck(_ context.Context, _, _ string, ids ...string) *redis.IntCmd {
	s.mu.Lock()
	s.calls = append(s.calls, ids...)
	s.mu.Unlock()
	cmd := redis.NewIntCmd(context.Background())
	if s.err != nil {
		cmd.SetErr(s.err)
	} else {
		cmd.SetVal(1)
	}
	return cmd
}

// newTestBus constructs a minimal RedisBus with stub internals for unit tests.
func newTestBus(dlq *stubDLQRepo, sl *stubSlack, xa *stubXAcker) *RedisBus {
	return &RedisBus{
		client:      redis.NewClient(&redis.Options{Addr: "localhost:0"}),
		xack:        xa,
		dlqRepo:     dlq,
		slackPoster: sl,
		log:         slog.Default(),
	}
}

func testMsg() redis.XMessage {
	return redis.XMessage{
		ID: "1715856930000-0",
		Values: map[string]interface{}{
			"event_id":        "evt-test-001",
			"event_type":      "test.topic.v1",
			"idempotency_key": "idem-test-001",
			"market":          "TR",
			"currency":        "TRY",
			"occurred_at":     time.Now().UTC().Format(time.RFC3339),
			"payload":         `{"order_id":42}`,
		},
	}
}

func testAttempt(outcome string) AttemptRow {
	return AttemptRow{
		Stream: "test.topic.v1", MessageID: "1715856930000-0",
		ConsumerGroup: "test-group", ConsumerName: "test-consumer-1",
		Outcome: outcome, ErrorMessage: "handler error",
	}
}

// ── Tests ─────────────────────────────────────────────────────────────────────

// 1. First DLQ insertion: INSERT succeeds → XACK called once, Slack called once with SEV3.
func TestDLQInsertion_FirstTime_InsertsAndAlerts(t *testing.T) {
	dlq := &stubDLQRepo{insertResult: DLQInserted, insertID: 42, countResult: 1}
	sl := &stubSlack{}
	xa := &stubXAcker{}
	bus := newTestBus(dlq, sl, xa)

	bus.insertDLQIfThreshold(context.Background(),
		"test.topic.v1", "test-group", "test-consumer-1",
		testMsg(), testAttempt("error"), Event{IdempotencyKey: "idem-test-001"})

	if dlq.insertCalls != 1 {
		t.Errorf("want 1 insert call, got %d", dlq.insertCalls)
	}
	xa.mu.Lock()
	xackCalls := len(xa.calls)
	xa.mu.Unlock()
	if xackCalls != 1 {
		t.Errorf("want 1 XACK call, got %d", xackCalls)
	}
	sl.mu.Lock()
	slackCalls := len(sl.calls)
	sl.mu.Unlock()
	if slackCalls != 1 {
		t.Errorf("want 1 Slack call, got %d", slackCalls)
	}
}

//  2. Already DLQed (UNIQUE conflict): INSERT returns DLQAlreadyExists →
//     Slack NOT called, XACK attempted to clear PEL.
func TestDLQInsertion_AlreadyDLQed_SkipsSlack(t *testing.T) {
	dlq := &stubDLQRepo{insertResult: DLQAlreadyExists, insertID: 17}
	sl := &stubSlack{}
	xa := &stubXAcker{}
	bus := newTestBus(dlq, sl, xa)

	bus.insertDLQIfThreshold(context.Background(),
		"test.topic.v1", "test-group", "test-consumer-1",
		testMsg(), testAttempt("error"), Event{})

	sl.mu.Lock()
	slackCalls := len(sl.calls)
	sl.mu.Unlock()
	if slackCalls != 0 {
		t.Errorf("want 0 Slack calls on conflict, got %d", slackCalls)
	}
	xa.mu.Lock()
	xackCalls := len(xa.calls)
	xa.mu.Unlock()
	if xackCalls != 1 {
		t.Errorf("want 1 XACK retry on conflict, got %d", xackCalls)
	}
}

// 3. DB insert fails → XACK NOT called, Slack NOT called.
func TestDLQInsertion_DBFails_NoXACK(t *testing.T) {
	dlq := &stubDLQRepo{insertErr: errors.New("connection reset")}
	sl := &stubSlack{}
	xa := &stubXAcker{}
	bus := newTestBus(dlq, sl, xa)

	bus.insertDLQIfThreshold(context.Background(),
		"test.topic.v1", "test-group", "test-consumer-1",
		testMsg(), testAttempt("error"), Event{})

	xa.mu.Lock()
	xackCalls := len(xa.calls)
	xa.mu.Unlock()
	if xackCalls != 0 {
		t.Errorf("want 0 XACK calls on DB failure, got %d", xackCalls)
	}
	sl.mu.Lock()
	slackCalls := len(sl.calls)
	sl.mu.Unlock()
	if slackCalls != 0 {
		t.Errorf("want 0 Slack calls on DB failure, got %d", slackCalls)
	}
}

// 4. Below threshold (DLQBelowThreshold): neither XACK nor Slack fired.
func TestDLQInsertion_BelowThreshold_NoAction(t *testing.T) {
	dlq := &stubDLQRepo{insertResult: DLQBelowThreshold}
	sl := &stubSlack{}
	xa := &stubXAcker{}
	bus := newTestBus(dlq, sl, xa)

	bus.insertDLQIfThreshold(context.Background(),
		"test.topic.v1", "test-group", "test-consumer-1",
		testMsg(), testAttempt("error"), Event{})

	xa.mu.Lock()
	xackCalls := len(xa.calls)
	xa.mu.Unlock()
	sl.mu.Lock()
	slackCalls := len(sl.calls)
	sl.mu.Unlock()
	if xackCalls != 0 || slackCalls != 0 {
		t.Errorf("want no actions below threshold, got xack=%d slack=%d", xackCalls, slackCalls)
	}
}

// 5. SEV2 storm rate triggered (countResult > sev2Threshold).
func TestDLQInsertion_SEV2_RateTriggered(t *testing.T) {
	dlq := &stubDLQRepo{insertResult: DLQInserted, insertID: 99, countResult: sev2Threshold + 1}
	sl := &stubSlack{}
	xa := &stubXAcker{}
	bus := newTestBus(dlq, sl, xa)

	bus.insertDLQIfThreshold(context.Background(),
		"test.topic.v1", "test-group", "c", testMsg(), testAttempt("error"), Event{})

	sl.mu.Lock()
	defer sl.mu.Unlock()
	if len(sl.calls) == 0 {
		t.Fatal("expected Slack call for SEV2, got none")
	}
	msg := sl.calls[0]
	if !contains(msg, "SEV2") {
		t.Errorf("expected SEV2 in Slack text, got: %s", msg)
	}
}

// 6. SEV2 dedup: two insertions on same topic within 10 min → SEV2 sent once.
func TestDLQInsertion_SEV2_DeduplFromSyncMap(t *testing.T) {
	dlq := &stubDLQRepo{insertResult: DLQInserted, insertID: 100, countResult: sev2Threshold + 1}
	sl := &stubSlack{}
	xa := &stubXAcker{}
	bus := newTestBus(dlq, sl, xa)

	// Two calls on same topic — SEV2 should fire only once per 10-min window.
	bus.insertDLQIfThreshold(context.Background(),
		"test.topic.v1", "g", "c", testMsg(), testAttempt("error"), Event{})
	bus.insertDLQIfThreshold(context.Background(),
		"test.topic.v1", "g", "c", testMsg(), testAttempt("error"), Event{})

	sl.mu.Lock()
	defer sl.mu.Unlock()
	// Count SEV2 calls specifically
	sev2Count := 0
	for _, msg := range sl.calls {
		if contains(msg, "SEV2") {
			sev2Count++
		}
	}
	if sev2Count != 1 {
		t.Errorf("want exactly 1 SEV2 Slack alert, got %d", sev2Count)
	}
}

// 7. XACK fails after DLQ insertion: DLQ row exists, error logged, no panic.
func TestDLQInsertion_XACKFails_Logged(t *testing.T) {
	dlq := &stubDLQRepo{insertResult: DLQInserted, insertID: 55}
	sl := &stubSlack{}
	xa := &stubXAcker{err: fmt.Errorf("redis: connection refused")}
	bus := newTestBus(dlq, sl, xa)

	// Must not panic even when XACK fails.
	bus.insertDLQIfThreshold(context.Background(),
		"test.topic.v1", "test-group", "c", testMsg(), testAttempt("error"),
		Event{IdempotencyKey: "idem-001"})

	if dlq.insertCalls != 1 {
		t.Errorf("want insert called once, got %d", dlq.insertCalls)
	}
	xa.mu.Lock()
	xackCalls := len(xa.calls)
	xa.mu.Unlock()
	if xackCalls != 1 {
		t.Errorf("want XACK attempt (even if failed), got %d", xackCalls)
	}
}

func contains(s, sub string) bool {
	return len(s) > 0 && len(sub) > 0 && (s == sub || (len(s) >= len(sub) &&
		func() bool {
			for i := 0; i <= len(s)-len(sub); i++ {
				if s[i:i+len(sub)] == sub {
					return true
				}
			}
			return false
		}()))
}
