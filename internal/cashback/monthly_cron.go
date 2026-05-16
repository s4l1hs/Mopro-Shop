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

// MonthlyCron schedules RunMonth for each configured market on the 1st of each month.
type MonthlyCron struct {
	svc     Service
	markets []MarketConfig
	pinger  healthcheck.Pinger
	log     *slog.Logger
	c       *cron.Cron
}

// NewMonthlyCron constructs a MonthlyCron.
// loc must be the Istanbul timezone; pass time.LoadLocation("Europe/Istanbul").
// pinger is called with Start/Success/Fail around each full run; noopPinger if nil URL.
func NewMonthlyCron(svc Service, markets []MarketConfig, loc *time.Location, pinger healthcheck.Pinger, log *slog.Logger) *MonthlyCron {
	if log == nil {
		log = slog.Default()
	}
	c := cron.New(cron.WithLocation(loc), cron.WithSeconds())
	mc := &MonthlyCron{svc: svc, markets: markets, pinger: pinger, log: log, c: c}
	// "0 0 2 1 * *" = second 0, minute 0, hour 2, day-of-month 1, every month.
	// cron.WithSeconds() enables the 6-field format.
	_, _ = c.AddFunc("0 0 2 1 * *", mc.runAll)
	return mc
}

// Start begins the cron scheduler. Call Stop to gracefully shut it down.
func (mc *MonthlyCron) Start() { mc.c.Start() }

// Stop halts the scheduler and waits for any in-progress run to finish.
func (mc *MonthlyCron) Stop() { mc.c.Stop() }

// runAll is the cron callback — runs RunMonth for every configured market.
func (mc *MonthlyCron) runAll() {
	ctx := context.Background()
	now := time.Now().UTC()
	period := timeToPeriod(now)

	mc.pinger.Start(ctx)
	mc.log.InfoContext(ctx, "cashback: monthly cron start", "period", period, "markets", len(mc.markets))

	var totalFailed int
	for _, m := range mc.markets {
		res, err := mc.svc.RunMonth(ctx, period, now, m.Currency)
		if err != nil {
			mc.log.ErrorContext(ctx, "cashback: RunMonth error",
				"market", m.Market, "currency", m.Currency, "period", period, "err", err)
			totalFailed++
			continue
		}
		mc.log.InfoContext(ctx, "cashback: monthly cron market done",
			"market", m.Market, "currency", m.Currency, "period", period,
			"processed", res.Processed, "skipped", res.Skipped,
			"failed", res.Failed, "retries", res.TotalRetries)
		totalFailed += res.Failed
	}

	if totalFailed > 0 {
		mc.pinger.Fail(ctx, fmt.Sprintf("cashback: %d plan(s) failed in period %d", totalFailed, period))
	} else {
		mc.pinger.Success(ctx)
	}
}
