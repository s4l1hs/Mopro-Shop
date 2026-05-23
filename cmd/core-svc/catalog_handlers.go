package main

import (
	"errors"
	"log/slog"
	"net/http"
	"strconv"

	"github.com/mopro/platform/internal/catalog"
	"github.com/mopro/platform/pkg/mediaurl"
)

const (
	// referenceInterestRateBps mirrors cashback.ReferenceInterestRateBpsConst.
	// Duplicated here to avoid core-svc importing fin-svc packages.
	referenceInterestRateBps = 5000
)

// handleListCategories returns all active categories with locale-resolved name.
// GET /v1/categories
func handleListCategories(svc catalog.Service, defaultLocale string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		locale := parseLocale(r, defaultLocale)
		cats, err := svc.ListCategories(r.Context(), locale)
		if err != nil {
			slog.Error("catalog: ListCategories", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		jsonOK(w, http.StatusOK, buildCategoryListResponse(cats))
	}
}

// handleListProducts handles GET /v1/products?category_id=X&page=1&per_page=20
func handleListProducts(svc catalog.Service, defaultLocale, defaultMarket, cashbackCurrency string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		q := r.URL.Query()
		categoryIDStr := q.Get("category_id")
		if categoryIDStr == "" {
			jsonError(w, "category_id required", http.StatusBadRequest)
			return
		}
		categoryID, err := strconv.ParseInt(categoryIDStr, 10, 64)
		if err != nil || categoryID <= 0 {
			jsonError(w, "invalid category_id", http.StatusBadRequest)
			return
		}

		page := parseIntQuery(q.Get("page"), 1)
		perPage := parseIntQuery(q.Get("per_page"), 20)
		if perPage > 50 {
			perPage = 50
		}

		locale := parseLocale(r, defaultLocale)
		market := q.Get("market")
		if market == "" {
			market = defaultMarket
		}

		rows, total, err := svc.ListProductsByCategory(r.Context(), categoryID, locale, market, page, perPage)
		if err != nil {
			slog.Error("catalog: ListProductsByCategory", "category_id", categoryID, "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}

		jsonOK(w, http.StatusOK, buildProductListResponse(rows, total, page, perPage, cashbackCurrency))
	}
}

// handleSearch handles GET /v1/search?q=...&page=1&per_page=20
func handleSearch(svc catalog.Service, defaultLocale, defaultMarket, cashbackCurrency string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		q := r.URL.Query()
		query := q.Get("q")
		if query == "" {
			jsonError(w, "q required", http.StatusBadRequest)
			return
		}

		page := parseIntQuery(q.Get("page"), 1)
		perPage := parseIntQuery(q.Get("per_page"), 20)
		if perPage > 50 {
			perPage = 50
		}

		locale := parseLocale(r, defaultLocale)
		market := q.Get("market")
		if market == "" {
			market = defaultMarket
		}

		rows, total, err := svc.SearchSummary(r.Context(), query, locale, market, page, perPage)
		if err != nil {
			slog.Error("catalog: SearchSummary", "query", query, "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}

		jsonOK(w, http.StatusOK, buildProductListResponse(rows, total, page, perPage, cashbackCurrency))
	}
}

// handleGetProductDetail handles GET /v1/products/{id} with cashback_preview.
// Replaces the original stub in main.go (wired separately).
func handleGetProductDetail(svc catalog.Service, defaultMarket, cashbackCurrency string) http.HandlerFunc {
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
			slog.Error("catalog: GetByID", "id", id, "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}

		market := r.URL.Query().Get("market")
		if market == "" {
			market = defaultMarket
		}

		// Compute cashback preview from the cheapest variant + category commission.
		var cashbackPreview *cashbackPreviewJSON
		cheapest := cheapestVariant(variants)
		if cheapest != nil {
			comm, commErr := svc.GetCommissionForCategory(r.Context(), market, p.CategoryID)
			if commErr == nil {
				commMinor := cheapest.PriceMinor * int64(comm.CommissionPctBps) / 10000
				yearlyYield := commMinor * referenceInterestRateBps / 10000
				monthlyMinor := yearlyYield / 12
				cashbackPreview = &cashbackPreviewJSON{
					MonthlyAmountMinor: monthlyMinor,
					Currency:           cashbackCurrency,
					ReferenceRateBps:   referenceInterestRateBps,
					CommissionPctBps:   comm.CommissionPctBps,
				}
			}
		}

		// Enrich variants with CDN image URLs.
		type variantOut struct {
			catalog.Variant
			CoverImageURL string `json:"cover_image_url,omitempty"`
		}
		variantsOut := make([]variantOut, len(variants))
		for i, v := range variants {
			vo := variantOut{Variant: v}
			if len(v.ImageKeys) > 0 {
				vo.CoverImageURL = mediaurl.CDNUrl(v.ImageKeys[0])
			}
			variantsOut[i] = vo
		}

		jsonOK(w, http.StatusOK, map[string]any{
			"product":          p,
			"variants":         variantsOut,
			"translations":     translations,
			"cashback_preview": cashbackPreview,
		})
	}
}

// handleListBanners is a 200-empty stub. GET /v1/banners
func handleListBanners() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		slog.Debug("banners: stub called")
		jsonOK(w, http.StatusOK, map[string]any{"data": []any{}})
	}
}

// handleListRecommendations is a 200-empty stub. GET /v1/recommendations
func handleListRecommendations() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		slog.Debug("recommendations: stub called")
		jsonOK(w, http.StatusOK, map[string]any{"data": []any{}})
	}
}

