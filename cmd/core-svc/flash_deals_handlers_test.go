package main

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/mopro/platform/internal/catalog"
)

func flashResult() *catalog.FlashDealsResult {
	return &catalog.FlashDealsResult{
		ID:     7,
		Title:  "Bugünün Fırsatları",
		EndsAt: time.Date(2026, 6, 1, 18, 0, 0, 0, time.UTC),
		Products: []catalog.FlashDealProduct{
			{
				Summary: catalog.ProductSummaryRow{
					ID: 1, SellerID: 10, CategoryID: 3, Brand: "B", Status: "active",
					Title: "P1", PriceMinor: 20000, PriceCurrency: "TRY", CommissionPctBps: 1000,
				},
				FlashPriceMinor: 9999,
			},
		},
	}
}

func TestHomeFlashDeals_ActiveCollection_SurfacesFlashPrice(t *testing.T) {
	svc := &stubCatalogSvc{
		homeFlashDealsFn: func(_ context.Context, _ string, _ *int64) (*catalog.FlashDealsResult, error) {
			return flashResult(), nil
		},
	}
	rec := httptest.NewRecorder()
	handleHomeFlashDeals(svc, "tr-TR", "TRY_COIN")(
		rec, httptest.NewRequest(http.MethodGet, "/home/flash-deals", nil))

	if rec.Code != http.StatusOK {
		t.Fatalf("status: got %d, want 200 (body %s)", rec.Code, rec.Body.String())
	}
	var body struct {
		ID       int64  `json:"id"`
		Title    string `json:"title"`
		EndsAt   string `json:"endsAt"`
		Products []struct {
			ID              int64  `json:"id"`
			PriceMinor      int64  `json:"price_minor"`
			FlashPriceMinor *int64 `json:"flash_price_minor"`
		} `json:"products"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if body.ID != 7 || body.Title != "Bugünün Fırsatları" {
		t.Fatalf("meta: id=%d title=%q", body.ID, body.Title)
	}
	if body.EndsAt != "2026-06-01T18:00:00Z" {
		t.Fatalf("endsAt: %q", body.EndsAt)
	}
	if len(body.Products) != 1 {
		t.Fatalf("products: got %d, want 1", len(body.Products))
	}
	if body.Products[0].PriceMinor != 20000 {
		t.Fatalf("original price_minor: %d", body.Products[0].PriceMinor)
	}
	if body.Products[0].FlashPriceMinor == nil || *body.Products[0].FlashPriceMinor != 9999 {
		t.Fatalf("flash_price_minor not surfaced: %v", body.Products[0].FlashPriceMinor)
	}
}

func TestHomeFlashDeals_NoActiveCollection_204(t *testing.T) {
	svc := &stubCatalogSvc{
		homeFlashDealsFn: func(_ context.Context, _ string, _ *int64) (*catalog.FlashDealsResult, error) {
			return nil, nil
		},
	}
	rec := httptest.NewRecorder()
	handleHomeFlashDeals(svc, "tr-TR", "TRY_COIN")(
		rec, httptest.NewRequest(http.MethodGet, "/home/flash-deals", nil))
	if rec.Code != http.StatusNoContent {
		t.Fatalf("status: got %d, want 204", rec.Code)
	}
}

func TestHomeFlashDeals_MissingCollectionID_404(t *testing.T) {
	svc := &stubCatalogSvc{
		homeFlashDealsFn: func(_ context.Context, _ string, _ *int64) (*catalog.FlashDealsResult, error) {
			return nil, nil // not found
		},
	}
	rec := httptest.NewRecorder()
	handleHomeFlashDeals(svc, "tr-TR", "TRY_COIN")(
		rec, httptest.NewRequest(http.MethodGet, "/home/flash-deals?collectionId=5", nil))
	if rec.Code != http.StatusNotFound {
		t.Fatalf("status: got %d, want 404", rec.Code)
	}
}

func TestHomeFlashDeals_InvalidCollectionID_400(t *testing.T) {
	called := false
	svc := &stubCatalogSvc{
		homeFlashDealsFn: func(_ context.Context, _ string, _ *int64) (*catalog.FlashDealsResult, error) {
			called = true
			return nil, nil
		},
	}
	rec := httptest.NewRecorder()
	handleHomeFlashDeals(svc, "tr-TR", "TRY_COIN")(
		rec, httptest.NewRequest(http.MethodGet, "/home/flash-deals?collectionId=abc", nil))
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status: got %d, want 400", rec.Code)
	}
	if called {
		t.Fatal("service should not be called for an invalid collectionId")
	}
}
