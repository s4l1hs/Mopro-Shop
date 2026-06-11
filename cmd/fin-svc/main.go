package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"
	_ "time/tzdata"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"

	finapi "github.com/mopro/platform/internal/api"
	genfin "github.com/mopro/platform/internal/api/gen/fin"
	"github.com/mopro/platform/internal/cashback"
	"github.com/mopro/platform/internal/commission"
	"github.com/mopro/platform/internal/eventbus"
	identityjwt "github.com/mopro/platform/internal/identity/jwt"
	identitymw "github.com/mopro/platform/internal/identity/middleware"
	"github.com/mopro/platform/internal/orderledger"
	"github.com/mopro/platform/internal/outbox"
	"github.com/mopro/platform/internal/reconcile"
	"github.com/mopro/platform/internal/refund"
	"github.com/mopro/platform/internal/sellerpayout"
	"github.com/mopro/platform/internal/sellerpayout/sipay"
	"github.com/mopro/platform/internal/wallet"
	"github.com/mopro/platform/pkg/healthcheck"
	"github.com/mopro/platform/pkg/logx"
	"github.com/mopro/platform/pkg/metrics"
	"github.com/mopro/platform/pkg/otelx"
	"github.com/mopro/platform/pkg/pagerduty"
	"github.com/mopro/platform/pkg/slack"
	"github.com/mopro/platform/pkg/timex"
)

