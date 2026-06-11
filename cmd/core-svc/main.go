package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"

	"github.com/mopro/platform/internal/analytics"
	"github.com/mopro/platform/internal/attachments"
	"github.com/mopro/platform/internal/cart"
	"github.com/mopro/platform/internal/catalog"
	"github.com/mopro/platform/internal/eventbus"
	"github.com/mopro/platform/internal/help"
	"github.com/mopro/platform/internal/idempotency"
	"github.com/mopro/platform/internal/identity"
	"github.com/mopro/platform/internal/identity/cleanup"
	identityemail "github.com/mopro/platform/internal/identity/email"
	emailmock "github.com/mopro/platform/internal/identity/email/mock"
	identityjwt "github.com/mopro/platform/internal/identity/jwt"
	"github.com/mopro/platform/internal/identity/middleware"
	"github.com/mopro/platform/internal/identity/ratelimit"
	"github.com/mopro/platform/internal/identity/sms"
	"github.com/mopro/platform/internal/identity/sms/mock"
	"github.com/mopro/platform/internal/identity/sms/netgsm"
	"github.com/mopro/platform/internal/inbox"
	"github.com/mopro/platform/internal/order"
	"github.com/mopro/platform/internal/outbox"
	"github.com/mopro/platform/internal/payment"
	"github.com/mopro/platform/internal/payment/sipay"
	"github.com/mopro/platform/internal/seller"
	"github.com/mopro/platform/internal/shipping"
	"github.com/mopro/platform/internal/shipping/hepsijet"
	"github.com/mopro/platform/internal/shipping/mng"
	"github.com/mopro/platform/internal/shipping/surat"
	"github.com/mopro/platform/internal/storage"
	"github.com/mopro/platform/internal/support"
	"github.com/mopro/platform/pkg/logx"
	"github.com/mopro/platform/pkg/metrics"
	"github.com/mopro/platform/pkg/otelx"
	"github.com/mopro/platform/pkg/slack"
)

