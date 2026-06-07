//go:build integration

package outbox_test

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"os"
	"sort"
	"sync"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/leanovate/gopter"
	"github.com/leanovate/gopter/gen"
	"github.com/leanovate/gopter/prop"
	"github.com/redis/go-redis/v9"

	"github.com/mopro/platform/internal/eventbus"
	"github.com/mopro/platform/internal/outbox"
)

// Connection details for the ephemeral test containers (Phase 0.4 integration run).
// PG16:  docker run --rm -d --name pg-test  -p 6434:5432 -e POSTGRES_USER=ledger_admin ...
// Redis: docker run --rm -d --name redis-test -p 6380:6379 redis:7-alpine
// DSN/addr are env-overridable (F-018) so the suite reuses the shared verify
// fixtures (pg-ledger-test :6434 / redis-e2e :6381) — same envs as eventbus.
const testTable = "wallet_schema.outbox"

func testDSN() string {
	if v := os.Getenv("LEDGER_TEST_DSN"); v != "" {
		return v
	}
	return "postgres://ledger_admin:test123@localhost:6434/mopro_ledger" //nolint:gosec
}

func testRedisAddr() string {
	if v := os.Getenv("REDIS_TEST_ADDR"); v != "" {
		return v
	}
	return "localhost:6380"
}

var (
	tPool *pgxpool.Pool
	tRdb  *redis.Client
)

func TestMain(m *testing.M) {
	ctx := context.Background()

	var err error
	tPool, err = pgxpool.New(ctx, testDSN())
	if err != nil {
		fmt.Fprintf(os.Stderr, "outbox integration: cannot connect to postgres (%s): %v\n", testDSN(), err)
		os.Exit(1)
	}
	if err := tPool.Ping(ctx); err != nil {
		fmt.Fprintf(os.Stderr, "outbox integration: postgres ping failed: %v\n", err)
		os.Exit(1)
	}

	tRdb = redis.NewClient(&redis.Options{Addr: testRedisAddr()})
	if err := tRdb.Ping(ctx).Err(); err != nil {
		fmt.Fprintf(os.Stderr, "outbox integration: cannot connect to redis (%s): %v\n", testRedisAddr(), err)
		os.Exit(1)
	}

	code := m.Run()
	tPool.Close()
	tRdb.Close()
	os.Exit(code)
}

// ─── helpers ───────────────────────────────────────────────────────────────────

func testRepo() outbox.Repository { return outbox.NewRepository(testTable) }
func testBus() *eventbus.RedisBus { return eventbus.NewRedisBus(tRdb, slog.Default()) }
func testPublisher() (*outbox.Publisher, error) {
	return outbox.NewPublisher(tPool, testRepo(), testBus(), slog.Default())
}

// uniqueStream returns a test-scoped stream name that won't collide across iterations.
func uniqueStream(prefix string) string {
	return fmt.Sprintf("test.outbox.%s.%d.v1", prefix, time.Now().UnixNano())
}

// insertRow inserts one Row in its own transaction and commits.
func insertRow(ctx context.Context, stream, key string) error {
	tx, err := tPool.Begin(ctx)
	if err != nil {
		return err
	}
	err = testRepo().Insert(ctx, tx, outbox.Row{
		Aggregate:      "test",
		EventType:      stream,
		Payload:        json.RawMessage(`{"test":true}`),
		IdempotencyKey: key,
		Market:         "TR",
		Currency:       "TRY",
	})
	if err != nil {
		tx.Rollback(ctx)
		return err
	}
	return tx.Commit(ctx)
}

// cleanTestData removes rows and the stream for a given stream name.
func cleanTestData(ctx context.Context, stream string) {
	tPool.Exec(ctx, "DELETE FROM "+testTable+" WHERE event_type = $1", stream)
	tRdb.Del(ctx, stream)
}

// ─── Test 1: Every inserted row is eventually published ────────────────────────

