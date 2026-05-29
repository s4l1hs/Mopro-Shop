package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/mopro/platform/internal/catalog"
)

// stubCatalogSvc is a minimal catalog.Service implementation that records the
// arguments handler tests need to verify. Other methods are no-op stubs.
type stubCatalogSvc struct {
	listCategoriesFn func(ctx context.Context, locale string, maxDepth int) ([]catalog.CategoryRow, error)
}

func (s *stubCatalogSvc) CreateProduct(_ context.Context, _ catalog.CreateProductRequest) (catalog.Product, error) {
	return catalog.Product{}, nil
}
func (s *stubCatalogSvc) AddVariant(_ context.Context, _ int64, _ catalog.AddVariantRequest) (catalog.Variant, error) {
	return catalog.Variant{}, nil
}
func (s *stubCatalogSvc) UpdateTranslation(_ context.Context, _ int64, _, _, _ string) error {
	return nil
}
func (s *stubCatalogSvc) GetByID(_ context.Context, _ int64) (catalog.Product, []catalog.Variant, []catalog.ProductTranslation, error) {
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
func (s *stubCatalogSvc) ListProductsByCategory(_ context.Context, _ int64, _, _ string, _, _ int) ([]catalog.ProductSummaryRow, int, error) {
	return nil, 0, nil
}
func (s *stubCatalogSvc) SearchSummary(_ context.Context, _, _, _ string, _, _ int) ([]catalog.ProductSummaryRow, int, error) {
	return nil, 0, nil
}
func (s *stubCatalogSvc) ListProductsByIDs(_ context.Context, _ []int64, _, _ string) ([]catalog.ProductSummaryRow, error) {
	return nil, nil
}
func (s *stubCatalogSvc) HomeRails(_ context.Context, _ string) ([]catalog.HomeRailRow, error) {
	return nil, nil
}
func (s *stubCatalogSvc) HomeBanners(_ context.Context) ([]catalog.HomeBannerRow, error) {
	return nil, nil
}
func (s *stubCatalogSvc) HomeMoodStories(_ context.Context) ([]catalog.HomeMoodStoryRow, error) {
	return nil, nil
}
func (s *stubCatalogSvc) ListReviews(_ context.Context, _ int64, _, _ int) ([]catalog.ProductReviewRow, int, error) {
	return nil, 0, nil
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
}

func contains(haystack, needle string) bool {
	for i := 0; i+len(needle) <= len(haystack); i++ {
		if haystack[i:i+len(needle)] == needle {
			return true
		}
	}
	return false
}