func main() {
	// Startup connections use plain Background; signal context begins after init.
	initCtx := context.Background()

	market := os.Getenv("MARKET")
	defaultCurrency := os.Getenv("DEFAULT_CURRENCY")
	defaultLocale := os.Getenv("DEFAULT_LOCALE")
	// Web origin for sitemap/robots/canonical URLs (the SPA host, distinct from
	// the API host). Defaults to the launch domain when unset.
	webBaseURL := os.Getenv("WEB_BASE_URL")
	if webBaseURL == "" {
		webBaseURL = "https://mopro.shop"
	}
	logx.Setup("core-svc", market)

	otelEndpoint := os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
	otelShutdown, err := otelx.Init(initCtx, otelx.Config{
		ServiceName:  "core-svc",
		Market:       market,
		OTLPEndpoint: otelEndpoint,
	})
	if err != nil {
		slog.Warn("core-svc: OTel init failed, traces disabled", "err", err)
		otelShutdown = func(_ context.Context) error { return nil }
	}
	defer func() { _ = otelShutdown(context.Background()) }()

	// ── Prometheus metrics (registry + all metrics pre-instantiated at startup) ─
	metricsReg := metrics.New("core-svc")
	httpM := metrics.NewHTTPMetrics(metricsReg)
	dbM := metrics.NewDBMetrics(metricsReg)
	redisM := metrics.NewRedisMetrics(metricsReg)
	metrics.NewEventBusMetrics(metricsReg)
	outboxM := metrics.NewOutboxMetrics(metricsReg)
	bizM := metrics.NewBusinessMetrics(metricsReg)
	sipayM := sipay.NewSipayMetrics(metricsReg)
	// /metrics server starts after signal ctx is created below.

	slog.Info("core-svc: starting", "market", market)

	// ── Database pool for catalog (connects through pgbouncer-ecom) ──────────
	catalogDSN := buildCatalogDSN()
	poolCfg, err := pgxpool.ParseConfig(catalogDSN)
	if err != nil {
		slog.Error("catalog: failed to parse DB DSN", "err", err)
		os.Exit(1)
	}
	// PgBouncer transaction-pool mode requires simple query protocol (no prepared statements).
	poolCfg.ConnConfig.DefaultQueryExecMode = pgx.QueryExecModeSimpleProtocol
	dbM.WirePool(poolCfg, "core-svc")
	pool, err := pgxpool.NewWithConfig(initCtx, poolCfg)
	if err != nil {
		slog.Error("catalog: failed to create DB pool", "err", err)
		os.Exit(1)
	}

	// ── Catalog module wiring ────────────────────────────────────────────────
	catalogRepo := catalog.NewRepository(pool)
	catalogSvc := catalog.NewService(catalogRepo, defaultCurrency, defaultLocale)

	// ── Redis client (cart stock reservation + eventbus) ────────────────────
	rc, err := buildRedisClient(initCtx)
	if err != nil {
		slog.Error("cart: failed to connect to Redis", "err", err)
		os.Exit(1)
	}
	rc.AddHook(redisM.Hook("core-svc"))

	// ── Cart module wiring (loads Lua EVALSHA at startup) ───────────────────
	cartRepo, err := cart.NewRepository(initCtx, rc)
	if err != nil {
		slog.Error("cart: failed to load Lua scripts", "err", err)
		os.Exit(1)
	}
	cartSvc := cart.NewService(cartRepo, catalogSvc)

	// Seed Redis stock counters from Postgres on startup using SET NX.
	// Redis stock keys are the authoritative reservation counter; they are not
	// auto-populated by the seed tool. SET NX ensures restarts don't overwrite
	// a live decremented counter from an in-flight reservation.
	{
		stocks, syncErr := catalogSvc.ListAllVariantStocks(initCtx)
		if syncErr != nil {
			slog.Warn("cart: stock sync skipped", "err", syncErr)
		} else {
			var seeded int
			for _, vs := range stocks {
				if err := cartSvc.SeedStockIfAbsent(initCtx, vs.VariantID, vs.Stock); err != nil {
					slog.Warn("cart: stock sync failed", "variant_id", vs.VariantID, "err", err)
				} else {
					seeded++
				}
			}
			slog.Info("cart: stock sync complete", "variants", seeded)
		}
	}

	// ── Signal-aware context for goroutines + HTTP shutdown ─────────────────
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, os.Interrupt)

	go metrics.StartServer(ctx, metricsReg, "0.0.0.0:9100", slog.Default())
	metricsReg.AssertCardinalityUnder(10_000)
	httpTrace = func(h http.Handler) http.Handler {
		return otelx.TraceLogAndMetrics(httpM, "core-svc", h)
	}

	// ── Order module wiring ──────────────────────────────────────────────────
	cashbackCurrency := mustEnv("DEFAULT_CASHBACK_CURRENCY")
	orderOutbox := outbox.NewRepository("order_schema.outbox")
	orderRepo := order.NewRepository(pool)
	checkoutSessionRepo := order.NewCheckoutSessionRepository(pool)
	returnRepo := order.NewReturnRepository(pool)
	returnSvc := order.NewReturnService(orderRepo, returnRepo)
	inboxSvc := inbox.NewService(inbox.NewRepository(pool))
	helpSvc := help.NewService(help.NewRepository(pool), slog.Default())
	supportSvc := support.NewService(support.NewRepository(pool))
	ugcSvc := catalog.NewUGCService(catalog.NewUGCRepository(pool)) // ReviewWriteService + QAService
	analyticsSvc := analytics.NewService(analytics.NewRepository(pool))
	// Seller storefronts + seller-role binding (Tranche 5a). storefrontReader is
	// the catalog-side read surface used by the storefront + dashboard handlers.
	sellerSvc := seller.NewService(seller.NewRepository(pool))
	storefrontReader := catalog.NewStorefrontReader(pool)

	// Media uploads (photos) — gated by STORAGE_ENABLED until an app bucket is
	// provisioned (ADR-0004). When disabled, the upload route 503s and the
	// consumer surfaces stay dormant.
	var attachmentsSvc attachments.Service
	storageCfg := storage.Config{ // A-003: env read at the binary entry, injected into storage.New
		Enabled:   os.Getenv("STORAGE_ENABLED") == "true",
		Backend:   os.Getenv("STORAGE_BACKEND"),
		FSPath:    os.Getenv("PHOTO_STORAGE_PATH"),
		Endpoint:  os.Getenv("STORAGE_ENDPOINT"),
		Bucket:    os.Getenv("STORAGE_BUCKET"),
		Region:    os.Getenv("STORAGE_REGION"),
		AccessKey: os.Getenv("STORAGE_ACCESS_KEY"),
		SecretKey: os.Getenv("STORAGE_SECRET_KEY"),
	}
	if photoStore, perr := storage.New(initCtx, storageCfg); perr == nil {
		attachmentsSvc = attachments.NewService(attachments.NewRepository(pool), photoStore)
	} else if !errors.Is(perr, storage.ErrDisabled) {
		slog.Error("media: storage init failed", "err", perr)
	}
	uploadLim := newUploadLimiter()

	// Payment module wired before order so orderSvc can receive the PSP reference.
	paymentRepo := payment.NewRepository(pool)
	paymentOutbox := outbox.NewRepository("order_schema.outbox")
	sipaycfg := payment.SipayConfig{
		BaseURL:     mustEnv("SIPAY_BASE_URL"),
		MerchantKey: mustEnv("SIPAY_MERCHANT_KEY"),
		AppID:       mustEnv("SIPAY_APP_ID"),
		AppSecret:   mustEnv("SIPAY_APP_SECRET"),
		MerchantID:  mustEnv("SIPAY_MERCHANT_ID"),
		ReturnURL:   os.Getenv("SIPAY_RETURN_URL"),
		CancelURL:   os.Getenv("SIPAY_CANCEL_URL"),
		Environment: os.Getenv("GO_ENV"), // A-003: prod-safety guard now reads injected config
	}
	paymentSvc, err := payment.NewService(os.Getenv("PSP_PROVIDER"), sipaycfg, paymentRepo)
	if err != nil {
		slog.Error("payment: NewService failed", "err", err)
		os.Exit(1)
	}

	orderSvc := order.NewServiceFull(
		orderRepo, checkoutSessionRepo,
		cartSvc, catalogSvc, orderOutbox,
		market, cashbackCurrency,
		paymentSvc,
		&redisDiskPanicChecker{rc: rc},
		bizM,
	)

	// ── Outbox publisher — drains order_schema.outbox → Redis Streams ───────
	bus := eventbus.NewRedisBus(rc, slog.Default())
	pub, err := outbox.NewPublisher(pool, orderOutbox, bus, slog.Default(),
		outbox.WithServiceName("core"),
		outbox.WithLagTable("order_schema.outbox"),
		outbox.WithOutboxMetrics(outboxM),
	)
	if err != nil {
		slog.Error("core-svc: outbox publisher init", "err", err)
		os.Exit(1)
	}
	go func() {
		if err := pub.Run(ctx); err != nil && !errors.Is(err, context.Canceled) {
			slog.Error("core-svc: outbox publisher exited unexpectedly", "err", err)
		}
	}()

	// ── Sipay adapter + webhook handler ──────────────────────────────────────
	sipayAdapter, err := sipay.NewAdapter(sipaycfg, paymentRepo, slog.Default(), sipay.WithMetrics(sipayM))
	if err != nil {
		slog.Error("sipay: adapter init failed", "err", err)
		os.Exit(1)
	}

	// captureFinalizer: called after every successful Sipay payment capture.
	// Looks up the checkout session (providerRef == session_id) and marks all
	// linked orders as paid, then commits the cart reservation.
	captureFinalizer := sipay.CaptureFinalizer(func(ctx context.Context, providerRef string) error {
		session, err := checkoutSessionRepo.FindCheckoutSessionByID(ctx, providerRef)
		if err != nil {
			// providerRef might be a legacy single-order invoice_id — not fatal.
			slog.Warn("captureFinalizer: checkout session not found (may be legacy)", "provider_ref", providerRef)
			return nil
		}
		for _, oid := range session.OrderIDs {
			if mErr := orderSvc.MarkPaid(ctx, oid); mErr != nil {
				slog.Error("captureFinalizer: MarkPaid failed", "order_id", oid, "err", mErr)
			}
		}
		if session.ReservationID != "" {
			if rErr := cartSvc.CommitReservation(ctx, session.ReservationID); rErr != nil {
				slog.Warn("captureFinalizer: CommitReservation failed (non-fatal)", "err", rErr)
			}
		}
		return nil
	})

	webhookHandler := sipay.NewWebhookHandler(
		sipayAdapter, paymentRepo, paymentOutbox, rc, market, cashbackCurrency, slog.Default(),
	).WithCaptureFinalizer(captureFinalizer)

	// ── Payment reconciler — catches webhooks dropped by Sipay ───────────────
	paymentReconciler := payment.NewReconciler(
		paymentRepo, paymentSvc, paymentOutbox, market, cashbackCurrency, slog.Default(),
	)
	go func() {
		if err := paymentReconciler.Run(ctx); err != nil && !errors.Is(err, context.Canceled) {
			slog.Error("core-svc: payment reconciler exited unexpectedly", "err", err)
		}
	}()

	// ── Shipping module wiring ───────────────────────────────────────────────
	shippingRepo := shipping.NewRepository(pool)
	shippingAdapters := map[string]shipping.Adapter{}

	if cfg := (shipping.SuratConfig{
		BaseURL:       os.Getenv("SURAT_BASE_URL"),
		Username:      os.Getenv("SURAT_USERNAME"),
		Password:      os.Getenv("SURAT_PASSWORD"),
		WebhookSecret: os.Getenv("SURAT_WEBHOOK_SECRET"),
	}); cfg.BaseURL != "" {
		shippingAdapters["surat"] = surat.New(cfg)
	}

	if cfg := (shipping.MNGConfig{
		BaseURL:       os.Getenv("MNG_BASE_URL"),
		APIKey:        os.Getenv("MNG_API_KEY"),
		WebhookSecret: os.Getenv("MNG_WEBHOOK_SECRET"),
	}); cfg.BaseURL != "" {
		shippingAdapters["mng"] = mng.New(cfg)
	}

	if cfg := (shipping.HepsiJetConfig{
		BaseURL:      os.Getenv("HEPSIJET_BASE_URL"),
		ClientID:     os.Getenv("HEPSIJET_CLIENT_ID"),
		ClientSecret: os.Getenv("HEPSIJET_CLIENT_SECRET"),
		WebhookToken: os.Getenv("HEPSIJET_WEBHOOK_TOKEN"),
	}); cfg.BaseURL != "" {
		shippingAdapters["hepsijet"] = hepsijet.New(cfg)
	}

	// Poll-only carrier configs (built from env; adapters constructed inside poll worker).
	arasCarrierCfg := shipping.ArasConfig{
		BaseURL:      os.Getenv("ARAS_BASE_URL"),
		Username:     os.Getenv("ARAS_USERNAME"),
		Password:     os.Getenv("ARAS_PASSWORD"),
		CustomerCode: os.Getenv("ARAS_CUSTOMER_CODE"),
	}
	yurticiCarrierCfg := shipping.YurticiConfig{
		WSDLURL:      os.Getenv("YURTICI_WSDL_URL"),
		Username:     os.Getenv("YURTICI_USERNAME"),
		Password:     os.Getenv("YURTICI_PASSWORD"),
		CustomerCode: os.Getenv("YURTICI_CUSTOMER_CODE"),
	}
	pttCarrierCfg := shipping.PTTConfig{
		WSDLURL:      os.Getenv("PTT_WSDL_URL"),
		Username:     os.Getenv("PTT_USERNAME"),
		Password:     os.Getenv("PTT_PASSWORD"),
		CustomerCode: os.Getenv("PTT_CUSTOMER_CODE"),
	}

	kargDefault := os.Getenv("KARGO_DEFAULT")
	shippingSvc, err := shipping.NewService(kargDefault, shippingAdapters, shippingRepo, orderSvc, os.Getenv("GO_ENV") == "production")
	if err != nil {
		slog.Error("shipping: NewService failed", "err", err)
		os.Exit(1)
	}

	// Env-configurable poll intervals (Answer A).
	arasInterval := mustParseDuration("ARAS_POLL_INTERVAL", "5m")
	yurticiInterval := mustParseDuration("YURTICI_POLL_INTERVAL", "5m")
	pttInterval := mustParseDuration("PTT_POLL_INTERVAL", "6h")

	go runShippingPollWorker(ctx, shippingSvc, shippingAdapters, pollConfig{
		arasInterval:    arasInterval,
		yurticiInterval: yurticiInterval,
		pttInterval:     pttInterval,
	}, struct {
		Aras    shipping.ArasConfig
		Yurtici shipping.YurticiConfig
		PTT     shipping.PTTConfig
	}{Aras: arasCarrierCfg, Yurtici: yurticiCarrierCfg, PTT: pttCarrierCfg})

	// ── Identity module wiring ────────────────────────────────────────────────
	jwtSigningKey := []byte(mustEnv("JWT_SIGNING_KEY"))
	jwtSigner, err := identityjwt.NewHS256Signer(jwtSigningKey)
	if err != nil {
		slog.Error("core-svc: jwt signer init", "err", err)
		os.Exit(1)
	}
	identityRepo := identity.NewRepository(pool)
	identityLimiter := ratelimit.New(rc)
	// Email provider — always mock in local dev; SMTP in production.
	mockEmail := emailmock.New(slog.Default())
	var emailProv identityemail.Provider = mockEmail

	var smsProv sms.Provider
	switch os.Getenv("SMS_PROVIDER") {
	case "netgsm":
		slackForSMS := slack.New(os.Getenv("SLACK_PANIC_WEBHOOK"))
		smsProv = netgsm.New(
			mustEnv("NETGSM_USERNAME"), mustEnv("NETGSM_PASSWORD"),
			mustEnv("NETGSM_HEADER"), os.Getenv("NETGSM_API_URL"),
			slackForSMS,
		)
	default: // "mock" or empty
		smsProv = mock.New(slog.Default())
	}
	identitySvc := identity.NewService(
		identityRepo, smsProv, emailProv, identityLimiter, jwtSigner,
		market, defaultLocale, slog.Default(),
		bizM,
		// A-003: dev OTP bypass injected (was os.Getenv in identity); NewService panics if enabled in prod.
		identity.WithDevOTPBypass(os.Getenv("DEV_OTP_ACCEPT_ANY") == "true", os.Getenv("ENV") == "production"),
	)
	cleanup.StartCleanupWorker(ctx, pool, slog.Default())

	// ── HTTP router (Go 1.22+ stdlib mux with method+path patterns) ─────────
	mux := http.NewServeMux()

	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	mux.HandleFunc("GET /__version", handleVersion("core-svc"))

	// ── SEO: sitemap + robots (public, backend-served; Tranche 5b) ───────────
	mux.Handle("GET /sitemap.xml",
		httpTrace(http.HandlerFunc(handleSitemap(webBaseURL, time.Hour,
			catalog.NewSitemapReader(pool),
			seller.NewSitemapReader(pool),
			help.NewSitemapReader(pool),
		))),
	)
	mux.Handle("GET /robots.txt",
		httpTrace(http.HandlerFunc(handleRobots(webBaseURL))),
	)

	// Identity / auth routes
	requireAuth := middleware.RequireAuth(jwtSigner)
	optionalAuth := middleware.OptionalAuth(jwtSigner)
	// requireSellerRole gates the seller dashboard: RequireAuth resolves the user,
	// then this resolves their seller binding (403 if none) and puts seller_id in ctx.
	requireSellerRole := middleware.RequireSellerRole(sellerSvc.ResolveSellerForUser)
	// onUserDeleted cascades account deletion to the analytics tables (blocker #3,
	// §2.4). DELETE /me is a soft delete and emits no event yet, so erasure is
	// orchestrated here synchronously rather than via a consumer.
	auth := &authHandlers{
		svc:           identitySvc,
		log:           slog.Default(),
		onUserDeleted: analyticsSvc.DeleteUserData,
		// Enrich /me with the seller binding (null when unbound) for client-side
		// role detection (seller dashboard).
		sellerBinding: func(ctx context.Context, userID int64) (*seller.Binding, error) {
			b, ok, err := sellerSvc.GetBindingForUser(ctx, userID)
			if err != nil || !ok {
				return nil, err
			}
			return &b, nil
		},
	}
	auth.registerRoutes(mux, requireAuth)

	// ── Dev-only endpoint — returns last verification code for an email ───────
	// Active only when ENV != production. Safe to expose in local dev.
	if os.Getenv("ENV") != "production" {
		mux.HandleFunc("GET /dev/email-code", func(w http.ResponseWriter, r *http.Request) {
			email := r.URL.Query().Get("email")
			if email == "" {
				jsonError(w, "email query param required", http.StatusBadRequest)
				return
			}
			code := mockEmail.LastVerificationCode(email)
			if code == "" {
				jsonError(w, "no code found for this email", http.StatusNotFound)
				return
			}
			jsonOK(w, http.StatusOK, map[string]string{"email": email, "code": code})
		})
	}

	// Catalog routes
	mux.Handle("POST /products",
		httpTrace(http.HandlerFunc(handleCreateProduct(catalogSvc, defaultCurrency, defaultLocale))),
	)
	mux.Handle("GET /products",
		httpTrace(http.HandlerFunc(handleListProducts(analyticsSvc, catalogSvc, sellerSvc, defaultLocale, market, cashbackCurrency))),
	)
	mux.Handle("GET /products/{id}",
		httpTrace(http.HandlerFunc(handleGetProductDetail(catalogSvc, sellerSvc, shippingSvc, defaultLocale, market, cashbackCurrency))),
	)
	mux.Handle("POST /products/{id}/variants",
		httpTrace(http.HandlerFunc(handleAddVariant(catalogSvc, defaultCurrency))),
	)
	mux.Handle("PUT /products/{id}/translations/{locale}",
		httpTrace(http.HandlerFunc(handleUpdateTranslation(catalogSvc))),
	)
	mux.Handle("GET /categories",
		httpTrace(http.HandlerFunc(handleListCategories(catalogSvc, defaultLocale))),
	)
	mux.Handle("GET /categories/{id}/commission",
		httpTrace(http.HandlerFunc(handleGetCommission(catalogSvc, market))),
	)
	mux.Handle("GET /categories/{id}/facets",
		httpTrace(http.HandlerFunc(handleCategoryFacets(catalogSvc, defaultLocale))),
	)
	mux.Handle("GET /search",
		httpTrace(http.HandlerFunc(handleSearch(analyticsSvc, catalogSvc, sellerSvc, defaultLocale, market, cashbackCurrency))),
	)
	mux.Handle("GET /search/suggest",
		httpTrace(http.HandlerFunc(handleSearchSuggest(catalogSvc, defaultLocale, cashbackCurrency))),
	)
	mux.Handle("GET /banners",
		httpTrace(http.HandlerFunc(handleListBanners())),
	)
	mux.Handle("GET /recommendations/home",
		httpTrace(optionalAuth(http.HandlerFunc(
			handleHomeRecommendations(analyticsSvc, catalogSvc, defaultLocale, market, cashbackCurrency),
		))),
	)
	mux.Handle("GET /products/{id}/similar",
		httpTrace(http.HandlerFunc(
			handleSimilarProducts(analyticsSvc, catalogSvc, defaultLocale, market, cashbackCurrency),
		)),
	)

	// ── Home composition + batch ──────────────────────────────────────────────
	mux.Handle("GET /home/banners",
		httpTrace(http.HandlerFunc(handleHomeBanners(catalogSvc))),
	)
	mux.Handle("GET /home/rails",
		httpTrace(http.HandlerFunc(handleHomeRails(catalogSvc, defaultLocale))),
	)
	mux.Handle("GET /home/stories",
		httpTrace(http.HandlerFunc(handleHomeMoodStories(catalogSvc, defaultLocale))),
	)
	mux.Handle("GET /home/flash-deals",
		httpTrace(http.HandlerFunc(handleHomeFlashDeals(catalogSvc, defaultLocale, cashbackCurrency))),
	)
	mux.Handle("POST /products/batch",
		httpTrace(http.HandlerFunc(handleProductsBatch(catalogSvc, defaultLocale, market, cashbackCurrency))),
	)
	// Reviews list: public read, but OptionalAuth personalizes votedByCurrentUser.
	mux.Handle("GET /products/{id}/reviews",
		httpTrace(optionalAuth(http.HandlerFunc(handleProductReviews(catalogSvc, identitySvc, attachmentsSvc)))),
	)
	// Helpful-vote toggle: auth required (401 for guests).
	mux.Handle("POST /products/{id}/reviews/{reviewId}/helpful",
		httpTrace(requireAuth(http.HandlerFunc(handleReviewHelpfulVote(catalogSvc)))),
	)
	mux.Handle("GET /search/trending",
		httpTrace(http.HandlerFunc(handleSearchTrending())),
	)
	mux.Handle("POST /favorites/sync",
		httpTrace(requireAuth(http.HandlerFunc(handleFavoritesSync(pool)))),
	)
	mux.Handle("GET /favorites",
		httpTrace(requireAuth(http.HandlerFunc(handleFavoritesList(pgFavoritesReader{pool: pool})))),
	)
	// Cart merge — guest items added to server cart on login
	mux.Handle("POST /cart/merge",
		httpTrace(requireAuth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			userID := middleware.UserIDFromCtx(r.Context())
			var req struct {
				Items []struct {
					VariantID int64 `json:"variant_id"`
					Qty       int   `json:"qty"`
				} `json:"items"`
			}
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				jsonError(w, "invalid JSON", http.StatusBadRequest)
				return
			}
			for _, item := range req.Items {
				if item.Qty <= 0 || item.VariantID <= 0 {
					continue
				}
				if err := cartSvc.AddItem(r.Context(), userID, item.VariantID, item.Qty); err != nil {
					slog.Warn("cart merge: add item", "user_id", userID, "variant_id", item.VariantID, "err", err)
				}
			}
			jsonOK(w, http.StatusOK, map[string]any{"merged": len(req.Items)})
		}))),
	)

	// Address routes — require JWT authentication (IDOR-safe: user_id from JWT)
	mux.Handle("GET /addresses",
		httpTrace(requireAuth(http.HandlerFunc(handleListAddresses(identitySvc)))),
	)
	mux.Handle("POST /addresses",
		httpTrace(requireAuth(http.HandlerFunc(handleCreateAddress(identitySvc)))),
	)
	mux.Handle("GET /addresses/{id}",
		httpTrace(requireAuth(http.HandlerFunc(handleGetAddress(identitySvc)))),
	)
	mux.Handle("PUT /addresses/{id}",
		httpTrace(requireAuth(http.HandlerFunc(handleUpdateAddress(identitySvc)))),
	)
	mux.Handle("DELETE /addresses/{id}",
		httpTrace(requireAuth(http.HandlerFunc(handleDeleteAddress(identitySvc)))),
	)

	// Cart routes — require JWT authentication
	mux.Handle("POST /cart/items",
		httpTrace(requireAuth(http.HandlerFunc(handleCartAddItem(cartSvc)))),
	)
	mux.Handle("DELETE /cart/items/{variant_id}",
		httpTrace(requireAuth(http.HandlerFunc(handleCartRemoveItem(cartSvc)))),
	)
	mux.Handle("GET /cart",
		httpTrace(requireAuth(http.HandlerFunc(handleGetCart(cartSvc, catalogSvc, sellerSvc, orderSvc, defaultLocale, market)))),
	)
	mux.Handle("POST /cart/reserve",
		httpTrace(requireAuth(http.HandlerFunc(handleCartReserve(cartSvc)))),
	)
	mux.Handle("POST /cart/release",
		httpTrace(http.HandlerFunc(handleCartRelease(cartSvc))),
	)

	// Checkout route — initiates the v8 multi-seller saga (cart → PSP → 3DS)
	mux.Handle("POST /checkout/initiate",
		httpTrace(requireAuth(http.HandlerFunc(
			order.HandleInitiateCheckout(orderSvc, func(r *http.Request) (int64, bool) {
				id := middleware.UserIDFromCtx(r.Context())
				return id, id != 0
			}),
		))),
	)

	// Order routes — require JWT authentication where user ID is needed
	mux.Handle("POST /orders",
		httpTrace(requireAuth(http.HandlerFunc(handleCreateOrder(orderSvc)))),
	)
	mux.Handle("GET /orders/{id}",
		httpTrace(http.HandlerFunc(handleGetOrder(orderSvc, returnSvc, paymentRepo))),
	)
	mux.Handle("GET /orders",
		httpTrace(requireAuth(http.HandlerFunc(handleListOrders(orderSvc)))),
	)
	mux.Handle("POST /orders/{id}/status",
		httpTrace(http.HandlerFunc(handleUpdateOrderStatus(orderSvc))),
	)
	mux.Handle("POST /orders/{id}/deliver",
		httpTrace(http.HandlerFunc(handleMarkDelivered(orderSvc))),
	)
	mux.Handle("POST /orders/{id}/cancel",
		httpTrace(http.HandlerFunc(handleCancelOrder(orderSvc))),
	)
	mux.Handle("POST /orders/{id}/refund",
		httpTrace(http.HandlerFunc(handleRefundOrder(orderSvc, paymentSvc, paymentRepo, paymentOutbox, market, defaultCurrency))),
	)
	mux.Handle("POST /orders/{id}/returns",
		httpTrace(requireAuth(http.HandlerFunc(handleCreateReturn(returnSvc)))),
	)
	mux.Handle("GET /returns",
		httpTrace(requireAuth(http.HandlerFunc(handleListReturns(returnSvc)))),
	)
	mux.Handle("GET /returns/{id}",
		httpTrace(requireAuth(http.HandlerFunc(handleGetReturn(returnSvc)))),
	)
	// ── Notification inbox (Tranche 2a) ──────────────────────────────────────
	mux.Handle("GET /notifications",
		httpTrace(requireAuth(http.HandlerFunc(handleListNotifications(inboxSvc)))),
	)
	mux.Handle("GET /notifications/unread-count",
		httpTrace(requireAuth(http.HandlerFunc(handleUnreadCount(inboxSvc)))),
	)
	mux.Handle("POST /notifications/{id}/read",
		httpTrace(requireAuth(http.HandlerFunc(handleMarkNotificationRead(inboxSvc)))),
	)
	mux.Handle("POST /notifications/read-all",
		httpTrace(requireAuth(http.HandlerFunc(handleMarkAllRead(inboxSvc)))),
	)
	mux.Handle("GET /notifications/preferences",
		httpTrace(requireAuth(http.HandlerFunc(handleGetPreferences(inboxSvc)))),
	)
	mux.Handle("PUT /notifications/preferences",
		httpTrace(requireAuth(http.HandlerFunc(handlePutPreferences(inboxSvc)))),
	)
	mux.Handle("POST /push-tokens",
		httpTrace(requireAuth(http.HandlerFunc(handleRegisterPushToken(inboxSvc)))),
	)
	mux.Handle("DELETE /push-tokens",
		httpTrace(requireAuth(http.HandlerFunc(handleDeletePushToken(inboxSvc)))),
	)
	// ── Help / FAQ (public) ───────────────────────────────────────────────────
	mux.Handle("GET /help/categories",
		httpTrace(http.HandlerFunc(handleHelpCategories(helpSvc, defaultLocale))),
	)
	mux.Handle("GET /help/categories/{slug}/articles",
		httpTrace(http.HandlerFunc(handleHelpArticles(helpSvc, defaultLocale))),
	)
	mux.Handle("GET /help/articles/{slug}",
		httpTrace(http.HandlerFunc(handleHelpArticle(helpSvc, defaultLocale))),
	)
	mux.Handle("GET /help/search",
		httpTrace(http.HandlerFunc(handleHelpSearch(helpSvc, defaultLocale))),
	)
	// ── Support tickets (create = OptionalAuth; list/detail = RequireAuth) ────
	mux.Handle("POST /support/tickets",
		httpTrace(optionalAuth(http.HandlerFunc(handleCreateTicket(supportSvc)))),
	)
	mux.Handle("GET /support/tickets",
		httpTrace(requireAuth(http.HandlerFunc(handleListTickets(supportSvc)))),
	)
	mux.Handle("GET /support/tickets/{id}",
		httpTrace(requireAuth(http.HandlerFunc(handleGetTicket(supportSvc)))),
	)
	// ── Reviews write-side (Tranche 3) ────────────────────────────────────────
	mux.Handle("POST /products/{productId}/reviews",
		httpTrace(requireAuth(http.HandlerFunc(handleCreateReview(ugcSvc)))),
	)
	mux.Handle("PUT /products/{productId}/reviews/{reviewId}",
		httpTrace(requireAuth(http.HandlerFunc(handleUpdateReview(ugcSvc)))),
	)
	mux.Handle("DELETE /products/{productId}/reviews/{reviewId}",
		httpTrace(requireAuth(http.HandlerFunc(handleDeleteReview(ugcSvc)))),
	)
	mux.Handle("GET /me/reviews",
		httpTrace(requireAuth(http.HandlerFunc(handleListUserReviews(ugcSvc)))),
	)
	mux.Handle("GET /products/{id}/review-eligibility",
		httpTrace(requireAuth(http.HandlerFunc(handleReviewEligibility(ugcSvc, catalogSvc, orderSvc)))),
	)
	// ── Q&A (Tranche 3) ───────────────────────────────────────────────────────
	mux.Handle("POST /products/{productId}/questions",
		httpTrace(requireAuth(http.HandlerFunc(handleCreateQuestion(ugcSvc, identitySvc)))),
	)
	mux.Handle("GET /products/{productId}/questions",
		httpTrace(http.HandlerFunc(handleListQuestions(ugcSvc))),
	)
	mux.Handle("GET /products/{productId}/questions/{questionId}",
		httpTrace(http.HandlerFunc(handleGetQuestion(ugcSvc))),
	)
	mux.Handle("POST /products/{productId}/questions/{questionId}/answers",
		httpTrace(requireAuth(http.HandlerFunc(handleCreateAnswer(ugcSvc, identitySvc, sellerSvc, storefrontReader)))),
	)
	mux.Handle("GET /me/questions",
		httpTrace(requireAuth(http.HandlerFunc(handleListUserQuestions(ugcSvc)))),
	)

	// ── Seller storefronts (public) + seller dashboard (role-gated) — Tranche 5a ──
	mux.Handle("GET /sellers/{slug}",
		httpTrace(http.HandlerFunc(handleSellerStorefront(sellerSvc, storefrontReader, defaultLocale))),
	)
	mux.Handle("GET /sellers/{slug}/products",
		httpTrace(http.HandlerFunc(handleSellerStorefrontProducts(sellerSvc, storefrontReader, defaultLocale, cashbackCurrency))),
	)
	mux.Handle("GET /sellers/{slug}/reviews",
		httpTrace(http.HandlerFunc(handleSellerStorefrontReviews(sellerSvc, storefrontReader, defaultLocale))),
	)
	mux.Handle("GET /seller/returns",
		httpTrace(requireAuth(requireSellerRole(http.HandlerFunc(handleSellerReturns(storefrontReader, returnSvc))))),
	)
	mux.Handle("POST /seller/returns/{id}/approve",
		httpTrace(requireAuth(requireSellerRole(http.HandlerFunc(handleSellerApproveReturn(storefrontReader, returnSvc))))),
	)
	mux.Handle("POST /seller/returns/{id}/reject",
		httpTrace(requireAuth(requireSellerRole(http.HandlerFunc(handleSellerRejectReturn(storefrontReader, returnSvc))))),
	)
	// P-032: a seller updates the price of a variant they own; #92 trigger logs history.
	mux.Handle("PUT /seller/variants/{id}/price",
		httpTrace(requireAuth(requireSellerRole(http.HandlerFunc(handleUpdateVariantPrice(catalogSvc))))),
	)
	mux.Handle("GET /seller/questions",
		httpTrace(requireAuth(requireSellerRole(http.HandlerFunc(handleSellerQuestions(storefrontReader, ugcSvc))))),
	)

	// ── Media upload (photos) — auth-gated; 503 until STORAGE_ENABLED (ADR-0004) ─
	mux.Handle("POST /uploads/photos",
		httpTrace(requireAuth(http.HandlerFunc(
			handleUploadPhoto(attachmentsSvc, storageCfg.Enabled, uploadLim),
		))),
	)

	// ── Analytics pipeline (Tranche 4a) ─────────────────────────────────────────
	// Ingest is OptionalAuth (guest sessions); the rest require auth.
	mux.Handle("POST /analytics/events",
		httpTrace(optionalAuth(http.HandlerFunc(handleIngestEvents(analyticsSvc)))),
	)
	mux.Handle("POST /analytics/sessions/identify",
		httpTrace(requireAuth(http.HandlerFunc(handleIdentifySession(analyticsSvc)))),
	)
	mux.Handle("GET /me/consent",
		httpTrace(requireAuth(http.HandlerFunc(handleGetConsent(analyticsSvc)))),
	)
	mux.Handle("PUT /me/consent",
		httpTrace(requireAuth(http.HandlerFunc(handleSetConsent(analyticsSvc)))),
	)
	mux.Handle("DELETE /me/analytics-data",
		httpTrace(requireAuth(http.HandlerFunc(handleDeleteAnalyticsData(analyticsSvc)))),
	)
	mux.Handle("GET /me/recently-viewed",
		httpTrace(requireAuth(http.HandlerFunc(
			handleRecentlyViewed(analyticsSvc, catalogSvc, defaultLocale, market, cashbackCurrency),
		))),
	)

	mux.Handle("GET /seller/orders/{id}/breakdown",
		httpTrace(http.HandlerFunc(handleSellerBreakdown(orderSvc))),
	)

	// Payment routes — require JWT authentication
	mux.Handle("POST /payments",
		httpTrace(requireAuth(http.HandlerFunc(handleInitiatePayment(paymentSvc)))),
	)
	mux.Handle("GET /payments/{provider_ref}/status",
		httpTrace(http.HandlerFunc(handlePaymentStatus(paymentSvc))),
	)
	// DB-only status poll for the web redirect page; no auth needed (UUID is unguessable).
	mux.Handle("GET /payments/{invoiceID}/intent-status",
		httpTrace(http.HandlerFunc(handlePaymentIntentStatus(paymentRepo))),
	)
	// Webhook route — must match Caddyfile @psp_webhook path /payments/webhook/*
	// so the explicit no-middleware handle block applies (CLAUDE.md § 9).
	mux.Handle("POST /payments/webhook/sipay",
		httpTrace(http.HandlerFunc(handleSipayWebhook(webhookHandler))),
	)

	// Shipping webhook routes — Caddyfile @shipping_webhook path /shipping/webhook/*
	mux.Handle("POST /shipping/webhook/surat",
		httpTrace(http.HandlerFunc(handleShippingWebhook(shippingSvc, "surat"))),
	)
	mux.Handle("POST /shipping/webhook/mng",
		httpTrace(http.HandlerFunc(handleShippingWebhook(shippingSvc, "mng"))),
	)
	mux.Handle("POST /shipping/webhook/hepsijet",
		httpTrace(http.HandlerFunc(handleShippingWebhook(shippingSvc, "hepsijet"))),
	)

	idemMW := idempotency.New(
		idempotency.NewRedisStore(rc),
		middleware.UserIDFromCtx,
	)

	srv := &http.Server{
		Addr:         ":8080",
		Handler:      idemMW.Wrap(mux),
		ReadTimeout:  5 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  60 * time.Second,
	}
	go func() {
		<-ctx.Done()
		stop() // release signal resources; ctx is already cancelled
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		if err := srv.Shutdown(shutdownCtx); err != nil {
			slog.Error("core-svc: http shutdown failed", "err", err)
		}
	}()
	slog.Info("core-svc: starting", "market", market, "addr", srv.Addr)
	if err := srv.ListenAndServe(); !errors.Is(err, http.ErrServerClosed) {
		slog.Error("core-svc: http server exited unexpectedly", "err", err)
	}
}

