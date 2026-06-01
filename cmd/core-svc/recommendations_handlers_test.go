package main

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/mopro/platform/internal/analytics"
	"github.com/mopro/platform/internal/catalog"
	"github.com/mopro/platform/internal/identity/middleware"
)

// fakeRecsSvc is an analytics.Service whose recommendation reads are injectable;
// the rest of the interface is no-op (not exercised by these handlers).
type fakeRecsSvc struct {
	consent    analytics.Consent
	homeIDs    []int64
	popularIDs []int64
	similarIDs func(productID int64) []int64
}

func (f *fakeRecsSvc) Ingest(context.Context, analytics.IngestBatch) error  { return nil }
func (f *fakeRecsSvc) IdentifySession(context.Context, string, int64) error { return nil }
func (f *fakeRecsSvc) GetConsent(context.Context, int64) (analytics.Consent, error) {
	return f.consent, nil
}
func (f *fakeRecsSvc) SetConsent(context.Context, int64, bool) (analytics.Consent, error) {
	return f.consent, nil
}
func (f *fakeRecsSvc) DeleteUserData(context.Context, int64) error { return nil }
func (f *fakeRecsSvc) RecentlyViewed(context.Context, int64, int) ([]analytics.RecentlyViewedItem, error) {
	return nil, nil
}
func (f *fakeRecsSvc) PruneEvents(context.Context, time.Time, int) (int64, error) { return 0, nil }
func (f *fakeRecsSvc) RebuildRecentlyViewed(context.Context, time.Time) error     { return nil }
func (f *fakeRecsSvc) RefreshRecommendations(context.Context) error               { return nil }
func (f *fakeRecsSvc) PopularProductIDs(_ context.Context, limit int) ([]int64, error) {
	if len(f.popularIDs) > limit {
		return f.popularIDs[:limit], nil
	}
	return f.popularIDs, nil
}
func (f *fakeRecsSvc) HomeRecommendationIDs(context.Context, int64, int) ([]int64, error) {
	return f.homeIDs, nil
}
func (f *fakeRecsSvc) SimilarProductIDs(_ context.Context, productID int64, _ int) ([]int64, error) {
	if f.similarIDs != nil {
		return f.similarIDs(productID), nil
	}
	return nil, nil
}

// summaryRows turns IDs into minimal catalog rows so hydration succeeds.
func summaryRows(ids []int64) []catalog.ProductSummaryRow {
	out := make([]catalog.ProductSummaryRow, len(ids))
	for i, id := range ids {
		out[i] = catalog.ProductSummaryRow{
			ID: id, Title: "P", PriceMinor: 1000, PriceCurrency: "TRY", Status: "active",
		}
	}
	return out
}

