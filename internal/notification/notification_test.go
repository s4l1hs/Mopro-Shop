package notification_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"

	"github.com/mopro/platform/internal/eventbus"
	"github.com/mopro/platform/internal/notification"
	pkg_slack "github.com/mopro/platform/pkg/slack"
)

// ── helpers ───────────────────────────────────────────────────────────────────

// stubDedupStore implements notification.DedupStore in memory.
type stubDedupStore struct {
	seen map[string]bool
}

func newStubDedupStore() *stubDedupStore {
	return &stubDedupStore{seen: make(map[string]bool)}
}

func (s *stubDedupStore) MarkSent(_ context.Context, key, _ string) (bool, error) {
	if s.seen[key] {
		return true, nil
	}
	s.seen[key] = true
	return false, nil
}

// stubBus delivers a single event synchronously to the registered handler.
type stubBus struct {
	ev eventbus.Event
}

func (b *stubBus) Subscribe(_ context.Context, _, _ string, handler func(context.Context, eventbus.Event) error) error {
	return handler(context.Background(), b.ev)
}

func makeDriftEvent(idempotencyKey string, alertID int64) eventbus.Event {
	payload, _ := json.Marshal(map[string]any{
		"alert_id":           alertID,
		"check_name":         "wallet_balance_vs_entries",
		"currency_or_period": "TRY",
		"drift_minor":        9999,
	})
	return eventbus.Event{
		EventID:        idempotencyKey,
		EventType:      notification.TopicReconcileDrift,
		IdempotencyKey: idempotencyKey,
		Market:         "TR",
		Currency:       "TRY",
		OccurredAt:     time.Now(),
		Payload:        payload,
	}
}

// ── Test C: happy-path dedup ──────────────────────────────────────────────────

// TestReconcileDrift_DedupPreventsDoubleSend verifies that when the dedup store
// returns alreadySent=true on the second call, Slack.Post is NOT called again.
func TestReconcileDrift_DedupPreventsDoubleSend(t *testing.T) {
	var slackCalls atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		slackCalls.Add(1)
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()

	slack := pkg_slack.New(srv.URL)
	dedup := newStubDedupStore()
	ev := makeDriftEvent("dedup-test-idem-key-001", 42)

	bus1 := &stubBus{ev: ev}
	if err := notification.StartReconcileDriftConsumer(context.Background(), bus1, slack, dedup, nil); err != nil {
		t.Fatalf("first delivery: %v", err)
	}
	if slackCalls.Load() != 1 {
		t.Errorf("after first delivery: want 1 Slack call, got %d", slackCalls.Load())
	}

	// Second delivery of the SAME idempotency key.
	bus2 := &stubBus{ev: ev}
	if err := notification.StartReconcileDriftConsumer(context.Background(), bus2, slack, dedup, nil); err != nil {
		t.Fatalf("second delivery: %v", err)
	}
	if slackCalls.Load() != 1 {
		t.Errorf("after second (duplicate) delivery: want still 1 Slack call, got %d", slackCalls.Load())
	}
}

// ── Test D: Slack 503 → 200 retry ─────────────────────────────────────────────

// TestReconcileDrift_SlackRetryOn503 verifies that a transient Slack 503 is
// retried and the message is delivered exactly once when the second attempt succeeds.
func TestReconcileDrift_SlackRetryOn503(t *testing.T) {
	var callCount atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		n := callCount.Add(1)
		if n == 1 {
			w.WriteHeader(http.StatusServiceUnavailable) // first attempt: 503
			return
		}
		w.WriteHeader(http.StatusOK) // second attempt: success
	}))
	defer srv.Close()

	slack := pkg_slack.New(srv.URL)
	dedup := newStubDedupStore()
	ev := makeDriftEvent("retry-test-idem-key-002", 99)

	bus := &stubBus{ev: ev}
	if err := notification.StartReconcileDriftConsumer(context.Background(), bus, slack, dedup, nil); err != nil {
		t.Fatalf("consumer returned error: %v", err)
	}

	if callCount.Load() != 2 {
		t.Errorf("want 2 HTTP calls (1 fail + 1 retry), got %d", callCount.Load())
	}
}