func mustEnv(key string) string {
	v := os.Getenv(key)
	if v == "" {
		slog.Error("core-svc: required env not set", "key", key)
		os.Exit(1)
	}
	return v
}

// mustParseDuration reads key from env; if absent or empty returns def.
// If the value is present but not parseable, it exits (bad config = startup abort).
func mustParseDuration(key, def string) time.Duration {
	v := os.Getenv(key)
	if v == "" {
		d, _ := time.ParseDuration(def)
		return d
	}
	d, err := time.ParseDuration(v)
	if err != nil {
		slog.Error("core-svc: invalid duration env", "key", key, "value", v, "err", err)
		os.Exit(1)
	}
	return d
}

// buildCatalogDSN constructs the DSN from env vars.
// Connections go through pgbouncer-ecom (never directly to postgres-ecom).
func buildCatalogDSN() string {
	if dsn := os.Getenv("CATALOG_DSN"); dsn != "" {
		return dsn
	}
	host := os.Getenv("PGBOUNCER_ECOM_HOST")
	if host == "" {
		host = "pgbouncer-ecom"
	}
	port := os.Getenv("PGBOUNCER_ECOM_PORT")
	if port == "" {
		port = "5432"
	}
	password := os.Getenv("ECOM_DB_PASSWORD")
	return fmt.Sprintf("postgres://ecom_admin:%s@%s:%s/mopro_ecom?sslmode=disable", password, host, port)
}

