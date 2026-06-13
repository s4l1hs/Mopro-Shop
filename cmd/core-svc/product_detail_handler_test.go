package main

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/mopro/platform/internal/catalog"
	"github.com/mopro/platform/internal/seller"
	"github.com/mopro/platform/internal/shipping"
)

// stubETASvc is a minimal deliveryEstimator for the product-detail handler test.
type stubETASvc struct {
	fn func(market, originCity string, destCity *string) (shipping.ETAResult, error)
}

func (s *stubETASvc) EstimateETA(_ context.Context, market, originCity string, destCity *string) (shipping.ETAResult, error) {
	if s.fn != nil {
		return s.fn(market, originCity, destCity)
	}
	return shipping.ETAResult{}, nil
}

// stubSellerSvc is a minimal seller.Service for the product-detail handler test.
type stubSellerSvc struct {
	getByIDFn func(id int64) (seller.Seller, error)
	bindingFn func(userID int64) (seller.Binding, bool, error)
}

func (s *stubSellerSvc) GetBindingForUser(_ context.Context, userID int64) (seller.Binding, bool, error) {
	if s.bindingFn != nil {
		return s.bindingFn(userID)
	}
	return seller.Binding{}, false, nil
}

func (s *stubSellerSvc) GetBySlug(_ context.Context, _ string) (seller.Seller, error) {
	return seller.Seller{}, seller.ErrSellerNotFound
}
func (s *stubSellerSvc) GetByID(_ context.Context, id int64) (seller.Seller, error) {
	if s.getByIDFn != nil {
		return s.getByIDFn(id)
	}
	return seller.Seller{}, seller.ErrSellerNotFound
}
func (s *stubSellerSvc) ResolveSellerForUser(_ context.Context, _ int64) (int64, bool, error) {
	return 0, false, nil
}
func (s *stubSellerSvc) OfficialSellerIDs(_ context.Context, _ []int64) (map[int64]bool, error) {
	return map[int64]bool{}, nil
}
func (s *stubSellerSvc) SellerNamesByIDs(_ context.Context, _ []int64) (map[int64]string, error) {
	return map[int64]string{}, nil
}
func (s *stubSellerSvc) CreateSizeChart(_ context.Context, _ int64, _ seller.SizeChart) (int64, error) {
	return 0, nil
}
func (s *stubSellerSvc) UpdateSizeChart(_ context.Context, _, _ int64, _ seller.SizeChart) error {
	return nil
}
func (s *stubSellerSvc) ListSizeCharts(_ context.Context, _ int64) ([]seller.SizeChart, error) {
	return nil, nil
}
func (s *stubSellerSvc) AttachProductChart(_ context.Context, _, _, _ int64) error { return nil }
func (s *stubSellerSvc) DetachProductChart(_ context.Context, _, _ int64) error    { return nil }
func (s *stubSellerSvc) SizeChartForProduct(_ context.Context, _ int64) (seller.SizeChart, bool, error) {
	return seller.SizeChart{}, false, nil
}
func (s *stubSellerSvc) StandardSizeChart(_ context.Context, _, _, _ string) (seller.SizeChart, error) {
	return seller.SizeChart{}, nil
}

// stubRatingReader stubs the PD-04 seller-rating carrier (default: no reviews).
type stubRatingReader struct {
	avg   float64
	count int
}

func (s *stubRatingReader) SellerReviewSummary(_ context.Context, _ int64) (float64, int, error) {
	return s.avg, s.count, nil
}

func newProductDetailRequest(productID string) *http.Request {
	r := httptest.NewRequest(http.MethodGet, "/products/"+productID, nil)
	r.SetPathValue("id", productID)
	return r
}

