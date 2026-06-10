package main

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/mopro/platform/internal/catalog"
)

// stubCatalogSvc is a minimal catalog.Service implementation that records the
// arguments handler tests need to verify. Other methods are no-op stubs.
type stubCatalogSvc struct {
	listCategoriesFn    func(ctx context.Context, locale string, maxDepth int) ([]catalog.CategoryRow, error)
	homeFlashDealsFn    func(ctx context.Context, locale string, collectionID *int64) (*catalog.FlashDealsResult, error)
	homeRailsRows       []catalog.HomeRailRow
	listReviewsFn       func() ([]catalog.ProductReviewRow, int, error)
	reviewsSummaryFn    func() (catalog.ReviewsSummary, error)
	reviewProductIDFn   func(reviewID int64) (int64, error)
	toggleHelpfulFn     func() (catalog.HelpfulVoteResult, error)
	getByIDFn           func(id int64) (catalog.Product, []catalog.Variant, []catalog.ProductTranslation, error)
	listByIDsFn         func(ids []int64) ([]catalog.ProductSummaryRow, error)
	listProductsFn      func(filter catalog.ProductFilter) ([]catalog.ProductSummaryRow, int, error)
	facetsFn            func() ([]catalog.Facet, error)
	productAttributesFn func() ([]catalog.ProductAttribute, error)
}

func (s *stubCatalogSvc) CreateProduct(_ context.Context, _ catalog.CreateProductRequest) (catalog.Product, error) {
	return catalog.Product{}, nil
}
func (s *stubCatalogSvc) AddVariant(_ context.Context, _ int64, _ catalog.AddVariantRequest) (catalog.Variant, error) {
	return catalog.Variant{}, nil
}

func (s *stubCatalogSvc) UpdateVariantPrice(_ context.Context, _ int64, _ catalog.UpdateVariantPriceRequest) error {
	return nil
}
func (s *stubCatalogSvc) UpdateTranslation(_ context.Context, _ int64, _, _, _ string) error {
	return nil
}
func (s *stubCatalogSvc) GetByID(_ context.Context, id int64) (catalog.Product, []catalog.Variant, []catalog.ProductTranslation, error) {
	if s.getByIDFn != nil {
		return s.getByIDFn(id)
	}
	return catalog.Product{}, nil, nil, nil
}
func (s *stubCatalogSvc) Search(_ context.Context, _, _, _ string) ([]catalog.Product, error) {
	return nil, nil
}
func (s *stubCatalogSvc) GetCommissionForCategory(_ context.Context, _ string, _ int64) (catalog.CategoryCommission, error) {
	return catalog.CategoryCommission{}, nil
}
func (s *stubCatalogSvc) GetVariantByID(_ context.Context, _ int64) (catalog.Variant, error) {
	return catalog.Variant{}, nil
}
func (s *stubCatalogSvc) ListCategories(ctx context.Context, locale string, maxDepth int) ([]catalog.CategoryRow, error) {
	if s.listCategoriesFn != nil {
		return s.listCategoriesFn(ctx, locale, maxDepth)
	}
	return []catalog.CategoryRow{}, nil
}
func (s *stubCatalogSvc) ListProductsByCategory(_ context.Context, _ int64, _, _ string, _ catalog.ProductFilter, _, _ int) ([]catalog.ProductSummaryRow, int, error) {
	return nil, 0, nil
}
func (s *stubCatalogSvc) ListProducts(_ context.Context, _, _ string, filter catalog.ProductFilter, _, _ int) ([]catalog.ProductSummaryRow, int, error) {
	if s.listProductsFn != nil {
		return s.listProductsFn(filter)
	}
	return nil, 0, nil
}
func (s *stubCatalogSvc) SearchSummary(_ context.Context, _, _, _ string, _ catalog.ProductFilter, _, _ int) ([]catalog.ProductSummaryRow, int, error) {
	return nil, 0, nil
}

