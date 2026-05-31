//go:build integration

package catalog_test

// Integration tests for the seller-storefront reader (Tranche 5a). Run against
// the same ephemeral PG16 as integration_test.go:
//
//	go test -tags=integration -v ./internal/catalog/...

import (
	"context"
	"testing"

	"github.com/mopro/platform/internal/catalog"
)

// ensureStorefrontSchema adds the columns the storefront reader needs on top of
// the base schema (rating_avg/rating_count on products, original_price_minor on
// variants) and the reviews status column. One statement per Exec.
func ensureStorefrontSchema(ctx context.Context, t *testing.T) {
	t.Helper()
	ensureUGCSchema(ctx, t) // adds product_reviews.status + (re)creates Q&A tables
	stmts := []string{
		`ALTER TABLE catalog_schema.products ADD COLUMN IF NOT EXISTS rating_avg NUMERIC`,
		`ALTER TABLE catalog_schema.products ADD COLUMN IF NOT EXISTS rating_count INT NOT NULL DEFAULT 0`,
		`ALTER TABLE catalog_schema.variants ADD COLUMN IF NOT EXISTS original_price_minor BIGINT`,
		// The shared DB accumulates one commission_rules row per run (effective_from
		// defaults to now()); collapse to the newest per (market, category) so the
		// LEFT JOIN in the storefront query stays 1:1 with products.
		`DELETE FROM ref_schema.commission_rules cr
		   USING ref_schema.commission_rules newer
		  WHERE cr.market = newer.market AND cr.category_id = newer.category_id
		    AND cr.effective_from < newer.effective_from`,
	}
	for _, s := range stmts {
		if _, err := integPool.Exec(ctx, s); err != nil {
			t.Fatalf("storefront schema: %v", err)
		}
	}
}

// resetSeller removes any rows a prior run left for the test seller id (the
// ephemeral DB is shared + persistent across runs). Children first (FKs).
func resetSeller(t *testing.T, sellerID int64) {
	t.Helper()
	ctx := context.Background()
	mustExec(t, `DELETE FROM catalog_schema.product_reviews WHERE product_id IN (SELECT id FROM catalog_schema.products WHERE seller_id=$1)`, sellerID)
	mustExec(t, `DELETE FROM catalog_schema.variants WHERE product_id IN (SELECT id FROM catalog_schema.products WHERE seller_id=$1)`, sellerID)
	mustExec(t, `DELETE FROM catalog_schema.product_translations WHERE product_id IN (SELECT id FROM catalog_schema.products WHERE seller_id=$1)`, sellerID)
	mustExec(t, `DELETE FROM catalog_schema.products WHERE seller_id=$1`, sellerID)
	_ = ctx
}

// seedStorefrontProduct inserts a product (+ title + cheapest variant) for a
// seller and returns its id.
func seedStorefrontProduct(t *testing.T, sellerID int64, status, title string, priceMinor int64) int64 {
	t.Helper()
	ctx := context.Background()
	var pid int64
	if err := integPool.QueryRow(ctx,
		`INSERT INTO catalog_schema.products (seller_id, category_id, brand, status)
		 VALUES ($1, 30, 'B', $2) RETURNING id`, sellerID, status).Scan(&pid); err != nil {
		t.Fatalf("seed product: %v", err)
	}
	if _, err := integPool.Exec(ctx,
		`INSERT INTO catalog_schema.product_translations (product_id, locale, title)
		 VALUES ($1, 'tr-TR', $2)`, pid, title); err != nil {
		t.Fatalf("seed translation: %v", err)
	}
	if _, err := integPool.Exec(ctx,
		`INSERT INTO catalog_schema.variants (product_id, sku, price_minor)
		 VALUES ($1, $2, $3)`, pid, title+"-sku", priceMinor); err != nil {
		t.Fatalf("seed variant: %v", err)
	}
	return pid
}

func TestIntegration_StorefrontReader(t *testing.T) {
	ctx := context.Background()
	ensureStorefrontSchema(ctx, t)
	reader := catalog.NewStorefrontReader(integPool)

	const sellerID int64 = 9001
	resetSeller(t, sellerID)
	active := seedStorefrontProduct(t, sellerID, "active", "Aktif Ürün", 50000)
	inactive := seedStorefrontProduct(t, sellerID, "draft", "Taslak Ürün", 60000)

	// ListProductsBySeller excludes the non-active product.
	rows, total, err := reader.ListProductsBySeller(ctx, sellerID, "tr-TR", 20, 0)
	if err != nil {
		t.Fatalf("ListProductsBySeller: %v", err)
	}
	if total != 1 || len(rows) != 1 {
		t.Fatalf("want 1 active product, got total=%d len=%d", total, len(rows))
	}
	if rows[0].ID != active || rows[0].Title != "Aktif Ürün" {
		t.Errorf("row mismatch: id=%d title=%q", rows[0].ID, rows[0].Title)
	}

	// ProductIDsBySeller returns all products (active + draft) for return scoping.
	ids, err := reader.ProductIDsBySeller(ctx, sellerID)
	if err != nil {
		t.Fatalf("ProductIDsBySeller: %v", err)
	}
	if !contains(ids, active) || !contains(ids, inactive) {
		t.Errorf("ProductIDsBySeller missing ids: %v (want %d, %d)", ids, active, inactive)
	}

	// ProductSellerID resolves the owning seller; 0 for unknown product.
	if got, _ := reader.ProductSellerID(ctx, active); got != sellerID {
		t.Errorf("ProductSellerID(active): want %d got %d", sellerID, got)
	}
	if got, _ := reader.ProductSellerID(ctx, 7777777); got != 0 {
		t.Errorf("ProductSellerID(unknown): want 0 got %d", got)
	}
}

