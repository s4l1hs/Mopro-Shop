//go:build integration

package cart_test

// Property test: 100 concurrent Reserve attempts on a single variant with stock=10.
// 5 workers attempt AddItem with qty=-1 first (must all get ErrInvalidQty).
// Invariants:
//   - negRejected == negWorkers (negative qty guard fires every time).
//   - At most 10 succeed (Lua atomicity guarantees no over-sell).
//   - finalStock == initialStock - successes (no phantom stock increase or loss).
//   - successes + failures == workers.
// Run with -race to catch data races.

import (
	"context"
	"errors"
	"strconv"
	"sync"
	"testing"

	"github.com/mopro/platform/internal/cart"
)

func TestProperty_ConcurrentReservationAtomicity(t *testing.T) {
	const (
		variantID  = int64(9001)
		stock      = 10
		workers    = 100
		negWorkers = 5 // first N workers use qty=-1; all must be rejected with ErrInvalidQty
	)

	ctx := context.Background()

	repo, err := cart.NewRepository(ctx, integRedis)
	if err != nil {
		t.Fatalf("NewRepository: %v", err)
	}
	svc := cart.NewService(repo, alwaysValidCatalog{})

	// Reset stock to exactly 10 before the test.
	if err := integRedis.Del(ctx, "mopro:stock:"+strconv.FormatInt(variantID, 10)).Err(); err != nil {
		t.Fatalf("Del stock: %v", err)
	}
	if err := svc.SeedStock(ctx, variantID, stock); err != nil {
		t.Fatalf("SeedStock: %v", err)
	}

	// Workers [0, negWorkers) attempt qty=-1 — must be rejected before any Lua call.
	negRejected := 0
	for i := 0; i < negWorkers; i++ {
		if err := svc.AddItem(ctx, int64(i+1), variantID, -1); !errors.Is(err, cart.ErrInvalidQty) {
			t.Fatalf("worker %d: expected ErrInvalidQty for qty=-1, got %v", i, err)
		}
		negRejected++
	}
	if negRejected != negWorkers {
		t.Errorf("expected %d ErrInvalidQty rejections, got %d", negWorkers, negRejected)
	}

	// Workers [negWorkers, workers) add qty=1 normally.
	for i := negWorkers; i < workers; i++ {
		if err := svc.AddItem(ctx, int64(i+1), variantID, 1); err != nil {
			t.Fatalf("AddItem worker %d: %v", i, err)
		}
	}

	var (
		wg        sync.WaitGroup
		mu        sync.Mutex
		successes int
		failures  int
	)

	for i := 0; i < workers; i++ {
		wg.Add(1)
		go func(userID int64) {
			defer wg.Done()
			_, _, resErr := svc.Reserve(ctx, userID)
			mu.Lock()
			if resErr == nil {
				successes++
			} else {
				failures++
			}
			mu.Unlock()
		}(int64(i + 1))
	}

	wg.Wait()

	if successes > stock {
		t.Errorf("OVER-SELL: %d reservations succeeded but stock was %d", successes, stock)
	}
	if successes+failures != workers {
		t.Errorf("successes(%d) + failures(%d) != workers(%d)", successes, failures, workers)
	}

	finalStr, err := integRedis.Get(ctx, "mopro:stock:"+strconv.FormatInt(variantID, 10)).Result()
	if err != nil {
		t.Fatalf("GET final stock: %v", err)
	}
	finalStock, _ := strconv.Atoi(finalStr)

	if finalStock > stock {
		t.Errorf("STOCK LEAK: final stock %d > initial %d (negative qty guard failed)", finalStock, stock)
	}
	if finalStock != stock-successes {
		t.Errorf("stock accounting: initial=%d successes=%d expected_final=%d got=%d",
			stock, successes, stock-successes, finalStock)
	}

	t.Logf("result: negRejected=%d successes=%d failures=%d initialStock=%d finalStock=%d workers=%d",
		negRejected, successes, failures, stock, finalStock, workers)
}