func (s *stubCatalogSvc) Suggest(_ context.Context, _, _ string, _, _ int) (catalog.SuggestResult, error) {
	return catalog.SuggestResult{}, nil
}
func (s *stubCatalogSvc) FacetsByCategory(_ context.Context, _ int64, _ string) ([]catalog.Facet, error) {
	if s.facetsFn != nil {
		return s.facetsFn()
	}
	return nil, nil
}
func (s *stubCatalogSvc) ProductAttributes(_ context.Context, _ int64, _ string) ([]catalog.ProductAttribute, error) {
	if s.productAttributesFn != nil {
		return s.productAttributesFn()
	}
	return nil, nil
}
func (s *stubCatalogSvc) ListProductsByIDs(_ context.Context, ids []int64, _, _ string) ([]catalog.ProductSummaryRow, error) {
	if s.listByIDsFn != nil {
		return s.listByIDsFn(ids)
	}
	return nil, nil
}
func (s *stubCatalogSvc) HomeRails(_ context.Context, _ string) ([]catalog.HomeRailRow, error) {
	return s.homeRailsRows, nil
}
func (s *stubCatalogSvc) HomeBanners(_ context.Context) ([]catalog.HomeBannerRow, error) {
	return nil, nil
}
func (s *stubCatalogSvc) HomeMoodStories(_ context.Context) ([]catalog.HomeMoodStoryRow, error) {
	return nil, nil
}

func (s *stubCatalogSvc) HomeFlashDeals(ctx context.Context, locale string, collectionID *int64) (*catalog.FlashDealsResult, error) {
	if s.homeFlashDealsFn != nil {
		return s.homeFlashDealsFn(ctx, locale, collectionID)
	}
	return nil, nil
}
func (s *stubCatalogSvc) ListReviews(_ context.Context, _ int64, _ catalog.ReviewSort, _, _ int, _ int64) ([]catalog.ProductReviewRow, int, error) {
	if s.listReviewsFn != nil {
		return s.listReviewsFn()
	}
	return nil, 0, nil
}
func (s *stubCatalogSvc) ReviewsSummary(_ context.Context, _ int64) (catalog.ReviewsSummary, error) {
	if s.reviewsSummaryFn != nil {
		return s.reviewsSummaryFn()
	}
	return catalog.ReviewsSummary{Distribution: map[int]int{1: 0, 2: 0, 3: 0, 4: 0, 5: 0}}, nil
}
func (s *stubCatalogSvc) ReviewProductID(_ context.Context, reviewID int64) (int64, error) {
	if s.reviewProductIDFn != nil {
		return s.reviewProductIDFn(reviewID)
	}
	return 0, catalog.ErrReviewNotFound
}
func (s *stubCatalogSvc) ToggleHelpfulVote(_ context.Context, _, _ int64) (catalog.HelpfulVoteResult, error) {
	if s.toggleHelpfulFn != nil {
		return s.toggleHelpfulFn()
	}
	return catalog.HelpfulVoteResult{}, nil
}
func (s *stubCatalogSvc) ListAllVariantStocks(_ context.Context) ([]catalog.VariantStock, error) {
	return nil, nil
}

// ── handler tests ─────────────────────────────────────────────────────────────

