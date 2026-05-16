package sellerpayout

import (
	"context"
	"fmt"
	"log/slog"
	"time"

	"github.com/robfig/cron/v3"

	"github.com/mopro/platform/pkg/healthcheck"
)

// DailyCron wraps the daily payout cron (02:30 UTC) and the reconcile cron (every 30 min).
type DailyCron struct {
	svc      Service
	market   string
	currency string
	loc      *time.Location
	pinger   healthcheck.Pinger
	log      *slog.Logger
	c        *cron.Cron
}

// NewDailyCron constructs a DailyCron. loc must be the configured timezone (e.g. UTC or Istanbul).
// pinger signals job liveness to an external monitor; pass healthcheck.NewNoop() to disable.
func NewDailyCron(svc Service, market, currency string, loc *time.Location, pinger healthcheck.Pinger, log *slog.Logger) *DailyCron {
	if pinger == nil {
		pinger = healthcheck.NewNoop()
	}
	if log == nil {
		log = slog.Default()
	}
	return &DailyCron{
		svc:      svc,
		market:   market,
		currency: currency,
		loc:      loc,
		pinger:   pinger,
		log:      log,
	}
}

// Start registers the cron jobs and starts the scheduler.
// "0 30 2 * * *" with cron.WithSeconds() = 02:30:00 UTC daily.
// "0 */30 * * * *" with cron.WithSeconds() = every 30 minutes.
func (d *DailyCron) Start() {
	d.c = cron.New(cron.WithSeconds(), cron.WithLocation(d.loc))

	d.c.AddFunc("0 30 2 * * *", func() { //nolint:errcheck
		d.runDaily()
	})
	d.c.AddFunc("0 */30 * * * *", func() { //nolint:errcheck
		d.runReconcile()
	})

	d.c.Start()
	d.log.Info("sellerpayout: daily cron started",
		"market", d.market,
		"currency", d.currency,
	)
}

// Stop halts the cron scheduler gracefully.
func (d *DailyCron) Stop() {
	if d.c != nil {
		d.c.Stop()
	}
}

func (d *DailyCron) runDaily() {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Hour)
	defer cancel()

	d.pinger.Start(ctx)

	today := time.Now().In(d.loc).Truncate(24 * time.Hour)
	d.log.InfoContext(ctx, "sellerpayout: daily cron starting",
		"payout_date", today.Format("2006-01-02"),
		"market", d.market,
		"currency", d.currency,
	)

	res, err := d.svc.RunDailyPayouts(ctx, today, d.market, d.currency)
	if err != nil {
		d.pinger.Fail(ctx, err.Error())
		d.log.ErrorContext(ctx, "sellerpayout: RunDailyPayouts error", "err", err)
		return
	}

	d.log.InfoContext(ctx, "sellerpayout: daily cron finished",
		"payout_date", res.PayoutDate.Format("2006-01-02"),
		"batched", res.Batched,
		"paid", res.Paid,
		"shadow", res.Shadow,
		"failed", res.Failed,
		"skipped", res.Skipped,
		"ambiguous", res.Ambiguous,
	)

	if res.Failed > 0 || res.Ambiguous > 0 {
		d.pinger.Fail(ctx, fmt.Sprintf("failed=%d ambiguous=%d", res.Failed, res.Ambiguous))
		return
	}
	d.pinger.Success(ctx)
}

func (d *DailyCron) runReconcile() {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Minute)
	defer cancel()

	if err := d.svc.ReconcileProcessing(ctx); err != nil {
		d.log.ErrorContext(ctx, "sellerpayout: ReconcileProcessing error", "err", err)
	}
}
