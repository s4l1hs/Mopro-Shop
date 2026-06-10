package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/mopro/platform/internal/analytics"
	"github.com/mopro/platform/internal/catalog"
	"github.com/mopro/platform/internal/seller"
	"github.com/mopro/platform/internal/shipping"
	"github.com/mopro/platform/pkg/mediaurl"
)

const (
	// referenceInterestRateBps mirrors cashback.ReferenceInterestRateBpsConst.
	// Duplicated here to avoid core-svc importing fin-svc packages.
	referenceInterestRateBps = 5000
)

// handleListCategories returns active categories with locale-resolved name.
// GET /categories[?depth=N]
//
// Optional `depth` query param (Session 4c §3) filters the response to
// categories whose chain length to a root parent is at most N. Valid range
// 1..3; out-of-range values return 400 bad_request. Omitting the param
// preserves the historical "return all depths" behavior (mobile callers
// rely on this — do not change the default).
func handleListCategories(svc catalog.Service, defaultLocale string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		locale := parseLocale(r, defaultLocale)

		maxDepth := 0 // 0 = no limit
		if raw := r.URL.Query().Get("depth"); raw != "" {
			n, err := strconv.Atoi(raw)
			if err != nil || n < 1 || n > 3 {
				jsonError(w, "bad_request: depth must be an integer in [1,3]", http.StatusBadRequest)
				return
			}
			maxDepth = n
		}

		cats, err := svc.ListCategories(r.Context(), locale, maxDepth)
		if err != nil {
			slog.Error("catalog: ListCategories", "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		jsonOK(w, http.StatusOK, buildCategoryListResponse(cats))
	}
}

// handleCategoryFacets serves GET /categories/{id}/facets — the PLP-13 facet
// aggregation: for each facetable attribute of the category (+ its PLP-12
// subtree), the (value, count) buckets. The first real facet-aggregation surface
// (brands are derived from the result set; this is server-computed).
func handleCategoryFacets(svc catalog.Service, defaultLocale string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
		if err != nil || id <= 0 {
			jsonError(w, "invalid category id", http.StatusBadRequest)
			return
		}
		facets, err := svc.FacetsByCategory(r.Context(), id, parseLocale(r, defaultLocale))
		if err != nil {
			slog.Error("catalog: FacetsByCategory", "category_id", id, "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}
		jsonOK(w, http.StatusOK, map[string]any{"facets": facets})
	}
}

// bestsellerPopularCap bounds how many globally-popular product IDs the
// bestseller sort seeds (caps the array_position cost per row).
const bestsellerPopularCap = 200

// applyBestsellerOrder fills filter.PopularIDs with a popularity ranking (from
// analytics) when sort=bestseller, so the repo orders by it (P-029). With a
// category filter it uses per-category popularity (P-031), falling back to the
// global proxy on empty; with no category it uses global. On error/empty the
// filter is left as-is → the repo falls back to recommended.
// categoryID scopes the popularity ranking (the category PLP's category, or the
// search category filter); nil = global. It is passed explicitly because the
// category-PLP handler keeps it out of ProductFilter (the base query already
// scopes by category).
func applyBestsellerOrder(ctx context.Context, analyticsSvc analytics.Service, categoryID *int64, filter *catalog.ProductFilter) {
	if filter.Sort != "bestseller" {
		return
	}
	var ids []int64
	var err error
	if categoryID != nil {
		// Per-category popularity (P-031). Most categories have no per-category
		// data until product_view events carrying categoryId (P-033) accrue, so
		// fall back to the global proxy on empty — never regress to recommended.
		ids, err = analyticsSvc.PopularProductIDsInCategory(ctx, *categoryID, bestsellerPopularCap)
		if err == nil && len(ids) == 0 {
			ids, err = analyticsSvc.PopularProductIDs(ctx, bestsellerPopularCap)
		}
	} else {
		ids, err = analyticsSvc.PopularProductIDs(ctx, bestsellerPopularCap)
	}
	if err != nil {
		slog.Warn("catalog: bestseller popular IDs unavailable", "err", err)
		return
	}
	filter.PopularIDs = ids
}

// handleListProducts handles GET /products?category_id=X&page=1&per_page=20
func handleListProducts(analyticsSvc analytics.Service, svc catalog.Service, defaultLocale, defaultMarket, cashbackCurrency string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		q := r.URL.Query()

		// category_id is OPTIONAL (OpenAPI FilterCategoryId is required:false).
		// Present → category-scoped PLP; absent → the global, catalog-wide listing
		// the server-driven Home rails (recommended / bestseller / newest) need. A
		// present-but-malformed value is still a 400 (category-scoped validation
		// is unchanged for callers that pass one).
		var categoryID *int64
		if categoryIDStr := q.Get("category_id"); categoryIDStr != "" {
			id, err := strconv.ParseInt(categoryIDStr, 10, 64)
			if err != nil || id <= 0 {
				jsonError(w, "invalid category_id", http.StatusBadRequest)
				return
			}
			categoryID = &id
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

		filter := parseProductFilter(q, false)
		// nil categoryID → global bestseller popularity (applyBestsellerOrder
		// already handles the nil case).
		applyBestsellerOrder(r.Context(), analyticsSvc, categoryID, &filter)

		var (
			rows  []catalog.ProductSummaryRow
			total int
			err   error
		)
		if categoryID != nil {
			rows, total, err = svc.ListProductsByCategory(r.Context(), *categoryID, locale, market, filter, page, perPage)
		} else {
			rows, total, err = svc.ListProducts(r.Context(), locale, market, filter, page, perPage)
		}
		if err != nil {
			slog.Error("catalog: list products", "category_id", categoryID, "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}

		jsonOK(w, http.StatusOK, buildProductListResponse(rows, total, page, perPage, cashbackCurrency))
	}
}

// handleSearch handles GET /search?q=...&page=1&per_page=20
func handleSearch(analyticsSvc analytics.Service, svc catalog.Service, defaultLocale, defaultMarket, cashbackCurrency string) http.HandlerFunc {
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

		filter := parseProductFilter(q, true)
		applyBestsellerOrder(r.Context(), analyticsSvc, filter.CategoryID, &filter)
		rows, total, err := svc.SearchSummary(r.Context(), query, locale, market, filter, page, perPage)
		if err != nil {
			slog.Error("catalog: SearchSummary", "query", query, "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}

		jsonOK(w, http.StatusOK, buildProductListResponse(rows, total, page, perPage, cashbackCurrency))
	}
}

// handleSearchSuggest serves GET /search/suggest?q= (SE-06): structured brand +
// product autocomplete for the search dropdown. Products reuse the ProductSummary
// shape (same as /search) so the dropdown can route to PDP; brands route to the
// brand-filtered listing. Both come from catalog_schema (§5-safe). Limits are
// small (top brands + top products) — this is a type-ahead surface, not a listing.
func handleSearchSuggest(svc catalog.Service, defaultLocale, cashbackCurrency string) http.HandlerFunc {
	const (
		brandLimit   = 5
		productLimit = 6
	)
	return func(w http.ResponseWriter, r *http.Request) {
		q := strings.TrimSpace(r.URL.Query().Get("q"))
		if q == "" {
			jsonError(w, "q required", http.StatusBadRequest)
			return
		}
		locale := parseLocale(r, defaultLocale)

		res, err := svc.Suggest(r.Context(), q, locale, brandLimit, productLimit)
		if err != nil {
			slog.Error("catalog: Suggest", "query", q, "err", err)
			jsonError(w, "internal error", http.StatusInternalServerError)
			return
		}

		products := make([]productSummaryJSON, len(res.Products))
		for i, p := range res.Products {
			products[i] = buildProductSummaryJSON(p, cashbackCurrency)
		}
		brands := res.Brands
		if brands == nil {
			brands = []catalog.BrandSuggestion{}
		}

		jsonOK(w, http.StatusOK, map[string]any{
			"brands":   brands,
			"products": products,
		})
	}
}

// parseProductFilter extracts the optional catalog filter + sort knobs (P-028)
// from the query string. Invalid/absent values are simply omitted (no error) —
// the listing degrades to "no constraint on that dimension". When
// includeCategory is true (search), an optional category_id filter is parsed
// too (on /products the category is the dedicated required arg). The raw sort
// token is passed through; the repository maps unknown tokens to recommended.
func parseProductFilter(q url.Values, includeCategory bool) catalog.ProductFilter {
	f := catalog.ProductFilter{Sort: q.Get("sort")}
	if includeCategory {
		if v, err := strconv.ParseInt(q.Get("category_id"), 10, 64); err == nil && v > 0 {
			f.CategoryID = &v
		}
	}
	if v, err := strconv.ParseInt(q.Get("min_price"), 10, 64); err == nil && v >= 0 {
		f.MinPriceMinor = &v
	}
	if v, err := strconv.ParseInt(q.Get("max_price"), 10, 64); err == nil && v >= 0 {
		f.MaxPriceMinor = &v
	}
	if brands := q["brand"]; len(brands) > 0 {
		f.Brands = brands
	}
	if v, err := strconv.Atoi(q.Get("rating")); err == nil && v >= 1 && v <= 5 {
		f.MinRating = &v
	}
	if q.Get("free_shipping") == "true" {
		t := true
		f.FreeShipping = &t
	}
	if q.Get("in_stock") == "true" {
		t := true
		f.InStock = &t
	}
	if q.Get("price_dropped") == "true" {
		t := true
		f.PriceDropped = &t
	}
	// PLP-13 attribute filter: repeated ?attr=<slug>:<value> (e.g. attr=renk:Siyah
	// &attr=renk:Beyaz) → map[slug][]values. Malformed entries (no ':' or empty
	// slug/value) are skipped.
	if raw := q["attr"]; len(raw) > 0 {
		attrs := make(map[string][]string)
		for _, e := range raw {
			slug, val, ok := strings.Cut(e, ":")
			if !ok || slug == "" || val == "" {
				continue
			}
			attrs[slug] = append(attrs[slug], val)
		}
		if len(attrs) > 0 {
			f.Attrs = attrs
		}
	}
	return f
}

// handleGetProductDetail handles GET /products/{id} with cashback_preview.
// Replaces the original stub in main.go (wired separately).
// deliveryEstimator is the narrow read-only slice of shipping.Service the PDP
// needs for the pre-purchase delivery estimate (P-034). Kept local so the catalog
// handler depends only on EstimateETA, not the full carrier surface.
type deliveryEstimator interface {
	EstimateETA(ctx context.Context, market, originCity string, destCity *string) (shipping.ETAResult, error)
}

func handleGetProductDetail(svc catalog.Service, sellerSvc seller.Service, etaSvc deliveryEstimator, defaultLocale, defaultMarket, cashbackCurrency string) http.HandlerFunc {
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
					MonthlyCoinMinor: monthlyMinor,
					Currency:         cashbackCurrency,
				}
			}
		}

		// Variants: emit the spec Variant shape — image_urls is the CDN-resolved
		// gallery (mediaurl.CDNUrl over every image_key), NOT raw image_keys (PD-06).
		variantsOut := make([]variantDetailJSON, len(variants))
		for i, v := range variants {
			variantsOut[i] = variantDetailJSON{
				ID:                  v.ID,
				SKU:                 v.SKU,
				Color:               v.Color,
				Size:                v.Size,
				PriceMinor:          v.PriceMinor,
				PriceCurrency:       v.PriceCurrency,
				Stock:               v.Stock,
				ImageURLs:           cdnURLs(v.ImageKeys),
				OriginalPriceMinor:  v.OriginalPriceMinor,
				Lowest30dPriceMinor: v.Lowest30dPriceMinor,
			}
		}

		// Resolve the seller for storefront deep-linking. seller_name is required
		// by the Product schema; seller_slug is nullable — both empty/null when the
		// product's seller_id doesn't resolve to an active seller (pre-5a data or a
		// suspended seller).
		var sellerName string
		var sellerSlug *string
		var originCity string
		if s, sErr := sellerSvc.GetByID(r.Context(), p.SellerID); sErr == nil {
			sellerName = s.DisplayName
			slug := s.Slug
			sellerSlug = &slug
			if s.DispatchCity != nil {
				originCity = *s.DispatchCity
			}
		} else if !errors.Is(sErr, seller.ErrSellerNotFound) {
			slog.Error("catalog: resolve seller for product", "seller_id", p.SellerID, "err", sErr)
		}

		// Pre-purchase delivery estimate (P-034). dest_city is optional — the
		// client passes the user's selected delivery city when known; absent (a
		// guest) yields the conservative national fallback. A failure here never
		// fails the PDP: we log and omit the line.
		var deliveryETA *deliveryEtaJSON
		if etaSvc != nil {
			var destCity *string
			if dc := r.URL.Query().Get("dest_city"); dc != "" {
				destCity = &dc
			}
			if eta, etaErr := etaSvc.EstimateETA(r.Context(), market, originCity, destCity); etaErr != nil {
				slog.Error("catalog: estimate delivery eta", "product_id", id, "err", etaErr)
			} else if eta.MaxDays > 0 {
				deliveryETA = &deliveryEtaJSON{
					MinDays:   eta.MinDays,
					MaxDays:   eta.MaxDays,
					Confident: eta.Confident,
				}
				if originCity != "" {
					deliveryETA.DispatchCity = &originCity
				}
			}
		}

		// title/description are locale-resolved server-side (the Product schema's
		// contract) from the product translations; the legacy response leaked the
		// raw translations array, which the spec + mobile client do not carry.
		title, description := resolveTranslation(translations, parseLocale(r, defaultLocale), defaultLocale)

		// Normalized attributes for the PDP specs tab (PLP-13 / PD-01). A failure
		// here never fails the PDP — log and return an empty list.
		attributes, attrErr := svc.ProductAttributes(r.Context(), id, parseLocale(r, defaultLocale))
		if attrErr != nil {
			slog.Error("catalog: ProductAttributes", "id", id, "err", attrErr)
		}
		if attributes == nil {
			attributes = []catalog.ProductAttribute{} // spec-required array — never null
		}

		// Flat, spec-conformant Product (PD-06): the previous {product, variants,
		// translations, …} envelope did not match the OpenAPI Product schema (nor
		// the generated mobile client), so the PDP could not parse it.
		jsonOK(w, http.StatusOK, productDetailJSON{
			ID:              p.ID,
			SellerID:        p.SellerID,
			SellerName:      sellerName,
			SellerSlug:      sellerSlug,
			CategoryID:      p.CategoryID,
			Brand:           p.Brand,
			Status:          p.Status,
			Title:           title,
			Description:     description,
			Variants:        variantsOut,
			Attributes:      attributes,
			CashbackPreview: cashbackPreview,
			DeliveryEta:     deliveryETA,
			CreatedAt:       p.CreatedAt.Format(time.RFC3339),
		})
	}
}

// productDetailJSON is the flat, spec-conformant GET /products/{id} 200 body
// (OpenAPI Product). It replaces the legacy {product, variants, translations, …}
// envelope (PD-06) that neither the spec nor the generated mobile client matched.
type productDetailJSON struct {
	ID              int64                      `json:"id"`
	SellerID        int64                      `json:"seller_id"`
	SellerName      string                     `json:"seller_name"`
	SellerSlug      *string                    `json:"seller_slug"`
	CategoryID      int64                      `json:"category_id"`
	Brand           string                     `json:"brand"`
	Status          string                     `json:"status"`
	Title           string                     `json:"title"`
	Description     string                     `json:"description"`
	Variants        []variantDetailJSON        `json:"variants"`
	Attributes      []catalog.ProductAttribute `json:"attributes"`
	CashbackPreview *cashbackPreviewJSON       `json:"cashback_preview"`
	DeliveryEta     *deliveryEtaJSON           `json:"delivery_eta"`
	CreatedAt       string                     `json:"created_at"`
}

// variantDetailJSON is the spec Variant: image_urls is the CDN-resolved gallery
// (never raw storage keys). color/size are emitted as-is (spec nullable string).
type variantDetailJSON struct {
	ID                  int64    `json:"id"`
	SKU                 string   `json:"sku"`
	Color               string   `json:"color"`
	Size                string   `json:"size"`
	PriceMinor          int64    `json:"price_minor"`
	PriceCurrency       string   `json:"price_currency"`
	Stock               int      `json:"stock"`
	ImageURLs           []string `json:"image_urls"`
	OriginalPriceMinor  *int64   `json:"original_price_minor,omitempty"`
	Lowest30dPriceMinor *int64   `json:"lowest_30d_price_minor,omitempty"`
}

// cdnURLs maps raw storage keys to CDN-resolved URLs (mediaurl.CDNUrl), always
// returning a non-nil slice so the spec-required image_urls array is present.
func cdnURLs(keys []string) []string {
	out := make([]string, 0, len(keys))
	for _, k := range keys {
		if k != "" {
			out = append(out, mediaurl.CDNUrl(k))
		}
	}
	return out
}

// resolveTranslation picks a product's title/description for the requested
// locale, falling back to the default locale, then the first available — so the
// spec-required title/description are always populated when any translation exists.
func resolveTranslation(translations []catalog.ProductTranslation, locale, fallback string) (title, description string) {
	var fb *catalog.ProductTranslation
	for i := range translations {
		if translations[i].Locale == locale {
			return translations[i].Title, translations[i].Description
		}
		if translations[i].Locale == fallback {
			fb = &translations[i]
		}
	}
	if fb != nil {
		return fb.Title, fb.Description
	}
	if len(translations) > 0 {
		return translations[0].Title, translations[0].Description
	}
	return "", ""
}

// handleListBanners is a 200-empty stub. GET /banners
func handleListBanners() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		slog.Debug("banners: stub called")
		jsonOK(w, http.StatusOK, map[string]any{"data": []any{}})
	}
}