// TestListCategories_DepthValidation exercises the depth query param's
// validation gate (Session 4c §3): valid values 1..3 pass through; everything
// else returns 400 bad_request; missing param preserves maxDepth=0 (no limit).
func TestListCategories_DepthValidation(t *testing.T) {
	cases := []struct {
		name              string
		query             string
		wantStatus        int
		wantMaxDepthPass  int // value the handler should have forwarded to the service
		wantHandlerCalled bool
	}{
		{name: "missing depth → no limit", query: "", wantStatus: 200, wantMaxDepthPass: 0, wantHandlerCalled: true},
		{name: "depth=1 valid", query: "depth=1", wantStatus: 200, wantMaxDepthPass: 1, wantHandlerCalled: true},
		{name: "depth=3 valid (max)", query: "depth=3", wantStatus: 200, wantMaxDepthPass: 3, wantHandlerCalled: true},
		{name: "depth=0 invalid → 400", query: "depth=0", wantStatus: 400, wantHandlerCalled: false},
		{name: "depth=4 invalid → 400", query: "depth=4", wantStatus: 400, wantHandlerCalled: false},
		{name: "depth=99 invalid → 400", query: "depth=99", wantStatus: 400, wantHandlerCalled: false},
		{name: "depth=-1 invalid → 400", query: "depth=-1", wantStatus: 400, wantHandlerCalled: false},
		{name: "depth=abc invalid → 400", query: "depth=abc", wantStatus: 400, wantHandlerCalled: false},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			var capturedDepth int
			called := false
			svc := &stubCatalogSvc{
				listCategoriesFn: func(_ context.Context, _ string, maxDepth int) ([]catalog.CategoryRow, error) {
					called = true
					capturedDepth = maxDepth
					return []catalog.CategoryRow{}, nil
				},
			}

			handler := handleListCategories(svc, "tr-TR")
			url := "/categories"
			if tc.query != "" {
				url += "?" + tc.query
			}
			req := httptest.NewRequest(http.MethodGet, url, nil)
			rec := httptest.NewRecorder()
			handler(rec, req)

			if rec.Code != tc.wantStatus {
				t.Fatalf("status: got %d, want %d (body: %s)", rec.Code, tc.wantStatus, rec.Body.String())
			}
			if called != tc.wantHandlerCalled {
				t.Fatalf("service called: got %v, want %v", called, tc.wantHandlerCalled)
			}
			if tc.wantHandlerCalled && capturedDepth != tc.wantMaxDepthPass {
				t.Fatalf("maxDepth forwarded: got %d, want %d", capturedDepth, tc.wantMaxDepthPass)
			}
		})
	}
}

// TestListCategories_DefaultResponseShapeUnchanged guards the mobile contract:
// the default-depth (no param) response is a flat `{data: [...]}` envelope.
// Mobile callers rely on this; widening or nesting would be a breaking change.
func TestListCategories_DefaultResponseShapeUnchanged(t *testing.T) {
	svc := &stubCatalogSvc{
		listCategoriesFn: func(_ context.Context, _ string, _ int) ([]catalog.CategoryRow, error) {
			parentID := int64(1)
			return []catalog.CategoryRow{
				{ID: 1, Slug: "erkek", Name: "Erkek", CommissionPctBps: 500},
				{ID: 2, Slug: "giyim", Name: "Giyim", ParentID: &parentID, CommissionPctBps: 700},
			}, nil
		},
	}

	handler := handleListCategories(svc, "tr-TR")
	req := httptest.NewRequest(http.MethodGet, "/categories", nil)
	rec := httptest.NewRecorder()
	handler(rec, req)

	if rec.Code != 200 {
		t.Fatalf("status: got %d, want 200", rec.Code)
	}
	body := rec.Body.String()
	// Top-level envelope must still be `{"data":[...]}` — flat list with
	// parent_id for client-side tree reconstruction.
	if !contains(body, `"data"`) {
		t.Fatalf("response missing top-level `data` envelope: %s", body)
	}
	if !contains(body, `"parent_id"`) {
		t.Fatalf("response missing per-row `parent_id` (flat shape contract): %s", body)
	}
	// And must NOT have nested `children` (we deliberately keep the wire format
	// flat; nesting is a client-side concern).
	if contains(body, `"children"`) {
		t.Fatalf("response should not be nested: %s", body)
	}
	// Default-depth response must NOT include promo_slot when no rows have
	// one — the `omitempty` on categoryJSON.PromoSlot suppresses it. (When
	// rows DO have a promo, the field appears on those rows only; covered
	// by TestListCategories_PromoSlot_TopLevelOnly below.)
	if contains(body, `"promo_slot"`) {
		t.Fatalf("response should not include promo_slot on rows without one: %s", body)
	}
}