func TestPropertyEveryInsertedRowIsEventuallyPublished(t *testing.T) {
	params := gopter.DefaultTestParameters()
	params.MinSuccessfulTests = 30

	properties := gopter.NewProperties(params)
	properties.Property(
		"every inserted row is eventually published (published_at IS NOT NULL)",
		prop.ForAll(
			func(seed uint8) bool {
				count := int(seed)%40 + 1 // [1, 40]
				ctx := context.Background()
				stream := uniqueStream("prop1")
				prefix := fmt.Sprintf("p1-%d", time.Now().UnixNano())
				t.Cleanup(func() { cleanTestData(ctx, stream) })

				for i := 0; i < count; i++ {
					if err := insertRow(ctx, stream, fmt.Sprintf("%s-%04d", prefix, i)); err != nil {
						t.Logf("insertRow[%d] failed: %v", i, err)
						return false
					}
				}

				pub, err := testPublisher()
				if err != nil {
					t.Logf("testPublisher: %v", err)
					return false
				}

				totalPublished := 0
				for cycle := 0; cycle < 3 && totalPublished < count; cycle++ {
					n, err := pub.RunBatch(ctx)
					if err != nil {
						t.Logf("RunBatch cycle %d: %v", cycle, err)
						return false
					}
					totalPublished += n
				}

				var publishedInDB int
				tPool.QueryRow(ctx,
					"SELECT count(*) FROM "+testTable+
						" WHERE event_type = $1 AND published_at IS NOT NULL",
					stream,
				).Scan(&publishedInDB)

				if publishedInDB != count {
					t.Logf("want %d published rows, got %d", count, publishedInDB)
				}
				return publishedInDB == count
			},
			gen.UInt8(),
		),
	)
	properties.TestingRun(t)
}

// ─── Test 2: Per-aggregate insertion order preserved in the Redis stream ───────

func TestPropertyPerAggregateOrderPreserved(t *testing.T) {
	params := gopter.DefaultTestParameters()
	params.MinSuccessfulTests = 10

	properties := gopter.NewProperties(params)
	properties.Property(
		"XADD order matches ORDER BY id ASC within a single RunBatch",
		prop.ForAll(
			func(seed uint8) bool {
				count := int(seed)%30 + 10 // [10, 39]
				ctx := context.Background()
				stream := uniqueStream("prop2")
				prefix := fmt.Sprintf("p2-%d", time.Now().UnixNano())
				t.Cleanup(func() { cleanTestData(ctx, stream) })

				// Insert N rows sequentially — BIGSERIALs will be N consecutive values.
				keys := make([]string, count)
				for i := 0; i < count; i++ {
					keys[i] = fmt.Sprintf("%s-%06d", prefix, i) // zero-padded → lexicographically sortable
					if err := insertRow(ctx, stream, keys[i]); err != nil {
						t.Logf("insertRow[%d]: %v", i, err)
						return false
					}
				}

				pub, _ := testPublisher()
				if _, err := pub.RunBatch(ctx); err != nil {
					t.Logf("RunBatch: %v", err)
					return false
				}

				msgs, err := tRdb.XRange(ctx, stream, "-", "+").Result()
				if err != nil {
					t.Logf("XRange: %v", err)
					return false
				}
				if len(msgs) != count {
					t.Logf("stream entries: want %d, got %d", count, len(msgs))
					return false
				}

				// Extract received idempotency_keys in Redis delivery order.
				received := make([]string, len(msgs))
				for i, msg := range msgs {
					if ik, ok := msg.Values["idempotency_key"].(string); ok {
						received[i] = ik
					}
				}

				// Expected: keys sorted lexicographically (matches sequential BIGSERIAL → ORDER BY id ASC).
				expected := make([]string, len(keys))
				copy(expected, keys)
				sort.Strings(expected)

				for i := range expected {
					if received[i] != expected[i] {
						t.Logf("order mismatch pos %d: got %q, want %q", i, received[i], expected[i])
						return false
					}
				}
				return true
			},
			gen.UInt8(),
		),
	)
	properties.TestingRun(t)
}

// ─── Test 3: Duplicate idempotency_key rejected; zero extra stream entries ─────

