package main

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/mopro/platform/internal/attachments"
	"github.com/mopro/platform/internal/catalog"
	"github.com/mopro/platform/internal/identity"
	"github.com/mopro/platform/internal/identity/middleware"
	"github.com/mopro/platform/pkg/mediaurl"
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

// ── GET /home/stories ─────────────────────────────────────────────────────────
//
// Returns the home-screen "mood stories" strip — a horizontally-scrolled row
// of circular tiles. Locale is resolved from Accept-Language; English clients
// receive title_en, everything else falls back to title_tr (TR launch market).

func handleHomeMoodStories(svc catalog.Service, defaultLocale string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		locale := parseLocale(r, defaultLocale)
		stories, err := svc.HomeMoodStories(r.Context())
		if err != nil {
			slog.Error("home: HomeMoodStories", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		out := make([]map[string]any, len(stories))
		for i, s := range stories {
			title := s.TitleTR
			if locale == "en-US" || locale == "en" {
				title = s.TitleEN
			}
			out[i] = map[string]any{
				"id":         s.ID,
				"title":      title,
				"image_url":  s.ImageURL,
				"deep_link":  s.DeepLink,
				"sort_order": s.SortOrder,
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
		// Layout hint (§6.3): desktop surfaces up to 6 rails, mobile up to 3.
		limit := 3
		if r.URL.Query().Get("layout") == "desktop" {
			limit = 6
		}
		if len(out) > limit {
			out = out[:limit]
		}
		jsonOK(w, http.StatusOK, map[string]any{"data": out})
	}
}

// ── GET /home/flash-deals ─────────────────────────────────────────────────────
//
// Returns the single active flash-deals collection (within its time window),
// or the one given by ?collectionId (admin/preview, ignores the window).
// 204 No Content when there is no active collection; 404 when a requested
// collectionId doesn't exist. Each product carries flash_price_minor.

func handleHomeFlashDeals(svc catalog.Service, defaultLocale, cashbackCurrency string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		locale := parseLocale(r, defaultLocale)
		var collectionID *int64
		if q := r.URL.Query().Get("collectionId"); q != "" {
			id, err := strconv.ParseInt(q, 10, 64)
			if err != nil || id <= 0 {
				jsonError(w, "invalid collectionId", http.StatusBadRequest)
				return
			}
			collectionID = &id
		}
		res, err := svc.HomeFlashDeals(r.Context(), locale, collectionID)
		if err != nil {
			slog.Error("home: HomeFlashDeals", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		if res == nil {
			if collectionID != nil {
				jsonError(w, "collection not found", http.StatusNotFound)
				return
			}
			w.WriteHeader(http.StatusNoContent)
			return
		}
		products := make([]productSummaryJSON, len(res.Products))
		for i, p := range res.Products {
			j := buildProductSummaryJSON(p.Summary, cashbackCurrency)
			fp := p.FlashPriceMinor
			j.FlashPriceMinor = &fp
			products[i] = j
		}
		jsonOK(w, http.StatusOK, map[string]any{
			"id":       res.ID,
			"title":    res.Title,
			"endsAt":   res.EndsAt.UTC().Format(time.RFC3339),
			"products": products,
		})
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

// reviewJSON is the per-review wire shape (camelCase). helpfulCount is the
// denormalized cache; votedByCurrentUser is true only for the viewing user's own
// helpful votes (always false for guests).
type reviewJSON struct {
	ID                 int64    `json:"id"`
	UserID             int64    `json:"userId"`
	ReviewerName       string   `json:"reviewerName"`
	Rating             int      `json:"rating"`
	Title              string   `json:"title"`
	Body               string   `json:"body"`
	PhotoURLs          []string `json:"photoUrls"`
	HelpfulCount       int      `json:"helpfulCount"`
	VotedByCurrentUser bool     `json:"votedByCurrentUser"`
	CreatedAt          string   `json:"createdAt"`
}

// reviewUserNamer is the narrow slice of identity.Service the reviews handler
// needs — the reviewer's display name (masked before it leaves the server).
// GetMe(userID) is the established user-by-id fetch (see ugc displayName); the
// "Me" naming is historical — it takes any userID.
type reviewUserNamer interface {
	GetMe(ctx context.Context, userID int64) (identity.User, error)
}

// reviewPhotoLister is the narrow slice of attachments.Service the reviews
// handler needs — a review's attached photos, in display order.
type reviewPhotoLister interface {
	ListByEntity(ctx context.Context, entityType string, entityID int64) ([]attachments.PhotoAttachment, error)
}

// maskReviewerName renders a display name Trendyol-style ("Ahmet Yılmaz" →
// "A** Y**") so the reviewer is identifiable but not fully exposed. Empty input
// (or a name with no letters) yields "" — the UI shows a generic fallback.
func maskReviewerName(name string) string {
	var parts []string
	for _, w := range strings.Fields(name) {
		r := []rune(w)
		if len(r) == 0 {
			continue
		}
		parts = append(parts, string(r[0])+"**")
	}
	return strings.Join(parts, " ")
}

// handleProductReviews serves GET /products/{id}/reviews with sort + pagination +
// a product-level summary (identical across pages). No auth required, but
// OptionalAuth lets it personalize votedByCurrentUser for signed-in viewers.
func handleProductReviews(svc catalog.Service, namer reviewUserNamer, photos reviewPhotoLister) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		productID, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
		if err != nil || productID <= 0 {
			jsonError(w, "invalid product id", http.StatusBadRequest)
			return
		}

		sortRaw := r.URL.Query().Get("sort")
		if sortRaw == "" {
			sortRaw = string(catalog.ReviewSortNewest)
		}
		sort, ok := catalog.ParseReviewSort(sortRaw)
		if !ok {
			jsonError(w, "invalid sort", http.StatusBadRequest)
			return
		}

		// Strict validation: absent → default; present-but-invalid → 400 (we cannot
		// use parseIntQuery here because it silently coerces 0/invalid to the default).
		page := 1
		if raw := r.URL.Query().Get("page"); raw != "" {
			v, err := strconv.Atoi(raw)
			if err != nil || v < 1 {
				jsonError(w, "page must be >= 1", http.StatusBadRequest)
				return
			}
			page = v
		}

		// Prefer pageSize; accept legacy per_page as an alias for backward compat.
		pageSize := 10
		pageSizeRaw := r.URL.Query().Get("pageSize")
		if pageSizeRaw == "" {
			pageSizeRaw = r.URL.Query().Get("per_page")
		}
		if pageSizeRaw != "" {
			v, err := strconv.Atoi(pageSizeRaw)
			if err != nil || v < 1 || v > 50 {
				jsonError(w, "pageSize must be between 1 and 50", http.StatusBadRequest)
				return
			}
			pageSize = v
		}

		viewerUserID := middleware.UserIDFromCtx(r.Context()) // 0 for guest

		reviews, total, err := svc.ListReviews(r.Context(), productID, sort, page, pageSize, viewerUserID)
		if err != nil {
			slog.Error("catalog: ListReviews", "product_id", productID, "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		summary, err := svc.ReviewsSummary(r.Context(), productID)
		if err != nil {
			slog.Error("catalog: ReviewsSummary", "product_id", productID, "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}

		items := make([]reviewJSON, len(reviews))
		for i, rv := range reviews {
			// Reviewer name (PD-07) — masked; §5-safe identity lookup, never a
			// cross-schema JOIN. A failure never fails the page: log + leave blank.
			var reviewerName string
			if namer != nil {
				if u, uErr := namer.GetMe(r.Context(), rv.UserID); uErr != nil {
					slog.Error("catalog: reviewer name lookup", "user_id", rv.UserID, "err", uErr)
				} else {
					reviewerName = maskReviewerName(u.Name)
				}
			}
			// Review photos (PD-07) — CDN-mapped; §5-safe attachments lookup. Always
			// a non-nil array. A failure never fails the page.
			photoURLs := []string{}
			if photos != nil {
				if atts, pErr := photos.ListByEntity(r.Context(), "review", rv.ID); pErr != nil {
					slog.Error("catalog: review photos lookup", "review_id", rv.ID, "err", pErr)
				} else {
					for _, a := range atts {
						if a.StorageKey != "" {
							photoURLs = append(photoURLs, mediaurl.CDNUrl(a.StorageKey))
						}
					}
				}
			}
			items[i] = reviewJSON{
				ID: rv.ID, UserID: rv.UserID, ReviewerName: reviewerName, Rating: rv.Rating,
				Title: rv.Title, Body: rv.Body, PhotoURLs: photoURLs,
				HelpfulCount: rv.HelpfulCount, VotedByCurrentUser: rv.VotedByCurrentUser,
				CreatedAt: rv.CreatedAt,
			}
		}

		jsonOK(w, http.StatusOK, map[string]any{
			"items":    items,
			"total":    total,
			"page":     page,
			"pageSize": pageSize,
			"summary": map[string]any{
				"average":      summary.Average,
				"distribution": distributionJSON(summary.Distribution),
				"totalCount":   summary.TotalCount,
			},
		})
	}
}

// distributionJSON renders the rating histogram with stable string keys "1".."5".
func distributionJSON(d map[int]int) map[string]int {
	return map[string]int{
		"1": d[1], "2": d[2], "3": d[3], "4": d[4], "5": d[5],
	}
}

// ── POST /products/{id}/reviews/{reviewId}/helpful ────────────────────────────

// handleReviewHelpfulVote toggles the current user's helpful vote on a review.
// Auth is required (wired via requireAuth). Validates that {reviewId} belongs to
// {id} (404 otherwise), then toggles. Returns {helpfulCount, voted}.
func handleReviewHelpfulVote(svc catalog.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		productID, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
		if err != nil || productID <= 0 {
			jsonError(w, "invalid product id", http.StatusBadRequest)
			return
		}
		reviewID, err := strconv.ParseInt(r.PathValue("reviewId"), 10, 64)
		if err != nil || reviewID <= 0 {
			jsonError(w, "invalid review id", http.StatusBadRequest)
			return
		}
		userID := middleware.UserIDFromCtx(r.Context())
		if userID == 0 {
			jsonError(w, "auth_required", http.StatusUnauthorized)
			return
		}

		// The review must exist AND belong to the product in the URL.
		ownerProductID, err := svc.ReviewProductID(r.Context(), reviewID)
		if err != nil {
			if errors.Is(err, catalog.ErrReviewNotFound) {
				jsonError(w, "review not found", http.StatusNotFound)
				return
			}
			slog.Error("catalog: ReviewProductID", "review_id", reviewID, "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		if ownerProductID != productID {
			jsonError(w, "review not found", http.StatusNotFound)
			return
		}

		res, err := svc.ToggleHelpfulVote(r.Context(), reviewID, userID)
		if err != nil {
			slog.Error("catalog: ToggleHelpfulVote", "review_id", reviewID, "user_id", userID, "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		jsonOK(w, http.StatusOK, map[string]any{
			"helpfulCount": res.HelpfulCount,
			"voted":        res.Voted,
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
