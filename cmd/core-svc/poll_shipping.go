package main

import (
	"context"
	"log/slog"
	"time"

	"github.com/mopro/platform/internal/shipping"
	"github.com/mopro/platform/internal/shipping/aras"
	"github.com/mopro/platform/internal/shipping/ptt"
	"github.com/mopro/platform/internal/shipping/yurtici"
)

const pollBatchLimit = 50

// pollConfig holds the per-carrier poll intervals parsed from env at startup.
type pollConfig struct {
	arasInterval    time.Duration
	yurticiInterval time.Duration
	pttInterval     time.Duration
}

// runShippingPollWorker starts per-carrier poll goroutines.
// It blocks until ctx is cancelled, then returns so the caller can wait on wg.
// Each carrier's adapter is only polled if the adapter is configured (BaseURL present).
func runShippingPollWorker(ctx context.Context, svc shipping.Service, shippingAdapters map[string]shipping.Adapter, pcfg pollConfig, carrierCfg struct {
	Aras    shipping.ArasConfig
	Yurtici shipping.YurticiConfig
	PTT     shipping.PTTConfig
}) {
	if _, ok := shippingAdapters["aras"]; !ok {
		if carrierCfg.Aras.BaseURL != "" {
			shippingAdapters["aras"] = aras.New(carrierCfg.Aras)
		}
	}
	if _, ok := shippingAdapters["yurtici"]; !ok {
		if carrierCfg.Yurtici.WSDLURL != "" {
			shippingAdapters["yurtici"] = yurtici.New(carrierCfg.Yurtici)
		}
	}
	if _, ok := shippingAdapters["ptt"]; !ok {
		if carrierCfg.PTT.WSDLURL != "" {
			shippingAdapters["ptt"] = ptt.New(carrierCfg.PTT)
		}
	}

	type carrierPoll struct {
		name     string
		interval time.Duration
	}

	carriers := []carrierPoll{
		{"aras", pcfg.arasInterval},
		{"yurtici", pcfg.yurticiInterval},
		{"ptt", pcfg.pttInterval},
		// Sürat, MNG, HepsiJet are webhook-primary; poll is a fallback.
		{"surat", pcfg.arasInterval},
		{"mng", pcfg.arasInterval},
		{"hepsijet", pcfg.arasInterval},
	}

	for _, c := range carriers {
		if _, ok := shippingAdapters[c.name]; !ok {
			continue // adapter not configured; skip
		}
		go func(carrier string, interval time.Duration) {
			ticker := time.NewTicker(interval)
			defer ticker.Stop()
			slog.Info("shipping poll worker started", "carrier", carrier, "interval", interval)
			for {
				select {
				case <-ctx.Done():
					slog.Info("shipping poll worker stopped", "carrier", carrier)
					return
				case <-ticker.C:
					if err := svc.PollCarrier(ctx, carrier, pollBatchLimit); err != nil {
						slog.Error("shipping poll: PollCarrier", "carrier", carrier, "err", err)
					}
				}
			}
		}(c.name, c.interval)
	}
}
