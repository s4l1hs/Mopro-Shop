package main

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/mopro/platform/internal/catalog"
	"github.com/mopro/platform/internal/identity/middleware"
	"github.com/mopro/platform/internal/seller"
)

// fakeChartSvc is a seller.Service whose chart methods are configurable; the rest
// return zero values (the handlers only touch the chart surface).
type fakeChartSvc struct {
	createID      int64
	createErr     error
	attachErr     error
	standardChart seller.SizeChart
	standardErr   error
}

func (f *fakeChartSvc) GetBySlug(context.Context, string) (seller.Seller, error) {
	return seller.Seller{}, nil
}
func (f *fakeChartSvc) GetByID(context.Context, int64) (seller.Seller, error) {
	return seller.Seller{}, nil
}
func (f *fakeChartSvc) OfficialSellerIDs(context.Context, []int64) (map[int64]bool, error) {
	return nil, nil
}
func (f *fakeChartSvc) SellerNamesByIDs(context.Context, []int64) (map[int64]string, error) {
	return nil, nil
}
func (f *fakeChartSvc) ResolveSellerForUser(context.Context, int64) (int64, bool, error) {
	return 0, false, nil
}
func (f *fakeChartSvc) GetBindingForUser(context.Context, int64) (seller.Binding, bool, error) {
	return seller.Binding{}, false, nil
}
func (f *fakeChartSvc) CreateSizeChart(context.Context, int64, seller.SizeChart) (int64, error) {
	return f.createID, f.createErr
}
func (f *fakeChartSvc) UpdateSizeChart(context.Context, int64, int64, seller.SizeChart) error {
	return nil
}
func (f *fakeChartSvc) ListSizeCharts(context.Context, int64) ([]seller.SizeChart, error) {
	return nil, nil
}
func (f *fakeChartSvc) AttachProductChart(context.Context, int64, int64, int64) error {
	return f.attachErr
}
func (f *fakeChartSvc) DetachProductChart(context.Context, int64, int64) error { return nil }
func (f *fakeChartSvc) SizeChartForProduct(context.Context, int64) (seller.SizeChart, bool, error) {
	return seller.SizeChart{}, false, nil
}
func (f *fakeChartSvc) StandardSizeChart(context.Context, string, string, string) (seller.SizeChart, error) {
	return f.standardChart, f.standardErr
}

func sellerReq(method, target string, body any) *http.Request {
	var r *http.Request
	if body != nil {
		b, _ := json.Marshal(body)
		r = httptest.NewRequest(method, target, bytes.NewReader(b))
	} else {
		r = httptest.NewRequest(method, target, nil)
	}
	r.Header.Set("Idempotency-Key", "test-key")
	return r.WithContext(middleware.ContextWithSellerID(r.Context(), 42))
}

func TestCreateSizeChart_MissingIdempotencyKey(t *testing.T) {
	r := httptest.NewRequest(http.MethodPost, "/seller/size-charts", nil)
	r = r.WithContext(middleware.ContextWithSellerID(r.Context(), 42))
	w := httptest.NewRecorder()
	handleCreateSizeChart(&fakeChartSvc{})(w, r)
	if w.Code != http.StatusUnprocessableEntity {
		t.Fatalf("missing idempotency key → 422, got %d", w.Code)
	}
}

func TestCreateSizeChart_Invalid422(t *testing.T) {
	w := httptest.NewRecorder()
	handleCreateSizeChart(&fakeChartSvc{createErr: seller.ErrInvalidChart})(
		w, sellerReq(http.MethodPost, "/seller/size-charts", map[string]any{"name": "x"}))
	if w.Code != http.StatusUnprocessableEntity {
		t.Fatalf("invalid chart → 422, got %d (%s)", w.Code, w.Body.String())
	}
}

func TestCreateSizeChart_OK201(t *testing.T) {
	w := httptest.NewRecorder()
	handleCreateSizeChart(&fakeChartSvc{createID: 7})(
		w, sellerReq(http.MethodPost, "/seller/size-charts", map[string]any{"name": "x"}))
	if w.Code != http.StatusCreated {
		t.Fatalf("valid chart → 201, got %d (%s)", w.Code, w.Body.String())
	}
	var resp map[string]any
	_ = json.NewDecoder(w.Body).Decode(&resp)
	if resp["id"] != float64(7) {
		t.Fatalf("want id=7, got %v", resp["id"])
	}
}

