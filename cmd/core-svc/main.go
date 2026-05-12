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
	"strconv"
	"strings"
	"time"

	"github.com/redis/go-redis/v9"

	"github.com/mopro/platform/internal/cart"
	"github.com/mopro/platform/internal/catalog"
	"github.com/mopro/platform/pkg/dbx"
	"github.com/mopro/platform/pkg/httpx"
)

func main() {
	market := os.Getenv("MARKET")
	defaultCurrency := os.Getenv("DEFAULT_CURRENCY")
	defaultLocale := os.Getenv("DEFAULT_LOCALE")
	log.Printf("starting core-svc market=%s", market)

	// ── Database pool for catalog (connects through pgbouncer-ecom) ──────────
	catalogDSN := buildCatalogDSN()
	pool, err := dbx.Connect(context.Background(), catalogDSN)
	if err != nil {
		slog.Error("catalog: failed to create DB pool", "err", err)
		os.Exit(1)
	}
	// pool.Close() is called on graceful shutdown; log.Fatal will call os.Exit
	// directly, so cleanup runs only when the server exits cleanly (Phase 2+
	// adds SIGTERM handling with explicit pool.Close()).

	// ── Catalog module wiring ────────────────────────────────────────────────
	catalogRepo := catalog.NewRepository(pool)
	catalogSvc := catalog.NewService(catalogRepo, defaultCurrency, defaultLocale)

	// ── Redis client (cart stock reservation + future eventbus) ─────────────
	rc, err := buildRedisClient(context.Background())
	if err != nil {
		slog.Error("cart: failed to connect to Redis", "err", err)
		os.Exit(1)
	}

	// ── Cart module wiring (loads Lua EVALSHA at startup) ───────────────────
	cartRepo, err := cart.NewRepository(context.Background(), rc)
	if err != nil {
		slog.Error("cart: failed to load Lua scripts", "err", err)
		os.Exit(1)
	}
	cartSvc := cart.NewService(cartRepo, catalogSvc)

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

	srv := &http.Server{
		Addr:         ":8080",
		Handler:      mux,
		ReadTimeout:  5 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  60 * time.Second,
	}
	log.Fatal(srv.ListenAndServe())
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

		// TODO(Phase 1.2): enforce idempotency dedup via idempotency store.
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
			if errors.Is(err, cart.ErrVariantNotFound) {
				jsonError(w, "variant not found", http.StatusNotFound)
				return
			}
			slog.Error("cart: AddItem", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
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
