package main

import (
	"context"
	"log/slog"
	"strconv"
	"strings"

	"github.com/mopro/platform/internal/cart"
	"github.com/mopro/platform/internal/catalog"
	"github.com/mopro/platform/pkg/mediaurl"
)

// cartCatalogResolver is the slice of catalog.Service the cart enrichment needs
// (variant → label/price/seller, product → title/cover, category → KDV). Narrow
// so handleGetCart is contract-testable without a live catalog.
type cartCatalogResolver interface {
	GetVariantByID(ctx context.Context, variantID int64) (catalog.Variant, error)
	ListProductsByIDs(ctx context.Context, ids []int64, locale, market string) ([]catalog.ProductSummaryRow, error)
	GetCommissionForCategory(ctx context.Context, market string, categoryID int64) (catalog.CategoryCommission, error)
}

// cartSellerNamer resolves seller display names (CT-01).
type cartSellerNamer interface {
	SellerNamesByIDs(ctx context.Context, ids []int64) (map[int64]string, error)
}

// cartLineJSON / sellerTotalJSON / cartJSON mirror the mobile CartLineDto /
// SellerTotalDto / CartDto exactly (hand-written; cart isn't in the OpenAPI spec).
type cartLineJSON struct {
	ID            string `json:"id"`
	ProductID     int64  `json:"product_id"`
	VariantID     int64  `json:"variant_id"`
	SellerID      int64  `json:"seller_id"`
	SellerName    string `json:"seller_name"`
	Title         string `json:"title"`
	VariantLabel  string `json:"variant_label"`
	PriceMinor    int64  `json:"price_minor"`
	Qty           int    `json:"qty"`
	CoverImageURL string `json:"cover_image_url,omitempty"`
}

type sellerTotalJSON struct {
	SellerID      int64 `json:"seller_id"`
	ItemsMinor    int64 `json:"items_minor"`
	ShippingMinor int64 `json:"shipping_minor"`
	TotalMinor    int64 `json:"total_minor"`
}

type cartJSON struct {
	ID               string            `json:"id"`
	UserID           int64             `json:"user_id"`
	Lines            []cartLineJSON    `json:"lines"`
	TotalsBySeller   []sellerTotalJSON `json:"totals_by_seller"`
	GrandTotalMinor  int64             `json:"grand_total_minor"`
	KdvIncludedMinor int64             `json:"kdv_included_minor"`
}

// variantLabel joins the variant's non-empty colour/size into a display string
// ("Siyah, M"). Values only (no locale-specific "Renk:"/"Beden:" prefixes) so the
// server stays locale-agnostic; the client prefixes if it wants.
func variantLabel(v catalog.Variant) string {
	parts := make([]string, 0, 2)
	if v.Color != "" {
		parts = append(parts, v.Color)
	}
	if v.Size != "" {
		parts = append(parts, v.Size)
	}
	return strings.Join(parts, ", ")
}

// enrichCart turns the raw cart (variant_id + qty) into the rich cartJSON the
// mobile expects, resolving everything §5-safely via in-process service calls
// (no cross-schema JOIN; the merge lives here in cmd/core-svc, not internal/cart).
// Per-line resolution failures skip that line rather than failing the whole cart.
func enrichCart(ctx context.Context, c cart.Cart, cat cartCatalogResolver, namer cartSellerNamer, locale, market string) cartJSON {
	out := cartJSON{
		ID:             "",
		UserID:         c.UserID,
		Lines:          []cartLineJSON{},
		TotalsBySeller: []sellerTotalJSON{},
	}
	if len(c.Items) == 0 {
		return out
	}

	type pending struct {
		item    cart.CartItem
		variant catalog.Variant
	}
	resolved := make([]pending, 0, len(c.Items))
	productIDset := map[int64]struct{}{}
	sellerIDset := map[int64]struct{}{}
	categoryIDset := map[int64]struct{}{}
	for _, it := range c.Items {
		v, err := cat.GetVariantByID(ctx, it.VariantID)
		if err != nil {
			slog.Warn("cart: enrich resolve variant", "variant_id", it.VariantID, "err", err)
			continue
		}
		resolved = append(resolved, pending{item: it, variant: v})
		productIDset[v.ProductID] = struct{}{}
		sellerIDset[v.SellerID] = struct{}{}
		categoryIDset[v.CategoryID] = struct{}{}
	}
	if len(resolved) == 0 {
		return out
	}

	// Product titles + cover images (batch).
	prodByID := map[int64]catalog.ProductSummaryRow{}
	if products, err := cat.ListProductsByIDs(ctx, keysOf(productIDset), locale, market); err == nil {
		for _, p := range products {
			prodByID[p.ID] = p
		}
	} else {
		slog.Warn("cart: enrich products", "err", err)
	}

	// Seller names (batch, §5-safe carrier).
	names, err := namer.SellerNamesByIDs(ctx, keysOf(sellerIDset))
	if err != nil {
		slog.Warn("cart: enrich seller names", "err", err)
		names = map[int64]string{}
	}

	// KDV rate per category (for the KDV-inclusive portion).
	kdvByCat := map[int64]int{}
	for catID := range categoryIDset {
		if cc, err := cat.GetCommissionForCategory(ctx, market, catID); err == nil {
			kdvByCat[catID] = cc.KdvPctBps
		}
	}

	// Build lines + accumulate per-seller totals + KDV (preserving cart order).
	type acc struct {
		items int64
		order int
	}
	totals := map[int64]*acc{}
	sellerOrder := 0
	var grand, kdv int64
	for _, pr := range resolved {
		v := pr.variant
		lineTotal := v.PriceMinor * int64(pr.item.Qty)
		grand += lineTotal
		if bps, ok := kdvByCat[v.CategoryID]; ok && bps > 0 {
			kdv += lineTotal * int64(bps) / int64(10000+bps)
		}

		cover := ""
		if len(v.ImageKeys) > 0 {
			cover = mediaurl.CDNUrl(v.ImageKeys[0])
		} else if p, ok := prodByID[v.ProductID]; ok {
			cover = mediaurl.CDNUrl(p.CoverImageKey)
		}
		out.Lines = append(out.Lines, cartLineJSON{
			ID:            strconv.FormatInt(v.ID, 10),
			ProductID:     v.ProductID,
			VariantID:     v.ID,
			SellerID:      v.SellerID,
			SellerName:    names[v.SellerID],
			Title:         prodByID[v.ProductID].Title,
			VariantLabel:  variantLabel(v),
			PriceMinor:    v.PriceMinor,
			Qty:           pr.item.Qty,
			CoverImageURL: cover,
		})

		a := totals[v.SellerID]
		if a == nil {
			a = &acc{order: sellerOrder}
			sellerOrder++
			totals[v.SellerID] = a
		}
		a.items += lineTotal
	}

	// Emit totals_by_seller in first-seen order.
	ordered := make([]int64, len(totals))
	for sid, a := range totals {
		ordered[a.order] = sid
	}
	for _, sid := range ordered {
		a := totals[sid]
		out.TotalsBySeller = append(out.TotalsBySeller, sellerTotalJSON{
			SellerID:      sid,
			ItemsMinor:    a.items,
			ShippingMinor: 0, // v1: cargo handled separately (CLAUDE.md §2.3/§4.8)
			TotalMinor:    a.items,
		})
	}
	out.GrandTotalMinor = grand
	out.KdvIncludedMinor = kdv
	return out
}

func keysOf(m map[int64]struct{}) []int64 {
	out := make([]int64, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	return out
}
