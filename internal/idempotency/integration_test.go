//go:build integration

package idempotency_test

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"sync"
	"testing"
	"time"

	"github.com/redis/go-redis/v9"

	"github.com/mopro/platform/internal/idempotency"
)

func redisClient(t *testing.T) *redis.Client {
	t.Helper()
	addr := os.Getenv("REDIS_URL")
	if addr == "" {
		addr = "redis://localhost:6379/15" // test DB 15 to avoid polluting dev data
	}
	opt, err := redis.ParseURL(addr)
	if err != nil {
		t.Fatalf("invalid REDIS_URL: %v", err)
	}
	rc := redis.NewClient(opt)
	t.Cleanup(func() { _ = rc.Close() })
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	if err := rc.Ping(ctx).Err(); err != nil {
		t.Skipf("Redis not reachable at %s: %v", addr, err)
	}
	return rc
}

func TestIntegration_AcquireAndSave(t *testing.T) {
	rc := redisClient(t)
	store := idempotency.NewRedisStore(rc)
	ctx := context.Background()
	key := "idem:test:acquire-save-" + t.Name()
	t.Cleanup(func() { _ = rc.Del(ctx, key) })

	acquired, err := store.Acquire(ctx, key)
	if err != nil || !acquired {
		t.Fatalf("first Acquire should succeed: acquired=%v err=%v", acquired, err)
	}

	acquired2, err := store.Acquire(ctx, key)
	if err != nil || acquired2 {
		t.Fatalf("second Acquire should fail: acquired=%v err=%v", acquired2, err)
	}

	resp := idempotency.CachedResponse{
		Status:      http.StatusCreated,
		ContentType: "application/json",
		Body:        []byte(`{"id":1}`),
	}
	if err := store.Save(ctx, key, resp); err != nil {
		t.Fatalf("Save: %v", err)
	}

	loaded, found, err := store.Load(ctx, key)
	if err != nil || !found {
		t.Fatalf("Load after Save: found=%v err=%v", found, err)
	}
	if loaded.Status != http.StatusCreated {
		t.Errorf("status mismatch: got %d", loaded.Status)
	}
}

func TestIntegration_PollReceivesResponse(t *testing.T) {
	rc := redisClient(t)
	store := idempotency.NewRedisStore(rc)
	ctx := context.Background()
	key := "idem:test:poll-" + t.Name()
	t.Cleanup(func() { _ = rc.Del(ctx, key) })

	// Acquire lock in main goroutine
	acquired, err := store.Acquire(ctx, key)
	if err != nil || !acquired {
		t.Fatalf("Acquire failed: %v", err)
	}

	// Goroutine saves the response after 150ms
	go func() {
		time.Sleep(150 * time.Millisecond)
		_ = store.Save(ctx, key, idempotency.CachedResponse{
			Status:      http.StatusOK,
			ContentType: "application/json",
			Body:        []byte(`{"done":true}`),
		})
	}()

	cr, err := store.Poll(ctx, key)
	if err != nil {
		t.Fatalf("Poll returned error: %v", err)
	}
	if cr == nil || cr.Status != http.StatusOK {
		t.Fatalf("unexpected poll result: %+v", cr)
	}
}

func TestIntegration_ConcurrentRequests_OnlyOneExecutes(t *testing.T) {
	rc := redisClient(t)
	store := idempotency.NewRedisStore(rc)
	ctx := context.Background()
	key := "idem:test:concurrent-" + t.Name()
	t.Cleanup(func() { _ = rc.Del(ctx, key) })

	extractID := func(_ context.Context) int64 { return 1 }

	var handlerCalls int
	var mu sync.Mutex
	handler := http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		mu.Lock()
		handlerCalls++
		mu.Unlock()
		time.Sleep(80 * time.Millisecond) // simulate work
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusCreated)
		_, _ = w.Write([]byte(`{"id":1}`))
	})

	mw := idempotency.New(store, extractID)
	wrapped := mw.Wrap(handler)

	const goroutines = 5
	var wg sync.WaitGroup
	responses := make([]int, goroutines)

	for i := range goroutines {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			r := httptest.NewRequest(http.MethodPost, "/test", nil)
			r.Header.Set("Idempotency-Key", "concurrent-key")
			w := httptest.NewRecorder()
			wrapped.ServeHTTP(w, r)
			responses[i] = w.Code
		}(i)
	}
	wg.Wait()

	// Handler must have run exactly once
	mu.Lock()
	calls := handlerCalls
	mu.Unlock()
	if calls != 1 {
		t.Errorf("handler executed %d times, expected exactly 1", calls)
	}

	// All responses must be 201 Created (either real or replayed)
	for i, code := range responses {
		if code != http.StatusCreated {
			t.Errorf("goroutine %d: expected 201, got %d", i, code)
		}
	}
}