func main() {
	runOnce := flag.Bool("run-once", false, "Run a single cron job and exit (use with --cron)")
	cronName := flag.String("cron", "", "Cron name for --run-once: cashback-monthly | seller-payout-daily | ledger-reconcile-weekly")
	flag.Parse()

	// Startup connections use plain Background; signal context begins after init.
	initCtx := context.Background()

	market := mustEnv("MARKET")
	defaultCurrency := mustEnv("DEFAULT_CURRENCY")
	cashbackCurrency := mustEnv("DEFAULT_CASHBACK_CURRENCY")
	logx.Setup("fin-svc", market)

	otelEndpoint := os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
	otelShutdown, err := otelx.Init(initCtx, otelx.Config{
		ServiceName:  "fin-svc",
		Market:       market,
		OTLPEndpoint: otelEndpoint,
	})
	if err != nil {
		slog.Warn("fin-svc: OTel init failed, traces disabled", "err", err)
		otelShutdown = func(_ context.Context) error { return nil }
	}
	defer func() { _ = otelShutdown(context.Background()) }()

	// ── Prometheus metrics (registry + all metrics pre-instantiated at startup) ─
	metricsReg := metrics.New("fin-svc")
	dbM := metrics.NewDBMetrics(metricsReg)
	redisM := metrics.NewRedisMetrics(metricsReg)
	ebM := metrics.NewEventBusMetrics(metricsReg)
	outboxM := metrics.NewOutboxMetrics(metricsReg)
	bizM := metrics.NewBusinessMetrics(metricsReg)
	jobM := metrics.NewJobStatusMetrics(metricsReg)
	_ = metrics.NewHTTPMetrics(metricsReg) // registered; fin-svc routes are minimal

	// ── postgres-ledger pool ─────────────────────────────────────────────────
	ledgerDSN := mustEnv("LEDGER_DATABASE_URL")
	ledgerCfg, err := pgxpool.ParseConfig(ledgerDSN)
	if err != nil {
		slog.Error("fin-svc: parse ledger DSN", "err", err)
		os.Exit(1)
	}
	ledgerCfg.ConnConfig.DefaultQueryExecMode = pgx.QueryExecModeSimpleProtocol
	dbM.WirePool(ledgerCfg, "fin-svc")
	pool, err := pgxpool.NewWithConfig(initCtx, ledgerCfg)
	if err != nil {
		slog.Error("fin-svc: postgres-ledger pool", "err", err)
		os.Exit(1)
	}
	if err := pool.Ping(initCtx); err != nil {
		slog.Error("fin-svc: postgres-ledger ping", "err", err)
		os.Exit(1)
	}
	metrics.RegisterPgxPoolCollector(metricsReg, pool, "fin-svc", "ledger")

	// ── Redis client ─────────────────────────────────────────────────────────
	redisAddr := mustEnv("REDIS_ADDR")
	redisClient := redis.NewClient(&redis.Options{
		Addr:     redisAddr,
		Password: os.Getenv("REDIS_PASSWORD"),
	})
	if err := redisClient.Ping(initCtx).Err(); err != nil {
		slog.Error("fin-svc: redis ping", "err", err)
		os.Exit(1)
	}
	redisClient.AddHook(redisM.Hook("fin-svc"))

	// ── Signal-aware context for goroutines + HTTP shutdown ─────────────────
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, os.Interrupt)

	go metrics.StartServer(ctx, metricsReg, "0.0.0.0:9101", slog.Default())
	metricsReg.AssertCardinalityUnder(10_000)

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
	cashbackSvc := cashback.NewService(cashbackRepo, cashbackOutbox, calLoader, cashbackCurrency, walletSvc, slog.Default(), bizM)

	// RT-01 refund settlement: mints approved-return refunds as coin (D
	// equity:refund_distribution ↔ C user wallet) on ecom.return.refunded.v1.
	refundSvc := refund.NewService(walletSvc, cashbackCurrency, slog.Default())

	// Slack client for DLQ alerts (EXCEPTION: fin-svc → Slack direct; see CLAUDE.md §5).
	// SLACK_DLQ_WEBHOOK_URL is optional; no-op when absent.
	slackDLQClient := slack.New(os.Getenv("SLACK_DLQ_WEBHOOK_URL"))

	attemptRepo := eventbus.NewPgxAttemptRepository(pool)
	dlqRepo := eventbus.NewPgxDLQRepository(pool)
	bus := eventbus.NewRedisBus(
		redisClient,
		slog.Default(),
		eventbus.WithAttemptRepo(attemptRepo),
		eventbus.WithDLQRepo(dlqRepo),
		eventbus.WithSlackPoster(eventbus.NewSlackPosterAdapter(slackDLQClient)),
		eventbus.WithMetrics(ebM, "fin-svc"),
	)

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
	pub, err := outbox.NewPublisher(pool, cashbackOutbox, bus, slog.Default(),
		outbox.WithServiceName("fin"),
		outbox.WithLagTable("wallet_schema.outbox"),
		outbox.WithOutboxMetrics(outboxM),
	)
	if err != nil {
		slog.Error("fin-svc: outbox publisher init", "err", err)
		os.Exit(1)
	}
	go func() {
		if err := pub.Run(ctx); err != nil && !errors.Is(err, context.Canceled) {
			slog.Error("fin-svc: outbox publisher exited unexpectedly", "err", err)
		}
	}()

	// ── Order capture ledger consumer ─────────────────────────────��──────────
	orderledgerRepo := orderledger.NewRepository(pool)
	// commission.CaptureRecorder is the seam through which orderledger
	// persists capture-posting audit rows; the commission package owns
	// the underlying schema access (see internal/commission/).
	captureRecorder := commission.NewCaptureRecorder(pool)
	orderledgerSvc := orderledger.NewService(orderledgerRepo, captureRecorder, walletSvc, slog.Default(), bizM)
	go func() {
		if err := orderledger.StartConsumer(ctx, bus, orderledgerSvc); err != nil && !errors.Is(err, context.Canceled) {
			slog.Error("fin-svc: orderledger consumer exited unexpectedly", "err", err)
		}
	}()

	// ── Start cashback consumer goroutine ────────────────────────────────────
	go func() {
		if err := cashback.StartConsumer(ctx, bus, cashbackSvc); err != nil && !errors.Is(err, context.Canceled) {
			slog.Error("fin-svc: cashback consumer exited unexpectedly", "err", err)
		}
	}()

	// ── Start refund consumer goroutine (RT-01) ──────────────────────────────
	go func() {
		if err := refund.StartConsumer(ctx, bus, refundSvc); err != nil && !errors.Is(err, context.Canceled) {
			slog.Error("fin-svc: refund consumer exited unexpectedly", "err", err)
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
	reconcileCfg, err := pgxpool.ParseConfig(reconcileDSN)
	if err != nil {
		slog.Error("fin-svc: parse reconcile DSN", "err", err)
		os.Exit(1)
	}
	dbM.WirePool(reconcileCfg, "fin-svc")
	reconcilePool, err := pgxpool.NewWithConfig(initCtx, reconcileCfg)
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

	// ── Run-once mode: execute one cron job and exit (for manual ops / testing) ──
	if *runOnce {
		_ = otelShutdown(context.Background())
		os.Exit(runOnceCron(initCtx, *cronName, cashbackSvc, payoutSvc, reconcileSvc, market, defaultCurrency, istanbulLoc))
	}

	cronMarkets := buildCronMarkets(market, cashbackCurrency)
	hcPinger := newJobPinger(
		healthcheck.NewFromUUID(os.Getenv("HEALTHCHECK_CASHBACK_CRON_UUID"), 5*time.Second, slog.Default()),
		jobM, "fin-svc", "cashback-monthly",
	)
	monthlyCron := cashback.NewMonthlyCron(cashbackSvc, cronMarkets, istanbulLoc, hcPinger, slog.Default())
	monthlyCron.Start()
	defer monthlyCron.Stop()

	// ── Seller payout daily cron (02:30 UTC) ───────────────────────────────────
	payoutPinger := newJobPinger(
		healthcheck.NewFromUUID(os.Getenv("HEALTHCHECK_SELLER_PAYOUT_CRON_UUID"), 5*time.Second, slog.Default()),
		jobM, "fin-svc", "seller-payout-daily",
	)
	dailyCron := sellerpayout.NewDailyCron(payoutSvc, market, defaultCurrency, time.UTC, payoutPinger, slog.Default())
	dailyCron.Start()
	defer dailyCron.Stop()

	// ── Reconcile cron (weekly Sunday 03:05 Europe/Istanbul) ────────────────────
	reconcilePinger := newJobPinger(
		healthcheck.NewFromUUID(os.Getenv("HEALTHCHECK_LEDGER_RECONCILE_UUID"), 5*time.Second, slog.Default()),
		jobM, "fin-svc", "ledger-reconcile",
	)
	weeklyCron := reconcile.NewWeeklyCron(reconcileSvc, istanbulLoc, reconcilePinger, slog.Default())
	weeklyCron.Start(ctx)
	defer weeklyCron.Stop()

	// ── JWT signer (shared key with core-svc; used to verify access tokens) ──
	jwtKey := []byte(mustEnv("JWT_SIGNING_KEY"))
	jwtSigner, err := identityjwt.NewHS256Signer(jwtKey)
	if err != nil {
		slog.Error("fin-svc: jwt signer init", "err", err)
		os.Exit(1)
	}

	// ── FinServer — wallet + cashback HTTP endpoints ──────────────────────────
	finServer := &finapi.FinServer{
		WalletSvc:       walletSvc,
		CashbackRepo:    cashbackRepo,
		DefaultCurrency: cashbackCurrency,
	}

	// ── HTTP server ──────────────────────────────────────────────────────────
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})

	// Register /* routes behind JWT auth middleware.
	finMux := http.NewServeMux()
	genfin.HandlerFromMuxWithBaseURL(genfin.NewStrictHandler(finServer, nil), finMux, "")
	mux.Handle("/", identitymw.RequireAuth(jwtSigner)(finMux))
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

