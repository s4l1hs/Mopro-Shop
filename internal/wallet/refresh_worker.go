package wallet

import (
	"context"
	"log/slog"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// RefreshWorker periodically refreshes wallet_schema.balances (materialized view).
// Controlled by WALLET_BALANCE_REFRESH_INTERVAL (default 1h). The worker registers
// graceful shutdown via context cancellation — fin-svc passes the signal-aware ctx.
type RefreshWorker struct {
	pool     *pgxpool.Pool
	interval time.Duration
	log      *slog.Logger
}

// NewRefreshWorker constructs a RefreshWorker. interval ≤ 0 defaults to 1 hour.
func NewRefreshWorker(pool *pgxpool.Pool, interval time.Duration, log *slog.Logger) *RefreshWorker {
	if interval <= 0 {
		interval = time.Hour
	}
	return &RefreshWorker{pool: pool, interval: interval, log: log}
}

// Run starts the refresh loop. Blocks until ctx is cancelled.
// Call as a goroutine from fin-svc/main.go:
//
//	go wallet.NewRefreshWorker(pool, interval, log).Run(ctx)
func (w *RefreshWorker) Run(ctx context.Context) {
	ticker := time.NewTicker(w.interval)
	defer ticker.Stop()
	w.log.Info("wallet: balance MV refresh worker started", "interval", w.interval)
	for {
		select {
		case <-ctx.Done():
			w.log.Info("wallet: balance MV refresh worker stopped")
			return
		case <-ticker.C:
			if err := w.refresh(ctx); err != nil {
				w.log.Error("wallet: balance MV refresh failed", "err", err)
			} else {
				w.log.Debug("wallet: balance MV refreshed")
			}
		}
	}
}

// RefreshOnce performs a single REFRESH MATERIALIZED VIEW CONCURRENTLY.
// Exposed for testing (integration test triggers the refresh and verifies balances update).
func (w *RefreshWorker) RefreshOnce(ctx context.Context) error {
	return w.refresh(ctx)
}

func (w *RefreshWorker) refresh(ctx context.Context) error {
	_, err := w.pool.Exec(ctx, "REFRESH MATERIALIZED VIEW CONCURRENTLY wallet_schema.balances")
	return err
}