// ── helpers ───────────────────────────────────────────────────────────────────

type cashbackPreviewJSON struct {
	MonthlyAmountMinor int64  `json:"monthly_amount_minor"`
	Currency           string `json:"currency"`
	ReferenceRateBps   int    `json:"reference_rate_bps"`
	CommissionPctBps   int    `json:"commission_pct_bps"`
}

type paginationMeta struct {
	Page       int `json:"page"`
	PerPage    int `json:"per_page"`
	Total      int `json:"total"`
	TotalPages int `json:"total_pages"`
}

type productSummaryJSON struct {
	ID               int64  `json:"id"`
	SellerID         int64  `json:"seller_id"`
	CategoryID       int64  `json:"category_id"`
	Brand            string `json:"brand"`
	Status           string `json:"status"`
	Title            string `json:"title"`
	PriceMinor       int64  `json:"price_minor"`
	PriceCurrency    string `json:"price_currency"`
	CoverImageURL    string `json:"cover_image_url,omitempty"`
	CommissionPctBps int    `json:"commission_pct_bps"`

	CashbackPreview cashbackPreviewJSON `json:"cashback_preview"`
}

func buildProductListResponse(rows []catalog.ProductSummaryRow, total, page, perPage int, cashbackCurrency string) map[string]any {
	out := make([]productSummaryJSON, len(rows))
	for i, r := range rows {
		commMinor := r.PriceMinor * int64(r.CommissionPctBps) / 10000
		yearlyYield := commMinor * referenceInterestRateBps / 10000
		monthlyMinor := yearlyYield / 12
		out[i] = productSummaryJSON{
			ID:               r.ID,
			SellerID:         r.SellerID,
			CategoryID:       r.CategoryID,
			Brand:            r.Brand,
			Status:           r.Status,
			Title:            r.Title,
			PriceMinor:       r.PriceMinor,
			PriceCurrency:    r.PriceCurrency,
			CoverImageURL:    mediaurl.CDNUrl(r.CoverImageKey),
			CommissionPctBps: r.CommissionPctBps,

			CashbackPreview: cashbackPreviewJSON{

				MonthlyAmountMinor: monthlyMinor,

				Currency: cashbackCurrency,

				ReferenceRateBps: referenceInterestRateBps,

				CommissionPctBps: r.CommissionPctBps,
			},
		}
	}
	totalPages := 0
	if perPage > 0 && total > 0 {
		totalPages = (total + perPage - 1) / perPage
	}
	return map[string]any{
		"data": out,
		"meta": paginationMeta{
			Page:       page,
			PerPage:    perPage,
			Total:      total,
			TotalPages: totalPages,
		},
	}
}

func cheapestVariant(variants []catalog.Variant) *catalog.Variant {
	if len(variants) == 0 {
		return nil
	}
	best := &variants[0]
	for i := range variants[1:] {
		if variants[i+1].PriceMinor < best.PriceMinor {
			best = &variants[i+1]
		}
	}
	return best
}

func parseIntQuery(s string, def int) int {
	if s == "" {
		return def
	}
	v, err := strconv.Atoi(s)
	if err != nil || v < 1 {
		return def
	}
	return v
}

type categoryJSON struct {
	ID               int64  `json:"id"`
	Slug             string `json:"slug"`
	Name             string `json:"name"`
	ParentID         *int64 `json:"parent_id"`
	CommissionPctBps int    `json:"commission_pct_bps"`
}

func buildCategoryListResponse(rows []catalog.CategoryRow) map[string]any {
	out := make([]categoryJSON, len(rows))
	for i, r := range rows {
		out[i] = categoryJSON{
			ID:               r.ID,
			Slug:             r.Slug,
			Name:             r.Name,
			ParentID:         r.ParentID,
			CommissionPctBps: r.CommissionPctBps,
		}
	}
	return map[string]any{"data": out}
}
