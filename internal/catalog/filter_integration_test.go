//go:build integration

package catalog_test

// Integration tests for the P-028 catalog filter/sort dimensions, against the
// shared ephemeral PG16 from integration_test.go (TestMain + setupSchema).
//
//	go test -tags=integration -run Filter ./internal/catalog/...
//
// Fixtures live in a dedicated category (pfCat=31) that each test cleans + reseeds
// for determinism. The filter/sort logic is shared by ListProductsByCategory and
// SearchProductsSummary (appendProductFilters + orderByClause), so the PLP path
// exercises the dimensions and a focused search test confirms the wiring threads.

import (
	"context"
	"fmt"
	"testing"

	"github.com/mopro/platform/internal/catalog"
)

const pfCat = 31

func pfI64(v int64) *int64     { return &v }
func pfF64(v float64) *float64 { return &v }
func pfBool(v bool) *bool      { return &v }
func pfInt(v int) *int         { return &v }

// pfSetupCat ensures category 31 + its commission rule exist and removes any
// prior fixtures so each test starts from a known set.
func pfSetupCat(t *testing.T, ctx context.Context) {
	t.Helper()
	stmts := []string{
		`INSERT INTO ref_schema.categories (id, slug, name_tr, name_en)
		   VALUES (31, 'p028-filter', 'P028 Filtre', 'P028 Filter') ON CONFLICT DO NOTHING`,
		// Exactly one active commission rule for cat 31. ON CONFLICT can't be used:
		// effective_from defaults to now() so each insert is a distinct key, which
		// would leave multiple active rules and multiply rows via the summary's
		// commission LEFT JOIN. Delete-then-insert keeps it singular + deterministic.
		`DELETE FROM ref_schema.commission_rules WHERE category_id = 31`,
		`INSERT INTO ref_schema.commission_rules (market, category_id, commission_pct_bps, kdv_pct_bps)
		   VALUES ('TR', 31, 1000, 2000)`,
		`DELETE FROM catalog_schema.variants v USING catalog_schema.products p
		   WHERE v.product_id = p.id AND p.category_id = 31`,
		`DELETE FROM catalog_schema.product_translations t USING catalog_schema.products p
		   WHERE t.product_id = p.id AND p.category_id = 31`,
		`DELETE FROM catalog_schema.products WHERE category_id = 31`,
	}
	for _, q := range stmts {
		if _, err := integPool.Exec(ctx, q); err != nil {
			t.Fatalf("pfSetupCat: %v", err)
		}
	}
}

// pfSeed inserts one active product (+ tr-TR translation + a single variant) in
// pfCat and returns its id. ratingAvg nil => no reviews (rating_avg IS NULL).
func pfSeed(t *testing.T, ctx context.Context, brand, title string, price int64, ratingAvg *float64, ratingCount int, freeShipping bool, stock int) int64 {
	t.Helper()
	var id int64
	if err := integPool.QueryRow(ctx,
		`INSERT INTO catalog_schema.products
		   (seller_id, category_id, brand, status, rating_avg, rating_count, free_shipping)
		 VALUES (900, 31, $1, 'active', $2, $3, $4) RETURNING id`,
		brand, ratingAvg, ratingCount, freeShipping).Scan(&id); err != nil {
		t.Fatalf("pfSeed product: %v", err)
	}
	if _, err := integPool.Exec(ctx,
		`INSERT INTO catalog_schema.product_translations (product_id, locale, title)
		 VALUES ($1, 'tr-TR', $2)`, id, title); err != nil {
		t.Fatalf("pfSeed translation: %v", err)
	}
	if _, err := integPool.Exec(ctx,
		`INSERT INTO catalog_schema.variants (product_id, sku, price_minor, stock)
		 VALUES ($1, $2, $3, $4)`, id, fmt.Sprintf("P028-%d", id), price, stock); err != nil {
		t.Fatalf("pfSeed variant: %v", err)
	}
	return id
}

func pfIDs(rows []catalog.ProductSummaryRow) []int64 {
	ids := make([]int64, len(rows))
	for i, r := range rows {
		ids[i] = r.ID
	}
	return ids
}

