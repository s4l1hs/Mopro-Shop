package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/redis/go-redis/v9"

	"github.com/mopro/platform/internal/cart"
	"github.com/mopro/platform/internal/catalog"
	"github.com/mopro/platform/internal/eventbus"
	"github.com/mopro/platform/internal/order"
	"github.com/mopro/platform/internal/outbox"
	"github.com/mopro/platform/internal/payment"
	"github.com/mopro/platform/internal/payment/sipay"
	"github.com/mopro/platform/internal/shipping"
	"github.com/mopro/platform/internal/shipping/hepsijet"
	"github.com/mopro/platform/internal/shipping/mng"
	"github.com/mopro/platform/internal/shipping/surat"
	"github.com/mopro/platform/pkg/dbx"
	"github.com/mopro/platform/pkg/httpx"
)

func main() {
	// Startup connections use plain Background; signal context begins after init.
	initCtx := context.Background()

	market := os.Getenv("MARKET")
	defaultCurrency := os.Getenv("DEFAULT_CURRENCY")
	defaultLocale := os.Getenv("DEFAULT_LOCALE")
	log.Printf("starting core-svc market=%s", market)

	// ── Database pool for catalog (connects through pgbouncer-ecom) ──────────
	catalogDSN := buildCatalogDSN()
	pool, err := dbx.Connect(initCtx, catalogDSN)
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

	// ── Cart module wiring (loads Lua EVALSHA at startup) ───────────────────
	cartRepo, err := cart.NewRepository(initCtx, rc)
	if err != nil {
		slog.Error("cart: failed to load Lua scripts", "err", err)
		os.Exit(1)
	}
	cartSvc := cart.NewService(cartRepo, catalogSvc)

	// ── Signal-aware context for goroutines + HTTP shutdown ─────────────────
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, os.Interrupt)

	// ── Order module wiring ──────────────────────────────────────────────────
	cashbackCurrency := mustEnv("DEFAULT_CASHBACK_CURRENCY")
	orderOutbox := outbox.NewRepository("order_schema.outbox")
	orderRepo := order.NewRepository(pool)
	orderSvc := order.NewService(orderRepo, cartSvc, catalogSvc, orderOutbox, market, cashbackCurrency)

	// ── Outbox publisher — drains order_schema.outbox → Redis Streams ───────
	bus := eventbus.NewRedisBus(rc, slog.Default())
	pub, err := outbox.NewPublisher(pool, orderOutbox, bus, slog.Default())
	if err != nil {
		slog.Error("core-svc: outbox publisher init", "err", err)
		os.Exit(1)
	}
	go func() {
		if err := pub.Run(ctx); err != nil && !errors.Is(err, context.Canceled) {
			slog.Error("core-svc: outbox publisher exited unexpectedly", "err", err)
		}
	}()

	// ── Payment module wiring ────────────────────────────────────────────────
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
	}
	paymentSvc := payment.NewService(sipaycfg, paymentRepo)

	sipayAdapter, err := sipay.NewAdapter(sipaycfg, paymentRepo, slog.Default())
	if err != nil {
		slog.Error("sipay: adapter init failed", "err", err)
		os.Exit(1)
	}
	webhookHandler := sipay.NewWebhookHandler(
		sipayAdapter, paymentRepo, paymentOutbox, rc, market, cashbackCurrency, slog.Default(),
	)

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

	kargDefault := os.Getenv("KARGO_DEFAULT")
	shippingSvc, err := shipping.NewService(kargDefault, shippingAdapters, shippingRepo, orderSvc)
	if err != nil {
		slog.Error("shipping: NewService failed", "err", err)
		os.Exit(1)
	}

	// ── HTTP router (Go 1.22+ stdlib mux with method+path patterns) ─────────
	mux := http.NewServeMux()

	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})

	// Catalog routes
	mux.Handle("POST /v1/products",
		httpx.TraceAndLog(http.HandlerFunc(handleCreateProduct(catalogSvc, defaultCurrency, defaultLocale))),
	)
	mux.Handle("GET /v1/products/{id}",
		httpx.TraceAndLog(http.HandlerFunc(handleGetProduct(catalogSvc))),
	)
	mux.Handle("POST /v1/products/{id}/variants",
		httpx.TraceAndLog(http.HandlerFunc(handleAddVariant(catalogSvc, defaultCurrency))),
	)
	mux.Handle("PUT /v1/products/{id}/translations/{locale}",
		httpx.TraceAndLog(http.HandlerFunc(handleUpdateTranslation(catalogSvc))),
	)
	mux.Handle("GET /v1/categories/{id}/commission",
		httpx.TraceAndLog(http.HandlerFunc(handleGetCommission(catalogSvc, market))),
	)

	// Cart routes
	mux.Handle("POST /v1/cart/items",
		httpx.TraceAndLog(http.HandlerFunc(handleCartAddItem(cartSvc))),
	)
	mux.Handle("DELETE /v1/cart/items/{variant_id}",
		httpx.TraceAndLog(http.HandlerFunc(handleCartRemoveItem(cartSvc))),
	)
	mux.Handle("GET /v1/cart",
		httpx.TraceAndLog(http.HandlerFunc(handleGetCart(cartSvc))),
	)
	mux.Handle("POST /v1/cart/reserve",
		httpx.TraceAndLog(http.HandlerFunc(handleCartReserve(cartSvc))),
	)
	mux.Handle("POST /v1/cart/release",
		httpx.TraceAndLog(http.HandlerFunc(handleCartRelease(cartSvc))),
	)

	// Order routes
	mux.Handle("POST /v1/orders",
		httpx.TraceAndLog(http.HandlerFunc(handleCreateOrder(orderSvc))),
	)
	mux.Handle("GET /v1/orders/{id}",
		httpx.TraceAndLog(http.HandlerFunc(handleGetOrder(orderSvc))),
	)
	mux.Handle("GET /v1/orders",
		httpx.TraceAndLog(http.HandlerFunc(handleListOrders(orderSvc))),
	)
	mux.Handle("POST /v1/orders/{id}/status",
		httpx.TraceAndLog(http.HandlerFunc(handleUpdateOrderStatus(orderSvc))),
	)
	mux.Handle("POST /v1/orders/{id}/deliver",
		httpx.TraceAndLog(http.HandlerFunc(handleMarkDelivered(orderSvc))),
	)
	mux.Handle("POST /v1/orders/{id}/cancel",
		httpx.TraceAndLog(http.HandlerFunc(handleCancelOrder(orderSvc))),
	)
	mux.Handle("POST /v1/orders/{id}/refund",
		httpx.TraceAndLog(http.HandlerFunc(handleRefundOrder(orderSvc, paymentSvc, paymentRepo, paymentOutbox, market, defaultCurrency))),
	)
	mux.Handle("GET /v1/seller/orders/{id}/breakdown",
		httpx.TraceAndLog(http.HandlerFunc(handleSellerBreakdown(orderSvc))),
	)

	// Payment routes
	mux.Handle("POST /v1/payments",
		httpx.TraceAndLog(http.HandlerFunc(handleInitiatePayment(paymentSvc))),
	)
	mux.Handle("GET /v1/payments/{provider_ref}/status",
		httpx.TraceAndLog(http.HandlerFunc(handlePaymentStatus(paymentSvc))),
	)
	// Webhook route — must match Caddyfile @psp_webhook path /v1/payments/webhook/*
	// so the explicit no-middleware handle block applies (CLAUDE.md § 9).
	mux.Handle("POST /v1/payments/webhook/sipay",
		httpx.TraceAndLog(http.HandlerFunc(handleSipayWebhook(webhookHandler))),
	)

	// Shipping webhook routes — Caddyfile @shipping_webhook path /v1/shipping/webhook/*
	mux.Handle("POST /v1/shipping/webhook/surat",
		httpx.TraceAndLog(http.HandlerFunc(handleShippingWebhook(shippingSvc, "surat"))),
	)
	mux.Handle("POST /v1/shipping/webhook/mng",
		httpx.TraceAndLog(http.HandlerFunc(handleShippingWebhook(shippingSvc, "mng"))),
	)
	mux.Handle("POST /v1/shipping/webhook/hepsijet",
		httpx.TraceAndLog(http.HandlerFunc(handleShippingWebhook(shippingSvc, "hepsijet"))),
	)

	srv := &http.Server{
		Addr:         ":8080",
		Handler:      mux,
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
		log.Fatal(err)
	}
}

