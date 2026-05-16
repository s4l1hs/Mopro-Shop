package reconcile

import (
	"context"
	"log/slog"
	"time"

	"github.com/robfig/cron/v3"
)

// WeeklyCron wraps a robfig/cron that runs RunWeekly every Sunday at 03:05
// Europe/Istanbul (cron expression "0 5 3 * * 0" with cron.WithSeconds()).
type WeeklyCron struct {
	svc  Service
	loc  *time.Location
	log  *slog.Logger
	cron *cron.Cron
}

// NewWeeklyCron constructs the cron. loc should be Europe/Istanbul.
func NewWeeklyCron(svc Service, loc *time.Location, log *slog.Logger) *WeeklyCron {
	if log == nil {
		log = slog.Default()
	}
	return &WeeklyCron{svc: svc, loc: loc, log: log}
}

// Start registers the job and starts the cron scheduler.
func (c *WeeklyCron) Start(ctx context.Context) {
	c.cron = cron.New(
		cron.WithSeconds(),
		cron.WithLocation(c.loc),
		cron.WithLogger(cron.DiscardLogger),
	)
	_, _ = c.cron.AddFunc("0 5 3 * * 0", func() {
		asOf := time.Now().In(c.loc)
		result, err := c.svc.RunWeekly(ctx, asOf)
		if err != nil {
			c.log.ErrorContext(ctx, "reconcile: weekly cron error", "err", err)
			return
		}
		c.log.InfoContext(ctx, "reconcile: weekly cron complete",
			"alerts_inserted", result.AlertsInserted,
			"errors", len(result.Errors))
	})
	c.cron.Start()
	c.log.InfoContext(ctx, "reconcile: weekly cron started", "schedule", "0 5 3 * * 0 (Europe/Istanbul)")
}

// Stop gracefully shuts down the cron.
func (c *WeeklyCron) Stop() {
	if c.cron != nil {
		c.cron.Stop()
	}
}
