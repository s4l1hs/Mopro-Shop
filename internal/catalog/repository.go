package catalog

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"strings"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

// pgxUniqueViolation is the PostgreSQL error code for unique constraint violation.
const pgxUniqueViolation = "23505"

type pgxRepository struct {
	pool *pgxpool.Pool
}

// NewRepository returns a Repository backed by pgx connecting through PgBouncer.
// The pool DSN must point to pgbouncer-ecom, not directly to Postgres.
func NewRepository(pool *pgxpool.Pool) Repository {
	return &pgxRepository{pool: pool}
}

func (r *pgxRepository) IsCurrencyActive(ctx context.Context, code string) (bool, error) {
	var exists bool
	err := r.pool.QueryRow(ctx,
		`SELECT EXISTS(
			SELECT 1 FROM ref_schema.currencies
			WHERE code = $1 AND active = TRUE
		)`,
		code,
	).Scan(&exists)
	if err != nil {
		return false, fmt.Errorf("catalog.repo: IsCurrencyActive: %w", err)
	}
	return exists, nil
}

func (r *pgxRepository) InsertProduct(ctx context.Context, p Product) (Product, error) {
	err := r.pool.QueryRow(ctx,
		`INSERT INTO catalog_schema.products
			(seller_id, category_id, brand, default_currency, default_locale, status)
		VALUES ($1, $2, $3, $4, $5, $6)
		RETURNING id, created_at, updated_at`,
		p.SellerID, p.CategoryID, p.Brand,
		p.DefaultCurrency, p.DefaultLocale, p.Status,
	).Scan(&p.ID, &p.CreatedAt, &p.UpdatedAt)
	if err != nil {
		return Product{}, fmt.Errorf("catalog.repo: InsertProduct: %w", err)
	}
	return p, nil
}

func (r *pgxRepository) InsertVariant(ctx context.Context, v Variant) (Variant, error) {
	err := r.pool.QueryRow(ctx,
		`INSERT INTO catalog_schema.variants
			(product_id, sku, color, size, price_minor, price_currency, stock, image_keys)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
		RETURNING id`,
		v.ProductID, v.SKU, v.Color, v.Size,
		v.PriceMinor, v.PriceCurrency, v.Stock, v.ImageKeys,
	).Scan(&v.ID)
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == pgxUniqueViolation {
			return Variant{}, ErrDuplicateSKU
		}
		return Variant{}, fmt.Errorf("catalog.repo: InsertVariant: %w", err)
	}
	return v, nil
}

func (r *pgxRepository) UpsertTranslation(ctx context.Context, t ProductTranslation) error {
	_, err := r.pool.Exec(ctx,
		`INSERT INTO catalog_schema.product_translations
			(product_id, locale, title, description)
		VALUES ($1, $2, $3, $4)
		ON CONFLICT (product_id, locale)
		DO UPDATE SET title = EXCLUDED.title, description = EXCLUDED.description`,
		t.ProductID, t.Locale, t.Title, t.Description,
	)
	if err != nil {
		return fmt.Errorf("catalog.repo: UpsertTranslation: %w", err)
	}
	return nil
}

func (r *pgxRepository) GetByID(ctx context.Context, id int64) (Product, []Variant, []ProductTranslation, error) {
	var p Product
	err := r.pool.QueryRow(ctx,
		`SELECT id, seller_id, category_id, brand, default_currency, default_locale,
		        status, created_at, updated_at
		FROM catalog_schema.products
		WHERE id = $1`,
		id,
	).Scan(
		&p.ID, &p.SellerID, &p.CategoryID, &p.Brand,
		&p.DefaultCurrency, &p.DefaultLocale,
		&p.Status, &p.CreatedAt, &p.UpdatedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return Product{}, nil, nil, ErrNotFound
		}
		return Product{}, nil, nil, fmt.Errorf("catalog.repo: GetByID product: %w", err)
	}

	variants, err := r.loadVariants(ctx, id, p.CategoryID, p.SellerID)
	if err != nil {
		return Product{}, nil, nil, err
	}

	translations, err := r.loadTranslations(ctx, id)
	if err != nil {
		return Product{}, nil, nil, err
	}

	return p, variants, translations, nil
}

