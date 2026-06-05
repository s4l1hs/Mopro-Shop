package main

import (
	"errors"
	"log/slog"
	"net/http"
	"strconv"
	"strings"

	"github.com/mopro/platform/internal/catalog"
	"github.com/mopro/platform/internal/identity/middleware"
	"github.com/mopro/platform/internal/order"
	"github.com/mopro/platform/internal/seller"
)

// resolveBio picks the seller bio for the request locale, falling back to the
// locale's base language, then English, then any present translation. de/ar
// fall back to en per the Tranche 2b content rule.
func resolveBio(translations map[string]string, locale string) string {
	if translations == nil {
		return ""
	}
	if v, ok := translations[locale]; ok && v != "" {
		return v
	}
	if base := strings.SplitN(locale, "-", 2)[0]; base != locale {
		if v, ok := translations[base]; ok && v != "" {
			return v
		}
	}
	if v, ok := translations["en"]; ok && v != "" {
		return v
	}
	for _, v := range translations {
		if v != "" {
			return v
		}
	}
	return ""
}

func sellerProfileJSON(s seller.Seller, bio string, ratingAvg float64, ratingCount int) map[string]any {
	return map[string]any{
		"id":               s.ID,
		"slug":             s.Slug,
		"display_name":     s.DisplayName,
		"bio":              bio,
		"logo_image_url":   s.LogoImageURL,
		"banner_image_url": s.BannerImageURL,
		"contact_email":    s.ContactEmail,
		"created_at":       s.CreatedAt,
		"rating_avg":       ratingAvg,
		"rating_count":     ratingCount,
	}
}

// ── Public storefront ─────────────────────────────────────────────────────────

