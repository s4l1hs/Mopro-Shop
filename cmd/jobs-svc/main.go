package main

import (
	"context"
	"errors"
	"log"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"

	"github.com/mopro/platform/internal/eventbus"
	"github.com/mopro/platform/internal/notification"
	pkg_slack "github.com/mopro/platform/pkg/slack"
)

func main() {
	initCtx := context.Background()

	market := mustEnv("MARKET")

	// ── postgres-ecom pool (for notification dedup store) ────────────────────────
	ecomDSN := mustEnv("NOTIFICATION_DATABASE_URL")
	pool, err := pgxpool.New(initCtx, ecomDSN)
	if err != nil {
		slog.Error("jobs-svc: postgres-ecom pool", "err", err)
		os.Exit(1)
	}
	if err := pool.Ping(initCtx); err != nil {
		slog.Error("jobs-svc: postgres-ecom ping", "err", err)
		os.Exit(1)
	}

	// ── Redis client ─────────────────────────────────────────────────────────────
	redisAddr := mustEnv("REDIS_ADDR")
	redisClient := redis.NewClient(&redis.Options{Addr: redisAddr})
	if err := redisClient.Ping(initCtx).Err(); err != nil {
		slog.Error("jobs-svc: redis ping", "err", err)
		os.Exit(1)
	}

	// ── Signal-aware context ─────────────────────────────────────────────────────
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, os.Interrupt)

	// ── Slack client (reconcile-drift alerts) ─────────────────────────────────────
	var slackClient *pkg_slack.Client
	if webhookURL := os.Getenv("SLACK_RECONCILE_WEBHOOK"); webhookURL != "" {
		slackClient = pkg_slack.New(webhookURL)
	} else {
		slackClient = pkg_slack.NewNoop()
	}

	// ── Notification dedup store ──────────────────────────────────────────────────
	dedupStore := notification.NewPgxDedupStore(pool)

	// ── Event bus ────────────────────────────────────────────────────────────────
	bus := eventbus.NewRedisBus(redisClient, slog.Default())

	// ── Start reconcile-drift consumer ───────────────────────────────────────────
	go func() {
		if err := notification.StartReconcileDriftConsumer(ctx, bus, slackClient, dedupStore, slog.Default()); err != nil && !errors.Is(err, context.Canceled) {
			slog.Error("jobs-svc: reconcile-drift consumer exited unexpectedly", "err", err)
		}
	}()

	// ── HTTP server ──────────────────────────────────────────────────────────────
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	srv := &http.Server{
		Addr:         ":8080",
		Handler:      mux,
		ReadTimeout:  5 * time.Second,
		WriteTimeout: 5 * time.Second,
		IdleTimeout:  60 * time.Second,
	}
	go func() {
		<-ctx.Done()
		stop()
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		if err := srv.Shutdown(shutdownCtx); err != nil {
			slog.Error("jobs-svc: http shutdown failed", "err", err)
		}
	}()
	slog.Info("jobs-svc: starting", "market", market, "addr", srv.Addr)
	if err := srv.ListenAndServe(); !errors.Is(err, http.ErrServerClosed) {
		slog.Error("jobs-svc: http server exited unexpectedly", "err", err)
	}
}

func mustEnv(key string) string {
	v := os.Getenv(key)
	if v == "" {
		log.Fatalf("jobs-svc: required env %s is not set", key)
	}
	return v
}