// buildRedisClient constructs a Redis client from env vars and verifies connectivity.
func buildRedisClient(ctx context.Context) (*redis.Client, error) {
	addr := os.Getenv("REDIS_ADDR")
	if addr == "" {
		addr = "redis:6379"
	}
	pw := os.Getenv("REDIS_PASSWORD")
	rc := redis.NewClient(&redis.Options{
		Addr:     addr,
		Password: pw,
	})
	if err := rc.Ping(ctx).Err(); err != nil {
		return nil, fmt.Errorf("redis ping %s: %w", addr, err)
	}
	return rc, nil
}

// requireIdempotencyKey returns false and writes 422 if the header is missing.
func requireIdempotencyKey(w http.ResponseWriter, r *http.Request) bool {
	// Accept either header: the Dart client + OpenAPI spec use X-Idempotency-Key,
	// while older hand-written handlers/tests use Idempotency-Key.
	if r.Header.Get("Idempotency-Key") == "" && r.Header.Get("X-Idempotency-Key") == "" {
		jsonError(w, "Idempotency-Key header required", http.StatusUnprocessableEntity)
		return false
	}
	return true
}

// parseLocale extracts the best-match locale from Accept-Language, falling back to def.
func parseLocale(r *http.Request, def string) string {
	v := r.Header.Get("Accept-Language")
	if v == "" {
		return def
	}
	// Take first comma-separated tag, strip quality value (e.g. "tr-TR;q=0.9").
	first := strings.TrimSpace(strings.SplitN(v, ",", 2)[0])
	if idx := strings.Index(first, ";"); idx >= 0 {
		first = strings.TrimSpace(first[:idx])
	}
	if first == "" {
		return def
	}
	return first
}

