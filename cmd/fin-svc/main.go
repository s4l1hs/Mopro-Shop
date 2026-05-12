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
	"github.com/mopro/platform/internal/sellerpayout"
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

	// ── Cashback engine ──────────────────────────────────────────────────────
	cashbackOutbox := outbox.NewRepository("wallet_schema.outbox")
	cashbackRepo := cashback.NewRepository(pool)
	calLoader := timex.NewStaticCalendarLoader(calendarMap)
	cashbackSvc := cashback.NewService(cashbackRepo, cashbackOutbox, calLoader, cashbackCurrency)

	bus := eventbus.NewRedisBus(redisClient, slog.Default())

	// ── Seller payout engine ─────────────────────────────────────────────────
	payoutRepo := sellerpayout.NewRepository(pool)
	payoutSvc := sellerpayout.NewService(payoutRepo, calLoader, defaultCurrency)

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

	// ── Start sellerpayout consumer goroutine ────────────────────────────────
	go func() {
		if err := sellerpayout.StartConsumer(ctx, bus, payoutSvc); err != nil && !errors.Is(err, context.Canceled) {
			slog.Error("fin-svc: sellerpayout consumer exited unexpectedly", "err", err)
		}
	}()

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
		log.Fatal(err)
	}
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