// handleSellerStorefront: GET /sellers/{slug} — public profile + review summary.
func handleSellerStorefront(sellerSvc seller.Service, reader catalog.SellerStorefrontReader, defaultLocale string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		slug := r.PathValue("slug")
		s, err := sellerSvc.GetBySlug(r.Context(), slug)
		if err != nil {
			if errors.Is(err, seller.ErrSellerNotFound) {
				jsonError(w, "seller not found", http.StatusNotFound)
				return
			}
			slog.Error("seller: GetBySlug", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		avg, count, err := reader.SellerReviewSummary(r.Context(), s.ID)
		if err != nil {
			slog.Error("seller: SellerReviewSummary", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		bio := resolveBio(s.BioTranslations, parseLocale(r, defaultLocale))
		jsonOK(w, http.StatusOK, map[string]any{"seller": sellerProfileJSON(s, bio, avg, count)})
	}
}

// handleSellerStorefrontProducts: GET /sellers/{slug}/products — paginated active products.
func handleSellerStorefrontProducts(sellerSvc seller.Service, reader catalog.SellerStorefrontReader, defaultLocale, cashbackCurrency string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		s, err := sellerSvc.GetBySlug(r.Context(), r.PathValue("slug"))
		if err != nil {
			if errors.Is(err, seller.ErrSellerNotFound) {
				jsonError(w, "seller not found", http.StatusNotFound)
				return
			}
			slog.Error("seller: GetBySlug", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		page := parseIntQuery(r.URL.Query().Get("page"), 1)
		perPage := parseIntQuery(r.URL.Query().Get("per_page"), 20)
		if perPage > 50 {
			perPage = 50
		}
		locale := parseLocale(r, defaultLocale)
		rows, total, err := reader.ListProductsBySeller(r.Context(), s.ID, locale, perPage, (page-1)*perPage)
		if err != nil {
			slog.Error("seller: ListProductsBySeller", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		jsonOK(w, http.StatusOK, buildProductListResponse(rows, total, page, perPage, cashbackCurrency))
	}
}

// handleSellerStorefrontReviews: GET /sellers/{slug}/reviews — reviews across the seller's products.
func handleSellerStorefrontReviews(sellerSvc seller.Service, reader catalog.SellerStorefrontReader, defaultLocale string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		s, err := sellerSvc.GetBySlug(r.Context(), r.PathValue("slug"))
		if err != nil {
			if errors.Is(err, seller.ErrSellerNotFound) {
				jsonError(w, "seller not found", http.StatusNotFound)
				return
			}
			slog.Error("seller: GetBySlug", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		page := parseIntQuery(r.URL.Query().Get("page"), 1)
		perPage := parseIntQuery(r.URL.Query().Get("per_page"), 20)
		if perPage > 50 {
			perPage = 50
		}
		locale := parseLocale(r, defaultLocale)
		items, total, err := reader.ListSellerReviews(r.Context(), s.ID, locale, perPage, (page-1)*perPage)
		if err != nil {
			slog.Error("seller: ListSellerReviews", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		jsonOK(w, http.StatusOK, map[string]any{
			"data": items, "total": total, "page": page, "hasMore": page*perPage < total,
		})
	}
}

// ── Seller dashboard: returns inbox (role-gated) ───────────────────────────────

// handleSellerReturns: GET /seller/returns — returns on the seller's products.
func handleSellerReturns(reader catalog.SellerStorefrontReader, returnSvc order.ReturnService) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		sellerID := middleware.SellerIDFromCtx(r.Context())
		productIDs, err := reader.ProductIDsBySeller(r.Context(), sellerID)
		if err != nil {
			slog.Error("seller: ProductIDsBySeller", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		status := r.URL.Query().Get("status") // "" = all
		limit := atoiDefault(r.URL.Query().Get("limit"), 20)
		offset := atoiDefault(r.URL.Query().Get("offset"), 0)
		recs, err := returnSvc.ListSellerReturns(r.Context(), productIDs, status, limit+1, offset)
		if err != nil {
			slog.Error("seller: ListSellerReturns", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		hasMore := len(recs) > limit
		if hasMore {
			recs = recs[:limit]
		}
		data := make([]map[string]any, 0, len(recs))
		for _, rec := range recs {
			data = append(data, map[string]any{
				"id":                  rec.ID,
				"order_id":            rec.OrderID,
				"status":              rec.Status,
				"reason":              rec.Reason,
				"description":         rec.Description,
				"refund_amount_minor": rec.RefundAmountMinor,
				"refund_currency":     rec.RefundCurrency,
				"created_at":          rec.CreatedAt,
			})
		}
		jsonOK(w, http.StatusOK, map[string]any{"data": data, "hasMore": hasMore})
	}
}

// sellerReturnTransition is the shared approve/reject path: resolve the seller's
// product ids, then transition with seller-ownership scoping.
func sellerReturnTransition(
	w http.ResponseWriter, r *http.Request,
	reader catalog.SellerStorefrontReader,
	do func(productIDs []int64, returnID int64) (order.Return, error),
) {
	sellerID := middleware.SellerIDFromCtx(r.Context())
	returnID, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		jsonError(w, "invalid return id", http.StatusBadRequest)
		return
	}
	productIDs, err := reader.ProductIDsBySeller(r.Context(), sellerID)
	if err != nil {
		slog.Error("seller: ProductIDsBySeller", "err", err)
		jsonError(w, "internal error", http.StatusInternalServerError)
		return
	}
	rec, err := do(productIDs, returnID)
	if err != nil {
		switch {
		case errors.Is(err, order.ErrReturnNotFound), errors.Is(err, order.ErrReturnNotOwned):
			jsonError(w, "return not found", http.StatusNotFound) // do not leak other sellers' returns
		case errors.Is(err, order.ErrReturnNotPending):
			jsonError(w, "return is not pending", http.StatusConflict)
		default:
			slog.Error("seller: return transition", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
		}
		return
	}
	jsonOK(w, http.StatusOK, map[string]any{
		"id": rec.ID, "order_id": rec.OrderID, "status": rec.Status,
	})
}

// handleSellerApproveReturn: POST /seller/returns/{id}/approve.
func handleSellerApproveReturn(reader catalog.SellerStorefrontReader, returnSvc order.ReturnService) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !requireIdempotencyKey(w, r) {
			return
		}
		sellerReturnTransition(w, r, reader, func(pids []int64, id int64) (order.Return, error) {
			return returnSvc.SellerApprove(r.Context(), id, pids)
		})
	}
}

// handleUpdateVariantPrice: PUT /seller/variants/{id}/price — a seller updates the
// price (+ optional strikethrough original) of a variant they own (P-032). The #92
// variants_price_history_trg records the change in variant_price_history. Ownership
// is enforced in the repository (ErrVariantNotFound => 404, no existence leak).
func handleUpdateVariantPrice(svc catalog.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !requireIdempotencyKey(w, r) {
			return
		}
		sellerID := middleware.SellerIDFromCtx(r.Context())
		variantID, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
		if err != nil {
			jsonError(w, "invalid variant id", http.StatusBadRequest)
			return
		}
		var req catalog.UpdateVariantPriceRequest
		if err := decodeJSON(w, r, &req); err != nil {
			return
		}
		req.VariantID = variantID
		switch err := svc.UpdateVariantPrice(r.Context(), sellerID, req); {
		case err == nil:
			jsonOK(w, http.StatusOK, map[string]any{
				"variant_id":           variantID,
				"price_minor":          req.PriceMinor,
				"original_price_minor": req.OriginalPriceMinor,
			})
		case errors.Is(err, catalog.ErrInvalidPrice):
			jsonError(w, "invalid price (price must be > 0; original >= price)", http.StatusUnprocessableEntity)
		case errors.Is(err, catalog.ErrVariantNotFound):
			jsonError(w, "variant not found", http.StatusNotFound) // do not leak other sellers' variants
		default:
			slog.Error("seller: UpdateVariantPrice", "variant_id", variantID, "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
		}
	}
}

// handleSellerRejectReturn: POST /seller/returns/{id}/reject.
func handleSellerRejectReturn(reader catalog.SellerStorefrontReader, returnSvc order.ReturnService) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if !requireIdempotencyKey(w, r) {
			return
		}
		var body struct {
			ReasonCode string `json:"reason_code"`
			Note       string `json:"note"`
		}
		if err := decodeJSON(w, r, &body); err != nil {
			return
		}
		sellerReturnTransition(w, r, reader, func(pids []int64, id int64) (order.Return, error) {
			return returnSvc.SellerReject(r.Context(), id, pids, body.ReasonCode, body.Note)
		})
	}
}

// ── Seller dashboard: Q&A inbox (role-gated) ───────────────────────────────────

// handleSellerQuestions: GET /seller/questions — questions on the seller's
// products; ?unanswered=true filters to those without a seller answer.
func handleSellerQuestions(reader catalog.SellerStorefrontReader, qaSvc catalog.QAService) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		sellerID := middleware.SellerIDFromCtx(r.Context())
		productIDs, err := reader.ProductIDsBySeller(r.Context(), sellerID)
		if err != nil {
			slog.Error("seller: ProductIDsBySeller", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		onlyUnanswered := r.URL.Query().Get("unanswered") == "true"
		page := atoiDefault(r.URL.Query().Get("page"), 1)
		pageSize := atoiDefault(r.URL.Query().Get("pageSize"), 20)
		items, total, err := qaSvc.ListSellerQuestions(r.Context(), productIDs, onlyUnanswered, pageSize, (page-1)*pageSize)
		if err != nil {
			slog.Error("seller: ListSellerQuestions", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		if items == nil {
			items = []catalog.Question{}
		}
		jsonOK(w, http.StatusOK, map[string]any{
			"data": items, "total": total, "page": page, "hasMore": page*pageSize < total,
		})
	}
}
