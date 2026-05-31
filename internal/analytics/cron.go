package analytics

import (
	"context"
	"log/slog"
	"time"

	"github.com/robfig/cron/v3"
)

// RetentionDays is the raw-event retention window (Decision 5).
const RetentionDays = 90

// pruneCapPerRun bounds rows deleted per DELETE to avoid lock contention (§3.6).
const pruneCapPerRun = 100_000

// Crons runs the jobs-svc analytics maintenance jobs: a daily retention prune
// (03:00) and a daily recently-viewed rebuild backstop (04:00), both in
// Europe/Istanbul (TRANCHE_4_DESIGN.md §3.6).
type Crons struct {
	svc           Service
	loc           *time.Location
	retentionDays int
	log           *slog.Logger
	cron          *cron.Cron
}

// NewCrons constructs the analytics crons. loc should be Europe/Istanbul;
// retentionDays <= 0 falls back to RetentionDays.
func NewCrons(svc Service, loc *time.Location, retentionDays int, log *slog.Logger) *Crons {
	if retentionDays <= 0 {
		retentionDays = RetentionDays
	}
	if log == nil {
		log = slog.Default()
	}
	return &Crons{svc: svc, loc: loc, retentionDays: retentionDays, log: log}
}

// Start registers both jobs and starts the scheduler.
func (c *Crons) Start(ctx context.Context) {
	c.cron = cron.New(
		cron.WithSeconds(),
		cron.WithLocation(c.loc),
		cron.WithLogger(cron.DiscardLogger),
	)
	_, _ = c.cron.AddFunc("0 0 3 * * *", func() { c.runPrune(ctx) })   // 03:00 daily
	_, _ = c.cron.AddFunc("0 0 4 * * *", func() { c.runRebuild(ctx) }) // 04:00 daily
	c.cron.Start()
	c.log.InfoContext(ctx, "analytics: crons started",
		"prune", "0 0 3 * * * (Europe/Istanbul)",
		"rebuild", "0 0 4 * * * (Europe/Istanbul)",
		"retention_days", c.retentionDays)
}

// Stop gracefully halts the scheduler.
func (c *Crons) Stop() {
	if c.cron != nil {
		c.cron.Stop()
	}
}

func (c *Crons) runPrune(ctx context.Context) {
	start := time.Now()
	before := time.Now().In(c.loc).AddDate(0, 0, -c.retentionDays)
	n, err := c.svc.PruneEvents(ctx, before, pruneCapPerRun)
	if err != nil {
		c.log.ErrorContext(ctx, "analytics: retention prune error", "err", err)
		return
	}
	c.log.InfoContext(ctx, "analytics: retention prune complete",
		"deleted", n, "before", before.Format(time.RFC3339), "took", time.Since(start).String())
}

func (c *Crons) runRebuild(ctx context.Context) {
	start := time.Now()
	since := time.Now().In(c.loc).AddDate(0, 0, -c.retentionDays)
	if err := c.svc.RebuildRecentlyViewed(ctx, since); err != nil {
		c.log.ErrorContext(ctx, "analytics: recently-viewed rebuild error", "err", err)
		return
	}
	c.log.InfoContext(ctx, "analytics: recently-viewed rebuild complete",
		"since", since.Format(time.RFC3339), "took", time.Since(start).String())
}