func (r *pgxRepository) loadVariants(ctx context.Context, productID, categoryID, sellerID int64) ([]Variant, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT id, product_id, sku, color, size, price_minor, price_currency, stock, image_keys
		FROM catalog_schema.variants
		WHERE product_id = $1
		ORDER BY id ASC`,
		productID,
	)
	if err != nil {
		return nil, fmt.Errorf("catalog.repo: loadVariants: %w", err)
	}
	defer rows.Close()

	var variants []Variant
	for rows.Next() {
		var v Variant
		if err := rows.Scan(
			&v.ID, &v.ProductID, &v.SKU, &v.Color, &v.Size,
			&v.PriceMinor, &v.PriceCurrency, &v.Stock, &v.ImageKeys,
		); err != nil {
			return nil, fmt.Errorf("catalog.repo: scan variant: %w", err)
		}
		if v.ImageKeys == nil {
			v.ImageKeys = []string{}
		}
		v.CategoryID = categoryID
		v.SellerID = sellerID
		variants = append(variants, v)
	}
	return variants, rows.Err()
}

func (r *pgxRepository) loadTranslations(ctx context.Context, productID int64) ([]ProductTranslation, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT product_id, locale, title, description
		FROM catalog_schema.product_translations
		WHERE product_id = $1
		ORDER BY locale ASC`,
		productID,
	)
	if err != nil {
		return nil, fmt.Errorf("catalog.repo: loadTranslations: %w", err)
	}
	defer rows.Close()

	var translations []ProductTranslation
	for rows.Next() {
		var t ProductTranslation
		if err := rows.Scan(&t.ProductID, &t.Locale, &t.Title, &t.Description); err != nil {
			return nil, fmt.Errorf("catalog.repo: scan translation: %w", err)
		}
		translations = append(translations, t)
	}
	return translations, rows.Err()
}

