package main

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/mopro/platform/internal/catalog"
	"github.com/mopro/platform/internal/seller"
)

// stubSellerSvc is a minimal seller.Service for the product-detail handler test.
type stubSellerSvc struct {
	getByIDFn func(id int64) (seller.Seller, error)
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

func newProductDetailRequest(productID string) *http.Request {
	r := httptest.NewRequest(http.MethodGet, "/products/"+productID, nil)
	r.SetPathValue("id", productID)
	return r
}

// productDetailBody is the seller-relevant slice of the product-detail response.
type productDetailBody struct {
	Product struct {
		ID         int64   `json:"id"`
		SellerID   int64   `json:"seller_id"`
		SellerName string  `json:"seller_name"`
		SellerSlug *string `json:"seller_slug"`
	} `json:"product"`
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
	handleGetProductDetail(catalogSvc, sellerSvc, "TR", "TRY_COIN")(rec, newProductDetailRequest("7"))

	if rec.Code != http.StatusOK {
		t.Fatalf("status: want 200 got %d (%s)", rec.Code, rec.Body.String())
	}
	var body productDetailBody
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode: %v (%s)", err, rec.Body.String())
	}
	if body.Product.SellerName != "Acme Store" {
		t.Errorf("seller_name: want %q got %q", "Acme Store", body.Product.SellerName)
	}
	if body.Product.SellerSlug == nil || *body.Product.SellerSlug != "acme-store" {
		t.Errorf("seller_slug: want %q got %v", "acme-store", body.Product.SellerSlug)
	}
	// The embedded product fields are still present at the top level.
	if body.Product.ID != 7 || body.Product.SellerID != 1 {
		t.Errorf("embedded product fields wrong: id=%d seller_id=%d", body.Product.ID, body.Product.SellerID)
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
	handleGetProductDetail(catalogSvc, sellerSvc, "TR", "TRY_COIN")(rec, newProductDetailRequest("7"))

	if rec.Code != http.StatusOK {
		t.Fatalf("status: want 200 got %d (%s)", rec.Code, rec.Body.String())
	}
	var body productDetailBody
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode: %v (%s)", err, rec.Body.String())
	}
	if body.Product.SellerSlug != nil {
		t.Errorf("seller_slug: want null got %q", *body.Product.SellerSlug)
	}
	if body.Product.SellerName != "" {
		t.Errorf("seller_name: want empty got %q", body.Product.SellerName)
	}
}
