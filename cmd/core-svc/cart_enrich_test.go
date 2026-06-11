package main

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"testing"

	"github.com/mopro/platform/internal/cart"
	"github.com/mopro/platform/internal/catalog"
	"github.com/mopro/platform/internal/order"
)

type fakeCartCatalog struct{}

func (fakeCartCatalog) GetVariantByID(_ context.Context, id int64) (catalog.Variant, error) {
	switch id {
	case 10:
		return catalog.Variant{ID: 10, ProductID: 100, CategoryID: 30, SellerID: 1,
			Color: "Siyah", Size: "M", PriceMinor: 10000, PriceCurrency: "TRY",
			ImageKeys: []string{"products/v10/1.jpg"}}, nil
	case 20:
		return catalog.Variant{ID: 20, ProductID: 200, CategoryID: 30, SellerID: 2,
			Color: "Beyaz", PriceMinor: 5000, PriceCurrency: "TRY"}, nil
	}
	return catalog.Variant{}, errors.New("variant not found")
}

func (fakeCartCatalog) ListProductsByIDs(_ context.Context, _ []int64, _, _ string) ([]catalog.ProductSummaryRow, error) {
	return []catalog.ProductSummaryRow{
		{ID: 100, Title: "Ürün A", CoverImageKey: "products/100/cover.jpg"},
		{ID: 200, Title: "Ürün B"},
	}, nil
}

func (fakeCartCatalog) GetCommissionForCategory(_ context.Context, _ string, _ int64) (catalog.CategoryCommission, error) {
	return catalog.CategoryCommission{KdvPctBps: 2000}, nil // 20%
}

type fakeNamer struct{}

func (fakeNamer) SellerNamesByIDs(_ context.Context, _ []int64) (map[int64]string, error) {
	return map[int64]string{1: "Acme Store", 2: "Moda Evi"}, nil
}

func TestEnrichCart(t *testing.T) {
	c := cart.Cart{UserID: 7, Items: []cart.CartItem{
		{VariantID: 10, Qty: 2},
		{VariantID: 20, Qty: 1},
	}}
	out := enrichCart(context.Background(), c, fakeCartCatalog{}, fakeNamer{}, "tr-TR", "TR")

	if len(out.Lines) != 2 {
		t.Fatalf("want 2 lines, got %d", len(out.Lines))
	}
	l0 := out.Lines[0]
	if l0.ID != "10" || l0.VariantID != 10 || l0.ProductID != 100 || l0.SellerID != 1 {
		t.Errorf("line0 ids wrong: %+v", l0)
	}
	if l0.SellerName != "Acme Store" {
		t.Errorf("line0 seller_name: want Acme Store got %q", l0.SellerName)
	}
	if l0.VariantLabel != "Siyah, M" {
		t.Errorf("line0 variant_label: want %q got %q", "Siyah, M", l0.VariantLabel)
	}
	if l0.Title != "Ürün A" || l0.PriceMinor != 10000 || l0.Qty != 2 {
		t.Errorf("line0 enrich wrong: %+v", l0)
	}
	if l0.CoverImageURL == "" {
		t.Errorf("line0 cover image not resolved (variant image)")
	}
	if out.Lines[1].VariantLabel != "Beyaz" { // size empty → colour only
		t.Errorf("line1 variant_label: want Beyaz got %q", out.Lines[1].VariantLabel)
	}

	// Totals: seller 1 = 20000, seller 2 = 5000, grand = 25000.
	if len(out.TotalsBySeller) != 2 {
		t.Fatalf("want 2 seller totals, got %d", len(out.TotalsBySeller))
	}
	if out.TotalsBySeller[0].SellerID != 1 || out.TotalsBySeller[0].ItemsMinor != 20000 ||
		out.TotalsBySeller[0].TotalMinor != 20000 || out.TotalsBySeller[0].ShippingMinor != 0 {
		t.Errorf("seller0 total wrong: %+v", out.TotalsBySeller[0])
	}
	if out.GrandTotalMinor != 25000 {
		t.Errorf("grand_total: want 25000 got %d", out.GrandTotalMinor)
	}
	// KDV-inclusive portion: 20000*2000/12000 + 5000*2000/12000 = 3333 + 833 = 4166.
	if out.KdvIncludedMinor != 4166 {
		t.Errorf("kdv_included: want 4166 got %d", out.KdvIncludedMinor)
	}

	// JSON keys must match the mobile CartDto/CartLineDto/SellerTotalDto exactly.
	b, _ := json.Marshal(out)
	for _, key := range []string{`"lines"`, `"totals_by_seller"`, `"grand_total_minor"`,
		`"kdv_included_minor"`, `"seller_name"`, `"variant_label"`, `"items_minor"`,
		`"shipping_minor"`, `"total_minor"`, `"price_minor"`, `"cover_image_url"`} {
		if !strings.Contains(string(b), key) {
			t.Errorf("marshaled cart missing key %s: %s", key, b)
		}
	}
}