// jsonError writes a JSON {"error":"..."} response.
func jsonError(w http.ResponseWriter, msg string, status int) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	fmt.Fprintf(w, `{"error":%q}`, msg)
}

// decodeJSON decodes the request body into v, writing a 400 on failure and returning a non-nil error.
func decodeJSON(w http.ResponseWriter, r *http.Request, v any) error {
	if err := json.NewDecoder(r.Body).Decode(v); err != nil {
		jsonError(w, "invalid JSON body", http.StatusBadRequest)
		return err
	}
	return nil
}

// jsonOK writes a JSON-encoded value with the given status code.
func jsonOK(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(v); err != nil {
		slog.Error("json encode error", "err", err)
	}
}

// redisDiskPanicChecker satisfies order.DiskPressureChecker using the Redis key
// written by disk-watch.sh when root filesystem usage reaches the panic threshold.
// Fails open: any Redis error returns false so checkout is never blocked by a
// Redis outage rather than actual disk pressure.
type redisDiskPanicChecker struct {
	rc *redis.Client
}

func (c *redisDiskPanicChecker) IsDiskPanic(ctx context.Context) bool {
	val, err := c.rc.Get(ctx, "panic:disk_full").Result()
	if err != nil {
		return false // fail-open: Redis unavailable → proceed with checkout
	}
	return val == "1"
}