func mustEnv(key string) string {
	v := os.Getenv(key)
	if v == "" {
		log.Fatalf("core-svc: required env %s is not set", key)
	}
	return v
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
	return fmt.Sprintf("postgres://ecom_admin:%s@%s:%s/mopro_ecom", password, host, port)
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
	if r.Header.Get("Idempotency-Key") == "" {
		jsonError(w, "Idempotency-Key header required", http.StatusUnprocessableEntity)
		return false
	}
	return true
}

// requireUserID extracts the user ID from X-Mopro-User-Id (dev-only; Phase 1.3 uses JWT).
func requireUserID(w http.ResponseWriter, r *http.Request) (int64, bool) {
	s := r.Header.Get("X-Mopro-User-Id")
	id, err := strconv.ParseInt(s, 10, 64)
	if err != nil || id <= 0 {
		jsonError(w, "X-Mopro-User-Id header required", http.StatusUnauthorized)
		return 0, false
	}
	return id, true
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

		// TODO(idempotency-sprint): enforce idempotency dedup via idempotency store.
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

func handleGetProduct(svc catalog.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
		if err != nil {
			jsonError(w, "invalid product id", http.StatusBadRequest)
			return
		}
		p, variants, translations, err := svc.GetByID(r.Context(), id)
		if err != nil {
			if errors.Is(err, catalog.ErrNotFound) {
				jsonError(w, "product not found", http.StatusNotFound)
				return
			}
			slog.Error("catalog: GetByID", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		jsonOK(w, http.StatusOK, map[string]any{
			"product":      p,
			"variants":     variants,
			"translations": translations,
		})
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
		userID, ok := requireUserID(w, r)
		if !ok {
			return
		}
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
		userID, ok := requireUserID(w, r)
		if !ok {
			return
		}
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

func handleGetCart(svc cart.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID, ok := requireUserID(w, r)
		if !ok {
			return
		}
		c, err := svc.GetCart(r.Context(), userID)
		if err != nil {
			slog.Error("cart: GetCart", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		jsonOK(w, http.StatusOK, c)
	}
}

func handleCartReserve(svc cart.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID, ok := requireUserID(w, r)
		if !ok {
			return
		}
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
		userID, ok := requireUserID(w, r)
		if !ok {
			return
		}
		if !requireIdempotencyKey(w, r) {
			return
		}
		var body struct {
			ReservationID string `json:"reservation_id"`
			Market        string `json:"market"`
			Currency      string `json:"currency"`
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

func handleGetOrder(svc order.Service) http.HandlerFunc {
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
		jsonOK(w, http.StatusOK, map[string]any{"order": o, "items": items})
	}
}

func handleListOrders(svc order.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID, ok := requireUserID(w, r)
		if !ok {
			return
		}
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
	VariantID             int64  `json:"variant_id"`
	Qty                   int    `json:"qty"`
	GrossMinor            int64  `json:"gross_minor"`
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
			breakdown = append(breakdown, sellerBreakdownItem{
				VariantID:             it.VariantID,
				Qty:                   it.Qty,
				GrossMinor:            gross,
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
			"order_id":      o.ID,
			"order_status":  o.Status,
			"seller_id":     sellerID,
			"items":         breakdown,
		})
	}
}
