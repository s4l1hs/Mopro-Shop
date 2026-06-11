package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
	_ "time/tzdata" // embed IANA tz DB: jobs-svc LoadLocation("Europe/Istanbul") on distroless

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"

	"github.com/mopro/platform/internal/analytics"
	"github.com/mopro/platform/internal/eventbus"
	"github.com/mopro/platform/internal/notification"
	"github.com/mopro/platform/pkg/logx"
	"github.com/mopro/platform/pkg/metrics"
	"github.com/mopro/platform/pkg/otelx"
	pkg_slack "github.com/mopro/platform/pkg/slack"
)

func main() {
	initCtx := context.Background()

	market := mustEnv("MARKET")
	logx.Setup("jobs-svc", market)

	otelEndpoint := os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
	otelShutdown, err := otelx.Init(initCtx, otelx.Config{
		ServiceName:  "jobs-svc",
		Market:       market,
		OTLPEndpoint: otelEndpoint,
	})
	if err != nil {
		slog.Warn("jobs-svc: OTel init failed, traces disabled", "err", err)
		otelShutdown = func(_ context.Context) error { return nil }
	}
	defer func() { _ = otelShutdown(context.Background()) }()

	// ── Prometheus metrics ───────────────────────────────────────────────────────
	metricsReg := metrics.New("jobs-svc")
	dbM := metrics.NewDBMetrics(metricsReg)
	redisM := metrics.NewRedisMetrics(metricsReg)
	ebM := metrics.NewEventBusMetrics(metricsReg)

	// ── postgres-ecom pool (for notification dedup store) ────────────────────────
	ecomDSN := mustEnv("NOTIFICATION_DATABASE_URL")
	ecomCfg, err := pgxpool.ParseConfig(ecomDSN)
	if err != nil {
		slog.Error("jobs-svc: parse ecom DSN", "err", err)
		os.Exit(1)
	}
	ecomCfg.ConnConfig.DefaultQueryExecMode = pgx.QueryExecModeSimpleProtocol
	dbM.WirePool(ecomCfg, "jobs-svc")
	pool, err := pgxpool.NewWithConfig(initCtx, ecomCfg)
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
	redisClient := redis.NewClient(&redis.Options{
		Addr:     redisAddr,
		Password: os.Getenv("REDIS_PASSWORD"),
	})
	if err := redisClient.Ping(initCtx).Err(); err != nil {
		slog.Error("jobs-svc: redis ping", "err", err)
		os.Exit(1)
	}
	redisClient.AddHook(redisM.Hook("jobs-svc"))

	// ── Signal-aware context ─────────────────────────────────────────────────────
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, os.Interrupt)

	go metrics.StartServer(ctx, metricsReg, "0.0.0.0:9102", slog.Default())
	metricsReg.AssertCardinalityUnder(10_000)

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
	bus := eventbus.NewRedisBus(redisClient, slog.Default(), eventbus.WithMetrics(ebM, "jobs-svc"))

	// ── Start reconcile-drift consumer ───────────────────────────────────────────
	go func() {
		if err := notification.StartReconcileDriftConsumer(ctx, bus, slackClient, dedupStore, slog.Default()); err != nil && !errors.Is(err, context.Canceled) {
			slog.Error("jobs-svc: reconcile-drift consumer exited unexpectedly", "err", err)
		}
	}()

	// ── Analytics maintenance crons (Tranche 4a: retention prune + rebuild) ───────
	istanbulLoc, err := time.LoadLocation("Europe/Istanbul")
	if err != nil {
		slog.Error("jobs-svc: load Europe/Istanbul timezone", "err", err)
		os.Exit(1)
	}
	analyticsSvc := analytics.NewService(analytics.NewRepository(pool))
	analyticsCrons := analytics.NewCrons(analyticsSvc, istanbulLoc, analytics.RetentionDays, slog.Default())
	analyticsCrons.Start(ctx)
	defer analyticsCrons.Stop()

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
		slog.Error("jobs-svc: required env not set", "key", key)
		os.Exit(1)
	}
	return v
}