// ── Catalog handlers ──────────────────────────────────────────────────────────

func handleCreateProduct(svc catalog.Service, defaultCurrency, defaultLocale string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !requireIdempotencyKey(w, r) {
			return
		}
		locale := parseLocale(r, defaultLocale)
		_ = locale // used by identity module in Phase 1.2+

		var req catalog.CreateProductRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			jsonError(w, "invalid JSON body", http.StatusBadRequest)
			return
		}

		p, err := svc.CreateProduct(r.Context(), req)
		if err != nil {
			if errors.Is(err, catalog.ErrInvalidCurrency) {
				jsonError(w, "invalid or inactive currency", http.StatusUnprocessableEntity)
				return
			}
			slog.Error("catalog: CreateProduct", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		jsonOK(w, http.StatusCreated, p)
	}
}

func handleAddVariant(svc catalog.Service, defaultCurrency string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !requireIdempotencyKey(w, r) {
			return
		}
		id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
		if err != nil {
			jsonError(w, "invalid product id", http.StatusBadRequest)
			return
		}
		var req catalog.AddVariantRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			jsonError(w, "invalid JSON body", http.StatusBadRequest)
			return
		}
		v, err := svc.AddVariant(r.Context(), id, req)
		if err != nil {
			switch {
			case errors.Is(err, catalog.ErrInvalidCurrency):
				jsonError(w, "invalid or inactive currency", http.StatusUnprocessableEntity)
			case errors.Is(err, catalog.ErrDuplicateSKU):
				jsonError(w, "duplicate SKU within product", http.StatusConflict)
			case errors.Is(err, catalog.ErrNotFound):
				jsonError(w, "product not found", http.StatusNotFound)
			default:
				slog.Error("catalog: AddVariant", "err", err)
				jsonError(w, "internal error", http.StatusInternalServerError)
			}
			return
		}
		jsonOK(w, http.StatusCreated, v)
	}
}