// ── helpers ───────────────────────────────────────────────────────────────────

// cashbackPreviewJSON is the OpenAPI CashbackPreview wire shape:
// {monthly_coin_minor, currency} ONLY. The earlier monthly_amount_minor key (+
// the off-spec reference_rate_bps/commission_pct_bps extras) broke the strict
// generated ProductSummary/CashbackPreview parse on every consumer — F-021.
type cashbackPreviewJSON struct {
	MonthlyCoinMinor int64  `json:"monthly_coin_minor"`
	Currency         string `json:"currency"`
}

// deliveryEtaJSON is the pre-purchase delivery estimate shown on the PDP (P-034).
// Confident=false marks a fallback (national) range that the UI hedges as
// "tahmini" — never an SLA promise. DispatchCity backs an optional "X'dan
// gönderilir" line. Null in the response when no estimate is available.
type deliveryEtaJSON struct {
	MinDays      int     `json:"min_days"`
	MaxDays      int     `json:"max_days"`
	Confident    bool    `json:"confident"`
	DispatchCity *string `json:"dispatch_city,omitempty"`
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

	// Trendyol-style display fields (all optional / zero when absent):
	// - OriginalPriceMinor: when > PriceMinor, render the original with a
	//   strikethrough and compute the discount %.
	// - RatingAvg / RatingCount: drive the star-rating chip; hidden when
	//   RatingCount == 0.
	OriginalPriceMinor *int64   `json:"original_price_minor,omitempty"`
	DiscountPct        *int     `json:"discount_pct,omitempty"`
	RatingAvg          *float64 `json:"rating_avg,omitempty"`
	RatingCount        int      `json:"rating_count"`

	// FlashPriceMinor is set only for flash-deals rail products; the original
	// price comes from PriceMinor (rendered with strikethrough on the UI).
	FlashPriceMinor *int64 `json:"flash_price_minor,omitempty"`

	// FreeShipping drives the "Kargo Bedava" badge (P-009); FavoritesCount is
	// social-proof on the card/PDP (P-004). Always emitted (0/false when absent).
	FreeShipping   bool `json:"free_shipping"`
	FavoritesCount int  `json:"favorites_count"`

	// IsBestseller drives the "Çok Satan" stamp; BasketDiscountPct drives the
	// "Sepette %X İndirim" pill (G-3). IsBestseller is always emitted (false when
	// absent); BasketDiscountPct is omitted when null (no pill).
	IsBestseller      bool `json:"is_bestseller"`
	BasketDiscountPct *int `json:"basket_discount_pct,omitempty"`

	// Lowest30dPriceMinor is the lowest price in the last 30 days (P-030, TR 6502 /
	// EU Omnibus). The frontend shows "30 günün en düşük fiyatı" only when it is
	// below PriceMinor — today it equals PriceMinor for every product (prices are
	// immutable post-creation). Omitted when null.
	Lowest30dPriceMinor *int64 `json:"lowest_30d_price_minor,omitempty"`

	CashbackPreview cashbackPreviewJSON `json:"cashback_preview"`
}