// productDetailBody is the seller-relevant slice of the product-detail response.
// PD-06: the response is the flat, spec-conformant Product — id/seller_* are at
// the top level (no longer nested under a "product" envelope).
type productDetailBody struct {
	ID                int64   `json:"id"`
	SellerID          int64   `json:"seller_id"`
	SellerName        string  `json:"seller_name"`
	SellerSlug        *string  `json:"seller_slug"`
	BasketDiscountPct *int     `json:"basket_discount_pct"`
	SellerRatingAvg   *float64 `json:"seller_rating_avg"`
	SellerRatingCount int      `json:"seller_rating_count"`
	DeliveryEta       *struct {
		MinDays      int     `json:"min_days"`
		MaxDays      int     `json:"max_days"`
		Confident    bool    `json:"confident"`
		DispatchCity *string `json:"dispatch_city"`
	} `json:"delivery_eta"`
}

// PD-03: the PDP surfaces the SAME products.basket_discount_pct the order charges
// (CT-09) → display==charge. The handler must echo the catalog column verbatim
// (non-zero) and omit it when 0.
func TestProductDetail_BasketDiscount_DisplayEqualsCharge(t *testing.T) {
	pct := 15
	catalogSvc := &stubCatalogSvc{
		getByIDFn: func(id int64) (catalog.Product, []catalog.Variant, []catalog.ProductTranslation, error) {
			return catalog.Product{ID: id, SellerID: 1, CategoryID: 30, Status: "active", BasketDiscountPct: &pct}, nil, nil, nil
		},
	}
	sellerSvc := &stubSellerSvc{getByIDFn: func(int64) (seller.Seller, error) {
		return seller.Seller{ID: 1, Slug: "s", DisplayName: "S"}, nil
	}}
	rec := httptest.NewRecorder()
	handleGetProductDetail(catalogSvc, sellerSvc, &stubRatingReader{}, &stubETASvc{}, "tr-TR", "TR", "TRY_COIN")(rec, newProductDetailRequest("7"))
	var body productDetailBody
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode: %v", err)
	}
	// display==charge: the PDP pct is exactly the charged snapshot (no recompute).
	if body.BasketDiscountPct == nil || *body.BasketDiscountPct != pct {
		t.Fatalf("basket_discount_pct: want %d got %v", pct, body.BasketDiscountPct)
	}
}

func TestProductDetail_BasketDiscount_OmittedWhenZero(t *testing.T) {
	zero := 0
	catalogSvc := &stubCatalogSvc{
		getByIDFn: func(id int64) (catalog.Product, []catalog.Variant, []catalog.ProductTranslation, error) {
			return catalog.Product{ID: id, SellerID: 1, Status: "active", BasketDiscountPct: &zero}, nil, nil, nil
		},
	}
	sellerSvc := &stubSellerSvc{getByIDFn: func(int64) (seller.Seller, error) {
		return seller.Seller{ID: 1, Slug: "s", DisplayName: "S"}, nil
	}}
	rec := httptest.NewRecorder()
	handleGetProductDetail(catalogSvc, sellerSvc, &stubRatingReader{}, &stubETASvc{}, "tr-TR", "TR", "TRY_COIN")(rec, newProductDetailRequest("7"))
	var body productDetailBody
	_ = json.Unmarshal(rec.Body.Bytes(), &body)
	if body.BasketDiscountPct != nil {
		t.Fatalf("basket_discount_pct must be omitted when 0, got %v", *body.BasketDiscountPct)
	}
}

// PD-04: the seller's aggregate rating is surfaced on the PDP via the §5-safe
// SellerReviewSummary carrier.
func TestProductDetail_SellerRating_Surfaced(t *testing.T) {
	catalogSvc := &stubCatalogSvc{getByIDFn: func(id int64) (catalog.Product, []catalog.Variant, []catalog.ProductTranslation, error) {
		return catalog.Product{ID: id, SellerID: 1, Status: "active"}, nil, nil, nil
	}}
	sellerSvc := &stubSellerSvc{getByIDFn: func(int64) (seller.Seller, error) {
		return seller.Seller{ID: 1, Slug: "s", DisplayName: "S"}, nil
	}}
	rec := httptest.NewRecorder()
	handleGetProductDetail(catalogSvc, sellerSvc, &stubRatingReader{avg: 4.5, count: 23}, &stubETASvc{}, "tr-TR", "TR", "TRY_COIN")(rec, newProductDetailRequest("7"))
	var body productDetailBody
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if body.SellerRatingAvg == nil || *body.SellerRatingAvg != 4.5 || body.SellerRatingCount != 23 {
		t.Fatalf("rating: want 4.5/23 got %v/%d", body.SellerRatingAvg, body.SellerRatingCount)
	}
}