func TestIntegration_StorefrontReviews(t *testing.T) {
	ctx := context.Background()
	ensureStorefrontSchema(ctx, t)
	reader := catalog.NewStorefrontReader(integPool)

	const sellerID int64 = 9002
	resetSeller(t, sellerID)
	pid := seedStorefrontProduct(t, sellerID, "active", "Yorumlu Ürün", 40000)

	// Two published reviews + one soft-deleted (must be excluded from summary).
	mustExec(t, `INSERT INTO catalog_schema.product_reviews (product_id, user_id, rating, title, body, status) VALUES ($1, 1, 4, 't', 'b', 'published')`, pid)
	mustExec(t, `INSERT INTO catalog_schema.product_reviews (product_id, user_id, rating, title, body, status) VALUES ($1, 2, 2, 't', 'b', 'published')`, pid)
	mustExec(t, `INSERT INTO catalog_schema.product_reviews (product_id, user_id, rating, title, body, status) VALUES ($1, 3, 1, 't', 'b', 'deleted')`, pid)

	avg, count, err := reader.SellerReviewSummary(ctx, sellerID)
	if err != nil {
		t.Fatalf("SellerReviewSummary: %v", err)
	}
	if count != 2 {
		t.Errorf("review count: want 2 (published only), got %d", count)
	}
	if avg < 2.9 || avg > 3.1 { // (4+2)/2 = 3.0
		t.Errorf("review avg: want ~3.0, got %v", avg)
	}

	items, total, err := reader.ListSellerReviews(ctx, sellerID, "tr-TR", 20, 0)
	if err != nil {
		t.Fatalf("ListSellerReviews: %v", err)
	}
	if total != 2 || len(items) != 2 {
		t.Fatalf("want 2 published reviews, got total=%d len=%d", total, len(items))
	}
	if items[0].ProductTitle != "Yorumlu Ürün" {
		t.Errorf("review product_title not joined: %q", items[0].ProductTitle)
	}
}

func mustExec(t *testing.T, sql string, args ...any) {
	t.Helper()
	if _, err := integPool.Exec(context.Background(), sql, args...); err != nil {
		t.Fatalf("exec %q: %v", sql, err)
	}
}

func contains(ids []int64, want int64) bool {
	for _, id := range ids {
		if id == want {
			return true
		}
	}
	return false
}

func TestIntegration_SellerQuestionsInbox(t *testing.T) {
	ctx := context.Background()
	ensureStorefrontSchema(ctx, t) // resets product_questions/product_answers
	svc := catalog.NewUGCService(catalog.NewUGCRepository(integPool))

	const sellerID int64 = 9003
	resetSeller(t, sellerID)
	pid := seedStorefrontProduct(t, sellerID, "active", "Soru Ürünü", 30000)

	// q1 has a seller answer (is_seller=true); q2 has only a buyer answer; q3 has none.
	var q1, q2, q3 int64
	mustQuery(t, &q1, `INSERT INTO catalog_schema.product_questions (product_id, user_id, body) VALUES ($1, 100, 'q1') RETURNING id`, pid)
	mustQuery(t, &q2, `INSERT INTO catalog_schema.product_questions (product_id, user_id, body) VALUES ($1, 101, 'q2') RETURNING id`, pid)
	mustQuery(t, &q3, `INSERT INTO catalog_schema.product_questions (product_id, user_id, body) VALUES ($1, 102, 'q3') RETURNING id`, pid)
	mustExec(t, `INSERT INTO catalog_schema.product_answers (question_id, user_id, is_seller, body) VALUES ($1, 1, true, 'seller answer')`, q1)
	mustExec(t, `INSERT INTO catalog_schema.product_answers (question_id, user_id, is_seller, body) VALUES ($1, 200, false, 'buyer answer')`, q2)

	pids := []int64{pid}

	// All questions (no filter).
	items, total, err := svc.ListSellerQuestions(ctx, pids, false, 20, 0)
	if err != nil {
		t.Fatalf("ListSellerQuestions(all): %v", err)
	}
	if total != 3 || len(items) != 3 {
		t.Fatalf("all: want 3, got total=%d len=%d", total, len(items))
	}

	// Unanswered = no SELLER answer → q2 (buyer answer only) + q3.
	items, total, err = svc.ListSellerQuestions(ctx, pids, true, 20, 0)
	if err != nil {
		t.Fatalf("ListSellerQuestions(unanswered): %v", err)
	}
	if total != 2 || len(items) != 2 {
		t.Fatalf("unanswered: want 2, got total=%d len=%d", total, len(items))
	}
	for _, it := range items {
		if it.ID == q1 {
			t.Errorf("q1 has a seller answer; must not appear in unanswered inbox")
		}
	}
}

func mustQuery(t *testing.T, dst *int64, sql string, args ...any) {
	t.Helper()
	if err := integPool.QueryRow(context.Background(), sql, args...).Scan(dst); err != nil {
		t.Fatalf("query %q: %v", sql, err)
	}
}