func TestAttachProductChart_NotOwned404(t *testing.T) {
	// Product belongs to a different seller → 404, no leak.
	cat := &stubCatalogSvc{getByIDFn: func(id int64) (catalog.Product, []catalog.Variant, []catalog.ProductTranslation, error) {
		return catalog.Product{ID: id, SellerID: 99}, nil, nil, nil
	}}
	w := httptest.NewRecorder()
	r := sellerReq(http.MethodPost, "/seller/products/5/size-chart", map[string]any{"chart_id": 1})
	r.SetPathValue("id", "5")
	handleAttachProductChart(&fakeChartSvc{}, cat)(w, r)
	if w.Code != http.StatusNotFound {
		t.Fatalf("non-owned product → 404, got %d", w.Code)
	}
}

func TestAttachProductChart_ChartNotFound404(t *testing.T) {
	// Owned product, but the chart isn't the seller's → 404.
	cat := &stubCatalogSvc{getByIDFn: func(id int64) (catalog.Product, []catalog.Variant, []catalog.ProductTranslation, error) {
		return catalog.Product{ID: id, SellerID: 42}, nil, nil, nil
	}}
	w := httptest.NewRecorder()
	r := sellerReq(http.MethodPost, "/seller/products/5/size-chart", map[string]any{"chart_id": 1})
	r.SetPathValue("id", "5")
	handleAttachProductChart(&fakeChartSvc{attachErr: seller.ErrChartNotFound}, cat)(w, r)
	if w.Code != http.StatusNotFound {
		t.Fatalf("unknown chart → 404, got %d", w.Code)
	}
}

func TestAttachProductChart_OK(t *testing.T) {
	cat := &stubCatalogSvc{getByIDFn: func(id int64) (catalog.Product, []catalog.Variant, []catalog.ProductTranslation, error) {
		return catalog.Product{ID: id, SellerID: 42}, nil, nil, nil
	}}
	w := httptest.NewRecorder()
	r := sellerReq(http.MethodPost, "/seller/products/5/size-chart", map[string]any{"chart_id": 1})
	r.SetPathValue("id", "5")
	handleAttachProductChart(&fakeChartSvc{}, cat)(w, r)
	if w.Code != http.StatusOK {
		t.Fatalf("attach → 200, got %d (%s)", w.Code, w.Body.String())
	}
}

func TestStandardSizeChart_OK(t *testing.T) {
	svc := &fakeChartSvc{standardChart: seller.SizeChart{
		GarmentType: "dress", Gender: "female", SizeSystem: "alpha", Source: "standard",
		Rows: []seller.SizeChartRow{{SizeLabel: "M", SortRank: 3, Measurement: "chest", MinMM: 900, MaxMM: 980}},
	}}
	w := httptest.NewRecorder()
	r := httptest.NewRequest(http.MethodGet, "/seller/size-charts/standard?garment_type=dress&gender=female", nil)
	handleStandardSizeChart(svc)(w, r)
	if w.Code != http.StatusOK {
		t.Fatalf("standard → 200, got %d (%s)", w.Code, w.Body.String())
	}
	var resp map[string]any
	_ = json.NewDecoder(w.Body).Decode(&resp)
	if resp["chart"] == nil {
		t.Fatalf("expected chart in body, got %v", resp)
	}
}

func TestStandardSizeChart_NotFound(t *testing.T) {
	w := httptest.NewRecorder()
	r := httptest.NewRequest(http.MethodGet, "/seller/size-charts/standard?garment_type=dress&gender=male", nil)
	handleStandardSizeChart(&fakeChartSvc{standardErr: seller.ErrChartNotFound})(w, r)
	if w.Code != http.StatusNotFound {
		t.Fatalf("absent combo → 404, got %d", w.Code)
	}
}

func TestStandardSizeChart_BadParams(t *testing.T) {
	w := httptest.NewRecorder()
	r := httptest.NewRequest(http.MethodGet, "/seller/size-charts/standard?garment_type=hat&gender=female", nil)
	handleStandardSizeChart(&fakeChartSvc{standardErr: seller.ErrInvalidChart})(w, r)
	if w.Code != http.StatusBadRequest {
		t.Fatalf("bad params → 400, got %d", w.Code)
	}
}