func handleUpdateTranslation(svc catalog.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !requireIdempotencyKey(w, r) {
			return
		}
		id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
		if err != nil {
			jsonError(w, "invalid product id", http.StatusBadRequest)
			return
		}
		locale := r.PathValue("locale")
		if locale == "" {
			jsonError(w, "locale required", http.StatusBadRequest)
			return
		}
		var body struct {
			Title       string `json:"title"`
			Description string `json:"description"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			jsonError(w, "invalid JSON body", http.StatusBadRequest)
			return
		}
		if err := svc.UpdateTranslation(r.Context(), id, locale, body.Title, body.Description); err != nil {
			slog.Error("catalog: UpdateTranslation", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

func handleGetCommission(svc catalog.Service, defaultMarket string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
		if err != nil {
			jsonError(w, "invalid category id", http.StatusBadRequest)
			return
		}
		market := r.URL.Query().Get("market")
		if market == "" {
			market = defaultMarket
		}
		cc, err := svc.GetCommissionForCategory(r.Context(), market, id)
		if err != nil {
			if errors.Is(err, catalog.ErrCommissionNotFound) {
				jsonError(w, "commission rule not found", http.StatusNotFound)
				return
			}
			slog.Error("catalog: GetCommission", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		jsonOK(w, http.StatusOK, map[string]any{
			"commission_pct_bps": cc.CommissionPctBps,
			"kdv_pct_bps":        cc.KdvPctBps,
		})
	}
}

// ── Cart handlers ─────────────────────────────────────────────────────────────

func handleCartAddItem(svc cart.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID := middleware.UserIDFromCtx(r.Context())
		var body struct {
			VariantID int64 `json:"variant_id"`
			Qty       int   `json:"qty"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			jsonError(w, "invalid JSON body", http.StatusBadRequest)
			return
		}
		if err := svc.AddItem(r.Context(), userID, body.VariantID, body.Qty); err != nil {
			switch {
			case errors.Is(err, cart.ErrInvalidQty):
				jsonError(w, "qty must be positive", http.StatusUnprocessableEntity)
			case errors.Is(err, cart.ErrVariantNotFound):
				jsonError(w, "variant not found", http.StatusNotFound)
			default:
				slog.Error("cart: AddItem", "err", err)
				jsonError(w, "internal error", http.StatusInternalServerError)
			}
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

func handleCartRemoveItem(svc cart.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID := middleware.UserIDFromCtx(r.Context())
		variantID, err := strconv.ParseInt(r.PathValue("variant_id"), 10, 64)
		if err != nil {
			jsonError(w, "invalid variant_id", http.StatusBadRequest)
			return
		}
		if err := svc.RemoveItem(r.Context(), userID, variantID); err != nil {
			slog.Error("cart: RemoveItem", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

func handleGetCart(svc cart.Service, cat cartCatalogResolver, namer cartSellerNamer, coupons cartCouponValidator, defaultLocale, defaultMarket string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID := middleware.UserIDFromCtx(r.Context())
		c, err := svc.GetCart(r.Context(), userID)
		if err != nil {
			slog.Error("cart: GetCart", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		// Enrich raw {variant_id, qty} into the rich CartDto the mobile expects
		// (lines + per-seller totals + grand total) §5-safely — no cross-schema JOIN.
		// An optional ?coupon=CODE applies the coupon discount for display (CT-03);
		// the same code passed at checkout charges the same total.
		locale := parseLocale(r, defaultLocale)
		couponCode := r.URL.Query().Get("coupon")
		jsonOK(w, http.StatusOK, enrichCart(r.Context(), c, cat, namer, coupons, couponCode, locale, defaultMarket))
	}
}

func handleCartReserve(svc cart.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID := middleware.UserIDFromCtx(r.Context())
		reservationID, expiresAt, err := svc.Reserve(r.Context(), userID)
		if err != nil {
			switch {
			case errors.Is(err, cart.ErrCartEmpty):
				jsonError(w, "cart is empty", http.StatusUnprocessableEntity)
			case errors.Is(err, cart.ErrOutOfStock):
				jsonError(w, "one or more items out of stock", http.StatusConflict)
			case errors.Is(err, cart.ErrInvalidQty):
				jsonError(w, "qty must be positive", http.StatusUnprocessableEntity)
			default:
				slog.Error("cart: Reserve", "err", err)
				jsonError(w, "internal error", http.StatusInternalServerError)
			}
			return
		}
		jsonOK(w, http.StatusCreated, map[string]any{
			"reservation_id": reservationID,
			"expires_at":     expiresAt,
		})
	}
}

func handleCartRelease(svc cart.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var body struct {
			ReservationID string `json:"reservation_id"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			jsonError(w, "invalid JSON body", http.StatusBadRequest)
			return
		}
		if err := svc.Release(r.Context(), body.ReservationID); err != nil {
			if errors.Is(err, cart.ErrReservationNotFound) {
				jsonError(w, "reservation not found", http.StatusNotFound)
				return
			}
			slog.Error("cart: Release", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

// ── Order handlers ────────────────────────────────────────────────────────────

func handleCreateOrder(svc order.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID := middleware.UserIDFromCtx(r.Context())
		if !requireIdempotencyKey(w, r) {
			return
		}
		var body struct {
			ReservationID string `json:"reservation_id"`
			Market        string `json:"market"`
			Currency      string `json:"currency"`
			CouponCode    string `json:"coupon_code"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			jsonError(w, "invalid JSON body", http.StatusBadRequest)
			return
		}
		o, items, err := svc.Checkout(r.Context(), order.CheckoutRequest{
			UserID:         userID,
			ReservationID:  body.ReservationID,
			Market:         body.Market,
			Currency:       body.Currency,
			CouponCode:     body.CouponCode,
			IdempotencyKey: r.Header.Get("Idempotency-Key"),
		})
		if err != nil {
			switch {
			case errors.Is(err, order.ErrEmptyCart):
				jsonError(w, "cart is empty", http.StatusUnprocessableEntity)
			case errors.Is(err, order.ErrDuplicateIdempotency):
				jsonError(w, "duplicate idempotency key", http.StatusConflict)
			default:
				slog.Error("order: Checkout", "err", err)
				jsonError(w, "internal error", http.StatusInternalServerError)
			}
			return
		}
		jsonOK(w, http.StatusCreated, map[string]any{"order": o, "items": items})
	}
}

func handleGetOrder(svc order.Service, returnSvc order.ReturnService, paymentRepo payment.Repository) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
		if err != nil {
			jsonError(w, "invalid order id", http.StatusBadRequest)
			return
		}
		o, items, err := svc.GetOrder(r.Context(), id)
		if err != nil {
			if errors.Is(err, order.ErrOrderNotFound) {
				jsonError(w, "order not found", http.StatusNotFound)
				return
			}
			slog.Error("order: GetOrder", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}

		// Server-computed eligibility + read-only refund visibility (§3.1/§3.4).
		resp := map[string]any{"order": o, "items": items}
		if actions, aErr := returnSvc.ComputeActions(r.Context(), o, items); aErr != nil {
			slog.Warn("order: ComputeActions", "err", aErr, "order_id", id)
		} else {
			resp["actions"] = actions
		}
		pi, pErr := paymentRepo.FindPaymentByOrderID(r.Context(), id)
		found := pErr == nil
		if !found && !errors.Is(pErr, payment.ErrPaymentNotFound) {
			slog.Warn("order: FindPaymentByOrderID for refund view", "err", pErr, "order_id", id)
		}
		if rv := buildOrderRefundView(o, pi, found); rv != nil {
			resp["refund"] = rv
		}
		jsonOK(w, http.StatusOK, resp)
	}
}

func handleListOrders(svc order.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID := middleware.UserIDFromCtx(r.Context())
		orders, err := svc.ListOrders(r.Context(), userID)
		if err != nil {
			slog.Error("order: ListOrders", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		if orders == nil {
			orders = []order.Order{}
		}
		jsonOK(w, http.StatusOK, map[string]any{"orders": orders})
	}
}

func handleUpdateOrderStatus(svc order.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
		if err != nil {
			jsonError(w, "invalid order id", http.StatusBadRequest)
			return
		}
		var body struct {
			Status string `json:"status"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			jsonError(w, "invalid JSON body", http.StatusBadRequest)
			return
		}
		if err := svc.UpdateStatus(r.Context(), id, order.OrderStatus(body.Status)); err != nil {
			if errors.Is(err, order.ErrOrderNotFound) {
				jsonError(w, "order not found", http.StatusNotFound)
				return
			}
			slog.Error("order: UpdateStatus", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

func handleMarkDelivered(svc order.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
		if err != nil {
			jsonError(w, "invalid order id", http.StatusBadRequest)
			return
		}
		var body struct {
			DeliveredAt time.Time `json:"delivered_at"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			jsonError(w, "invalid JSON body", http.StatusBadRequest)
			return
		}
		if body.DeliveredAt.IsZero() {
			body.DeliveredAt = time.Now().UTC()
		}
		if err := svc.MarkDelivered(r.Context(), id, body.DeliveredAt); err != nil {
			if errors.Is(err, order.ErrOrderNotFound) {
				jsonError(w, "order not found", http.StatusNotFound)
				return
			}
			slog.Error("order: MarkDelivered", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

func handleCancelOrder(svc order.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
		if err != nil {
			jsonError(w, "invalid order id", http.StatusBadRequest)
			return
		}
		var body struct {
			Reason string `json:"reason"`
		}
		if err := decodeJSON(w, r, &body); err != nil {
			return
		}
		if err := svc.CancelOrder(r.Context(), id, body.Reason); err != nil {
			switch {
			case errors.Is(err, order.ErrOrderNotFound):
				jsonError(w, "order not found", http.StatusNotFound)
			case errors.Is(err, order.ErrInvalidTransition):
				jsonError(w, err.Error(), http.StatusConflict)
			default:
				slog.Error("order: CancelOrder", "err", err)
				jsonError(w, "internal error", http.StatusInternalServerError)
			}
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

func handleRefundOrder(
	orderSvc order.Service,
	paymentSvc payment.Service,
	paymentRepo payment.Repository,
	paymentOutbox outbox.Repository,
	market, defaultCurrency string,
) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !requireIdempotencyKey(w, r) {
			return
		}
		orderID, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
		if err != nil {
			jsonError(w, "invalid order id", http.StatusBadRequest)
			return
		}

		o, _, err := orderSvc.GetOrder(r.Context(), orderID)
		if err != nil {
			if errors.Is(err, order.ErrOrderNotFound) {
				jsonError(w, "order not found", http.StatusNotFound)
				return
			}
			slog.Error("order: GetOrder for refund", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		if o.Status != order.StatusPaid && o.Status != order.StatusShipped && o.Status != order.StatusDelivered {
			jsonError(w, "order cannot be refunded in current status", http.StatusConflict)
			return
		}

		pi, err := paymentRepo.FindPaymentByOrderID(r.Context(), orderID)
		if err != nil {
			if errors.Is(err, payment.ErrPaymentNotFound) {
				jsonError(w, "no payment found for order", http.StatusNotFound)
				return
			}
			slog.Error("payment: FindPaymentByOrderID", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}

		idempKey := r.Header.Get("Idempotency-Key")
		refundResp, err := paymentSvc.Refund(r.Context(), payment.RefundRequest{
			ProviderRef:    pi.ProviderRef,
			AmountMinor:    0, // full refund
			IdempotencyKey: idempKey,
			OrderID:        orderID,
		})
		if err != nil {
			slog.Error("payment: Refund", "err", err)
			jsonError(w, "refund failed: "+err.Error(), http.StatusBadGateway)
			return
		}

		now := time.Now().UTC()
		refundedAtStr := now.Format(time.RFC3339)
		if err := paymentRepo.WithTx(r.Context(), func(tx pgx.Tx) error {
			if err := paymentRepo.UpdatePaymentStatus(
				r.Context(), tx, pi.ProviderRef,
				payment.PaymentStatusRefunded,
				nil, nil, &refundedAtStr,
				"", refundResp.RefundRef, refundResp.AmountMinor,
			); err != nil {
				return err
			}
			return orderSvc.UpdateStatus(r.Context(), orderID, order.StatusRefunded)
		}); err != nil {
			slog.Error("order: refund status update", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		_ = paymentOutbox
		_ = market
		_ = defaultCurrency

		jsonOK(w, http.StatusOK, map[string]any{
			"refund_ref":   refundResp.RefundRef,
			"refunded_at":  refundResp.RefundedAt,
			"amount_minor": refundResp.AmountMinor,
		})
	}
}

// sellerBreakdownItem is the per-line Trendyol-style transparent breakdown for sellers.
type sellerBreakdownItem struct {
	VariantID int64 `json:"variant_id"`
	Qty       int   `json:"qty"`
	// GrossMinor is the CHARGED (basket-discounted) gross — the reconciling base
	// (gross − commission − kdv = seller_net). ListGrossMinor / BasketDiscountMinor
	// expose the pre-discount gross and the seller-funded discount for transparency
	// (CT-09); BasketDiscountPct is the snapshotted rate (omitted when 0).
	GrossMinor            int64  `json:"gross_minor"`
	ListGrossMinor        int64  `json:"list_gross_minor"`
	BasketDiscountMinor   int64  `json:"basket_discount_minor"`
	BasketDiscountPct     int    `json:"basket_discount_pct,omitempty"`
	CommissionPctBps      int    `json:"commission_pct_bps"`
	KdvPctBps             int    `json:"kdv_pct_bps"`
	CommissionAmountMinor int64  `json:"commission_amount_minor"`
	KdvAmountMinor        int64  `json:"kdv_amount_minor"`
	CargoMinor            int64  `json:"cargo_minor"` // always 0 in v1 (cargo handled separately)
	SellerNetMinor        int64  `json:"seller_net_minor"`
	Currency              string `json:"currency"`
}

func handleSellerBreakdown(svc order.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		sellerIDStr := r.Header.Get("X-Mopro-Seller-Id")
		sellerID, err := strconv.ParseInt(sellerIDStr, 10, 64)
		if err != nil || sellerID <= 0 {
			jsonError(w, "X-Mopro-Seller-Id header required", http.StatusUnauthorized)
			return
		}
		orderID, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
		if err != nil {
			jsonError(w, "invalid order id", http.StatusBadRequest)
			return
		}
		o, items, err := svc.GetOrder(r.Context(), orderID)
		if err != nil {
			if errors.Is(err, order.ErrOrderNotFound) {
				jsonError(w, "order not found", http.StatusNotFound)
				return
			}
			slog.Error("order: GetOrder for breakdown", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}

		breakdown := make([]sellerBreakdownItem, 0, len(items))
		for _, it := range items {
			if it.SellerID != sellerID {
				continue
			}
			gross := it.UnitPriceMinor * int64(it.Qty)
			listGross := it.ListUnitPriceMinor * int64(it.Qty)
			if listGross == 0 {
				listGross = gross // pre-CT-09 rows have no list price snapshot
			}
			breakdown = append(breakdown, sellerBreakdownItem{
				VariantID:             it.VariantID,
				Qty:                   it.Qty,
				GrossMinor:            gross,
				ListGrossMinor:        listGross,
				BasketDiscountMinor:   listGross - gross,
				BasketDiscountPct:     it.BasketDiscountPct,
				CommissionPctBps:      it.CommissionPctBps,
				KdvPctBps:             it.KdvPctBps,
				CommissionAmountMinor: it.CommissionAmountMinor,
				KdvAmountMinor:        it.KdvAmountMinor,
				CargoMinor:            0,
				SellerNetMinor:        it.SellerNetMinor,
				Currency:              it.UnitPriceCurrency,
			})
		}
		if len(breakdown) == 0 {
			jsonError(w, "no items for this seller in this order", http.StatusNotFound)
			return
		}

		jsonOK(w, http.StatusOK, map[string]any{
			"order_id":     o.ID,
			"order_status": o.Status,
			"seller_id":    sellerID,
			"items":        breakdown,
		})
	}
}
