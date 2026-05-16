package main

import (
	"context"
	"errors"
	"log"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"

	"github.com/mopro/platform/internal/cashback"
	"github.com/mopro/platform/internal/eventbus"
	"github.com/mopro/platform/internal/outbox"
	"github.com/mopro/platform/internal/reconcile"
	"github.com/mopro/platform/internal/sellerpayout"
	"github.com/mopro/platform/internal/sellerpayout/sipay"
	"github.com/mopro/platform/internal/wallet"
	"github.com/mopro/platform/pkg/healthcheck"
	"github.com/mopro/platform/pkg/pagerduty"
	"github.com/mopro/platform/pkg/timex"
)

func main() {
	// Startup connections use plain Background; signal context begins after init.
	initCtx := context.Background()

	market := mustEnv("MARKET")
	defaultCurrency := mustEnv("DEFAULT_CURRENCY")
	cashbackCurrency := mustEnv("DEFAULT_CASHBACK_CURRENCY")

	// ── postgres-ledger pool ─────────────────────────────────────────────────
	ledgerDSN := mustEnv("LEDGER_DATABASE_URL")
	pool, err := pgxpool.New(initCtx, ledgerDSN)
	if err != nil {
		slog.Error("fin-svc: postgres-ledger pool", "err", err)
		os.Exit(1)
	}
	if err := pool.Ping(initCtx); err != nil {
		slog.Error("fin-svc: postgres-ledger ping", "err", err)
		os.Exit(1)
	}

	// ── Redis client ─────────────────────────────────────────────────────────
	redisAddr := mustEnv("REDIS_ADDR")
	redisClient := redis.NewClient(&redis.Options{Addr: redisAddr})
	if err := redisClient.Ping(initCtx).Err(); err != nil {
		slog.Error("fin-svc: redis ping", "err", err)
		os.Exit(1)
	}

	// ── Signal-aware context for goroutines + HTTP shutdown ─────────────────
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, os.Interrupt)

	// ── Business calendar (static — fin-svc cannot reach postgres-ecom) ──────
	// Holidays loaded from env BUSINESS_CALENDAR_<MARKET>=YYYY-MM-DD,YYYY-MM-DD,...
	// Example: BUSINESS_CALENDAR_TR=2026-01-01,2026-04-23,2026-05-01,...
	calendarMap := buildCalendarMap(market)

	// ── Wallet service (shared by cashback cron and future uses in fin-svc) ──
	walletRepo := wallet.NewRepository(pool)
	walletOutbox := outbox.NewRepository("wallet_schema.outbox")
	walletSvc := wallet.NewService(walletRepo, walletOutbox, slog.Default())

	// Start wallet system_state background refresher.
	walletSvc.StartRefresher(ctx)

	// ── Cashback engine ──────────────────────────────────────────────────────
	cashbackOutbox := outbox.NewRepository("wallet_schema.outbox")
	cashbackRepo := cashback.NewRepository(pool)
	calLoader := timex.NewStaticCalendarLoader(calendarMap)
	cashbackSvc := cashback.NewService(cashbackRepo, cashbackOutbox, calLoader, cashbackCurrency, walletSvc, slog.Default())

	bus := eventbus.NewRedisBus(redisClient, slog.Default())

	// ── Seller payout engine ─────────────────────────────────────────────────
	payoutRepo := sellerpayout.NewRepository(pool)
	pspMode := sipay.Mode(os.Getenv("SELLERPAYOUT_PSP_MODE")) // default "" → shadow
	sipayClient := sipay.New(
		pspMode,
		os.Getenv("SIPAY_BASE_URL"),
		os.Getenv("SIPAY_APP_KEY"),
		os.Getenv("SIPAY_APP_SECRET"),
		os.Getenv("SIPAY_APP_ID"),
		slog.Default(),
	)
	payoutSvc := sellerpayout.NewService(payoutRepo, walletSvc, sipayClient, calLoader, defaultCurrency, slog.Default())

	// ── Outbox publisher — drains wallet_schema.outbox → Redis Streams ───────
	pub, err := outbox.NewPublisher(pool, cashbackOutbox, bus, slog.Default())
	if err != nil {
		slog.Error("fin-svc: outbox publisher init", "err", err)
		os.Exit(1)
	}
	go func() {
		if err := pub.Run(ctx); err != nil && !errors.Is(err, context.Canceled) {
			slog.Error("fin-svc: outbox publisher exited unexpectedly", "err", err)
		}
	}()

	// ── Start cashback consumer goroutine ────────────────────────────────────
	go func() {
		if err := cashback.StartConsumer(ctx, bus, cashbackSvc); err != nil && !errors.Is(err, context.Canceled) {
			slog.Error("fin-svc: cashback consumer exited unexpectedly", "err", err)
		}
	}()

	// ── Start sellerpayout consumer goroutines ───────────────────────────────
	go func() {
		if err := sellerpayout.StartConsumer(ctx, bus, payoutSvc); err != nil && !errors.Is(err, context.Canceled) {
			slog.Error("fin-svc: sellerpayout order consumer exited unexpectedly", "err", err)
		}
	}()
	go func() {
		if err := sellerpayout.StartPspOnboardedConsumer(ctx, bus, payoutSvc); err != nil && !errors.Is(err, context.Canceled) {
			slog.Error("fin-svc: sellerpayout psp_onboarded consumer exited unexpectedly", "err", err)
		}
	}()
	go func() {
		if err := sellerpayout.StartFraudHoldConsumer(ctx, bus, payoutSvc); err != nil && !errors.Is(err, context.Canceled) {
			slog.Error("fin-svc: sellerpayout fraud_hold consumer exited unexpectedly", "err", err)
		}
	}()

	// ── Cashback monthly cron ─────────────────────────────────────────────────
	istanbulLoc, err := time.LoadLocation("Europe/Istanbul")
	if err != nil {
		slog.Error("fin-svc: load Europe/Istanbul timezone", "err", err)
		os.Exit(1)
	}

	// ── Reconcile pool init (before any defers, so os.Exit is safe) ──────────
	reconcileDSN := os.Getenv("RECONCILE_DATABASE_URL")
	if reconcileDSN == "" {
		reconcileDSN = ledgerDSN // fallback to wallet_user pool in dev (limited grants)
	}
	reconcilePool, err := pgxpool.New(initCtx, reconcileDSN)
	if err != nil {
		slog.Error("fin-svc: reconcile pool", "err", err)
		os.Exit(1)
	}
	if err := reconcilePool.Ping(initCtx); err != nil {
		slog.Error("fin-svc: reconcile pool ping", "err", err)
		os.Exit(1)
	}
	reconcileRepo := reconcile.NewRepository(reconcilePool)
	var pd *pagerduty.Client
	if key := os.Getenv("PAGERDUTY_ROUTING_KEY"); key != "" {
		pd = pagerduty.New(key, mustEnv("PAGERDUTY_API"))
	} else {
		pd = pagerduty.NewNoop()
	}
	dryRun := os.Getenv("LEDGER_RECONCILE_DRY_RUN") == "true"
	reconcileSvc := reconcile.NewService(reconcileRepo, pd, walletSvc, dryRun, slog.Default())

	cronMarkets := buildCronMarkets(market, cashbackCurrency)
	hcPinger := healthcheck.NewFromUUID(os.Getenv("HEALTHCHECK_CASHBACK_CRON_UUID"), 5*time.Second, slog.Default())
	monthlyCron := cashback.NewMonthlyCron(cashbackSvc, cronMarkets, istanbulLoc, hcPinger, slog.Default())
	monthlyCron.Start()
	defer monthlyCron.Stop()

	// ── Seller payout daily cron (02:30 UTC) ───────────────────────────────────
	payoutPinger := healthcheck.NewFromUUID(os.Getenv("HEALTHCHECK_SELLER_PAYOUT_CRON_UUID"), 5*time.Second, slog.Default())
	dailyCron := sellerpayout.NewDailyCron(payoutSvc, market, defaultCurrency, time.UTC, payoutPinger, slog.Default())
	dailyCron.Start()
	defer dailyCron.Stop()

	// ── Reconcile cron (weekly Sunday 03:05 Europe/Istanbul) ────────────────────
	reconcilePinger := healthcheck.NewFromUUID(os.Getenv("HEALTHCHECK_LEDGER_RECONCILE_UUID"), 5*time.Second, slog.Default())
	weeklyCron := reconcile.NewWeeklyCron(reconcileSvc, istanbulLoc, reconcilePinger, slog.Default())
	weeklyCron.Start(ctx)
	defer weeklyCron.Stop()

	// ── HTTP server ──────────────────────────────────────────────────────────
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	srv := &http.Server{
		Addr:         ":8081",
		Handler:      mux,
		ReadTimeout:  5 * time.Second,
		WriteTimeout: 5 * time.Second,
		IdleTimeout:  60 * time.Second,
	}
	go func() {
		<-ctx.Done()
		stop() // release signal resources; ctx is already cancelled
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		if err := srv.Shutdown(shutdownCtx); err != nil {
			slog.Error("fin-svc: http shutdown failed", "err", err)
		}
	}()
	slog.Info("fin-svc: starting", "market", market, "addr", srv.Addr)
	if err := srv.ListenAndServe(); !errors.Is(err, http.ErrServerClosed) {
		slog.Error("fin-svc: http server exited unexpectedly", "err", err)
		// defers (cron stops) run as main returns
	}
}