func decodeRecs(t *testing.T, rec *httptest.ResponseRecorder) (ids []int64, source string) {
	t.Helper()
	var body struct {
		Data []struct {
			ID int64 `json:"id"`
		} `json:"data"`
		Source string `json:"source"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode: %v (%s)", err, rec.Body.String())
	}
	for _, p := range body.Data {
		ids = append(ids, p.ID)
	}
	return ids, body.Source
}

func TestHomeRecs_GuestGetsPopular(t *testing.T) {
	svc := &fakeRecsSvc{popularIDs: []int64{5, 6, 7}}
	cat := &stubCatalogSvc{listByIDsFn: func(ids []int64) ([]catalog.ProductSummaryRow, error) {
		return summaryRows(ids), nil
	}}
	rec := httptest.NewRecorder()
	r := httptest.NewRequest(http.MethodGet, "/recommendations/home", nil)
	handleHomeRecommendations(svc, cat, "tr-TR", "TR", "TRY_COIN")(rec, r)

	if rec.Code != http.StatusOK {
		t.Fatalf("want 200, got %d", rec.Code)
	}
	ids, source := decodeRecs(t, rec)
	if source != "popular" {
		t.Fatalf("guest source: want popular, got %q", source)
	}
	if len(ids) != 3 {
		t.Fatalf("want 3 popular products, got %v", ids)
	}
}

func TestHomeRecs_ConsentedWithHistoryGetsPersonalized(t *testing.T) {
	svc := &fakeRecsSvc{
		consent:    analytics.Consent{AnalyticsEnabled: true},
		homeIDs:    []int64{11, 12},
		popularIDs: []int64{99},
	}
	cat := &stubCatalogSvc{listByIDsFn: func(ids []int64) ([]catalog.ProductSummaryRow, error) {
		return summaryRows(ids), nil
	}}
	rec := httptest.NewRecorder()
	r := httptest.NewRequest(http.MethodGet, "/recommendations/home", nil)
	r = r.WithContext(middleware.ContextWithUserID(r.Context(), 7))
	handleHomeRecommendations(svc, cat, "tr-TR", "TR", "TRY_COIN")(rec, r)

	ids, source := decodeRecs(t, rec)
	if source != "personalized" {
		t.Fatalf("want personalized, got %q", source)
	}
	if len(ids) != 2 || ids[0] != 11 {
		t.Fatalf("want personalized [11 12], got %v", ids)
	}
}

func TestHomeRecs_ConsentOffFallsBackToPopular(t *testing.T) {
	svc := &fakeRecsSvc{
		consent:    analytics.Consent{AnalyticsEnabled: false},
		homeIDs:    []int64{11, 12}, // should be ignored (no consent)
		popularIDs: []int64{99},
	}
	cat := &stubCatalogSvc{listByIDsFn: func(ids []int64) ([]catalog.ProductSummaryRow, error) {
		return summaryRows(ids), nil
	}}
	rec := httptest.NewRecorder()
	r := httptest.NewRequest(http.MethodGet, "/recommendations/home", nil)
	r = r.WithContext(middleware.ContextWithUserID(r.Context(), 7))
	handleHomeRecommendations(svc, cat, "tr-TR", "TR", "TRY_COIN")(rec, r)

	ids, source := decodeRecs(t, rec)
	if source != "popular" {
		t.Fatalf("consent off → popular, got %q", source)
	}
	if len(ids) != 1 || ids[0] != 99 {
		t.Fatalf("want popular [99], got %v", ids)
	}
}

func TestHomeRecs_ConsentedNoHistoryFallsBackToPopular(t *testing.T) {
	svc := &fakeRecsSvc{
		consent:    analytics.Consent{AnalyticsEnabled: true},
		homeIDs:    nil, // cold start
		popularIDs: []int64{99},
	}
	cat := &stubCatalogSvc{listByIDsFn: func(ids []int64) ([]catalog.ProductSummaryRow, error) {
		return summaryRows(ids), nil
	}}
	rec := httptest.NewRecorder()
	r := httptest.NewRequest(http.MethodGet, "/recommendations/home", nil)
	r = r.WithContext(middleware.ContextWithUserID(r.Context(), 7))
	handleHomeRecommendations(svc, cat, "tr-TR", "TR", "TRY_COIN")(rec, r)

	_, source := decodeRecs(t, rec)
	if source != "popular" {
		t.Fatalf("no history → popular, got %q", source)
	}
}

func TestSimilar_CoViewExcludesSelf(t *testing.T) {
	svc := &fakeRecsSvc{
		similarIDs: func(int64) []int64 { return []int64{20, 21} },
		popularIDs: []int64{42, 20, 30}, // 42=self, 20=already co-view → both skipped in pad
	}
	cat := &stubCatalogSvc{listByIDsFn: func(ids []int64) ([]catalog.ProductSummaryRow, error) {
		return summaryRows(ids), nil
	}}
	rec := httptest.NewRecorder()
	r := httptest.NewRequest(http.MethodGet, "/products/42/similar?limit=4", nil)
	r.SetPathValue("id", "42")
	handleSimilarProducts(svc, cat, "tr-TR", "TR", "TRY_COIN")(rec, r)

	ids, source := decodeRecs(t, rec)
	if source != "co_view" {
		t.Fatalf("want co_view source, got %q", source)
	}
	for _, id := range ids {
		if id == 42 {
			t.Fatalf("product 42 must never recommend itself, got %v", ids)
		}
	}
	// co-view {20,21} + popular pad 30 (42=self, 20=dup skipped).
	if len(ids) != 3 {
		t.Fatalf("want [20 21 30], got %v", ids)
	}
}

func TestSimilar_NoCoViewPadsFromPopular(t *testing.T) {
	svc := &fakeRecsSvc{
		similarIDs: func(int64) []int64 { return nil },
		popularIDs: []int64{42, 50, 51}, // 42=self skipped
	}
	cat := &stubCatalogSvc{listByIDsFn: func(ids []int64) ([]catalog.ProductSummaryRow, error) {
		return summaryRows(ids), nil
	}}
	rec := httptest.NewRecorder()
	r := httptest.NewRequest(http.MethodGet, "/products/42/similar", nil)
	r.SetPathValue("id", "42")
	handleSimilarProducts(svc, cat, "tr-TR", "TR", "TRY_COIN")(rec, r)

	ids, source := decodeRecs(t, rec)
	if source != "popular" {
		t.Fatalf("no co-view → popular source, got %q", source)
	}
	if len(ids) != 2 || ids[0] != 50 {
		t.Fatalf("want popular pad [50 51] (self excluded), got %v", ids)
	}
}

func TestSimilar_InvalidIDIs400(t *testing.T) {
	rec := httptest.NewRecorder()
	r := httptest.NewRequest(http.MethodGet, "/products/abc/similar", nil)
	r.SetPathValue("id", "abc")
	handleSimilarProducts(&fakeRecsSvc{}, &stubCatalogSvc{}, "tr-TR", "TR", "TRY_COIN")(rec, r)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("want 400 for non-numeric id, got %d", rec.Code)
	}
}
