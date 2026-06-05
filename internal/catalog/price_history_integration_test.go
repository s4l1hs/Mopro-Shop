//go:build integration

package catalog_test

// Integration tests for P-030 variant price-history tracking (Mechanism B: the
// AFTER INSERT OR UPDATE trigger on catalog_schema.variants) and the
// ProductSummary.lowest_30d_price_minor read. Reuses the pf* fixtures from
// filter_integration_test.go + the shared setupSchema, which mirrors migration
// 0083's trigger. See docs/internal/p030-price-history-architecture.md.

import (
	"context"
	"testing"

	"github.com/mopro/platform/internal/catalog"
)

// vphCount returns the number of variant_price_history rows for a product,
// optionally filtered by source ("" = any source).
func vphCount(t *testing.T, ctx context.Context, productID int64, source string) int {
	t.Helper()
	q := `SELECT count(*) FROM catalog_schema.variant_price_history WHERE product_id = $1`
	args := []any{productID}
	if source != "" {
		q += ` AND source = $2`
		args = append(args, source)
	}
	var n int
	if err := integPool.QueryRow(ctx, q, args...).Scan(&n); err != nil {
		t.Fatalf("vphCount: %v", err)
	}
	return n
}

func TestIntegration_VariantPriceHistory(t *testing.T) {
	ctx := context.Background()
	pfSetupCat(t, ctx)
	repo := catalog.NewRepository(integPool)

	// lowest fetches one product's ProductSummary.Lowest30dPriceMinor.
	lowest := func(productID int64) *int64 {
		rows, err := repo.ListProductsByIDs(ctx, []int64{productID}, "tr-TR")
		if err != nil {
			t.Fatalf("ListProductsByIDs: %v", err)
		}
		if len(rows) != 1 {
			t.Fatalf("want 1 row, got %d", len(rows))
		}
		return rows[0].Lowest30dPriceMinor
	}

	t.Run("trigger records a 'create' row on variant insert", func(t *testing.T) {
		p := pfSeed(t, ctx, "Casio", "VPH Create", 30000, nil, 0, false, 5)
		if got := vphCount(t, ctx, p, "create"); got != 1 {
			t.Errorf("create rows: got %d, want 1", got)
		}
		if l := lowest(p); l == nil || *l != 30000 {
			t.Errorf("lowest_30d: got %v, want 30000", l)
		}
	})

	t.Run("trigger records 'update' only when the price actually changes", func(t *testing.T) {
		p := pfSeed(t, ctx, "Seiko", "VPH Update", 50000, nil, 0, false, 5)
		// No-op update (same price) must NOT add a row (IS DISTINCT FROM guard).
		mustExec(t, `UPDATE catalog_schema.variants SET price_minor = 50000 WHERE product_id = $1`, p)
		if got := vphCount(t, ctx, p, "update"); got != 0 {
			t.Errorf("update rows after no-op: got %d, want 0", got)
		}
		// A real change adds exactly one update row.
		mustExec(t, `UPDATE catalog_schema.variants SET price_minor = 40000 WHERE product_id = $1`, p)
		if got := vphCount(t, ctx, p, "update"); got != 1 {
			t.Errorf("update rows after change: got %d, want 1", got)
		}
	})

	t.Run("lowest_30d is the historical low, not the current price", func(t *testing.T) {
		// Create at 20000, then raise to 25000: current price is 25000 but the
		// 30-day low remains 20000.
		p := pfSeed(t, ctx, "Timex", "VPH Low", 20000, nil, 0, false, 5)
		mustExec(t, `UPDATE catalog_schema.variants SET price_minor = 25000 WHERE product_id = $1`, p)
		rows, err := repo.ListProductsByIDs(ctx, []int64{p}, "tr-TR")
		if err != nil {
			t.Fatalf("ListProductsByIDs: %v", err)
		}
		r := rows[0]
		if r.PriceMinor != 25000 {
			t.Errorf("current price: got %d, want 25000", r.PriceMinor)
		}
		if r.Lowest30dPriceMinor == nil || *r.Lowest30dPriceMinor != 20000 {
			t.Errorf("lowest_30d: got %v, want 20000 (the historical low)", r.Lowest30dPriceMinor)
		}
	})

	t.Run("price points older than 30 days are excluded from the window", func(t *testing.T) {
		p := pfSeed(t, ctx, "Swatch", "VPH Window", 18000, nil, 0, false, 5)
		var vid int64
		if err := integPool.QueryRow(ctx,
			`SELECT id FROM catalog_schema.variants WHERE product_id = $1`, p).Scan(&vid); err != nil {
			t.Fatalf("variant id: %v", err)
		}
		// A cheaper price 31 days ago must NOT lower the 30-day window low.
		mustExec(t,
			`INSERT INTO catalog_schema.variant_price_history
			   (variant_id, product_id, price_minor, currency, source, effective_at)
			 VALUES ($1, $2, 9000, 'TRY', 'backfill', now() - interval '31 days')`, vid, p)
		if l := lowest(p); l == nil || *l != 18000 {
			t.Errorf("lowest_30d: got %v, want 18000 (the 9000 row is out of window)", l)
		}
	})
}
