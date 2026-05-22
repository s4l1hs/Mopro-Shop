// Package cleanup provides a background worker that purges expired identity records.
package cleanup

import (
	"context"
	"log/slog"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// StartCleanupWorker starts a goroutine that purges expired OTP codes and refresh tokens.
// It ticks every hour and deletes:
//   - otp_codes older than 7 days
//   - refresh_tokens that expired more than 30 days ago
//
// The goroutine stops when ctx is cancelled.
func StartCleanupWorker(ctx context.Context, pool *pgxpool.Pool, log *slog.Logger) {
	go run(ctx, pool, log)
}

func run(ctx context.Context, pool *pgxpool.Pool, log *slog.Logger) {
	// Run once immediately at startup, then every hour.
	tick := time.NewTicker(1 * time.Hour)
	defer tick.Stop()

	cleanup(ctx, pool, log)
	for {
		select {
		case <-ctx.Done():
			return
		case <-tick.C:
			cleanup(ctx, pool, log)
		}
	}
}

func cleanup(ctx context.Context, pool *pgxpool.Pool, log *slog.Logger) {
	cutoffOTP := time.Now().Add(-7 * 24 * time.Hour)
	tag, err := pool.Exec(ctx,
		`DELETE FROM identity_schema.otp_codes WHERE created_at < $1`,
		cutoffOTP,
	)
	if err != nil {
		log.Error("identity cleanup: delete otp_codes", "err", err)
	} else {
		log.Info("identity cleanup: otp_codes", "deleted", tag.RowsAffected())
	}

	cutoffTokens := time.Now().Add(-30 * 24 * time.Hour)
	tag, err = pool.Exec(ctx,
		`DELETE FROM identity_schema.refresh_tokens WHERE expires_at < $1`,
		cutoffTokens,
	)
	if err != nil {
		log.Error("identity cleanup: delete refresh_tokens", "err", err)
	} else {
		log.Info("identity cleanup: refresh_tokens", "deleted", tag.RowsAffected())
	}
}