func (r *pgxRepository) SearchProducts(ctx context.Context, query, locale, market string) ([]Product, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT DISTINCT p.id, p.seller_id, p.category_id, p.brand,
		        p.default_currency, p.default_locale, p.status, p.created_at, p.updated_at
		FROM catalog_schema.products p
		JOIN catalog_schema.product_translations t ON t.product_id = p.id AND t.locale = $1
		WHERE p.status = 'active'
		  AND (t.search_vector @@ plainto_tsquery('simple', $2)
		       OR t.title ILIKE '%' || $2 || '%')
		ORDER BY p.id ASC
		LIMIT 50`,
		locale, query,
	)
	if err != nil {
		return nil, fmt.Errorf("catalog.repo: SearchProducts: %w", err)
	}
	defer rows.Close()

	var products []Product
	for rows.Next() {
		var p Product
		if err := rows.Scan(
			&p.ID, &p.SellerID, &p.CategoryID, &p.Brand,
			&p.DefaultCurrency, &p.DefaultLocale,
			&p.Status, &p.CreatedAt, &p.UpdatedAt,
		); err != nil {
			return nil, fmt.Errorf("catalog.repo: scan search result: %w", err)
		}
		products = append(products, p)
	}
	return products, rows.Err()
}

func (r *pgxRepository) ListCategories(ctx context.Context, locale string, maxDepth int) ([]CategoryRow, error) {
	nameCol := "name_en"
	if locale == "tr-TR" || locale == "tr" {
		nameCol = "name_tr"
	}

	// `maxDepth <= 0` preserves the historical behavior (return all).
	// `maxDepth >= 1` filters via a recursive CTE that computes each
	// category's chain length to its root parent. Capped at 1000 nodes
	// to prevent runaway responses per the prompt's safety ceiling.
	const maxNodes = 1000

	// promo_slot (Session 4d §2): SELECT the JSONB column on every row but
	// only PARSE / surface it on top-level rows (parent_id IS NULL) in the
	// scan loop below. Subcategory/leaf rows get nil PromoSlot even when
	// the column is non-null (defense in depth — the seed only populates
	// top-level rows, but if someone manually backfills a leaf later the
	// API contract still holds).
	var query string
	var args []any
	if maxDepth <= 0 {
		query = `SELECT c.id, c.slug, c.` + nameCol + `, c.parent_id,
		        COALESCE(cr.commission_pct_bps, 0) AS commission_pct_bps,
		        c.promo_slot
		FROM ref_schema.categories c
		LEFT JOIN ref_schema.commission_rules cr
		       ON cr.category_id = c.id
		      AND cr.active = TRUE
		      AND (cr.effective_to IS NULL OR cr.effective_to > now())
		WHERE c.active = TRUE
		ORDER BY c.id ASC
		LIMIT $1`
		args = []any{maxNodes}
	} else {
		query = `WITH RECURSIVE cat_depth AS (
		    SELECT id, parent_id, 0 AS depth
		    FROM ref_schema.categories
		    WHERE parent_id IS NULL AND active = TRUE
		  UNION ALL
		    SELECT c.id, c.parent_id, cd.depth + 1
		    FROM ref_schema.categories c
		    JOIN cat_depth cd ON c.parent_id = cd.id
		    WHERE c.active = TRUE AND cd.depth + 1 <= $1
		)
		SELECT c.id, c.slug, c.` + nameCol + `, c.parent_id,
		        COALESCE(cr.commission_pct_bps, 0) AS commission_pct_bps,
		        c.promo_slot
		FROM ref_schema.categories c
		JOIN cat_depth cd ON cd.id = c.id
		LEFT JOIN ref_schema.commission_rules cr
		       ON cr.category_id = c.id
		      AND cr.active = TRUE
		      AND (cr.effective_to IS NULL OR cr.effective_to > now())
		ORDER BY c.id ASC
		LIMIT $2`
		args = []any{maxDepth, maxNodes}
	}

	rows, err := r.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("catalog.repo: ListCategories: %w", err)
	}
	defer rows.Close()

	var cats []CategoryRow
	for rows.Next() {
		var c CategoryRow
		var promoRaw []byte
		if err := rows.Scan(&c.ID, &c.Slug, &c.Name, &c.ParentID, &c.CommissionPctBps, &promoRaw); err != nil {
			return nil, fmt.Errorf("catalog.repo: scan category: %w", err)
		}
		// Parse promo_slot only on top-level rows. Subcategory/leaf rows
		// keep PromoSlot=nil even if the column happens to be non-null.
		if c.ParentID == nil && len(promoRaw) > 0 {
			var p PromoSlot
			if err := json.Unmarshal(promoRaw, &p); err != nil {
				// Malformed JSON: warn + null per the API contract. Do not
				// fail the request — one bad row shouldn't 500 the whole
				// categories endpoint.
				slog.Warn("catalog.repo: malformed promo_slot json; surfacing as null",
					"category_id", c.ID, "err", err)
			} else if p.ImageURL != "" || p.Title != "" || p.DeepLink != "" {
				c.PromoSlot = &p
			}
		}
		cats = append(cats, c)
	}
	if cats == nil {
		cats = []CategoryRow{}
	}
	return cats, rows.Err()
}

// productSummarySelect is the shared SELECT/FROM/JOIN preamble for the product
// listing + search summary queries. The lowest-priced variant (LATERAL) supplies
// the representative price; ref_schema.commission_rules is the allowed
// cross-schema join (CLAUDE.md §5). $1 is the leading arg (category id or search
// query); $2 is the locale. Callers append a base WHERE, optional filter clauses
// (appendProductFilters, from $3), an ORDER BY (orderByClause), and LIMIT/OFFSET.
const productSummarySelect = `SELECT p.id, p.seller_id, p.category_id, p.brand, p.status,
	        COALESCE(t.title, '') AS title,
	        v.price_minor, v.price_currency,
	        COALESCE(v.image_keys[1], '') AS cover_image_key,
	        COALESCE(cr.commission_pct_bps, 0) AS commission_pct_bps,
	        v.original_price_minor,
	        p.rating_avg, p.rating_count,
	        p.free_shipping,
	        (SELECT count(*) FROM catalog_schema.user_favorites uf
	         WHERE uf.product_id = p.id) AS favorites_count,
	        count(*) OVER() AS total_count
	FROM catalog_schema.products p
	JOIN catalog_schema.product_translations t
	     ON t.product_id = p.id AND t.locale = $2
	JOIN LATERAL (
	    SELECT price_minor, price_currency, image_keys, original_price_minor
	    FROM catalog_schema.variants
	    WHERE product_id = p.id
	    ORDER BY price_minor ASC
	    LIMIT 1
	) v ON TRUE
	LEFT JOIN ref_schema.commission_rules cr
	       ON cr.category_id = p.category_id
	      AND cr.active = TRUE
	      AND (cr.effective_to IS NULL OR cr.effective_to > now())`

// appendProductFilters appends the optional filter WHERE clauses for f to sb
// (which already holds the base SELECT…WHERE), binding values into args. argN is
// the next free positional placeholder; the returned int is the next free one
// after. Boolean filters constrain only when explicitly true. Every value is
// bound — the token-free clauses never interpolate user input.
func appendProductFilters(sb *strings.Builder, args []any, f ProductFilter, argN int) ([]any, int) {
	if f.CategoryID != nil {
		fmt.Fprintf(sb, " AND p.category_id = $%d", argN)
		args = append(args, *f.CategoryID)
		argN++
	}
	if f.MinPriceMinor != nil {
		fmt.Fprintf(sb, " AND v.price_minor >= $%d", argN)
		args = append(args, *f.MinPriceMinor)
		argN++
	}
	if f.MaxPriceMinor != nil {
		fmt.Fprintf(sb, " AND v.price_minor <= $%d", argN)
		args = append(args, *f.MaxPriceMinor)
		argN++
	}
	if len(f.Brands) > 0 {
		fmt.Fprintf(sb, " AND p.brand = ANY($%d)", argN)
		args = append(args, f.Brands)
		argN++
	}
	if f.MinRating != nil {
		fmt.Fprintf(sb, " AND p.rating_avg >= $%d", argN)
		args = append(args, *f.MinRating)
		argN++
	}
	if f.FreeShipping != nil && *f.FreeShipping {
		sb.WriteString(" AND p.free_shipping = TRUE")
	}
	if f.InStock != nil && *f.InStock {
		sb.WriteString(" AND EXISTS (SELECT 1 FROM catalog_schema.variants vs" +
			" WHERE vs.product_id = p.id AND vs.stock > 0)")
	}
	return args, argN
}

// orderByClause maps a PlpSort token to a safe ORDER BY. Unknown/unsupported
// tokens — including bestseller until P-029 — fall back to recommended; it never
// errors and never interpolates the token. The trailing p.id keeps order stable.
func orderByClause(sort string) string {
	switch sort {
	case "newest":
		return " ORDER BY p.created_at DESC, p.id DESC"
	case "price_asc":
		return " ORDER BY v.price_minor ASC, p.id DESC"
	case "price_desc":
		return " ORDER BY v.price_minor DESC, p.id DESC"
	case "cashback_desc":
		return " ORDER BY (v.price_minor * COALESCE(cr.commission_pct_bps, 0)) DESC, p.id DESC"
	default:
		return " ORDER BY p.id DESC"
	}
}

// scanProductSummaries scans rows into a ProductSummaryRow slice plus the
// windowed total. Shared by the listing + search summary queries.
func scanProductSummaries(rows pgx.Rows, label string) ([]ProductSummaryRow, int, error) {
	var results []ProductSummaryRow
	var total int
	for rows.Next() {
		var s ProductSummaryRow
		if err := rows.Scan(
			&s.ID, &s.SellerID, &s.CategoryID, &s.Brand, &s.Status,
			&s.Title, &s.PriceMinor, &s.PriceCurrency,
			&s.CoverImageKey, &s.CommissionPctBps,
			&s.OriginalPriceMinor, &s.RatingAvg, &s.RatingCount,
			&s.FreeShipping, &s.FavoritesCount, &total,
		); err != nil {
			return nil, 0, fmt.Errorf("catalog.repo: scan %s: %w", label, err)
		}
		results = append(results, s)
	}
	if results == nil {
		results = []ProductSummaryRow{}
	}
	return results, total, rows.Err()
}

func (r *pgxRepository) ListProductsByCategory(ctx context.Context, categoryID int64, locale string, filter ProductFilter, offset, limit int) ([]ProductSummaryRow, int, error) {
	var sb strings.Builder
	sb.WriteString(productSummarySelect)
	sb.WriteString(" WHERE p.category_id = $1 AND p.status = 'active'")
	args := []any{categoryID, locale}
	args, argN := appendProductFilters(&sb, args, filter, 3)
	sb.WriteString(orderByClause(filter.Sort))
	fmt.Fprintf(&sb, " LIMIT $%d OFFSET $%d", argN, argN+1)
	args = append(args, limit, offset)

	rows, err := r.pool.Query(ctx, sb.String(), args...)
	if err != nil {
		return nil, 0, fmt.Errorf("catalog.repo: ListProductsByCategory: %w", err)
	}
	defer rows.Close()
	return scanProductSummaries(rows, "product summary")
}

func (r *pgxRepository) SearchProductsSummary(ctx context.Context, query, locale string, filter ProductFilter, offset, limit int) ([]ProductSummaryRow, int, error) {
	var sb strings.Builder
	sb.WriteString(productSummarySelect)
	sb.WriteString(" WHERE p.status = 'active'" +
		" AND (t.search_vector @@ plainto_tsquery('simple', $1)" +
		" OR t.title ILIKE '%' || $1 || '%')")
	args := []any{query, locale}
	args, argN := appendProductFilters(&sb, args, filter, 3)
	sb.WriteString(orderByClause(filter.Sort))
	fmt.Fprintf(&sb, " LIMIT $%d OFFSET $%d", argN, argN+1)
	args = append(args, limit, offset)

	rows, err := r.pool.Query(ctx, sb.String(), args...)
	if err != nil {
		return nil, 0, fmt.Errorf("catalog.repo: SearchProductsSummary: %w", err)
	}
	defer rows.Close()
	return scanProductSummaries(rows, "search summary")
}

func (r *pgxRepository) GetVariantByID(ctx context.Context, variantID int64) (Variant, error) {
	var v Variant
	err := r.pool.QueryRow(ctx,
		`SELECT v.id, v.product_id, p.category_id, p.seller_id,
		        v.sku, v.color, v.size, v.price_minor, v.price_currency, v.stock, v.image_keys
		FROM catalog_schema.variants v
		JOIN catalog_schema.products p ON p.id = v.product_id
		WHERE v.id = $1`,
		variantID,
	).Scan(&v.ID, &v.ProductID, &v.CategoryID, &v.SellerID,
		&v.SKU, &v.Color, &v.Size,
		&v.PriceMinor, &v.PriceCurrency, &v.Stock, &v.ImageKeys)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return Variant{}, ErrNotFound
		}
		return Variant{}, fmt.Errorf("catalog.repo: GetVariantByID: %w", err)
	}
	if v.ImageKeys == nil {
		v.ImageKeys = []string{}
	}
	return v, nil
}

func (r *pgxRepository) ListAllVariantStocks(ctx context.Context) ([]VariantStock, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT id, stock FROM catalog_schema.variants WHERE stock > 0`)
	if err != nil {
		return nil, fmt.Errorf("catalog.repo: ListAllVariantStocks: %w", err)
	}
	defer rows.Close()
	var out []VariantStock
	for rows.Next() {
		var vs VariantStock
		if err := rows.Scan(&vs.VariantID, &vs.Stock); err != nil {
			return nil, fmt.Errorf("catalog.repo: ListAllVariantStocks scan: %w", err)
		}
		out = append(out, vs)
	}
	return out, rows.Err()
}