// PD-04 empty state: no reviews → null avg + 0 count (the card renders no rating).
func TestProductDetail_SellerRating_EmptyState(t *testing.T) {
	catalogSvc := &stubCatalogSvc{getByIDFn: func(id int64) (catalog.Product, []catalog.Variant, []catalog.ProductTranslation, error) {
		return catalog.Product{ID: id, SellerID: 1, Status: "active"}, nil, nil, nil
	}}
	sellerSvc := &stubSellerSvc{getByIDFn: func(int64) (seller.Seller, error) {
		return seller.Seller{ID: 1, Slug: "s", DisplayName: "S"}, nil
	}}
	rec := httptest.NewRecorder()
	handleGetProductDetail(catalogSvc, sellerSvc, &stubRatingReader{}, &stubETASvc{}, "tr-TR", "TR", "TRY_COIN")(rec, newProductDetailRequest("7"))
	var body productDetailBody
	_ = json.Unmarshal(rec.Body.Bytes(), &body)
	if body.SellerRatingAvg != nil || body.SellerRatingCount != 0 {
		t.Fatalf("empty state: want nil/0 got %v/%d", body.SellerRatingAvg, body.SellerRatingCount)
	}
}

func TestProductDetail_ResolvesSellerSlugAndName(t *testing.T) {
	catalogSvc := &stubCatalogSvc{
		getByIDFn: func(id int64) (catalog.Product, []catalog.Variant, []catalog.ProductTranslation, error) {
			return catalog.Product{ID: id, SellerID: 1, CategoryID: 30, Status: "active"}, nil, nil, nil
		},
	}
	sellerSvc := &stubSellerSvc{
		getByIDFn: func(id int64) (seller.Seller, error) {
			if id != 1 {
				t.Fatalf("GetByID called with seller_id=%d, want 1", id)
			}
			return seller.Seller{ID: 1, Slug: "acme-store", DisplayName: "Acme Store"}, nil
		},
	}

	rec := httptest.NewRecorder()
	handleGetProductDetail(catalogSvc, sellerSvc, &stubRatingReader{}, &stubETASvc{}, "tr-TR", "TR", "TRY_COIN")(rec, newProductDetailRequest("7"))

	if rec.Code != http.StatusOK {
		t.Fatalf("status: want 200 got %d (%s)", rec.Code, rec.Body.String())
	}
	var body productDetailBody
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode: %v (%s)", err, rec.Body.String())
	}
	if body.SellerName != "Acme Store" {
		t.Errorf("seller_name: want %q got %q", "Acme Store", body.SellerName)
	}
	if body.SellerSlug == nil || *body.SellerSlug != "acme-store" {
		t.Errorf("seller_slug: want %q got %v", "acme-store", body.SellerSlug)
	}
	// The embedded product fields are still present at the top level.
	if body.ID != 7 || body.SellerID != 1 {
		t.Errorf("embedded product fields wrong: id=%d seller_id=%d", body.ID, body.SellerID)
	}
}

func TestProductDetail_UnresolvedSellerYieldsNullSlug(t *testing.T) {
	catalogSvc := &stubCatalogSvc{
		getByIDFn: func(id int64) (catalog.Product, []catalog.Variant, []catalog.ProductTranslation, error) {
			// seller_id with no matching active seller (pre-5a data / suspended).
			return catalog.Product{ID: id, SellerID: 999, CategoryID: 30, Status: "active"}, nil, nil, nil
		},
	}
	sellerSvc := &stubSellerSvc{} // GetByID → ErrSellerNotFound

	rec := httptest.NewRecorder()
	handleGetProductDetail(catalogSvc, sellerSvc, &stubRatingReader{}, &stubETASvc{}, "tr-TR", "TR", "TRY_COIN")(rec, newProductDetailRequest("7"))

	if rec.Code != http.StatusOK {
		t.Fatalf("status: want 200 got %d (%s)", rec.Code, rec.Body.String())
	}
	var body productDetailBody
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode: %v (%s)", err, rec.Body.String())
	}
	if body.SellerSlug != nil {
		t.Errorf("seller_slug: want null got %q", *body.SellerSlug)
	}
	if body.SellerName != "" {
		t.Errorf("seller_name: want empty got %q", body.SellerName)
	}
}