func TestPropertyDuplicateIdempotencyKeyRejected(t *testing.T) {
	params := gopter.DefaultTestParameters()
	params.MinSuccessfulTests = 50

	properties := gopter.NewProperties(params)
	properties.Property(
		"second Insert with same idempotency_key returns ErrDuplicateIdempotency and produces no extra stream entry",
		prop.ForAll(
			func(salt uint32) bool {
				ctx := context.Background()
				stream := uniqueStream("prop3")
				key := fmt.Sprintf("p3-%d-%d", time.Now().UnixNano(), salt)
				t.Cleanup(func() { cleanTestData(ctx, stream) })

				// First insert — must succeed.
				if err := insertRow(ctx, stream, key); err != nil {
					t.Logf("first insert failed: %v", err)
					return false
				}

				// Second insert with same key — must return ErrDuplicateIdempotency.
				tx, _ := tPool.Begin(ctx)
				err := testRepo().Insert(ctx, tx, outbox.Row{
					Aggregate:      "test",
					EventType:      stream,
					Payload:        json.RawMessage(`{}`),
					IdempotencyKey: key,
					Market:         "TR",
					Currency:       "TRY",
				})
				tx.Rollback(ctx)

				if err != outbox.ErrDuplicateIdempotency {
					t.Logf("second insert: want ErrDuplicateIdempotency, got %v", err)
					return false
				}

				// Publish: only one row exists in the outbox.
				pub, _ := testPublisher()
				pub.RunBatch(ctx)

				msgs, err := tRdb.XRange(ctx, stream, "-", "+").Result()
				if err != nil {
					t.Logf("XRange: %v", err)
					return false
				}
				if len(msgs) != 1 {
					t.Logf("stream entry count: want 1, got %d", len(msgs))
					return false
				}
				ik, _ := msgs[0].Values["idempotency_key"].(string)
				if ik != key {
					t.Logf("stream entry has wrong idempotency_key: %q", ik)
					return false
				}
				return true
			},
			gen.UInt32(),
		),
	)
	properties.TestingRun(t)
}

// ─── Test 4: Re-delivery idempotency — handler applied exactly once ────────────

func TestPropertyReDeliveryIdempotency(t *testing.T) {
	params := gopter.DefaultTestParameters()
	params.MinSuccessfulTests = 20

	properties := gopter.NewProperties(params)
	properties.Property(
		"duplicate stream entries from re-publish are processed idempotently by a counting consumer",
		prop.ForAll(
			func(salt uint32) bool {
				ctx := context.Background()
				stream := uniqueStream("prop4")
				key := fmt.Sprintf("p4-%d-%d", time.Now().UnixNano(), salt)
				t.Cleanup(func() { cleanTestData(ctx, stream) })

				// Insert row.
				if err := insertRow(ctx, stream, key); err != nil {
					t.Logf("insertRow: %v", err)
					return false
				}

				// ── Simulate a publisher crash between XADD and MarkPublished. ──
				// Fetch the row (FOR UPDATE SKIP LOCKED inside tx), XADD manually,
				// then ROLLBACK instead of committing — row stays published_at=NULL.
				repo := testRepo()
				tx, _ := tPool.Begin(ctx)
				rows, _ := repo.FetchUnpublished(ctx, tx, 10)
				var target outbox.Row
				for _, r := range rows {
					if r.IdempotencyKey == key {
						target = r
						break
					}
				}
				if target.ID == 0 {
					tx.Rollback(ctx)
					t.Log("target row not found in FetchUnpublished")
					return false
				}
				// XADD manually (simulates the crash victim's successful Publish call).
				bus := testBus()
				_ = bus.Publish(ctx, eventbus.Event{
					EventID:        target.IdempotencyKey,
					EventType:      target.EventType,
					Aggregate:      target.Aggregate,
					IdempotencyKey: target.IdempotencyKey,
					Market:         target.Market,
					Currency:       target.Currency,
					TraceID:        target.TraceID,
					SpanID:         target.SpanID,
					OccurredAt:     target.CreatedAt,
					Payload:        target.Payload,
				})
				tx.Rollback(ctx) // crash: row NOT marked published, lock released

				// ── Run publisher: row is still published_at=NULL; re-published. ──
				pub, _ := testPublisher()
				if _, err := pub.RunBatch(ctx); err != nil {
					t.Logf("RunBatch: %v", err)
					return false
				}

				// Stream now contains ≥2 entries with the same idempotency_key.
				msgs, err := tRdb.XRange(ctx, stream, "-", "+").Result()
				if err != nil || len(msgs) < 2 {
					t.Logf("expected ≥2 stream entries (re-delivery), got %d (err=%v)", len(msgs), err)
					return false
				}

				// Counting consumer: mimics FindPlanByOrderID / FindPayoutByKey — checks
				// "already processed" before committing any side effect.
				processed := make(map[string]bool)
				sideEffectCount := 0
				for _, msg := range msgs {
					ik, _ := msg.Values["idempotency_key"].(string)
					if processed[ik] {
						continue // idempotent no-op — duplicate detected
					}
					processed[ik] = true
					sideEffectCount++
				}

				if sideEffectCount != 1 {
					t.Logf("idempotent consumer applied %d side effects, want 1", sideEffectCount)
				}
				return sideEffectCount == 1
			},
			gen.UInt32(),
		),
	)
	properties.TestingRun(t)
}