func (r *pgxRepository) GetCommission(ctx context.Context, market string, categoryID int64) (CategoryCommission, error) {
	var c CategoryCommission
	err := r.pool.QueryRow(ctx,
		`SELECT category_id, market, commission_pct_bps, kdv_pct_bps
		FROM ref_schema.commission_rules
		WHERE market = $1
		  AND category_id = $2
		  AND active = TRUE
		  AND (effective_to IS NULL OR effective_to > now())
		ORDER BY effective_from DESC
		LIMIT 1`,
		market, categoryID,
	).Scan(&c.CategoryID, &c.Market, &c.CommissionPctBps, &c.KdvPctBps)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return CategoryCommission{}, ErrCommissionNotFound
		}
		return CategoryCommission{}, fmt.Errorf("catalog.repo: GetCommission: %w", err)
	}
	return c, nil
}

// ── Batch + home + reviews ────────────────────────────────────────────────────

func (r *pgxRepository) ListProductsByIDs(ctx context.Context, ids []int64, locale string) ([]ProductSummaryRow, error) {
	if len(ids) == 0 {
		return []ProductSummaryRow{}, nil
	}
	rows, err := r.pool.Query(ctx,
		`SELECT p.id, p.seller_id, p.category_id, p.brand, p.status,
		        COALESCE(t.title, '') AS title,
		        v.price_minor, v.price_currency,
		        COALESCE(v.image_keys[1], '') AS cover_image_key,
		        COALESCE(cr.commission_pct_bps, 0) AS commission_pct_bps,
		        v.original_price_minor,
		        p.rating_avg, p.rating_count,
		        p.free_shipping,
		        (SELECT count(*) FROM catalog_schema.user_favorites uf
		         WHERE uf.product_id = p.id) AS favorites_count
		FROM catalog_schema.products p
		JOIN catalog_schema.product_translations t
		     ON t.product_id = p.id AND t.locale = $2
		JOIN LATERAL (
		    SELECT price_minor, price_currency, image_keys, original_price_minor
		    FROM catalog_schema.variants
		    WHERE product_id = p.id
		    ORDER BY price_minor ASC LIMIT 1
		) v ON TRUE
		LEFT JOIN ref_schema.commission_rules cr
		       ON cr.category_id = p.category_id
		      AND cr.active = TRUE
		      AND (cr.effective_to IS NULL OR cr.effective_to > now())
		WHERE p.id = ANY($1) AND p.status = 'active'
		ORDER BY p.id`,
		ids, locale,
	)
	if err != nil {
		return nil, fmt.Errorf("catalog.repo: ListProductsByIDs: %w", err)
	}
	defer rows.Close()

	var results []ProductSummaryRow
	for rows.Next() {
		var s ProductSummaryRow
		if err := rows.Scan(
			&s.ID, &s.SellerID, &s.CategoryID, &s.Brand, &s.Status,
			&s.Title, &s.PriceMinor, &s.PriceCurrency,
			&s.CoverImageKey, &s.CommissionPctBps,
			&s.OriginalPriceMinor, &s.RatingAvg, &s.RatingCount,
			&s.FreeShipping, &s.FavoritesCount,
		); err != nil {
			return nil, fmt.Errorf("catalog.repo: scan product: %w", err)
		}
		results = append(results, s)
	}
	if results == nil {
		results = []ProductSummaryRow{}
	}
	return results, rows.Err()
}