func pfAssertSet(t *testing.T, got []int64, want ...int64) {
	t.Helper()
	if len(got) != len(want) {
		t.Fatalf("set size: got %v, want %v", got, want)
	}
	gm := make(map[int64]bool, len(got))
	for _, id := range got {
		gm[id] = true
	}
	for _, w := range want {
		if !gm[w] {
			t.Fatalf("missing %d: got %v, want set %v", w, got, want)
		}
	}
}

func pfAssertOrder(t *testing.T, got []int64, want ...int64) {
	t.Helper()
	if len(got) != len(want) {
		t.Fatalf("len: got %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("order: got %v, want %v", got, want)
		}
	}
}

func TestIntegration_ProductFilters(t *testing.T) {
	ctx := context.Background()
	pfSetupCat(t, ctx)
	repo := catalog.NewRepository(integPool)

	a := pfSeed(t, ctx, "Apple", "P028 Alpha phone", 10000, pfF64(4.5), 10, true, 5)
	b := pfSeed(t, ctx, "Apple", "P028 Beta phone", 50000, pfF64(3.0), 4, false, 0)
	c := pfSeed(t, ctx, "Samsung", "P028 Gamma tablet", 30000, pfF64(5.0), 8, true, 10)
	d := pfSeed(t, ctx, "Nokia", "P028 Delta phone", 20000, nil, 0, false, 3)

	list := func(t *testing.T, f catalog.ProductFilter) ([]int64, int) {
		t.Helper()
		rows, total, err := repo.ListProductsByCategory(ctx, pfCat, "tr-TR", f, 0, 50)
		if err != nil {
			t.Fatalf("ListProductsByCategory: %v", err)
		}
		return pfIDs(rows), total
	}

	t.Run("no filter returns all active", func(t *testing.T) {
		got, total := list(t, catalog.ProductFilter{})
		pfAssertSet(t, got, a, b, c, d)
		if total != 4 {
			t.Fatalf("total: got %d, want 4", total)
		}
	})
	t.Run("brand single", func(t *testing.T) {
		got, _ := list(t, catalog.ProductFilter{Brands: []string{"Apple"}})
		pfAssertSet(t, got, a, b)
	})
	t.Run("brand multi", func(t *testing.T) {
		got, _ := list(t, catalog.ProductFilter{Brands: []string{"Apple", "Samsung"}})
		pfAssertSet(t, got, a, b, c)
	})
	t.Run("min price inclusive", func(t *testing.T) {
		got, _ := list(t, catalog.ProductFilter{MinPriceMinor: pfI64(20000)})
		pfAssertSet(t, got, b, c, d)
	})
	t.Run("max price inclusive", func(t *testing.T) {
		got, _ := list(t, catalog.ProductFilter{MaxPriceMinor: pfI64(20000)})
		pfAssertSet(t, got, a, d)
	})
	t.Run("price range", func(t *testing.T) {
		got, _ := list(t, catalog.ProductFilter{MinPriceMinor: pfI64(15000), MaxPriceMinor: pfI64(35000)})
		pfAssertSet(t, got, c, d)
	})
	t.Run("min rating excludes lower and null", func(t *testing.T) {
		got, _ := list(t, catalog.ProductFilter{MinRating: pfInt(4)})
		pfAssertSet(t, got, a, c) // 4.5, 5.0; B=3.0 out, D=NULL out
	})
	t.Run("free shipping only", func(t *testing.T) {
		got, _ := list(t, catalog.ProductFilter{FreeShipping: pfBool(true)})
		pfAssertSet(t, got, a, c)
	})
	t.Run("free shipping false is unconstrained", func(t *testing.T) {
		got, _ := list(t, catalog.ProductFilter{FreeShipping: pfBool(false)})
		pfAssertSet(t, got, a, b, c, d)
	})
	t.Run("in stock only", func(t *testing.T) {
		got, _ := list(t, catalog.ProductFilter{InStock: pfBool(true)})
		pfAssertSet(t, got, a, c, d) // B stock=0 out
	})
	t.Run("combined brand and rating AND", func(t *testing.T) {
		got, _ := list(t, catalog.ProductFilter{Brands: []string{"Apple"}, MinRating: pfInt(4)})
		pfAssertSet(t, got, a) // Apple AND rating>=4 -> A only
	})
	t.Run("over-filtered returns empty", func(t *testing.T) {
		got, total := list(t, catalog.ProductFilter{Brands: []string{"NoSuchBrand"}})
		pfAssertSet(t, got)
		if total != 0 {
			t.Fatalf("total: got %d, want 0", total)
		}
	})
}