// buildProductSummaryJSON maps one row to the wire DTO (cashback preview +
// discount %). Shared by the list response and the flash-deals endpoint.
func buildProductSummaryJSON(r catalog.ProductSummaryRow, cashbackCurrency string) productSummaryJSON {
	commMinor := r.PriceMinor * int64(r.CommissionPctBps) / 10000
	yearlyYield := commMinor * referenceInterestRateBps / 10000
	monthlyMinor := yearlyYield / 12
	var discountPct *int
	if r.OriginalPriceMinor != nil && *r.OriginalPriceMinor > r.PriceMinor && *r.OriginalPriceMinor > 0 {
		pct := int(((*r.OriginalPriceMinor - r.PriceMinor) * 100) / *r.OriginalPriceMinor)
		if pct > 0 {
			discountPct = &pct
		}
	}
	return productSummaryJSON{
		ID:                  r.ID,
		SellerID:            r.SellerID,
		CategoryID:          r.CategoryID,
		Brand:               r.Brand,
		Status:              r.Status,
		Title:               r.Title,
		PriceMinor:          r.PriceMinor,
		PriceCurrency:       r.PriceCurrency,
		CoverImageURL:       mediaurl.CDNUrl(r.CoverImageKey),
		CommissionPctBps:    r.CommissionPctBps,
		OriginalPriceMinor:  r.OriginalPriceMinor,
		DiscountPct:         discountPct,
		RatingAvg:           r.RatingAvg,
		RatingCount:         r.RatingCount,
		FreeShipping:        r.FreeShipping,
		FavoritesCount:      r.FavoritesCount,
		IsBestseller:        r.IsBestseller,
		BasketDiscountPct:   r.BasketDiscountPct,
		Lowest30dPriceMinor: r.Lowest30dPriceMinor,
		CashbackPreview: cashbackPreviewJSON{
			MonthlyCoinMinor: monthlyMinor,
			Currency:         cashbackCurrency,
		},
	}
}

