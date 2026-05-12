//go:build integration

package cart_test

// Property test: 100 concurrent Reserve attempts on a single variant with stock=10.
// Invariants:
//   - At most 10 succeed (Lua atomicity guarantees no over-sell).
//   - Exactly stock units consumed → final Redis stock = 0.
//   - successes + failures == 100.
// Run with -race to catch data races.

import (
	"context"
	"strconv"
	"sync"
	"testing"

	"github.com/mopro/platform/internal/cart"
)

func TestProperty_ConcurrentReservationAtomicity(t *testing.T) {
	const (
		variantID = int64(9001)
		stock     = 10
		workers   = 100
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

	// Pre-populate each worker's cart with 1 unit of the variant.
	for i := 0; i < workers; i++ {
		userID := int64(i + 1)
		if err := svc.AddItem(ctx, userID, variantID, 1); err != nil {
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

	// All 10 stock units must have been consumed (final stock = 0).
	finalStr, err := integRedis.Get(ctx, "mopro:stock:"+strconv.FormatInt(variantID, 10)).Result()
	if err != nil {
		t.Fatalf("GET final stock: %v", err)
	}
	finalStock, _ := strconv.Atoi(finalStr)
	if finalStock != 0 {
		t.Errorf("expected final stock=0, got %d (successes=%d)", finalStock, successes)
	}

	t.Logf("result: successes=%d failures=%d stock=%d workers=%d", successes, failures, stock, workers)
}
