//go:build integration

package catalog_test

// PLP-12: ListProductsByCategory rolls a category's whole subtree up — a parent
// category aggregates every descendant product; a leaf resolves to just itself.
//
//	go test -tags=integration -run Rollup ./internal/catalog/...

import (
	"context"
	"fmt"
	"testing"

	"github.com/mopro/platform/internal/catalog"
)

// rollupSeed inserts one active product (+ tr-TR translation + variant) in an
// arbitrary category and returns its id.
func rollupSeed(t *testing.T, ctx context.Context, catID int64, brand, title string) int64 {
	t.Helper()
	var id int64
	if err := integPool.QueryRow(ctx,
		`INSERT INTO catalog_schema.products (seller_id, category_id, brand, status)
		 VALUES (900, $1, $2, 'active') RETURNING id`,
		catID, brand).Scan(&id); err != nil {
		t.Fatalf("rollupSeed product: %v", err)
	}
	if _, err := integPool.Exec(ctx,
		`INSERT INTO catalog_schema.product_translations (product_id, locale, title)
		 VALUES ($1, 'tr-TR', $2)`, id, title); err != nil {
		t.Fatalf("rollupSeed translation: %v", err)
	}
	if _, err := integPool.Exec(ctx,
		`INSERT INTO catalog_schema.variants (product_id, sku, price_minor, stock)
		 VALUES ($1, $2, 1000, 5)`, id, fmt.Sprintf("RU-%d", id)); err != nil {
		t.Fatalf("rollupSeed variant: %v", err)
	}
	return id
}

func TestIntegration_SubtreeRollup(t *testing.T) {
	ctx := context.Background()

	// parent(40) → child(41) → grandchild(42). Insert parents first (FK).
	setup := []string{
		`DELETE FROM catalog_schema.variants v USING catalog_schema.products p
		   WHERE v.product_id = p.id AND p.category_id IN (40,41,42)`,
		`DELETE FROM catalog_schema.product_translations t USING catalog_schema.products p
		   WHERE t.product_id = p.id AND p.category_id IN (40,41,42)`,
		`DELETE FROM catalog_schema.products WHERE category_id IN (40,41,42)`,
		`DELETE FROM ref_schema.categories WHERE id IN (42,41,40)`,
		`INSERT INTO ref_schema.categories (id, slug, name_tr, name_en, parent_id)
		   VALUES (40, 'rollup-parent', 'P', 'P', NULL)`,
		`INSERT INTO ref_schema.categories (id, slug, name_tr, name_en, parent_id)
		   VALUES (41, 'rollup-child', 'C', 'C', 40)`,
		`INSERT INTO ref_schema.categories (id, slug, name_tr, name_en, parent_id)
		   VALUES (42, 'rollup-grandchild', 'G', 'G', 41)`,
	}
	for _, q := range setup {
		if _, err := integPool.Exec(ctx, q); err != nil {
			t.Fatalf("rollup setup: %v", err)
		}
	}
	t.Cleanup(func() {
		for _, q := range []string{
			`DELETE FROM catalog_schema.variants v USING catalog_schema.products p
			   WHERE v.product_id = p.id AND p.category_id IN (40,41,42)`,
			`DELETE FROM catalog_schema.product_translations t USING catalog_schema.products p
			   WHERE t.product_id = p.id AND p.category_id IN (40,41,42)`,
			`DELETE FROM catalog_schema.products WHERE category_id IN (40,41,42)`,
			`DELETE FROM ref_schema.categories WHERE id IN (42,41,40)`,
		} {
			integPool.Exec(ctx, q) //nolint:errcheck // best-effort cleanup
		}
	})

	childID := rollupSeed(t, ctx, 41, "ChildBrand", "Child Product")
	grandID := rollupSeed(t, ctx, 42, "GrandBrand", "Grand Product")

	repo := catalog.NewRepository(integPool)
	list := func(catID int64) ([]int64, int) {
		t.Helper()
		rows, total, err := repo.ListProductsByCategory(ctx, catID, "tr-TR", catalog.ProductFilter{}, 0, 50)
		if err != nil {
			t.Fatalf("ListProductsByCategory(%d): %v", catID, err)
		}
		return pfIDs(rows), total
	}

	// Parent has NO direct products but rolls up child + grandchild.
	got, total := list(40)
	pfAssertSet(t, got, childID, grandID)
	if total != 2 {
		t.Fatalf("parent total: got %d, want 2", total)
	}

	// Child (with a grandchild) rolls up the grandchild too.
	got, _ = list(41)
	pfAssertSet(t, got, childID, grandID)

	// Grandchild is a true leaf → resolves to just itself.
	got, _ = list(42)
	pfAssertSet(t, got, grandID)
}