func (r *pgxRepository) HomeRails(ctx context.Context) ([]HomeRailRow, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT rail_key, title_tr, title_en, sort_order
		FROM catalog_schema.home_rails WHERE active = TRUE ORDER BY sort_order`)
	if err != nil {
		return nil, fmt.Errorf("catalog.repo: HomeRails: %w", err)
	}
	defer rows.Close()
	var out []HomeRailRow
	for rows.Next() {
		var h HomeRailRow
		if err := rows.Scan(&h.RailKey, &h.TitleTR, &h.TitleEN, &h.SortOrder); err != nil {
			return nil, err
		}
		out = append(out, h)
	}
	if out == nil {
		out = []HomeRailRow{}
	}
	return out, rows.Err()
}

func (r *pgxRepository) HomeFlashDeals(ctx context.Context, collectionID *int64) (*FlashDealsCollectionRow, error) {
	var col FlashDealsCollectionRow
	var err error
	if collectionID != nil {
		// Preview by id — ignores the active window so admins can preview.
		err = r.pool.QueryRow(ctx,
			`SELECT id, title, ends_at FROM catalog_schema.home_flash_deals_collections WHERE id = $1`,
			*collectionID,
		).Scan(&col.ID, &col.Title, &col.EndsAt)
	} else {
		err = r.pool.QueryRow(ctx,
			`SELECT id, title, ends_at FROM catalog_schema.home_flash_deals_collections
			 WHERE is_active = TRUE AND NOW() BETWEEN starts_at AND ends_at
			 ORDER BY id LIMIT 1`,
		).Scan(&col.ID, &col.Title, &col.EndsAt)
	}
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("catalog.repo: HomeFlashDeals collection: %w", err)
	}

	rows, err := r.pool.Query(ctx,
		`SELECT product_id, flash_price_minor, sort_order
		 FROM catalog_schema.home_flash_deals_items
		 WHERE collection_id = $1 ORDER BY sort_order, product_id`,
		col.ID,
	)
	if err != nil {
		return nil, fmt.Errorf("catalog.repo: HomeFlashDeals items: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		var it FlashDealItemRow
		if err := rows.Scan(&it.ProductID, &it.FlashPriceMinor, &it.SortOrder); err != nil {
			return nil, err
		}
		col.Items = append(col.Items, it)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return &col, nil
}

func (r *pgxRepository) HomeBanners(ctx context.Context) ([]HomeBannerRow, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT id, image_url, deep_link, sort_order
		FROM catalog_schema.home_banners WHERE active = TRUE ORDER BY sort_order`)
	if err != nil {
		return nil, fmt.Errorf("catalog.repo: HomeBanners: %w", err)
	}
	defer rows.Close()
	var out []HomeBannerRow
	for rows.Next() {
		var b HomeBannerRow
		if err := rows.Scan(&b.ID, &b.ImageURL, &b.DeepLink, &b.SortOrder); err != nil {
			return nil, err
		}
		out = append(out, b)
	}
	if out == nil {
		out = []HomeBannerRow{}
	}
	return out, rows.Err()
}