// TestProductDetail_IncludesDeliveryEta asserts the PDP surfaces the P-034
// estimate, passes the seller's dispatch origin + the dest_city query param, and
// echoes the dispatch city back for the "X'dan gönderilir" line.
func TestProductDetail_IncludesDeliveryEta(t *testing.T) {
	catalogSvc := &stubCatalogSvc{
		getByIDFn: func(id int64) (catalog.Product, []catalog.Variant, []catalog.ProductTranslation, error) {
			return catalog.Product{ID: id, SellerID: 1, CategoryID: 30, Status: "active"}, nil, nil, nil
		},
	}
	dispatch := "istanbul"
	sellerSvc := &stubSellerSvc{
		getByIDFn: func(id int64) (seller.Seller, error) {
			return seller.Seller{ID: 1, Slug: "acme-store", DisplayName: "Acme Store", DispatchCity: &dispatch}, nil
		},
	}
	etaSvc := &stubETASvc{
		fn: func(market, originCity string, destCity *string) (shipping.ETAResult, error) {
			if originCity != "istanbul" {
				t.Errorf("origin city: want istanbul got %q", originCity)
			}
			if destCity == nil || *destCity != "ankara" {
				t.Errorf("dest city: want ankara got %v", destCity)
			}
			return shipping.ETAResult{MinDays: 2, MaxDays: 3, Confident: true}, nil
		},
	}

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/products/7?dest_city=ankara", nil)
	req.SetPathValue("id", "7")
	handleGetProductDetail(catalogSvc, sellerSvc, &stubRatingReader{}, etaSvc, "tr-TR", "TR", "TRY_COIN")(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status: want 200 got %d (%s)", rec.Code, rec.Body.String())
	}
	var body productDetailBody
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode: %v (%s)", err, rec.Body.String())
	}
	if body.DeliveryEta == nil {
		t.Fatalf("delivery_eta missing: %s", rec.Body.String())
	}
	if body.DeliveryEta.MinDays != 2 || body.DeliveryEta.MaxDays != 3 || !body.DeliveryEta.Confident {
		t.Errorf("delivery_eta wrong: %+v", *body.DeliveryEta)
	}
	if body.DeliveryEta.DispatchCity == nil || *body.DeliveryEta.DispatchCity != "istanbul" {
		t.Errorf("dispatch_city: want istanbul got %v", body.DeliveryEta.DispatchCity)
	}
}

// TestProductDetail_OmitsDeliveryEtaWhenNoData asserts the line is omitted (null)
// when the estimator has nothing to offer.
func TestProductDetail_OmitsDeliveryEtaWhenNoData(t *testing.T) {
	catalogSvc := &stubCatalogSvc{
		getByIDFn: func(id int64) (catalog.Product, []catalog.Variant, []catalog.ProductTranslation, error) {
			return catalog.Product{ID: id, SellerID: 1, CategoryID: 30, Status: "active"}, nil, nil, nil
		},
	}
	sellerSvc := &stubSellerSvc{
		getByIDFn: func(id int64) (seller.Seller, error) {
			return seller.Seller{ID: 1, Slug: "acme-store", DisplayName: "Acme Store"}, nil
		},
	}
	etaSvc := &stubETASvc{} // returns ETAResult{} → MaxDays 0

	rec := httptest.NewRecorder()
	handleGetProductDetail(catalogSvc, sellerSvc, &stubRatingReader{}, etaSvc, "tr-TR", "TR", "TRY_COIN")(rec, newProductDetailRequest("7"))

	var body productDetailBody
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode: %v (%s)", err, rec.Body.String())
	}
	if body.DeliveryEta != nil {
		t.Errorf("delivery_eta: want null got %+v", *body.DeliveryEta)
	}
}