func buildProductListResponse(rows []catalog.ProductSummaryRow, total, page, perPage int, cashbackCurrency string) map[string]any {
	out := make([]productSummaryJSON, len(rows))
	for i, r := range rows {
		out[i] = buildProductSummaryJSON(r, cashbackCurrency)
	}
	totalPages := 0
	if perPage > 0 && total > 0 {
		totalPages = (total + perPage - 1) / perPage
	}
	return map[string]any{
		"data": out,
		// Envelope key is "pagination" per the OpenAPI ListProducts/SearchProducts
		// 200 schema (required [data, pagination]); the generated clients type it
		// as a required PaginationMeta. (Was "meta" — F-021.)
		"pagination": paginationMeta{
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

type promoSlotJSON struct {
	ImageURL string `json:"image_url"`
	Title    string `json:"title"`
	DeepLink string `json:"deep_link"`
}

type categoryJSON struct {
	ID               int64          `json:"id"`
	Slug             string         `json:"slug"`
	Name             string         `json:"name"`
	ParentID         *int64         `json:"parent_id"`
	CommissionPctBps int            `json:"commission_pct_bps"`
	PromoSlot        *promoSlotJSON `json:"promo_slot,omitempty"`
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
		if r.PromoSlot != nil {
			out[i].PromoSlot = &promoSlotJSON{
				ImageURL: r.PromoSlot.ImageURL,
				Title:    r.PromoSlot.Title,
				DeepLink: r.PromoSlot.DeepLink,
			}
		}
	}
	return map[string]any{"data": out}
}
