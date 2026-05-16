package eventbus_test

import (
	"context"
	"sync"
	"testing"

	"github.com/mopro/platform/internal/eventbus"
)

// stubAttemptRepo is an in-memory AttemptRepository for unit tests.
type stubAttemptRepo struct {
	mu   sync.Mutex
	rows []eventbus.AttemptRow
}

func (s *stubAttemptRepo) Insert(_ context.Context, row eventbus.AttemptRow) error {
	s.mu.Lock()
	s.rows = append(s.rows, row)
	s.mu.Unlock()
	return nil
}

func (s *stubAttemptRepo) CountFailures(_ context.Context, stream, messageID, group string) (int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	n := 0
	for _, r := range s.rows {
		if r.Stream == stream && r.MessageID == messageID && r.ConsumerGroup == group &&
			(r.Outcome == "error" || r.Outcome == "panic") {
			n++
		}
	}
	return n, nil
}

// TestAttemptRepository_InsertAndCount verifies that Insert + CountFailures work correctly
// with the in-memory stub (tests the interface contract, not the DB implementation).
func TestAttemptRepository_InsertAndCount(t *testing.T) {
	ctx := context.Background()
	repo := &stubAttemptRepo{}

	// Insert two failures for the same stream/messageID/group.
	for i := 0; i < 2; i++ {
		if err := repo.Insert(ctx, eventbus.AttemptRow{
			Stream:        "ecom.order.delivered.v1",
			MessageID:     "1-1",
			ConsumerGroup: "cashback-engine",
			ConsumerName:  "cashback-engine:host:100",
			Outcome:       "error",
			ErrorMessage:  "some error",
			DurationMs:    42,
		}); err != nil {
			t.Fatalf("Insert: %v", err)
		}
	}

	// Insert a success for the same key — must NOT count.
	if err := repo.Insert(ctx, eventbus.AttemptRow{
		Stream:        "ecom.order.delivered.v1",
		MessageID:     "1-1",
		ConsumerGroup: "cashback-engine",
		ConsumerName:  "cashback-engine:host:101",
		Outcome:       "success",
	}); err != nil {
		t.Fatalf("Insert success: %v", err)
	}

	n, err := repo.CountFailures(ctx, "ecom.order.delivered.v1", "1-1", "cashback-engine")
	if err != nil {
		t.Fatalf("CountFailures: %v", err)
	}
	if n != 2 {
		t.Errorf("CountFailures: want 2, got %d", n)
	}
}

// TestAttemptRepository_SurvivesConsumerNameChange verifies that CountFailures counts
// failures across different consumer names (i.e., across process restarts).
func TestAttemptRepository_SurvivesConsumerNameChange(t *testing.T) {
	ctx := context.Background()
	repo := &stubAttemptRepo{}

	names := []string{
		"group:host:100",
		"group:host:200",
		"group:host:300",
	}
	for _, name := range names {
		if err := repo.Insert(ctx, eventbus.AttemptRow{
			Stream:        "test.stream.v1",
			MessageID:     "2-1",
			ConsumerGroup: "test-group",
			ConsumerName:  name,
			Outcome:       "error",
			ErrorMessage:  "transient error",
		}); err != nil {
			t.Fatalf("Insert: %v", err)
		}
	}

	n, err := repo.CountFailures(ctx, "test.stream.v1", "2-1", "test-group")
	if err != nil {
		t.Fatalf("CountFailures: %v", err)
	}
	// All 3 failures counted despite different consumer names.
	if n != 3 {
		t.Errorf("want 3 failures (survived name change), got %d", n)
	}
}

// TestAttemptRepository_DifferentMessagesIsolated verifies that failures for
// one messageID do not bleed into CountFailures for another.
func TestAttemptRepository_DifferentMessagesIsolated(t *testing.T) {
	ctx := context.Background()
	repo := &stubAttemptRepo{}

	for _, id := range []string{"msg-A", "msg-B"} {
		for i := 0; i < 2; i++ {
			_ = repo.Insert(ctx, eventbus.AttemptRow{
				Stream: "test.stream.v1", MessageID: id,
				ConsumerGroup: "grp", ConsumerName: "grp:h:1",
				Outcome: "error",
			})
		}
	}

	nA, _ := repo.CountFailures(ctx, "test.stream.v1", "msg-A", "grp")
	nB, _ := repo.CountFailures(ctx, "test.stream.v1", "msg-B", "grp")
	if nA != 2 || nB != 2 {
		t.Errorf("want nA=2, nB=2; got nA=%d, nB=%d", nA, nB)
	}
}

// TestNoopAttemptRepository_Noop verifies the noop implementation never errors.
func TestNoopAttemptRepository_Noop(t *testing.T) {
	ctx := context.Background()
	repo := eventbus.NewNoopAttemptRepository()

	if err := repo.Insert(ctx, eventbus.AttemptRow{Outcome: "error"}); err != nil {
		t.Errorf("noop Insert: %v", err)
	}
	n, err := repo.CountFailures(ctx, "s", "m", "g")
	if err != nil || n != 0 {
		t.Errorf("noop CountFailures: n=%d err=%v", n, err)
	}
}
