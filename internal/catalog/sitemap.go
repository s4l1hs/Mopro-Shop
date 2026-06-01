package catalog

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/mopro/platform/internal/sitemap"
)

// catalogSitemapReader enumerates public product + category URLs for the
// sitemap. Separate from catalog.Service (no mock churn), mirroring
// SellerStorefrontReader. Products route by id (/products/:id), categories by
// id (/categories/:id) — neither has a slug column.
type catalogSitemapReader struct{ pool *pgxpool.Pool }

// NewSitemapReader builds the catalog sitemap reader.
func NewSitemapReader(pool *pgxpool.Pool) *catalogSitemapReader {
	return &catalogSitemapReader{pool: pool}
}

func (r *catalogSitemapReader) SitemapURLs(ctx context.Context) ([]sitemap.URL, error) {
	out := []sitemap.URL{}

	prodRows, err := r.pool.Query(ctx,
		`SELECT id, updated_at FROM catalog_schema.products WHERE status = 'active' ORDER BY id`)
	if err != nil {
		return nil, fmt.Errorf("catalog.sitemap: products: %w", err)
	}
	defer prodRows.Close()
	for prodRows.Next() {
		var id int64
		var upd time.Time
		if err := prodRows.Scan(&id, &upd); err != nil {
			return nil, err
		}
		lm := upd
		out = append(out, sitemap.URL{
			Loc:        fmt.Sprintf("/products/%d", id),
			LastMod:    &lm,
			ChangeFreq: sitemap.ChangeFreqDaily,
		})
	}
	if err := prodRows.Err(); err != nil {
		return nil, err
	}

	// Categories live in ref_schema and have no updated_at → no lastmod.
	catRows, err := r.pool.Query(ctx,
		`SELECT id FROM ref_schema.categories WHERE active = TRUE ORDER BY id`)
	if err != nil {
		return nil, fmt.Errorf("catalog.sitemap: categories: %w", err)
	}
	defer catRows.Close()
	for catRows.Next() {
		var id int64
		if err := catRows.Scan(&id); err != nil {
			return nil, err
		}
		out = append(out, sitemap.URL{
			Loc:        fmt.Sprintf("/categories/%d", id),
			ChangeFreq: sitemap.ChangeFreqWeekly,
		})
	}
	return out, catRows.Err()
}
