package cashback

import (
	"context"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"github.com/robfig/cron/v3"

	"github.com/mopro/platform/pkg/healthcheck"
)

// MarketConfig binds a market code to its coin currency for cron scheduling.
// Kept for backward compat with main.go wiring; PayMonthlyInstallments processes
// all currencies in a single pass so the markets list is no longer iterated.
type MarketConfig struct {
	Market   string
	Currency string
}

// ParseMarketConfigs parses "MARKET:CURRENCY,..." env var format.
// Example: "TR:TRY_COIN,DE:EUR_COIN" → [{TR TRY_COIN} {DE EUR_COIN}]
func ParseMarketConfigs(raw string) ([]MarketConfig, error) {
	var configs []MarketConfig
	for _, pair := range strings.Split(raw, ",") {
		pair = strings.TrimSpace(pair)
		if pair == "" {
			continue
		}
		parts := strings.SplitN(pair, ":", 2)
		if len(parts) != 2 || parts[0] == "" || parts[1] == "" {
			return nil, fmt.Errorf("cashback: invalid market config %q (want MARKET:CURRENCY)", pair)
		}
		configs = append(configs, MarketConfig{Market: strings.TrimSpace(parts[0]), Currency: strings.TrimSpace(parts[1])})
	}
	if len(configs) == 0 {
		return nil, fmt.Errorf("cashback: CASHBACK_CRON_MARKETS is empty or invalid")
	}
	return configs, nil
}

// MonthlyCron schedules PayMonthlyInstallments on the 1st of each month at 03:00 Istanbul time.
type MonthlyCron struct {
	svc    Service
	pinger healthcheck.Pinger
	log    *slog.Logger
	loc    *time.Location
	c      *cron.Cron
}

// NewMonthlyCron constructs a MonthlyCron.
// loc must be the Istanbul timezone; pass time.LoadLocation("Europe/Istanbul").
// markets is accepted for API compat with main.go but is not used (v8 processes all currencies).
// pinger is called with Start/Success/Fail around each run.
func NewMonthlyCron(svc Service, _ []MarketConfig, loc *time.Location, pinger healthcheck.Pinger, log *slog.Logger) *MonthlyCron {
	if log == nil {
		log = slog.Default()
	}
	c := cron.New(cron.WithLocation(loc))
	mc := &MonthlyCron{svc: svc, pinger: pinger, log: log, loc: loc, c: c}
	// "0 3 1 * *" = minute 0, hour 3, day-of-month 1, every month, every year.
	_, _ = c.AddFunc("0 3 1 * *", mc.runAll)
	return mc
}

// Start begins the cron scheduler. Call Stop to gracefully shut it down.
func (mc *MonthlyCron) Start() { mc.c.Start() }

// Stop halts the scheduler and waits for any in-progress run to finish.
func (mc *MonthlyCron) Stop() { mc.c.Stop() }

// runAll is the cron callback — calls PayMonthlyInstallments for all due plans.
func (mc *MonthlyCron) runAll() {
	ctx := context.Background()
	now := time.Now().In(mc.loc)

	mc.pinger.Start(ctx)
	mc.log.InfoContext(ctx, "cashback: monthly cron start", "run_date", now.Format("2006-01-02"))

	summary, err := mc.svc.PayMonthlyInstallments(ctx, now)
	if err != nil {
		mc.log.ErrorContext(ctx, "cashback: PayMonthlyInstallments error", "err", err)
		mc.pinger.Fail(ctx, err.Error())
		return
	}

	mc.log.InfoContext(ctx, "cashback: monthly cron done",
		"processed", summary.Processed,
		"skipped", summary.Skipped,
		"failed", summary.Failed,
		"retries", summary.Retries,
	)
	if summary.Failed > 0 {
		mc.pinger.Fail(ctx, fmt.Sprintf("cashback: %d plan(s) failed", summary.Failed))
	} else {
		mc.pinger.Success(ctx)
	}
}