// ── jobPinger wraps healthcheck.Pinger and records mopro_job_last_run_status ─

type jobPinger struct {
	inner healthcheck.Pinger
	jobM  *metrics.JobStatusMetrics
	svc   string
	job   string
}

func newJobPinger(inner healthcheck.Pinger, jobM *metrics.JobStatusMetrics, svc, job string) healthcheck.Pinger {
	return &jobPinger{inner: inner, jobM: jobM, svc: svc, job: job}
}

func (p *jobPinger) Start(ctx context.Context) { p.inner.Start(ctx) }
func (p *jobPinger) Success(ctx context.Context) {
	p.inner.Success(ctx)
	p.jobM.SetSuccess(p.svc, p.job)
}
func (p *jobPinger) Fail(ctx context.Context, msg string) {
	p.inner.Fail(ctx, msg)
	p.jobM.SetFailure(p.svc, p.job)
}

// runOnceCron executes a single cron job and returns an exit code (0=ok, 1=fail).
// Used with --run-once --cron=<name> for manual ops and restore drills.
func runOnceCron(
	ctx context.Context,
	name string,
	cashbackSvc cashback.Service,
	payoutSvc sellerpayout.Service,
	reconcileSvc reconcile.Service,
	market, currency string,
	loc *time.Location,
) int {
	switch name {
	case "cashback-monthly":
		now := time.Now().In(loc)
		slog.Info("run-once: cashback-monthly", "run_date", now.Format("2006-01-02"))
		summary, err := cashbackSvc.PayMonthlyInstallments(ctx, now)
		if err != nil {
			slog.Error("run-once: cashback-monthly failed", "err", err)
			return 1
		}
		slog.Info("run-once: cashback-monthly done",
			"processed", summary.Processed,
			"skipped", summary.Skipped,
			"failed", summary.Failed,
			"retries", summary.Retries,
		)
		if summary.Failed > 0 {
			slog.Error("run-once: cashback-monthly had failures", "failed", summary.Failed)
			return 1
		}
		return 0

	case "seller-payout-daily":
		today := time.Now().In(time.UTC).Truncate(24 * time.Hour)
		slog.Info("run-once: seller-payout-daily", "payout_date", today.Format("2006-01-02"))
		res, err := payoutSvc.RunDailyPayouts(ctx, today, market, currency)
		if err != nil {
			slog.Error("run-once: seller-payout-daily failed", "err", err)
			return 1
		}
		slog.Info("run-once: seller-payout-daily done",
			"batched", res.Batched,
			"paid", res.Paid,
			"failed", res.Failed,
			"skipped", res.Skipped,
		)
		if res.Failed > 0 || res.Ambiguous > 0 {
			slog.Error("run-once: seller-payout-daily had failures", "failed", res.Failed, "ambiguous", res.Ambiguous)
			return 1
		}
		return 0

	case "ledger-reconcile-weekly":
		asOf := time.Now().In(loc)
		slog.Info("run-once: ledger-reconcile-weekly", "as_of", asOf.Format("2006-01-02"))
		result, err := reconcileSvc.RunWeekly(ctx, asOf)
		if err != nil {
			slog.Error("run-once: ledger-reconcile-weekly failed", "err", err)
			return 1
		}
		slog.Info("run-once: ledger-reconcile-weekly done", "result", fmt.Sprintf("%+v", result))
		return 0

	default:
		slog.Error("run-once: unknown --cron value",
			"name", name,
			"choices", "cashback-monthly, seller-payout-daily, ledger-reconcile-weekly",
		)
		return 1
	}
}

func mustEnv(key string) string {
	v := os.Getenv(key)
	if v == "" {
		slog.Error("fin-svc: required env not set", "key", key)
		os.Exit(1)
	}
	return v
}