func TestIntegration_ProductSort(t *testing.T) {
	ctx := context.Background()
	pfSetupCat(t, ctx)
	repo := catalog.NewRepository(integPool)

	a := pfSeed(t, ctx, "Apple", "P028 Alpha phone", 10000, pfF64(4.5), 10, true, 5)
	b := pfSeed(t, ctx, "Apple", "P028 Beta phone", 50000, pfF64(3.0), 4, false, 0)
	c := pfSeed(t, ctx, "Samsung", "P028 Gamma tablet", 30000, pfF64(5.0), 8, true, 10)
	d := pfSeed(t, ctx, "Nokia", "P028 Delta phone", 20000, nil, 0, false, 3)

	sorted := func(t *testing.T, token string) []int64 {
		t.Helper()
		rows, _, err := repo.ListProductsByCategory(ctx, pfCat, "tr-TR", catalog.ProductFilter{Sort: token}, 0, 50)
		if err != nil {
			t.Fatalf("sort %q: %v", token, err)
		}
		return pfIDs(rows)
	}

	// Prices: A=10000 D=20000 C=30000 B=50000. IDs ascend a<b<c<d.
	t.Run("price_asc", func(t *testing.T) { pfAssertOrder(t, sorted(t, "price_asc"), a, d, c, b) })
	t.Run("price_desc", func(t *testing.T) { pfAssertOrder(t, sorted(t, "price_desc"), b, c, d, a) })
	t.Run("recommended is id desc", func(t *testing.T) { pfAssertOrder(t, sorted(t, "recommended"), d, c, b, a) })
	t.Run("newest is created_at then id desc", func(t *testing.T) { pfAssertOrder(t, sorted(t, "newest"), d, c, b, a) })
	// Equal commission (cat 31) => cashback ∝ price => price-desc order.
	t.Run("cashback_desc", func(t *testing.T) { pfAssertOrder(t, sorted(t, "cashback_desc"), b, c, d, a) })
	// bestseller is carved (P-029) -> unknown token falls back to recommended.
	t.Run("bestseller falls back to recommended", func(t *testing.T) { pfAssertOrder(t, sorted(t, "bestseller"), d, c, b, a) })
	t.Run("empty token falls back to recommended", func(t *testing.T) { pfAssertOrder(t, sorted(t, ""), d, c, b, a) })
}

func TestIntegration_SearchFilters(t *testing.T) {
	ctx := context.Background()
	pfSetupCat(t, ctx)
	repo := catalog.NewRepository(integPool)

	// Unique token "Zqphone" so only these rows match the full-text search.
	a := pfSeed(t, ctx, "Apple", "Zqphone Alpha", 10000, pfF64(4.5), 10, true, 5)
	b := pfSeed(t, ctx, "Apple", "Zqphone Beta", 50000, pfF64(3.0), 4, false, 0)
	c := pfSeed(t, ctx, "Samsung", "Zqphone Gamma", 30000, pfF64(5.0), 8, true, 10)

	search := func(t *testing.T, f catalog.ProductFilter) []int64 {
		t.Helper()
		rows, _, err := repo.SearchProductsSummary(ctx, "Zqphone", "tr-TR", f, 0, 50)
		if err != nil {
			t.Fatalf("SearchProductsSummary: %v", err)
		}
		return pfIDs(rows)
	}

	t.Run("no filter matches all token rows", func(t *testing.T) {
		pfAssertSet(t, search(t, catalog.ProductFilter{}), a, b, c)
	})
	t.Run("filter threads into search (min rating)", func(t *testing.T) {
		pfAssertSet(t, search(t, catalog.ProductFilter{MinRating: pfInt(4)}), a, c)
	})
	t.Run("filter threads into search (free shipping)", func(t *testing.T) {
		pfAssertSet(t, search(t, catalog.ProductFilter{FreeShipping: pfBool(true)}), a, c)
	})
	t.Run("category_id filter on search", func(t *testing.T) {
		pfAssertSet(t, search(t, catalog.ProductFilter{CategoryID: pfI64(pfCat)}), a, b, c)
	})
	t.Run("category_id mismatch returns empty", func(t *testing.T) {
		pfAssertSet(t, search(t, catalog.ProductFilter{CategoryID: pfI64(999999)}))
	})
}

