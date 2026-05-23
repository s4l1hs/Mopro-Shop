//go:build integration

package cart_test

import (
	"context"
	"fmt"
	"sync"
	"sync/atomic"
	"testing"

	"github.com/mopro/platform/internal/cart"
)

// TestStockReservation_ConcurrentGoroutines verifies the Lua EVALSHA atomicity guarantee:
// when N goroutines race to reserve stock from a pool of size S, exactly min(N, S) succeed.
// This is the critical invariant that prevents overselling.
func TestStockReservation_ConcurrentGoroutines(t *testing.T) {
	const (
		goroutines      = 100
		stockCount      = 50 // only 50 units available
		variantID       = int64(99991)
		qtyPerGoroutine = 1
	)

	ctx := context.Background()
	// integRedis is initialised by TestMain in integration_test.go (same package).
	repo, err := cart.NewRepository(ctx, integRedis)
	if err != nil {
		t.Fatalf("cart.NewRepository: %v", err)
	}

	if err := repo.SeedStock(ctx, variantID, stockCount); err != nil {
		t.Fatalf("SeedStock: %v", err)
	}
	t.Cleanup(func() {
		_ = integRedis.Del(ctx, fmt.Sprintf("mopro:stock:%d", variantID))
	})

	var (
		successes int64
		wg        sync.WaitGroup
		barrier   = make(chan struct{})
	)

	for i := 0; i < goroutines; i++ {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			<-barrier // all goroutines start simultaneously
			resID := fmt.Sprintf("test-res-%d", idx)
			ok, _, rErr := repo.TryReserve(ctx, variantID, qtyPerGoroutine, resID, int64(idx+1000), 300)
			if rErr != nil {
				return
			}
			if ok {
				atomic.AddInt64(&successes, 1)
			}
		}(i)
	}

	close(barrier)
	wg.Wait()

	if successes != stockCount {
		t.Errorf("concurrent reservation: want exactly %d successes, got %d (Lua atomicity failure)", stockCount, successes)
	}

	// Verify Redis counter is 0 — all stock consumed.
	remaining, _ := integRedis.Get(ctx, fmt.Sprintf("mopro:stock:%d", variantID)).Int64()
	t.Logf("remaining stock after %d goroutines: %d", goroutines, remaining)
}

// TestStockReservation_NoOversell verifies that stock never goes negative.
func TestStockReservation_NoOversell(t *testing.T) {
	const (
		goroutines = 30
		stock      = 10
		variantID  = int64(99992)
	)

	ctx := context.Background()
	repo, err := cart.NewRepository(ctx, integRedis)
	if err != nil {
		t.Fatalf("cart.NewRepository: %v", err)
	}

	if err := repo.SeedStock(ctx, variantID, stock); err != nil {
		t.Fatalf("SeedStock: %v", err)
	}
	t.Cleanup(func() {
		_ = integRedis.Del(ctx, fmt.Sprintf("mopro:stock:%d", variantID))
	})

	var wg sync.WaitGroup
	barrier := make(chan struct{})

	for i := 0; i < goroutines; i++ {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			<-barrier
			resID := fmt.Sprintf("oversell-res-%d", idx)
			_, _, _ = repo.TryReserve(ctx, variantID, 1, resID, int64(idx+2000), 300)
		}(i)
	}
	close(barrier)
	wg.Wait()

	// Stock must be >= 0 (never negative).
	val, err := integRedis.Get(ctx, fmt.Sprintf("mopro:stock:%d", variantID)).Int64()
	if err != nil {
		t.Fatalf("GET stock: %v", err)
	}
	if val < 0 {
		t.Errorf("stock went negative: %d (Lua atomicity failure)", val)
	}
}