// buildCronMarkets builds the market config list for the cashback monthly cron.
// CASHBACK_CRON_MARKETS env var overrides the single primary market (e.g. "TR:TRY_COIN,DE:EUR_COIN").
// Defaults to primaryMarket:cashbackCurrency when env is not set.
func buildCronMarkets(primaryMarket, cashbackCurrency string) []cashback.MarketConfig {
	raw := os.Getenv("CASHBACK_CRON_MARKETS")
	if raw != "" {
		configs, err := cashback.ParseMarketConfigs(raw)
		if err != nil {
			slog.Warn("fin-svc: invalid CASHBACK_CRON_MARKETS, falling back to primary market",
				"raw", raw, "err", err)
		} else {
			return configs
		}
	}
	return []cashback.MarketConfig{{Market: primaryMarket, Currency: cashbackCurrency}}
}

// buildCalendarMap reads BUSINESS_CALENDAR_<MARKET> env vars and builds a map
// for timex.NewStaticCalendarLoader. Empty CSV → empty holiday set (weekends still skipped).
func buildCalendarMap(primaryMarket string) map[string]timex.Calendar {
	result := make(map[string]timex.Calendar)
	for _, market := range append([]string{primaryMarket}, extraMarkets()...) {
		envKey := "BUSINESS_CALENDAR_" + strings.ToUpper(market)
		csv := os.Getenv(envKey)
		cal, err := timex.ParseCalendarDates(market, csv)
		if err != nil {
			slog.Warn("fin-svc: invalid calendar dates", "market", market, "err", err)
			cal = timex.Calendar{Market: market, Holidays: map[string]struct{}{}}
		}
		result[market] = cal
	}
	return result
}

// extraMarkets returns additional market codes from EXTRA_MARKETS env var
// (comma-separated, e.g. "DE,US"). Empty by default.
func extraMarkets() []string {
	raw := os.Getenv("EXTRA_MARKETS")
	if raw == "" {
		return nil
	}
	var markets []string
	for _, m := range strings.Split(raw, ",") {
		if t := strings.TrimSpace(m); t != "" {
			markets = append(markets, t)
		}
	}
	return markets
}

func mustEnv(key string) string {
	v := os.Getenv(key)
	if v == "" {
		log.Fatalf("fin-svc: required env %s is not set", key)
	}
	return v
}
