package main

import (
	"context"
	"encoding/json"
	"strings"
	"testing"

	"github.com/mopro/platform/internal/order"
)

// TestEnrichOrderItems verifies the OR-05 §5 carrier produces the rich line the
// mobile OrderItemDto needs (title + variant_label + price_minor + cover) from the
// frozen snapshot, reusing fakeCartCatalog (variant 10 → product 100 "Ürün A",
// Siyah/M, cover from variant image).
func TestEnrichOrderItems(t *testing.T) {
	items := []order.OrderItem{
		{ID: 1, OrderID: 9, VariantID: 10, SellerID: 1, Qty: 2, UnitPriceMinor: 8500, UnitPriceCurrency: "TRY", CommissionPctBps: 700},
	}
	out := enrichOrderItems(context.Background(), items, fakeCartCatalog{}, "tr-TR", "TR")

	if len(out) != 1 {
		t.Fatalf("want 1 line, got %d", len(out))
	}
	l := out[0]
	if l.Title != "Ürün A" {
		t.Errorf("title: want %q, got %q", "Ürün A", l.Title)
	}
	if l.VariantLabel != "Siyah, M" {
		t.Errorf("variant_label: want %q, got %q", "Siyah, M", l.VariantLabel)
	}
	if l.ProductID != 100 {
		t.Errorf("product_id: want 100, got %d", l.ProductID)
	}
	if l.PriceMinor != 8500 { // = charged unit_price_minor
		t.Errorf("price_minor: want 8500, got %d", l.PriceMinor)
	}
	if l.Qty != 2 || l.CommissionPctBps != 700 {
		t.Errorf("frozen fields wrong: qty=%d bps=%d", l.Qty, l.CommissionPctBps)
	}
	if l.CoverImageURL == "" {
		t.Error("cover_image_url not resolved")
	}

	// The wire keys must match what mobile OrderItemDto.fromJson requires.
	b, _ := json.Marshal(l)
	for _, key := range []string{`"title"`, `"price_minor"`, `"variant_label"`,
		`"product_id"`, `"variant_id"`, `"qty"`, `"cover_image_url"`} {
		if !strings.Contains(string(b), key) {
			t.Errorf("marshaled item missing key %s: %s", key, b)
		}
	}
}

// Resolution failure degrades gracefully: the line is still emitted with its
// frozen fields (label/title empty), never dropped.
func TestEnrichOrderItems_VariantResolveFailureDegrades(t *testing.T) {
	items := []order.OrderItem{
		{ID: 2, OrderID: 9, VariantID: 999 /* not in fake */, Qty: 1, UnitPriceMinor: 5000},
	}
	out := enrichOrderItems(context.Background(), items, fakeCartCatalog{}, "tr-TR", "TR")
	if len(out) != 1 {
		t.Fatalf("want 1 line even on resolve failure, got %d", len(out))
	}
	if out[0].PriceMinor != 5000 || out[0].VariantLabel != "" || out[0].Title != "" {
		t.Errorf("degraded line wrong: %+v", out[0])
	}
}