func (r *pgxRepository) HomeMoodStories(ctx context.Context) ([]HomeMoodStoryRow, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT id, title_tr, title_en, image_url, deep_link, sort_order
		FROM catalog_schema.home_mood_stories WHERE active = TRUE ORDER BY sort_order`)
	if err != nil {
		return nil, fmt.Errorf("catalog.repo: HomeMoodStories: %w", err)
	}
	defer rows.Close()
	var out []HomeMoodStoryRow
	for rows.Next() {
		var s HomeMoodStoryRow
		if err := rows.Scan(&s.ID, &s.TitleTR, &s.TitleEN, &s.ImageURL, &s.DeepLink, &s.SortOrder); err != nil {
			return nil, err
		}
		out = append(out, s)
	}
	if out == nil {
		out = []HomeMoodStoryRow{}
	}
	return out, rows.Err()
}

// ListReviews returns one page of reviews ordered by sort. VotedByCurrentUser is
// computed via a LEFT JOIN to the authoritative review_helpful_votes table keyed
// on viewerUserID (0 matches no user → false for guests). The ORDER BY is a
// trusted whitelist (ReviewSort.orderByClause), never interpolated user input.
func (r *pgxRepository) ListReviews(ctx context.Context, productID int64, sort ReviewSort, offset, limit int, viewerUserID int64) ([]ProductReviewRow, int, error) {
	//nolint:gosec // orderByClause is a fixed whitelist, not user input.
	q := `SELECT r.id, r.product_id, r.user_id, r.rating,
	             COALESCE(r.title,''), COALESCE(r.body,''),
	             r.helpful_count,
	             (v.user_id IS NOT NULL) AS voted_by_current_user,
	             r.created_at::text,
	             count(*) OVER() AS total_count
	      FROM catalog_schema.product_reviews r
	      LEFT JOIN catalog_schema.review_helpful_votes v
	             ON v.review_id = r.id AND v.user_id = $4
	      WHERE r.product_id = $1
	      ORDER BY ` + sort.orderByClause() + `
	      LIMIT $2 OFFSET $3`
	rows, err := r.pool.Query(ctx, q, productID, limit, offset, viewerUserID)
	if err != nil {
		return nil, 0, fmt.Errorf("catalog.repo: ListReviews: %w", err)
	}
	defer rows.Close()
	var out []ProductReviewRow
	var total int
	for rows.Next() {
		var rv ProductReviewRow
		if err := rows.Scan(
			&rv.ID, &rv.ProductID, &rv.UserID, &rv.Rating,
			&rv.Title, &rv.Body, &rv.HelpfulCount, &rv.VotedByCurrentUser, &rv.CreatedAt, &total,
		); err != nil {
			return nil, 0, err
		}
		out = append(out, rv)
	}
	if out == nil {
		out = []ProductReviewRow{}
	}
	return out, total, rows.Err()
}

// ReviewsSummary computes the rating aggregate from product_reviews (authoritative
// for the histogram). Distribution always has keys 1..5 (zero when absent).
func (r *pgxRepository) ReviewsSummary(ctx context.Context, productID int64) (ReviewsSummary, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT rating, COUNT(*) FROM catalog_schema.product_reviews
		 WHERE product_id = $1 GROUP BY rating`, productID)
	if err != nil {
		return ReviewsSummary{}, fmt.Errorf("catalog.repo: ReviewsSummary: %w", err)
	}
	defer rows.Close()
	dist := map[int]int{1: 0, 2: 0, 3: 0, 4: 0, 5: 0}
	var total, weighted int
	for rows.Next() {
		var rating, count int
		if err := rows.Scan(&rating, &count); err != nil {
			return ReviewsSummary{}, err
		}
		if rating >= 1 && rating <= 5 {
			dist[rating] = count
		}
		total += count
		weighted += rating * count
	}
	if err := rows.Err(); err != nil {
		return ReviewsSummary{}, err
	}
	var avg float64
	if total > 0 {
		avg = float64(weighted) / float64(total)
	}
	return ReviewsSummary{Average: avg, Distribution: dist, TotalCount: total}, nil
}

