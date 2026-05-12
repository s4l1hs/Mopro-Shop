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

// requireIdempotencyKey returns false and writes 422 if the header is missing.
func requireIdempotencyKey(w http.ResponseWriter, r *http.Request) bool {
	if r.Header.Get("Idempotency-Key") == "" {
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

// jsonOK writes a JSON-encoded value with the given status code.
func jsonOK(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(v); err != nil {
		slog.Error("json encode error", "err", err)
	}
}

// ── Handlers ─────────────────────────────────────────────────────────────────

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