// TestListCategories_PromoSlot_TopLevelOnly guards the §2 promo_slot
// surface contract: appears on top-level rows when populated; absent
// from subcategory/leaf rows even if the service layer returned one.
func TestListCategories_PromoSlot_TopLevelOnly(t *testing.T) {
	parentID := int64(1)
	leafParent := int64(10)
	svc := &stubCatalogSvc{
		listCategoriesFn: func(_ context.Context, _ string, _ int) ([]catalog.CategoryRow, error) {
			return []catalog.CategoryRow{
				// Top-level with promo — should surface.
				{
					ID: 1, Slug: "erkek", Name: "Erkek", CommissionPctBps: 500,
					PromoSlot: &catalog.PromoSlot{
						ImageURL: "https://cdn.example.com/promos/erkek.png",
						Title:    "Erkek Yeni Sezon",
						DeepLink: "/categories/1?campaign=new",
					},
				},
				// Top-level without promo — should not have the field rendered.
				{ID: 2, Slug: "kadin", Name: "Kadın", CommissionPctBps: 500},
				// Subcategory: even if service returned a promo here (it
				// shouldn't), the handler / API contract says omit.
				{ID: 10, Slug: "giyim", Name: "Giyim", ParentID: &parentID, CommissionPctBps: 700},
				// Leaf.
				{ID: 100, Slug: "tshirt", Name: "T-shirt", ParentID: &leafParent, CommissionPctBps: 700},
			}, nil
		},
	}

	handler := handleListCategories(svc, "tr-TR")
	req := httptest.NewRequest(http.MethodGet, "/categories?depth=3", nil)
	rec := httptest.NewRecorder()
	handler(rec, req)

	if rec.Code != 200 {
		t.Fatalf("status: got %d, want 200", rec.Code)
	}
	body := rec.Body.String()
	// Surface on the populated top-level.
	if !contains(body, `"image_url":"https://cdn.example.com/promos/erkek.png"`) {
		t.Fatalf("promo_slot.image_url not surfaced on top-level: %s", body)
	}
	if !contains(body, `"deep_link":"/categories/1?campaign=new"`) {
		t.Fatalf("promo_slot.deep_link not surfaced on top-level: %s", body)
	}
	// Absent on subcategory + leaf: only one occurrence of "promo_slot"
	// (the one on the populated top-level row).
	if countOccurrences(body, `"promo_slot"`) != 1 {
		t.Fatalf("promo_slot should appear exactly once (top-level only); body: %s", body)
	}
}

func countOccurrences(s, sub string) int {
	count := 0
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			count++
		}
	}
	return count
}

func contains(haystack, needle string) bool {
	for i := 0; i+len(needle) <= len(haystack); i++ {
		if haystack[i:i+len(needle)] == needle {
			return true
		}
	}
	return false
}

// TestHandleListProducts_CategoryOptional locks the F-020 contract: category_id
// is optional on GET /products. Absent → the global (catalog-wide) list the Home
// rails need; present+valid → the category PLP (must NOT take the global path);
// present+malformed → 400 (category-scoped validation intact).
func TestHandleListProducts_CategoryOptional(t *testing.T) {
	var globalHit bool
	svc := &stubCatalogSvc{
		listProductsFn: func(_ catalog.ProductFilter) ([]catalog.ProductSummaryRow, int, error) {
			globalHit = true
			return []catalog.ProductSummaryRow{}, 0, nil
		},
	}
	h := handleListProducts(&fakeRecsSvc{}, svc, "tr-TR", "TR", "TRY_COIN")

	t.Run("no category_id serves the global list", func(t *testing.T) {
		globalHit = false
		rec := httptest.NewRecorder()
		h(rec, httptest.NewRequest(http.MethodGet, "/products?sort=newest&per_page=6", nil))
		if rec.Code != http.StatusOK {
			t.Fatalf("want 200, got %d", rec.Code)
		}
		if !globalHit {
			t.Fatal("no category_id must route to the global ListProducts")
		}
	})

	t.Run("malformed category_id is 400", func(t *testing.T) {
		for _, bad := range []string{"0", "-1", "abc"} {
			rec := httptest.NewRecorder()
			h(rec, httptest.NewRequest(http.MethodGet, "/products?category_id="+bad, nil))
			if rec.Code != http.StatusBadRequest {
				t.Fatalf("category_id=%q: want 400, got %d", bad, rec.Code)
			}
		}
	})

	t.Run("valid category_id does not take the global path", func(t *testing.T) {
		globalHit = false
		rec := httptest.NewRecorder()
		h(rec, httptest.NewRequest(http.MethodGet, "/products?category_id=5", nil))
		if rec.Code != http.StatusOK {
			t.Fatalf("want 200, got %d", rec.Code)
		}
		if globalHit {
			t.Fatal("category-scoped call must not invoke the global ListProducts")
		}
	})
}

