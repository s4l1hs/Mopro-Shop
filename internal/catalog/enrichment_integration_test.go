//go:build integration

package catalog_test

// Integration tests for the P-004/P-009 ProductSummary enrichment: favorites_count
// (count of user_favorites) + free_shipping passthrough. Reuses the pf* fixtures
// from filter_integration_test.go (same package, shared ephemeral PG).

import (
	"context"
	"testing"

	"github.com/mopro/platform/internal/catalog"
)

func pfFavorite(t *testing.T, ctx context.Context, userID int, productID int64) {
	t.Helper()
	if _, err := integPool.Exec(ctx,
		`INSERT INTO catalog_schema.user_favorites (user_id, product_id) VALUES ($1, $2)`,
		userID, productID); err != nil {
		t.Fatalf("seed favorite: %v", err)
	}
}

func TestIntegration_ProductSummaryEnrichment(t *testing.T) {
	ctx := context.Background()
	pfSetupCat(t, ctx)
	repo := catalog.NewRepository(integPool)

	a := pfSeed(t, ctx, "Apple", "Enrich Alpha", 10000, pfF64(4.5), 10, true, 5)
	b := pfSeed(t, ctx, "Nokia", "Enrich Beta", 20000, nil, 0, false, 3)

	// 3 users favorite A; 1 user favorites B.
	for _, uid := range []int{901, 902, 903} {
		pfFavorite(t, ctx, uid, a)
	}
	pfFavorite(t, ctx, 901, b)

	byID := func(rows []catalog.ProductSummaryRow) map[int64]catalog.ProductSummaryRow {
		m := make(map[int64]catalog.ProductSummaryRow, len(rows))
		for _, r := range rows {
			m[r.ID] = r
		}
		return m
	}

	t.Run("ListProductsByCategory enriches favorites_count + free_shipping", func(t *testing.T) {
		rows, _, err := repo.ListProductsByCategory(ctx, pfCat, "tr-TR", catalog.ProductFilter{}, 0, 50)
		if err != nil {
			t.Fatalf("ListProductsByCategory: %v", err)
		}
		m := byID(rows)
		if m[a].FavoritesCount != 3 {
			t.Errorf("A favorites_count: got %d, want 3", m[a].FavoritesCount)
		}
		if m[b].FavoritesCount != 1 {
			t.Errorf("B favorites_count: got %d, want 1", m[b].FavoritesCount)
		}
		if !m[a].FreeShipping {
			t.Error("A free_shipping: want true")
		}
		if m[b].FreeShipping {
			t.Error("B free_shipping: want false")
		}
	})

	// ListProductsByIDs had a pre-existing SELECT/scan column mismatch (the guest-
	// favorites hydration path) — this both fixes it (no scan error) and enriches.
	t.Run("ListProductsByIDs no longer errors + enriches", func(t *testing.T) {
		rows, err := repo.ListProductsByIDs(ctx, []int64{a, b}, "tr-TR")
		if err != nil {
			t.Fatalf("ListProductsByIDs: %v", err)
		}
		if len(rows) != 2 {
			t.Fatalf("ListProductsByIDs: got %d rows, want 2", len(rows))
		}
		m := byID(rows)
		if m[a].FavoritesCount != 3 || !m[a].FreeShipping {
			t.Errorf("A via ByIDs: favorites=%d free=%v, want 3/true",
				m[a].FavoritesCount, m[a].FreeShipping)
		}
		if m[a].RatingAvg == nil || *m[a].RatingAvg != 4.5 {
			t.Errorf("A via ByIDs: rating_avg not hydrated (got %v) — the scan fix", m[a].RatingAvg)
		}
	})

	t.Run("zero favorites -> count 0", func(t *testing.T) {
		c := pfSeed(t, ctx, "Sony", "Enrich Gamma", 5000, nil, 0, false, 1)
		rows, _, err := repo.ListProductsByCategory(ctx, pfCat, "tr-TR", catalog.ProductFilter{}, 0, 50)
		if err != nil {
			t.Fatalf("list: %v", err)
		}
		if byID(rows)[c].FavoritesCount != 0 {
			t.Errorf("C favorites_count: got %d, want 0", byID(rows)[c].FavoritesCount)
		}
	})
}
