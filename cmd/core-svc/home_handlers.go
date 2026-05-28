package main

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"strconv"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/mopro/platform/internal/catalog"
	"github.com/mopro/platform/internal/identity/middleware"
)

// ── GET /home/banners ─────────────────────────────────────────────────────────

func handleHomeBanners(svc catalog.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		banners, err := svc.HomeBanners(r.Context())
		if err != nil {
			slog.Error("home: HomeBanners", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		out := make([]map[string]any, len(banners))
		for i, b := range banners {
			out[i] = map[string]any{
				"id":         b.ID,
				"image_url":  b.ImageURL,
				"deep_link":  b.DeepLink,
				"sort_order": b.SortOrder,
			}
		}
		jsonOK(w, http.StatusOK, map[string]any{"data": out})
	}
}

// ── GET /home/rails ───────────────────────────────────────────────────────────

func handleHomeRails(svc catalog.Service, defaultLocale string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		locale := parseLocale(r, defaultLocale)
		rails, err := svc.HomeRails(r.Context(), locale)
		if err != nil {
			slog.Error("home: HomeRails", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		type railJSON struct {
			Key   string `json:"key"`
			Title string `json:"title"`
		}
		out := make([]railJSON, len(rails))
		for i, rail := range rails {
			title := rail.TitleTR
			if locale == "en-US" || locale == "en" {
				title = rail.TitleEN
			}
			out[i] = railJSON{Key: rail.RailKey, Title: title}
		}
		jsonOK(w, http.StatusOK, map[string]any{"data": out})
	}
}

// ── POST /products/batch ──────────────────────────────────────────────────────
// Public — no auth required. Body: {"ids":[1,2,3]}

func handleProductsBatch(svc catalog.Service, defaultLocale, defaultMarket, cashbackCurrency string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			IDs []int64 `json:"ids"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			jsonError(w, "invalid JSON", http.StatusBadRequest)
			return
		}
		if len(req.IDs) == 0 {
			jsonOK(w, http.StatusOK, map[string]any{"data": []any{}})
			return
		}
		if len(req.IDs) > 100 {
			jsonError(w, "ids: max 100 per request", http.StatusUnprocessableEntity)
			return
		}
		locale := parseLocale(r, defaultLocale)
		rows, err := svc.ListProductsByIDs(r.Context(), req.IDs, locale, defaultMarket)
		if err != nil {
			slog.Error("catalog: ListProductsByIDs", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		jsonOK(w, http.StatusOK, buildProductListResponse(rows, len(rows), 1, len(rows), cashbackCurrency))
	}
}

// ── GET /products/{id}/reviews ────────────────────────────────────────────────

func handleProductReviews(svc catalog.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		productID, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
		if err != nil || productID <= 0 {
			jsonError(w, "invalid product id", http.StatusBadRequest)
			return
		}
		page := parseIntQuery(r.URL.Query().Get("page"), 1)
		perPage := parseIntQuery(r.URL.Query().Get("per_page"), 20)
		if perPage > 50 {
			perPage = 50
		}
		reviews, total, err := svc.ListReviews(r.Context(), productID, page, perPage)
		if err != nil {
			slog.Error("catalog: ListReviews", "product_id", productID, "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		type reviewJSON struct {
			ID           int64  `json:"id"`
			UserID       int64  `json:"user_id"`
			Rating       int    `json:"rating"`
			Title        string `json:"title"`
			Body         string `json:"body"`
			HelpfulCount int    `json:"helpful_count"`
			CreatedAt    string `json:"created_at"`
		}
		out := make([]reviewJSON, len(reviews))
		for i, rv := range reviews {
			out[i] = reviewJSON{
				ID: rv.ID, UserID: rv.UserID, Rating: rv.Rating,
				Title: rv.Title, Body: rv.Body,
				HelpfulCount: rv.HelpfulCount, CreatedAt: rv.CreatedAt,
			}
		}
		totalPages := 0
		if perPage > 0 && total > 0 {
			totalPages = (total + perPage - 1) / perPage
		}
		jsonOK(w, http.StatusOK, map[string]any{
			"data": out,
			"meta": paginationMeta{Page: page, PerPage: perPage, Total: total, TotalPages: totalPages},
		})
	}
}

// ── GET /search/trending ──────────────────────────────────────────────────────

func handleSearchTrending() http.HandlerFunc {
	trending := []string{
		"Akıllı telefon", "Laptop", "Kulaklık", "Giyim",
		"Spor ayakkabı", "Çanta", "Parfüm", "Akıllı saat",
	}
	return func(w http.ResponseWriter, _ *http.Request) {
		jsonOK(w, http.StatusOK, map[string]any{"data": trending})
	}
}

// ── POST /favorites/sync ──────────────────────────────────────────────────────
// Auth required. Merges guest local favorites into server user_favorites.

func handleFavoritesSync(pool *pgxpool.Pool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		userID := middleware.UserIDFromCtx(r.Context())
		var req struct {
			ProductIDs []int64 `json:"product_ids"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			jsonError(w, "invalid JSON", http.StatusBadRequest)
			return
		}
		if len(req.ProductIDs) == 0 {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		// Upsert each product_id for the user (ignore duplicates).
		for _, pid := range req.ProductIDs {
			_, err := pool.Exec(r.Context(),
				`INSERT INTO catalog_schema.user_favorites (user_id, product_id)
				 VALUES ($1, $2) ON CONFLICT DO NOTHING`,
				userID, pid,
			)
			if err != nil {
				slog.Error("favorites: sync upsert", "user_id", userID, "product_id", pid, "err", err)
			}
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