// TestF021_ProductListResponse_SpecKeys locks the /products serializer to the
// OpenAPI shape so the generated ProductSummary/CashbackPreview parse never
// silently breaks again (the systemic root of F-020 + F-021): the pagination
// envelope must be `pagination` (not `meta`), and cashback_preview must carry
// `monthly_coin_minor` only (not the old `monthly_amount_minor` + off-spec extras).
func TestF021_ProductListResponse_SpecKeys(t *testing.T) {
	row := catalog.ProductSummaryRow{
		ID: 1, SellerID: 1, CategoryID: 1, Brand: "B", Status: "active",
		Title: "T", PriceMinor: 1000, PriceCurrency: "TRY", CommissionPctBps: 1000,
	}
	b, err := json.Marshal(buildProductListResponse([]catalog.ProductSummaryRow{row}, 1, 1, 20, "TRY_COIN"))
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	var m map[string]any
	if err := json.Unmarshal(b, &m); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}

	if _, ok := m["pagination"]; !ok {
		t.Error("missing OpenAPI `pagination` envelope key")
	}
	if _, ok := m["meta"]; ok {
		t.Error("off-spec `meta` envelope key present")
	}

	data, ok := m["data"].([]any)
	if !ok || len(data) == 0 {
		t.Fatal("response `data` missing or empty")
	}
	item, ok := data[0].(map[string]any)
	if !ok {
		t.Fatal("data[0] not an object")
	}
	cb, ok := item["cashback_preview"].(map[string]any)
	if !ok {
		t.Fatal("cashback_preview missing/not an object")
	}
	if _, ok := cb["monthly_coin_minor"]; !ok {
		t.Error("cashback_preview missing required `monthly_coin_minor`")
	}
	for _, bad := range []string{"monthly_amount_minor", "reference_rate_bps", "commission_pct_bps"} {
		if _, ok := cb[bad]; ok {
			t.Errorf("cashback_preview carries off-spec key %q", bad)
		}
	}
}

// TestProductSummaryJSON_MerchSignals locks the G-3 merch fields onto the wire
// DTO: is_bestseller is always emitted (false default), basket_discount_pct is
// emitted when set and omitted (omitempty) when nil.
func TestProductSummaryJSON_MerchSignals(t *testing.T) {
	pct := 15
	base := catalog.ProductSummaryRow{
		ID: 1, Brand: "B", Status: "active", Title: "T",
		PriceMinor: 1000, PriceCurrency: "TRY", CommissionPctBps: 1000,
	}

	// Set: both surface.
	set := base
	set.IsBestseller = true
	set.BasketDiscountPct = &pct
	m := marshalToMap(t, buildProductSummaryJSON(set, "TRY_COIN"))
	if m["is_bestseller"] != true {
		t.Errorf("is_bestseller = %v, want true", m["is_bestseller"])
	}
	got, ok := m["basket_discount_pct"]
	f, isNum := got.(float64)
	if !ok || !isNum || f != 15 {
		t.Errorf("basket_discount_pct = %v (ok=%v), want 15", got, ok)
	}

	// Unset: is_bestseller present (false), basket_discount_pct omitted.
	m = marshalToMap(t, buildProductSummaryJSON(base, "TRY_COIN"))
	if m["is_bestseller"] != false {
		t.Errorf("is_bestseller = %v, want false", m["is_bestseller"])
	}
	if _, ok := m["basket_discount_pct"]; ok {
		t.Error("basket_discount_pct present when nil; want omitted")
	}
}

func marshalToMap(t *testing.T, v any) map[string]any {
	t.Helper()
	b, err := json.Marshal(v)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	var m map[string]any
	if err := json.Unmarshal(b, &m); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	return m
}