// ReviewProductID returns the product a review belongs to, or ErrReviewNotFound.
func (r *pgxRepository) ReviewProductID(ctx context.Context, reviewID int64) (int64, error) {
	var pid int64
	err := r.pool.QueryRow(ctx,
		`SELECT product_id FROM catalog_schema.product_reviews WHERE id = $1`, reviewID).Scan(&pid)
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, ErrReviewNotFound
	}
	if err != nil {
		return 0, fmt.Errorf("catalog.repo: ReviewProductID: %w", err)
	}
	return pid, nil
}

// WithTx runs fn in a transaction at the given isolation level, retrying on
// serialization failures (40001) and deadlocks (40P01) — required because the
// helpful-vote toggle runs at SERIALIZABLE and concurrent toggles legitimately
// conflict. Each successful fn applies exactly one logical change regardless of
// how many times it is retried (nothing commits until the final attempt).
func (r *pgxRepository) WithTx(ctx context.Context, iso pgx.TxIsoLevel, fn func(pgx.Tx) error) error {
	const maxRetries = 10
	var lastErr error
	for attempt := 0; attempt < maxRetries; attempt++ {
		tx, err := r.pool.BeginTx(ctx, pgx.TxOptions{IsoLevel: iso})
		if err != nil {
			return fmt.Errorf("catalog.repo: begin tx: %w", err)
		}
		if err := fn(tx); err != nil {
			_ = tx.Rollback(ctx)
			if isSerializationFailure(err) {
				lastErr = err
				continue
			}
			return err
		}
		if err := tx.Commit(ctx); err != nil {
			_ = tx.Rollback(ctx)
			if isSerializationFailure(err) {
				lastErr = err
				continue
			}
			return fmt.Errorf("catalog.repo: commit tx: %w", err)
		}
		return nil
	}
	return fmt.Errorf("catalog.repo: tx serialization retries exhausted: %w", lastErr)
}

