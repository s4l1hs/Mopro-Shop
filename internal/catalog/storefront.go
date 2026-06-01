package catalog

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// SellerStorefrontReader serves the seller-storefront reads (Tranche 5a). Kept
// separate from catalog.Service so adding it doesn't churn that interface's
// mocks (same rationale as the Tranche 3 UGC interfaces).
type SellerStorefrontReader interface {
	ListProductsBySeller(ctx context.Context, sellerID int64, locale string, limit, offset int) ([]ProductSummaryRow, int, error)
	// ProductIDsBySeller lists the seller's active product ids (return scoping).
	ProductIDsBySeller(ctx context.Context, sellerID int64) ([]int64, error)
	// ProductSellerID returns the owning seller id for a product (is_seller calc).
	ProductSellerID(ctx context.Context, productID int64) (int64, error)
	SellerReviewSummary(ctx context.Context, sellerID int64) (avg float64, count int, err error)
	ListSellerReviews(ctx context.Context, sellerID int64, locale string, limit, offset int) ([]SellerReviewRow, int, error)
}

// SellerReviewRow is one review aggregated across a seller's products.
type SellerReviewRow struct {
	ID           int64     `json:"id"`
	ProductID    int64     `json:"product_id"`
	ProductTitle string    `json:"product_title"`
	Rating       int       `json:"rating"`
	Title        string    `json:"title"`
	Body         string    `json:"body"`
	CreatedAt    time.Time `json:"created_at"`
}

type storefrontReader struct{ pool *pgxpool.Pool }

// NewStorefrontReader builds the seller-storefront reader.
func NewStorefrontReader(pool *pgxpool.Pool) SellerStorefrontReader {
	return &storefrontReader{pool: pool}
}

func (r *storefrontReader) ListProductsBySeller(ctx context.Context, sellerID int64, locale string, limit, offset int) ([]ProductSummaryRow, int, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT p.id, p.seller_id, p.category_id, p.brand, p.status,
		        COALESCE(t.title, '') AS title,
		        v.price_minor, v.price_currency,
		        COALESCE(v.image_keys[1], '') AS cover_image_key,
		        COALESCE(cr.commission_pct_bps, 0) AS commission_pct_bps,
		        v.original_price_minor, p.rating_avg, p.rating_count,
		        count(*) OVER() AS total_count
		FROM catalog_schema.products p
		JOIN catalog_schema.product_translations t ON t.product_id = p.id AND t.locale = $2
		JOIN LATERAL (
		    SELECT price_minor, price_currency, image_keys, original_price_minor
		    FROM catalog_schema.variants WHERE product_id = p.id
		    ORDER BY price_minor ASC LIMIT 1
		) v ON TRUE
		LEFT JOIN ref_schema.commission_rules cr
		       ON cr.category_id = p.category_id AND cr.active = TRUE
		      AND (cr.effective_to IS NULL OR cr.effective_to > now())
		WHERE p.seller_id = $1 AND p.status = 'active'
		ORDER BY p.id DESC LIMIT $3 OFFSET $4`,
		sellerID, locale, limit, offset,
	)
	if err != nil {
		return nil, 0, fmt.Errorf("catalog.storefront: ListProductsBySeller: %w", err)
	}
	defer rows.Close()
	var out []ProductSummaryRow
	var total int
	for rows.Next() {
		var s ProductSummaryRow
		if err := rows.Scan(&s.ID, &s.SellerID, &s.CategoryID, &s.Brand, &s.Status,
			&s.Title, &s.PriceMinor, &s.PriceCurrency, &s.CoverImageKey,
			&s.CommissionPctBps, &s.OriginalPriceMinor, &s.RatingAvg, &s.RatingCount, &total); err != nil {
			return nil, 0, err
		}
		out = append(out, s)
	}
	if out == nil {
		out = []ProductSummaryRow{}
	}
	return out, total, rows.Err()
}

func (r *storefrontReader) ProductIDsBySeller(ctx context.Context, sellerID int64) ([]int64, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT id FROM catalog_schema.products WHERE seller_id = $1`, sellerID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var ids []int64
	for rows.Next() {
		var id int64
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	return ids, rows.Err()
}

func (r *storefrontReader) ProductSellerID(ctx context.Context, productID int64) (int64, error) {
	var sellerID int64
	err := r.pool.QueryRow(ctx,
		`SELECT seller_id FROM catalog_schema.products WHERE id = $1`, productID).Scan(&sellerID)
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, nil
	}
	return sellerID, err
}

func (r *storefrontReader) SellerReviewSummary(ctx context.Context, sellerID int64) (float64, int, error) {
	var avg float64
	var count int
	err := r.pool.QueryRow(ctx,
		`SELECT COALESCE(AVG(pr.rating), 0), COUNT(*)
		   FROM catalog_schema.product_reviews pr
		   JOIN catalog_schema.products p ON p.id = pr.product_id
		  WHERE p.seller_id = $1 AND pr.status = 'published'`, sellerID).Scan(&avg, &count)
	return avg, count, err
}

func (r *storefrontReader) ListSellerReviews(ctx context.Context, sellerID int64, locale string, limit, offset int) ([]SellerReviewRow, int, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT pr.id, pr.product_id, COALESCE(t.title, ''), pr.rating, pr.title, pr.body,
		        pr.created_at, count(*) OVER() AS total_count
		   FROM catalog_schema.product_reviews pr
		   JOIN catalog_schema.products p ON p.id = pr.product_id
		   LEFT JOIN catalog_schema.product_translations t
		          ON t.product_id = p.id AND t.locale = $2
		  WHERE p.seller_id = $1 AND pr.status = 'published'
		  ORDER BY pr.created_at DESC LIMIT $3 OFFSET $4`,
		sellerID, locale, limit, offset,
	)
	if err != nil {
		return nil, 0, fmt.Errorf("catalog.storefront: ListSellerReviews: %w", err)
	}
	defer rows.Close()
	var out []SellerReviewRow
	var total int
	for rows.Next() {
		var rv SellerReviewRow
		if err := rows.Scan(&rv.ID, &rv.ProductID, &rv.ProductTitle, &rv.Rating,
			&rv.Title, &rv.Body, &rv.CreatedAt, &total); err != nil {
			return nil, 0, err
		}
		out = append(out, rv)
	}
	if out == nil {
		out = []SellerReviewRow{}
	}
	return out, total, rows.Err()
}
