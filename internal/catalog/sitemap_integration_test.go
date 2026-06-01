//go:build integration

package catalog_test

import (
	"context"
	"strings"
	"testing"

	"github.com/mopro/platform/internal/catalog"
)

// TestIntegration_SitemapReader verifies the catalog sitemap SQL against the
// seeded schema: active products surface as /products/:id (with lastmod), active
// categories as /categories/:id.
func TestIntegration_SitemapReader(t *testing.T) {
	ctx := context.Background()
	// Reuse the base schema (products/categories) + seed one active product.
	repo := catalog.NewRepository(integPool)
	svc := catalog.NewService(repo, "TRY", "tr-TR")
	p, err := svc.CreateProduct(ctx, catalog.CreateProductRequest{SellerID: 1, CategoryID: 30, Brand: "SitemapCo"})
	if err != nil {
		t.Fatalf("CreateProduct: %v", err)
	}
	if _, err := integPool.Exec(ctx,
		`UPDATE catalog_schema.products SET status='active' WHERE id=$1`, p.ID); err != nil {
		t.Fatalf("activate: %v", err)
	}

	urls, err := catalog.NewSitemapReader(integPool).SitemapURLs(ctx)
	if err != nil {
		t.Fatalf("SitemapURLs: %v", err)
	}

	var sawProduct, sawCategory bool
	for _, u := range urls {
		if u.Loc == "/products/"+itoa(p.ID) {
			sawProduct = true
			if u.LastMod == nil {
				t.Error("product entry missing lastmod")
			}
			if u.ChangeFreq != "daily" {
				t.Errorf("product changefreq: want daily, got %q", u.ChangeFreq)
			}
		}
		if strings.HasPrefix(u.Loc, "/categories/") {
			sawCategory = true
		}
	}
	if !sawProduct {
		t.Errorf("active product not in sitemap; got %d urls", len(urls))
	}
	if !sawCategory {
		t.Error("no category in sitemap (expected seeded category 30)")
	}
}

func itoa(n int64) string {
	if n == 0 {
		return "0"
	}
	var b [20]byte
	i := len(b)
	for n > 0 {
		i--
		b[i] = byte('0' + n%10)
		n /= 10
	}
	return string(b[i:])
}