// ─── Test 5: Chaos — Redis down during publishing burst ────────────────────────
//
// faultInjector wraps an eventbus.Publisher and toggles error injection at runtime.
// Simulates a Redis outage: Publish returns an error while fail==true, then
// delegates normally after recovery.
type faultInjector struct {
	inner eventbus.Publisher
	mu    sync.Mutex
	fail  bool
}

func (f *faultInjector) setFail(v bool) {
	f.mu.Lock()
	f.fail = v
	f.mu.Unlock()
}

func (f *faultInjector) Publish(ctx context.Context, ev eventbus.Event) error {
	f.mu.Lock()
	fail := f.fail
	f.mu.Unlock()
	if fail {
		return fmt.Errorf("simulated Redis unavailable")
	}
	return f.inner.Publish(ctx, ev)
}

// TestChaos_RedisDownDuringBurst inserts N rows, then simulates a Redis outage
// for ~3 seconds while the publisher is running. After recovery it asserts:
//   - all N rows are eventually published (no data loss)
//   - the Redis stream contains at least N entries
//
// This validates the exponential backoff and catch-up behaviour defined in
// Prompt 3.3. The 3-second simulated outage mirrors the pattern of a 30-second
// real Redis restart (same backoff state machine; only the wall-clock duration differs).
func TestChaos_RedisDownDuringBurst(t *testing.T) {
	const n = 50
	ctx := context.Background()
	stream := uniqueStream("chaos")
	prefix := fmt.Sprintf("chaos-%d", time.Now().UnixNano())
	t.Cleanup(func() { cleanTestData(ctx, stream) })

	for i := 0; i < n; i++ {
		if err := insertRow(ctx, stream, fmt.Sprintf("%s-%04d", prefix, i)); err != nil {
			t.Fatalf("insertRow[%d]: %v", i, err)
		}
	}

	fault := &faultInjector{inner: testBus()}
	pub, err := outbox.NewPublisher(tPool, testRepo(), fault, slog.Default())
	if err != nil {
		t.Fatal(err)
	}

	runCtx, cancelRun := context.WithCancel(ctx)
	pubDone := make(chan error, 1)
	go func() { pubDone <- pub.Run(runCtx) }()

	// Enable Redis fault immediately — simulates outage during an active burst.
	fault.setFail(true)
	time.Sleep(3 * time.Second)

	// Restore Redis — publisher catches up via exponential backoff reset.
	fault.setFail(false)

	// Wait up to 30s for all rows to be published after recovery.
	deadline := time.Now().Add(30 * time.Second)
	var publishedInDB int
	for time.Now().Before(deadline) {
		tPool.QueryRow(ctx, //nolint:errcheck
			"SELECT count(*) FROM "+testTable+" WHERE event_type = $1 AND published_at IS NOT NULL",
			stream,
		).Scan(&publishedInDB) //nolint:errcheck
		if publishedInDB == n {
			break
		}
		time.Sleep(100 * time.Millisecond)
	}

	cancelRun()
	select {
	case <-pubDone:
	case <-time.After(35 * time.Second):
		t.Fatal("chaos: pub.Run did not return after context cancel")
	}

	// Assert no data loss.
	if publishedInDB != n {
		t.Errorf("chaos: published_in_db want %d, got %d (rows lost during outage)", n, publishedInDB)
	}

	// Assert Redis stream received all entries (at-least-once: duplicates tolerated).
	streamLen, _ := tRdb.XLen(ctx, stream).Result()
	if streamLen < int64(n) {
		t.Errorf("chaos: Redis stream has %d entries, want >= %d", streamLen, n)
	}
	t.Logf("chaos: n=%d db_published=%d stream_entries=%d", n, publishedInDB, streamLen)
}
