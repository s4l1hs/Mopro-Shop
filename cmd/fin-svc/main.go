package main

import (
	"context"
	"log"
	"log/slog"
	"net/http"
	"os"
	"strings"
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
	ctx := context.Background()

	market := mustEnv("MARKET")
	defaultCurrency := mustEnv("DEFAULT_CURRENCY")
	cashbackCurrency := mustEnv("DEFAULT_CASHBACK_CURRENCY")

	// ── postgres-ledger pool ─────────────────────────────────────────────────
	// pool.Close() is only called on graceful shutdown; log.Fatal exits directly
	// so cleanup runs only when the server exits cleanly (Phase 2+ adds SIGTERM handling).
	ledgerDSN := mustEnv("LEDGER_DATABASE_URL")
	pool, err := pgxpool.New(ctx, ledgerDSN)
	if err != nil {
		slog.Error("fin-svc: postgres-ledger pool", "err", err)
		os.Exit(1)
	}
	if err := pool.Ping(ctx); err != nil {
		slog.Error("fin-svc: postgres-ledger ping", "err", err)
		os.Exit(1)
	}

	// ── Redis client ─────────────────────────────────────────────────────────
	redisAddr := mustEnv("REDIS_ADDR")
	redisClient := redis.NewClient(&redis.Options{Addr: redisAddr})
	if err := redisClient.Ping(ctx).Err(); err != nil {
		slog.Error("fin-svc: redis ping", "err", err)
		os.Exit(1)
	}

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

	// ── Start cashback consumer goroutine ────────────────────────────────────
	go func() {
		if err := cashback.StartConsumer(ctx, bus, cashbackSvc); err != nil {
			slog.Error("fin-svc: cashback consumer exited", "err", err)
		}
	}()

	// ── Start sellerpayout consumer goroutine ────────────────────────────────
	go func() {
		if err := sellerpayout.StartConsumer(ctx, bus, payoutSvc); err != nil {
			slog.Error("fin-svc: sellerpayout consumer exited", "err", err)
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
	slog.Info("fin-svc: starting", "market", market, "addr", srv.Addr)
	log.Fatal(srv.ListenAndServe())
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
