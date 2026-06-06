package main

import (
	"context"
	"testing"

	"github.com/mopro/platform/internal/catalog"
)

// applyBestsellerOrder routing (P-031): category scope when a category is given,
// global fallback when that category has no data, global when none, no-op when
// the sort isn't bestseller. fakeRecsSvc is defined in recommendations_handlers_test.go.
func TestApplyBestsellerOrder_Routing(t *testing.T) {
	svc := &fakeRecsSvc{
		popularIDs:   []int64{1, 2},                // global ranking
		popularByCat: map[int64][]int64{5: {3, 4}}, // category 5 has data; others empty
	}
	cat5 := int64(5)
	cat9 := int64(9) // no per-category data → fallback path

	t.Run("category with data uses the category scope", func(t *testing.T) {
		f := catalog.ProductFilter{Sort: "bestseller"}
		applyBestsellerOrder(context.Background(), svc, &cat5, &f)
		if got := f.PopularIDs; len(got) != 2 || got[0] != 3 || got[1] != 4 {
			t.Fatalf("category scope: got %v, want [3 4]", got)
		}
	})

	t.Run("empty category falls back to the global proxy", func(t *testing.T) {
		f := catalog.ProductFilter{Sort: "bestseller"}
		applyBestsellerOrder(context.Background(), svc, &cat9, &f)
		if got := f.PopularIDs; len(got) != 2 || got[0] != 1 || got[1] != 2 {
			t.Fatalf("empty-category fallback: got %v, want global [1 2]", got)
		}
	})

	t.Run("no category uses global", func(t *testing.T) {
		f := catalog.ProductFilter{Sort: "bestseller"}
		applyBestsellerOrder(context.Background(), svc, nil, &f)
		if got := f.PopularIDs; len(got) != 2 || got[0] != 1 {
			t.Fatalf("global: got %v, want [1 2]", got)
		}
	})

	t.Run("non-bestseller sort is a no-op", func(t *testing.T) {
		f := catalog.ProductFilter{Sort: "price_asc"}
		applyBestsellerOrder(context.Background(), svc, &cat5, &f)
		if len(f.PopularIDs) != 0 {
			t.Fatalf("non-bestseller must not set PopularIDs, got %v", f.PopularIDs)
		}
	})
}