// discountCatalog returns variant 10 with a 20% basket discount (CT-09).
type discountCatalog struct{ fakeCartCatalog }

func (discountCatalog) GetVariantByID(_ context.Context, id int64) (catalog.Variant, error) {
	pct := 20
	return catalog.Variant{ID: id, ProductID: 100, CategoryID: 30, SellerID: 1,
		PriceMinor: 10000, PriceCurrency: "TRY", BasketDiscountPct: &pct}, nil
}

// TestEnrichCart_BasketDiscount is the CT-09 asymmetry guard: the cart DISPLAY
// charges the discounted price (PriceMinor) computed by the SAME helper the order
// build uses, surfaces the strikethrough (ListPriceMinor) and the "Sepette
// indirim" line (BasketDiscountMinor), and the grand total is the discounted sum.
func TestEnrichCart_BasketDiscount(t *testing.T) {
	c := cart.Cart{UserID: 7, Items: []cart.CartItem{{VariantID: 10, Qty: 2}}}
	out := enrichCart(context.Background(), c, discountCatalog{}, fakeNamer{}, "tr-TR", "TR")

	if len(out.Lines) != 1 {
		t.Fatalf("want 1 line, got %d", len(out.Lines))
	}
	l := out.Lines[0]
	// 10000 − round(10000*20/100)=2000 → 8000 charged unit; list = 10000.
	if l.PriceMinor != 8000 {
		t.Errorf("charged unit: want 8000, got %d", l.PriceMinor)
	}
	if l.ListPriceMinor != 10000 {
		t.Errorf("list (strikethrough) unit: want 10000, got %d", l.ListPriceMinor)
	}
	// Display == charge: the cart helper and the order build agree by construction.
	if l.PriceMinor != order.DiscountedUnitMinor(10000, 20) {
		t.Errorf("display/charge asymmetry: cart %d != order build %d",
			l.PriceMinor, order.DiscountedUnitMinor(10000, 20))
	}
	if out.BasketDiscountMinor != 4000 { // (10000−8000)*2
		t.Errorf("basket_discount_minor: want 4000, got %d", out.BasketDiscountMinor)
	}
	if out.GrandTotalMinor != 16000 { // 8000*2
		t.Errorf("grand_total (charged): want 16000, got %d", out.GrandTotalMinor)
	}
	// Pre-discount subtotal = charged total + the discount line.
	if out.GrandTotalMinor+out.BasketDiscountMinor != 20000 {
		t.Errorf("subtotal reconstruction: want 20000, got %d", out.GrandTotalMinor+out.BasketDiscountMinor)
	}
}

func TestEnrichCart_Empty(t *testing.T) {
	out := enrichCart(context.Background(), cart.Cart{UserID: 7}, fakeCartCatalog{}, fakeNamer{}, "tr-TR", "TR")
	if out.Lines == nil || len(out.Lines) != 0 || out.TotalsBySeller == nil {
		t.Errorf("empty cart must emit empty (non-nil) slices: %+v", out)
	}
	if b, _ := json.Marshal(out); !strings.Contains(string(b), `"lines":[]`) {
		t.Errorf("empty lines must marshal to []: %s", b)
	}
}
