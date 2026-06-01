package seller

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/mopro/platform/internal/sitemap"
)

// sellerSitemapReader enumerates active seller storefront URLs (/sellers/:slug)
// for the sitemap. Separate from seller.Service (no mock churn).
type sellerSitemapReader struct{ pool *pgxpool.Pool }

// NewSitemapReader builds the seller sitemap reader.
func NewSitemapReader(pool *pgxpool.Pool) *sellerSitemapReader {
	return &sellerSitemapReader{pool: pool}
}

func (r *sellerSitemapReader) SitemapURLs(ctx context.Context) ([]sitemap.URL, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT slug, updated_at FROM seller_schema.sellers WHERE status = 'active' ORDER BY id`)
	if err != nil {
		return nil, fmt.Errorf("seller.sitemap: %w", err)
	}
	defer rows.Close()
	out := []sitemap.URL{}
	for rows.Next() {
		var slug string
		var upd time.Time
		if err := rows.Scan(&slug, &upd); err != nil {
			return nil, err
		}
		lm := upd
		out = append(out, sitemap.URL{
			Loc:        "/sellers/" + slug,
			LastMod:    &lm,
			ChangeFreq: sitemap.ChangeFreqWeekly,
		})
	}
	return out, rows.Err()
}
