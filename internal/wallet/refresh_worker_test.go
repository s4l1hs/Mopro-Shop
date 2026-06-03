package wallet_test

// Unit test for RefreshWorker.Run's shutdown path (TESTING_AUDIT F-003), no DB.
// With a long interval no tick fires, so refresh() (and the pool) are never touched —
// this isolates the select/ctx.Done() branch of the loop. The integration tests
// (wallet_integration_test.go, on the integration-wallet gate) cover the tick→refresh
// path and error-resilience. See docs/internal/wallet-refresh-worker.md.

import (
	"context"
	"log/slog"
	"testing"
	"time"

	"github.com/mopro/platform/internal/wallet"
)

func TestRefreshWorker_Run_ExitsOnContextCancel(t *testing.T) {
	// Interval far in the future → the first tick never arrives during the test, so the
	// nil pool is never dereferenced; only the ctx.Done() branch executes.
	w := wallet.NewRefreshWorker(nil, time.Hour, slog.Default())
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		w.Run(ctx)
		close(done)
	}()
	cancel()
	select {
	case <-done:
		// Run returned promptly on cancel — the shutdown path works.
	case <-time.After(2 * time.Second):
		t.Fatal("RefreshWorker.Run did not return after context cancel")
	}
}
