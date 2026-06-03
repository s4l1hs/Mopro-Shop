//go:build integration

package ratelimit_test

// Burst tests proving the F-017 fix: the sliding-window limiter must enforce the actual
// per-window count even when many requests land in the same millisecond. Pre-fix the Lua
// used the ms timestamp as the zset member, so same-ms requests collided to one element and
// the limit was under-enforced. Runs on integration-identity / integration-identity-race
// (`./internal/identity/...`). Uses its own Redis DB index (2) to stay isolated from the
// identity integration tests on DB 1 — and unique keys per test so there's no F-016-style
// cross-test interference.

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/redis/go-redis/v9"

	"github.com/mopro/platform/internal/identity/ratelimit"
)

func burstRedis(t *testing.T) *redis.Client {
	t.Helper()
	addr := os.Getenv("IDENTITY_TEST_REDIS")
	if addr == "" {
		addr = "localhost:6380"
	}
	rdb := redis.NewClient(&redis.Options{
		Addr:     addr,
		Password: os.Getenv("REDIS_TEST_PASSWORD"),
		DB:       2, // isolated from identity integration tests (DB 1)
	})
	ctx := context.Background()
	if err := rdb.Ping(ctx).Err(); err != nil {
		t.Skipf("ratelimit burst: redis not available at %s: %v", addr, err)
	}
	t.Cleanup(func() { _ = rdb.Close() })
	return rdb
}

// The phone 10-minute OTP-request limit is 3 (see CheckOTPRequest). A same-millisecond
// burst of 10 must therefore allow EXACTLY 3 — not silently let extras through.
func TestRateLimiter_SameMillisecondBurst_EnforcesPhoneLimit(t *testing.T) {
	rdb := burstRedis(t)
	ctx := context.Background()
	lim := ratelimit.New(rdb)

	// Unique key per test run so prior runs / siblings don't interfere.
	phoneHash := []byte("f017-burst-same-ms-" + time.Now().Format("150405.000000000"))

	allowed := 0
	for i := 0; i < 10; i++ { // tight loop → most calls share a millisecond
		if err := lim.CheckOTPRequest(ctx, phoneHash, ""); err == nil {
			allowed++
		}
	}
	if allowed != 3 {
		t.Errorf("same-ms burst of 10: want exactly 3 allowed (phone 3/10min), got %d "+
			"(pre-F-017 this leaked extras via ms-member collision)", allowed)
	}
}

// Concurrent callers (run under -race via integration-identity-race) must still see exactly
// the limit allowed — proves the fix holds under real concurrency, not just a tight loop.
func TestRateLimiter_ConcurrentBurst_EnforcesLimit(t *testing.T) {
	rdb := burstRedis(t)
	ctx := context.Background()
	lim := ratelimit.New(rdb)
	phoneHash := []byte("f017-burst-concurrent-" + time.Now().Format("150405.000000000"))

	const callers = 12
	results := make(chan bool, callers)
	for i := 0; i < callers; i++ {
		go func() { results <- lim.CheckOTPRequest(ctx, phoneHash, "") == nil }()
	}
	allowed := 0
	for i := 0; i < callers; i++ {
		if <-results {
			allowed++
		}
	}
	if allowed != 3 {
		t.Errorf("concurrent burst of %d: want exactly 3 allowed, got %d", callers, allowed)
	}
}

// Steady-state under the limit must always succeed (no false positives from the fix).
func TestRateLimiter_UnderLimit_AllSucceed(t *testing.T) {
	rdb := burstRedis(t)
	ctx := context.Background()
	lim := ratelimit.New(rdb)
	phoneHash := []byte("f017-under-limit-" + time.Now().Format("150405.000000000"))

	for i := 0; i < 3; i++ { // exactly the phone 10-min limit
		if err := lim.CheckOTPRequest(ctx, phoneHash, ""); err != nil {
			t.Fatalf("request %d under the limit must succeed, got %v", i+1, err)
		}
	}
}
