package catalog

import (
	"context"
	"errors"
	"fmt"

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

func (r *pgxRepository) ListCategories(ctx context.Context, locale string) ([]CategoryRow, error) {
	nameCol := "name_en"
	if locale == "tr-TR" || locale == "tr" {
		nameCol = "name_tr"
	}
	rows, err := r.pool.Query(ctx,
		`SELECT c.id, c.slug, c.`+nameCol+`, c.parent_id,
		        COALESCE(cr.commission_pct_bps, 0) AS commission_pct_bps
		FROM ref_schema.categories c
		LEFT JOIN ref_schema.commission_rules cr
		       ON cr.category_id = c.id
		      AND cr.active = TRUE
		      AND (cr.effective_to IS NULL OR cr.effective_to > now())
		WHERE c.active = TRUE
		ORDER BY c.id ASC`,
	)
	if err != nil {
		return nil, fmt.Errorf("catalog.repo: ListCategories: %w", err)
	}
	defer rows.Close()

	var cats []CategoryRow
	for rows.Next() {
		var c CategoryRow
		if err := rows.Scan(&c.ID, &c.Slug, &c.Name, &c.ParentID, &c.CommissionPctBps); err != nil {
			return nil, fmt.Errorf("catalog.repo: scan category: %w", err)
		}
		cats = append(cats, c)
	}
	if cats == nil {
		cats = []CategoryRow{}
	}
	return cats, rows.Err()
}

func (r *pgxRepository) ListProductsByCategory(ctx context.Context, categoryID int64, locale string, offset, limit int) ([]ProductSummaryRow, int, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT p.id, p.seller_id, p.category_id, p.brand, p.status,
		        COALESCE(t.title, '') AS title,
		        v.price_minor, v.price_currency,
		        COALESCE(v.image_keys[1], '') AS cover_image_key,
		        COALESCE(cr.commission_pct_bps, 0) AS commission_pct_bps,
		        count(*) OVER() AS total_count
		FROM catalog_schema.products p
		JOIN catalog_schema.product_translations t
		     ON t.product_id = p.id AND t.locale = $2
		JOIN LATERAL (
		    SELECT price_minor, price_currency, image_keys
		    FROM catalog_schema.variants
		    WHERE product_id = p.id
		    ORDER BY price_minor ASC
		    LIMIT 1
		) v ON TRUE
		LEFT JOIN ref_schema.commission_rules cr
		       ON cr.category_id = p.category_id
		      AND cr.active = TRUE
		      AND (cr.effective_to IS NULL OR cr.effective_to > now())
		WHERE p.category_id = $1
		  AND p.status = 'active'
		ORDER BY p.id DESC
		LIMIT $3 OFFSET $4`,
		categoryID, locale, limit, offset,
	)
	if err != nil {
		return nil, 0, fmt.Errorf("catalog.repo: ListProductsByCategory: %w", err)
	}
	defer rows.Close()

	var results []ProductSummaryRow
	var total int
	for rows.Next() {
		var s ProductSummaryRow
		if err := rows.Scan(
			&s.ID, &s.SellerID, &s.CategoryID, &s.Brand, &s.Status,
			&s.Title, &s.PriceMinor, &s.PriceCurrency,
			&s.CoverImageKey, &s.CommissionPctBps, &total,
		); err != nil {
			return nil, 0, fmt.Errorf("catalog.repo: scan product summary: %w", err)
		}
		results = append(results, s)
	}
	if results == nil {
		results = []ProductSummaryRow{}
	}
	return results, total, rows.Err()
}

func (r *pgxRepository) SearchProductsSummary(ctx context.Context, query, locale string, offset, limit int) ([]ProductSummaryRow, int, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT p.id, p.seller_id, p.category_id, p.brand, p.status,
		        COALESCE(t.title, '') AS title,
		        v.price_minor, v.price_currency,
		        COALESCE(v.image_keys[1], '') AS cover_image_key,
		        COALESCE(cr.commission_pct_bps, 0) AS commission_pct_bps,
		        count(*) OVER() AS total_count
		FROM catalog_schema.products p
		JOIN catalog_schema.product_translations t
		     ON t.product_id = p.id AND t.locale = $2
		JOIN LATERAL (
		    SELECT price_minor, price_currency, image_keys
		    FROM catalog_schema.variants
		    WHERE product_id = p.id
		    ORDER BY price_minor ASC
		    LIMIT 1
		) v ON TRUE
		LEFT JOIN ref_schema.commission_rules cr
		       ON cr.category_id = p.category_id
		      AND cr.active = TRUE
		      AND (cr.effective_to IS NULL OR cr.effective_to > now())
		WHERE p.status = 'active'
		  AND (t.search_vector @@ plainto_tsquery('simple', $1)
		       OR t.title ILIKE '%' || $1 || '%')
		ORDER BY p.id DESC
		LIMIT $3 OFFSET $4`,
		query, locale, limit, offset,
	)
	if err != nil {
		return nil, 0, fmt.Errorf("catalog.repo: SearchProductsSummary: %w", err)
	}
	defer rows.Close()

	var results []ProductSummaryRow
	var total int
	for rows.Next() {
		var s ProductSummaryRow
		if err := rows.Scan(
			&s.ID, &s.SellerID, &s.CategoryID, &s.Brand, &s.Status,
			&s.Title, &s.PriceMinor, &s.PriceCurrency,
			&s.CoverImageKey, &s.CommissionPctBps, &total,
		); err != nil {
			return nil, 0, fmt.Errorf("catalog.repo: scan search summary: %w", err)
		}
		results = append(results, s)
	}
	if results == nil {
		results = []ProductSummaryRow{}
	}
	return results, total, rows.Err()
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