// TestIntegration_BestsellerOrder covers P-029: the repo orders by the
// handler-supplied PopularIDs (array_position, NULLS LAST), composes with
// filters, and falls back to recommended when PopularIDs is empty.
func TestIntegration_BestsellerOrder(t *testing.T) {
	ctx := context.Background()
	pfSetupCat(t, ctx)
	repo := catalog.NewRepository(integPool)

	a := pfSeed(t, ctx, "Apple", "BS Alpha", 10000, nil, 0, false, 5)
	b := pfSeed(t, ctx, "Nokia", "BS Beta", 20000, nil, 0, false, 5)
	c := pfSeed(t, ctx, "Sony", "BS Gamma", 30000, nil, 0, false, 5)

	list := func(t *testing.T, f catalog.ProductFilter) []int64 {
		t.Helper()
		rows, _, err := repo.ListProductsByCategory(ctx, pfCat, "tr-TR", f, 0, 50)
		if err != nil {
			t.Fatalf("ListProductsByCategory: %v", err)
		}
		return pfIDs(rows)
	}

	t.Run("orders by PopularIDs; unranked last (NULLS LAST)", func(t *testing.T) {
		// c, a ranked (that order); b unranked -> last.
		got := list(t, catalog.ProductFilter{Sort: "bestseller", PopularIDs: []int64{c, a}})
		pfAssertOrder(t, got, c, a, b)
	})

	t.Run("empty PopularIDs -> recommended fallback (id desc)", func(t *testing.T) {
		got := list(t, catalog.ProductFilter{Sort: "bestseller"})
		pfAssertOrder(t, got, c, b, a)
	})

	t.Run("composes with filters", func(t *testing.T) {
		got := list(t, catalog.ProductFilter{
			Sort:       "bestseller",
			PopularIDs: []int64{c, a, b},
			Brands:     []string{"Sony"},
		})
		pfAssertOrder(t, got, c)
	})
}

// TestIntegration_ListProductsGlobal covers the F-020 global (no-category) list
// path: catalog-wide results (no category scope), with sort + filters composing.
// A unique brand isolates the rows so the catalog-wide result is deterministic.
func TestIntegration_ListProductsGlobal(t *testing.T) {
	ctx := context.Background()
	pfSetupCat(t, ctx)
	repo := catalog.NewRepository(integPool)

	const brand = "ZqGlobalBrand"
	a := pfSeed(t, ctx, brand, "F020 Alpha", 10000, pfF64(4.0), 5, true, 5)
	b := pfSeed(t, ctx, brand, "F020 Beta", 20000, pfF64(3.0), 4, false, 3)
	c := pfSeed(t, ctx, brand, "F020 Gamma", 30000, pfF64(5.0), 8, true, 10)

	list := func(t *testing.T, f catalog.ProductFilter) []int64 {
		t.Helper()
		f.Brands = []string{brand}
		rows, _, err := repo.ListProducts(ctx, "tr-TR", f, 0, 50)
		if err != nil {
			t.Fatalf("ListProducts: %v", err)
		}
		return pfIDs(rows)
	}

	// IDs ascend a<b<c. No category arg is passed — the rows are still returned,
	// proving the global path applies no category scope.
	t.Run("global recommended is id desc", func(t *testing.T) {
		pfAssertOrder(t, list(t, catalog.ProductFilter{Sort: "recommended"}), c, b, a)
	})
	t.Run("global bestseller orders by PopularIDs (unranked last)", func(t *testing.T) {
		pfAssertOrder(t, list(t, catalog.ProductFilter{Sort: "bestseller", PopularIDs: []int64{b, c}}), b, c, a)
	})
	t.Run("filters compose on the global list", func(t *testing.T) {
		pfAssertSet(t, list(t, catalog.ProductFilter{FreeShipping: pfBool(true)}), a, c)
	})
}