// isSerializationFailure reports whether err is a Postgres serialization failure
// (40001) or deadlock (40P01) — the retryable transaction-conflict codes.
func isSerializationFailure(err error) bool {
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) {
		return pgErr.Code == "40001" || pgErr.Code == "40P01"
	}
	return false
}

// InsertHelpfulVote inserts the (reviewID, userID) row. On a 23505 unique
// violation it returns ErrAlreadyVoted — the EXPECTED concurrent / already-voted
// path (the PRIMARY KEY is the authoritative double-vote guard), NOT logged. The
// INSERT is wrapped in a savepoint so a conflict does not poison the outer
// transaction; the caller toggles off instead.
func (r *pgxRepository) InsertHelpfulVote(ctx context.Context, tx pgx.Tx, reviewID, userID int64) error {
	sp, err := tx.Begin(ctx) // nested tx = SAVEPOINT
	if err != nil {
		return fmt.Errorf("catalog.repo: InsertHelpfulVote savepoint: %w", err)
	}
	_, err = sp.Exec(ctx,
		`INSERT INTO catalog_schema.review_helpful_votes (review_id, user_id) VALUES ($1, $2)`,
		reviewID, userID)
	if err != nil {
		_ = sp.Rollback(ctx) // ROLLBACK TO SAVEPOINT — outer tx stays usable
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == pgxUniqueViolation {
			return ErrAlreadyVoted
		}
		return fmt.Errorf("catalog.repo: InsertHelpfulVote: %w", err)
	}
	if err := sp.Commit(ctx); err != nil { // RELEASE SAVEPOINT
		return fmt.Errorf("catalog.repo: InsertHelpfulVote release: %w", err)
	}
	return nil
}

// DeleteHelpfulVote removes the vote row; the bool reports whether a row existed.
func (r *pgxRepository) DeleteHelpfulVote(ctx context.Context, tx pgx.Tx, reviewID, userID int64) (bool, error) {
	ct, err := tx.Exec(ctx,
		`DELETE FROM catalog_schema.review_helpful_votes WHERE review_id = $1 AND user_id = $2`,
		reviewID, userID)
	if err != nil {
		return false, fmt.Errorf("catalog.repo: DeleteHelpfulVote: %w", err)
	}
	return ct.RowsAffected() > 0, nil
}

// RefreshHelpfulCountCache recomputes product_reviews.helpful_count from the
// authoritative review_helpful_votes rows. helpful_count is a DENORMALIZED CACHE,
// not the source of truth; this MUST run inside the same (SERIALIZABLE) tx as the
// vote insert/delete so the cache can never drift. Mirrors RefreshPaymentsMadeCache.
func (r *pgxRepository) RefreshHelpfulCountCache(ctx context.Context, tx pgx.Tx, reviewID int64) error {
	_, err := tx.Exec(ctx,
		`UPDATE catalog_schema.product_reviews
		    SET helpful_count = (SELECT COUNT(*) FROM catalog_schema.review_helpful_votes WHERE review_id = $1)
		  WHERE id = $1`, reviewID)
	if err != nil {
		return fmt.Errorf("catalog.repo: RefreshHelpfulCountCache: %w", err)
	}
	return nil
}

// HelpfulCount reads the cached helpful_count within the tx (called right after a
// refresh, so it reflects the authoritative vote rows).
func (r *pgxRepository) HelpfulCount(ctx context.Context, tx pgx.Tx, reviewID int64) (int, error) {
	var c int
	err := tx.QueryRow(ctx,
		`SELECT helpful_count FROM catalog_schema.product_reviews WHERE id = $1`, reviewID).Scan(&c)
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, ErrReviewNotFound
	}
	if err != nil {
		return 0, fmt.Errorf("catalog.repo: HelpfulCount: %w", err)
	}
	return c, nil
}
