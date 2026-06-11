package main

import (
	"context"
	"log/slog"

	"github.com/mopro/platform/internal/catalog"
	"github.com/mopro/platform/internal/order"
	"github.com/mopro/platform/pkg/mediaurl"
)

// orderCatalogResolver is the narrow slice of catalog.Service the order-detail
// item enrichment needs (OR-05). §5-safe carrier — resolves variant → label/cover/
// product and product → title via the catalog Service, never a cross-schema JOIN.
// Mirrors cartCatalogResolver so handleGetOrder is contract-testable without a live
// catalog.
type orderCatalogResolver interface {
	GetVariantByID(ctx context.Context, variantID int64) (catalog.Variant, error)
	ListProductsByIDs(ctx context.Context, ids []int64, locale, market string) ([]catalog.ProductSummaryRow, error)
}

// orderItemJSON is the enriched order-line shape the mobile OrderItemDto expects
// (title + price_minor + cover + variant_label). The raw order_items snapshot
// carries only variant_id/unit_price_minor, so without this the detail items don't
// render (OR-05 — the same pre-enrichment gap the cart had, #176).
type orderItemJSON struct {
	ID                int64  `json:"id"`
	OrderID           int64  `json:"order_id"`
	ProductID         int64  `json:"product_id"`
	VariantID         int64  `json:"variant_id"`
	SellerID          int64  `json:"seller_id"`
	Title             string `json:"title"`
	VariantLabel      string `json:"variant_label"`
	PriceMinor        int64  `json:"price_minor"`
	Qty               int    `json:"qty"`
	CommissionPctBps  int    `json:"commission_pct_bps"`
	CoverImageURL     string `json:"cover_image_url,omitempty"`
	UnitPriceCurrency string `json:"unit_price_currency"`
}

// enrichOrderItems resolves each frozen order item into the rich line the mobile
// expects, §5-safely via in-process catalog Service calls. Per-item resolution
// failures degrade gracefully (the line is still emitted with its frozen fields;
// title/label/cover just stay empty) rather than failing the whole order.
func enrichOrderItems(ctx context.Context, items []order.OrderItem, cat orderCatalogResolver, locale, market string) []orderItemJSON {
	out := make([]orderItemJSON, 0, len(items))
	if len(items) == 0 {
		return out
	}

	// Resolve variants (label, cover, product_id) and collect product ids for a
	// single batched title/cover lookup.
	type resolved struct {
		item    order.OrderItem
		variant catalog.Variant
		hasVar  bool
	}
	rs := make([]resolved, 0, len(items))
	productIDset := map[int64]struct{}{}
	for _, it := range items {
		v, err := cat.GetVariantByID(ctx, it.VariantID)
		if err != nil {
			slog.Warn("order: enrich resolve variant", "variant_id", it.VariantID, "err", err)
			rs = append(rs, resolved{item: it})
			continue
		}
		rs = append(rs, resolved{item: it, variant: v, hasVar: true})
		productIDset[v.ProductID] = struct{}{}
	}

	prodByID := map[int64]catalog.ProductSummaryRow{}
	if len(productIDset) > 0 {
		ids := make([]int64, 0, len(productIDset))
		for id := range productIDset {
			ids = append(ids, id)
		}
		if products, err := cat.ListProductsByIDs(ctx, ids, locale, market); err == nil {
			for _, p := range products {
				prodByID[p.ID] = p
			}
		} else {
			slog.Warn("order: enrich products", "err", err)
		}
	}

	for _, r := range rs {
		it := r.item
		line := orderItemJSON{
			ID:                it.ID,
			OrderID:           it.OrderID,
			VariantID:         it.VariantID,
			SellerID:          it.SellerID,
			PriceMinor:        it.UnitPriceMinor, // the charged (basket-discounted) unit
			Qty:               it.Qty,
			CommissionPctBps:  it.CommissionPctBps,
			UnitPriceCurrency: it.UnitPriceCurrency,
		}
		if r.hasVar {
			v := r.variant
			line.ProductID = v.ProductID
			line.VariantLabel = variantLabel(v) // reused from cart_enrich.go
			if len(v.ImageKeys) > 0 {
				line.CoverImageURL = mediaurl.CDNUrl(v.ImageKeys[0])
			}
			if p, ok := prodByID[v.ProductID]; ok {
				line.Title = p.Title
				if line.CoverImageURL == "" {
					line.CoverImageURL = mediaurl.CDNUrl(p.CoverImageKey)
				}
			}
		}
		out = append(out, line)
	}
	return out
}
