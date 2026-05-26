// Seed binary — idempotent catalog seeder for Mopro Shop.
// Usage: seed --db-url=postgres://... [flags]
// Run `seed --help` for all options.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/mopro/platform/internal/cashback"
)

// ─── Data types ──────────────────────────────────────────────────────────────

type CategorySeed struct {
	ID               int64   `json:"id"`
	Slug             string  `json:"slug"`
	NameTR           string  `json:"name_tr"`
	NameEN           string  `json:"name_en"`
	ParentSlug       *string `json:"parent_slug"`
	CommissionPctBps int     `json:"commission_pct_bps"`
	KdvPctBps        int     `json:"kdv_pct_bps"`
	Active           bool    `json:"active"`
}

type ProductSeed struct {
	ExternalSKU         string          `json:"external_sku"`
	CategorySlug        string          `json:"category_slug"`
	Brand               string          `json:"brand"`
	TitleTR             string          `json:"title_tr"`
	TitleEN             string          `json:"title_en"`
	DescriptionTR       string          `json:"description_tr"`
	PriceMinor          int64           `json:"price_minor"`
	DiscountPriceMinor  *int64          `json:"discount_price_minor"`
	StockQty            int             `json:"stock_qty"`
	Color               string          `json:"color"`
	Size                string          `json:"size"`
	ImageKey            string          `json:"image_key"`
	RatingStars         float32         `json:"rating_stars"`
	RatingCount         int             `json:"rating_count"`
	Specs               json.RawMessage `json:"specs"`
	DefaultLocale       string          `json:"default_locale"`
	DefaultCurrency     string          `json:"default_currency"`
	CashbackTotalMonths int             `json:"cashback_total_months"`
}

// ─── Config ───────────────────────────────────────────────────────────────────

type Config struct {
	DBURL    string
	DataDir  string
	DryRun   bool
	Scope    string // "all" | "categories" | "products"
	Force    bool
	SellerID int64
	Market   string
}

func parseFlags() Config {
	cfg := Config{}
	flag.StringVar(&cfg.DBURL, "db-url", "", "PostgreSQL connection string (required)")
	flag.StringVar(&cfg.DataDir, "data-dir", "scripts/seed/data", "Directory containing JSON seed files")
	flag.BoolVar(&cfg.DryRun, "dry-run", false, "Print what would change without writing")
	flag.StringVar(&cfg.Scope, "scope", "all", "Scope: all | categories | products")
	flag.BoolVar(&cfg.Force, "force", false, "Force overwrite even if record looks identical")
	flag.Int64Var(&cfg.SellerID, "seller-id", 1, "Seller ID to assign to seeded products")
	flag.StringVar(&cfg.Market, "market", "TR", "Market code for commission rules")
	flag.Parse()

	if cfg.DBURL == "" {
		cfg.DBURL = os.Getenv("DATABASE_URL")
	}
	if cfg.DBURL == "" {
		fmt.Fprintln(os.Stderr, "ERROR: --db-url or DATABASE_URL is required")
		flag.Usage()
		os.Exit(1)
	}
	switch cfg.Scope {
	case "all", "categories", "products":
	default:
		fmt.Fprintf(os.Stderr, "ERROR: --scope must be one of: all, categories, products (got %q)\n", cfg.Scope)
		os.Exit(1)
	}
	return cfg
}

// ─── Seeder ───────────────────────────────────────────────────────────────────

type Seeder struct {
	pool *pgxpool.Pool
	cfg  Config
	log  *slog.Logger
}

func (s *Seeder) loadJSON(filename string, out any) error {
	path := filepath.Join(s.cfg.DataDir, filename)
	f, err := os.Open(path)
	if err != nil {
		return fmt.Errorf("open %s: %w", path, err)
	}
	defer f.Close()
	if err := json.NewDecoder(f).Decode(out); err != nil {
		return fmt.Errorf("decode %s: %w", path, err)
	}
	return nil
}

// ─── Categories ───────────────────────────────────────────────────────────────

func (s *Seeder) SeedCategories(ctx context.Context) error {
	var cats []CategorySeed
	if err := s.loadJSON("categories.json", &cats); err != nil {
		return err
	}
	s.log.Info("categories loaded", "count", len(cats))
	if s.cfg.DryRun {
		for _, c := range cats {
			s.log.Info("[dry-run] would upsert category", "id", c.ID, "slug", c.Slug)
		}
		return nil
	}

	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	inserted, updated := 0, 0
	const batchSize = 50

	// Roots first (parent_slug == nil), then leaves.
	roots, leaves := splitByParent(cats)

	for idx, batch := range toBatches(roots, batchSize) {
		sp := fmt.Sprintf("sp_root_%d", idx)
		if _, err := tx.Exec(ctx, "SAVEPOINT "+sp); err != nil {
			return fmt.Errorf("savepoint %s: %w", sp, err)
		}
		for _, c := range batch {
			n, err := upsertCategory(ctx, tx, c, nil)
			if err != nil {
				_, _ = tx.Exec(ctx, "ROLLBACK TO SAVEPOINT "+sp)
				return fmt.Errorf("upsert root category %s: %w", c.Slug, err)
			}
			inserted += n.inserted; updated += n.updated
		}
		if _, err := tx.Exec(ctx, "RELEASE SAVEPOINT "+sp); err != nil {
			return fmt.Errorf("release savepoint %s: %w", sp, err)
		}
	}

	// Resolve parent IDs for leaves.
	slugToID, err := fetchCategorySlugs(ctx, tx)
	if err != nil {
		return err
	}

	for idx, batch := range toBatches(leaves, batchSize) {
		sp := fmt.Sprintf("sp_leaf_%d", idx)
		if _, err := tx.Exec(ctx, "SAVEPOINT "+sp); err != nil {
			return fmt.Errorf("savepoint %s: %w", sp, err)
		}
		for _, c := range batch {
			parentID, ok := slugToID[*c.ParentSlug]
			if !ok {
				return fmt.Errorf("category %s references unknown parent_slug %q", c.Slug, *c.ParentSlug)
			}
			n, err := upsertCategory(ctx, tx, c, &parentID)
			if err != nil {
				_, _ = tx.Exec(ctx, "ROLLBACK TO SAVEPOINT "+sp)
				return fmt.Errorf("upsert leaf category %s: %w", c.Slug, err)
			}
			inserted += n.inserted; updated += n.updated
		}
		if _, err := tx.Exec(ctx, "RELEASE SAVEPOINT "+sp); err != nil {
			return fmt.Errorf("release savepoint %s: %w", sp, err)
		}
	}

	// Upsert commission rules in a second pass (needs category IDs stable).
	slugToID, err = fetchCategorySlugs(ctx, tx)
	if err != nil {
		return err
	}
	for idx, batch := range toBatches(cats, batchSize) {
		sp := fmt.Sprintf("sp_rules_%d", idx)
		if _, err := tx.Exec(ctx, "SAVEPOINT "+sp); err != nil {
			return fmt.Errorf("savepoint %s: %w", sp, err)
		}
		for _, c := range batch {
			cid := slugToID[c.Slug]
			if err := upsertCommissionRule(ctx, tx, s.cfg.Market, cid, c); err != nil {
				_, _ = tx.Exec(ctx, "ROLLBACK TO SAVEPOINT "+sp)
				return fmt.Errorf("upsert commission rule for %s: %w", c.Slug, err)
			}
		}
		if _, err := tx.Exec(ctx, "RELEASE SAVEPOINT "+sp); err != nil {
			return fmt.Errorf("release savepoint %s: %w", sp, err)
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("commit categories: %w", err)
	}
	s.log.Info("categories done", "inserted", inserted, "updated", updated)
	return nil
}

type counts struct{ inserted, updated int }

func upsertCategory(ctx context.Context, tx pgx.Tx, c CategorySeed, parentID *int64) (counts, error) {
	var existing int64
	err := tx.QueryRow(ctx,
		`SELECT id FROM ref_schema.categories WHERE slug = $1`, c.Slug,
	).Scan(&existing)

	if errors.Is(err, pgx.ErrNoRows) {
		_, err = tx.Exec(ctx,
			`INSERT INTO ref_schema.categories (id, slug, name_tr, name_en, parent_id, active)
			 VALUES ($1, $2, $3, $4, $5, $6)`,
			c.ID, c.Slug, c.NameTR, c.NameEN, parentID, c.Active,
		)
		if err != nil {
			return counts{}, err
		}
		return counts{inserted: 1}, nil
	}
	if err != nil {
		return counts{}, err
	}
	tag, err := tx.Exec(ctx,
		`UPDATE ref_schema.categories
		    SET name_tr = $1, name_en = $2, parent_id = $3, active = $4
		  WHERE slug = $5
		    AND (name_tr IS DISTINCT FROM $1
		      OR name_en IS DISTINCT FROM $2
		      OR parent_id IS DISTINCT FROM $3
		      OR active IS DISTINCT FROM $4)`,
		c.NameTR, c.NameEN, parentID, c.Active, c.Slug,
	)
	if err != nil {
		return counts{}, err
	}
	if tag.RowsAffected() > 0 {
		return counts{updated: 1}, nil
	}
	return counts{}, nil // no change — truly idempotent
}

func upsertCommissionRule(ctx context.Context, tx pgx.Tx, market string, categoryID int64, c CategorySeed) error {
	effectiveFrom := time.Date(2024, 1, 1, 0, 0, 0, 0, time.UTC)
	_, err := tx.Exec(ctx,
		`INSERT INTO ref_schema.commission_rules
		     (market, category_id, commission_pct_bps, kdv_pct_bps, effective_from, active)
		 VALUES ($1, $2, $3, $4, $5, TRUE)
		 ON CONFLICT (market, category_id, effective_from) DO UPDATE
		     SET commission_pct_bps = EXCLUDED.commission_pct_bps,
		         kdv_pct_bps        = EXCLUDED.kdv_pct_bps,
		         active             = EXCLUDED.active`,
		market, categoryID, c.CommissionPctBps, c.KdvPctBps, effectiveFrom,
	)
	return err
}

func fetchCategorySlugs(ctx context.Context, tx pgx.Tx) (map[string]int64, error) {
	rows, err := tx.Query(ctx, `SELECT id, slug FROM ref_schema.categories`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	m := make(map[string]int64)
	for rows.Next() {
		var id int64
		var slug string
		if err := rows.Scan(&id, &slug); err != nil {
			return nil, err
		}
		m[slug] = id
	}
	return m, rows.Err()
}

// ─── Products ─────────────────────────────────────────────────────────────────

func (s *Seeder) SeedProducts(ctx context.Context) error {
	var products []ProductSeed
	if err := s.loadJSON("products.json", &products); err != nil {
		return err
	}
	s.log.Info("products loaded", "count", len(products))

	// Build slug → commissionBps map from DB for validation.
	slugBps, err := s.fetchSlugBps(ctx)
	if err != nil {
		return fmt.Errorf("fetch category commission rates: %w", err)
	}

	// Validate cashback formula for every product before any writes.
	if err := s.validateCashbackAll(products, slugBps); err != nil {
		return err
	}

	if s.cfg.DryRun {
		for _, p := range products {
			s.log.Info("[dry-run] would upsert product", "sku", p.ExternalSKU, "title", p.TitleTR)
		}
		return nil
	}

	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()

	slugToID, err := fetchCategorySlugs(ctx, tx)
	if err != nil {
		return err
	}

	inserted, updated := 0, 0
	const batchSize = 50

	for idx, batch := range toBatches(products, batchSize) {
		sp := fmt.Sprintf("sp_products_%d", idx)
		if _, err := tx.Exec(ctx, "SAVEPOINT "+sp); err != nil {
			return fmt.Errorf("savepoint %s: %w", sp, err)
		}
		for _, p := range batch {
			catID, ok := slugToID[p.CategorySlug]
			if !ok {
				_, _ = tx.Exec(ctx, "ROLLBACK TO SAVEPOINT "+sp)
				return fmt.Errorf("sku %s: unknown category_slug %q — run seed --scope=categories first", p.ExternalSKU, p.CategorySlug)
			}
			n, err := s.upsertProduct(ctx, tx, p, catID)
			if err != nil {
				_, _ = tx.Exec(ctx, "ROLLBACK TO SAVEPOINT "+sp)
				return fmt.Errorf("upsert product %s: %w", p.ExternalSKU, err)
			}
			inserted += n.inserted; updated += n.updated
		}
		if _, err := tx.Exec(ctx, "RELEASE SAVEPOINT "+sp); err != nil {
			return fmt.Errorf("release savepoint %s: %w", sp, err)
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("commit products: %w", err)
	}
	s.log.Info("products done", "inserted", inserted, "updated", updated)
	return nil
}

func (s *Seeder) fetchSlugBps(ctx context.Context) (map[string]int, error) {
	rows, err := s.pool.Query(ctx,
		`SELECT c.slug, r.commission_pct_bps
		   FROM ref_schema.categories c
		   JOIN ref_schema.commission_rules r ON r.category_id = c.id
		  WHERE r.market = $1 AND r.active = TRUE`,
		s.cfg.Market,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	m := make(map[string]int)
	for rows.Next() {
		var slug string
		var bps int
		if err := rows.Scan(&slug, &bps); err != nil {
			return nil, err
		}
		m[slug] = bps
	}
	return m, rows.Err()
}

func (s *Seeder) validateCashbackAll(products []ProductSeed, slugBps map[string]int) error {
	var errs []error
	for _, p := range products {
		bps, ok := slugBps[p.CategorySlug]
		if !ok {
			errs = append(errs, fmt.Errorf("sku %s: category_slug %q not found in DB (run --scope=categories first)", p.ExternalSKU, p.CategorySlug))
			continue
		}
		expectedT := int(cashback.CashbackK / int64(bps))
		if p.CashbackTotalMonths != expectedT {
			errs = append(errs, fmt.Errorf(
				"sku %s: cashback_total_months %d != K(%d)/bps(%d)=%d",
				p.ExternalSKU, p.CashbackTotalMonths, cashback.CashbackK, bps, expectedT,
			))
		}
	}
	return errors.Join(errs...)
}

func (s *Seeder) upsertProduct(ctx context.Context, tx pgx.Tx, p ProductSeed, catID int64) (counts, error) {
	// Look up variant by global SKU (requires unique index from migration 0061).
	var variantID, productID int64
	err := tx.QueryRow(ctx,
		`SELECT v.id, v.product_id FROM catalog_schema.variants v WHERE v.sku = $1`,
		p.ExternalSKU,
	).Scan(&variantID, &productID)

	if errors.Is(err, pgx.ErrNoRows) {
		// Insert product.
		specsBytes, _ := p.Specs.MarshalJSON()
		if err := tx.QueryRow(ctx,
			`INSERT INTO catalog_schema.products
			     (seller_id, category_id, brand, default_currency, default_locale, status,
			      rating_stars, rating_count)
			 VALUES ($1, $2, $3, $4, $5, 'active', $6, $7)
			 RETURNING id`,
			s.cfg.SellerID, catID, p.Brand, p.DefaultCurrency, p.DefaultLocale,
			p.RatingStars, p.RatingCount,
		).Scan(&productID); err != nil {
			return counts{}, fmt.Errorf("insert product: %w", err)
		}

		// Insert variant.
		if err := tx.QueryRow(ctx,
			`INSERT INTO catalog_schema.variants
			     (product_id, sku, color, size, price_minor, price_currency,
			      discount_price_minor, stock, image_keys)
			 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
			 RETURNING id`,
			productID, p.ExternalSKU, p.Color, p.Size, p.PriceMinor,
			p.DefaultCurrency, p.DiscountPriceMinor, p.StockQty,
			[]string{p.ImageKey},
		).Scan(&variantID); err != nil {
			return counts{}, fmt.Errorf("insert variant: %w", err)
		}

		// Insert TR translation.
		if _, err := tx.Exec(ctx,
			`INSERT INTO catalog_schema.product_translations
			     (product_id, locale, title, description, specs)
			 VALUES ($1, $2, $3, $4, $5)`,
			productID, p.DefaultLocale, p.TitleTR, p.DescriptionTR, specsBytes,
		); err != nil {
			return counts{}, fmt.Errorf("insert translation tr: %w", err)
		}
		// Insert EN translation if available.
		if p.TitleEN != "" && p.DefaultLocale != "en-US" {
			if _, err := tx.Exec(ctx,
				`INSERT INTO catalog_schema.product_translations
				     (product_id, locale, title, description, specs)
				 VALUES ($1, $2, $3, $4, $5)
				 ON CONFLICT (product_id, locale) DO UPDATE
				     SET title = EXCLUDED.title, specs = EXCLUDED.specs`,
				productID, "en-US", p.TitleEN, "", specsBytes,
			); err != nil {
				return counts{}, fmt.Errorf("insert translation en: %w", err)
			}
		}
		return counts{inserted: 1}, nil
	}
	if err != nil {
		return counts{}, fmt.Errorf("lookup variant: %w", err)
	}

	// Update existing product + variant + translation — only if values actually changed.
	specsBytes, _ := p.Specs.MarshalJSON()
	var changed bool

	pt, err := tx.Exec(ctx,
		`UPDATE catalog_schema.products
		    SET category_id = $1, brand = $2, rating_stars = $3, rating_count = $4, updated_at = now()
		  WHERE id = $5
		    AND (category_id IS DISTINCT FROM $1
		      OR brand IS DISTINCT FROM $2
		      OR rating_stars IS DISTINCT FROM $3
		      OR rating_count IS DISTINCT FROM $4)`,
		catID, p.Brand, p.RatingStars, p.RatingCount, productID,
	)
	if err != nil {
		return counts{}, fmt.Errorf("update product: %w", err)
	}
	if pt.RowsAffected() > 0 {
		changed = true
	}

	vt, err := tx.Exec(ctx,
		`UPDATE catalog_schema.variants
		    SET price_minor = $1, discount_price_minor = $2, stock = $3, image_keys = $4
		  WHERE id = $5
		    AND (price_minor IS DISTINCT FROM $1
		      OR discount_price_minor IS DISTINCT FROM $2
		      OR stock IS DISTINCT FROM $3)`,
		p.PriceMinor, p.DiscountPriceMinor, p.StockQty, []string{p.ImageKey}, variantID,
	)
	if err != nil {
		return counts{}, fmt.Errorf("update variant: %w", err)
	}
	if vt.RowsAffected() > 0 {
		changed = true
	}

	tt, err := tx.Exec(ctx,
		`INSERT INTO catalog_schema.product_translations
		     (product_id, locale, title, description, specs)
		 VALUES ($1, $2, $3, $4, $5)
		 ON CONFLICT (product_id, locale) DO UPDATE
		     SET title = EXCLUDED.title, description = EXCLUDED.description, specs = EXCLUDED.specs
		   WHERE product_translations.title IS DISTINCT FROM EXCLUDED.title
		      OR product_translations.description IS DISTINCT FROM EXCLUDED.description
		      OR product_translations.specs IS DISTINCT FROM EXCLUDED.specs`,
		productID, p.DefaultLocale, p.TitleTR, p.DescriptionTR, specsBytes,
	)
	if err != nil {
		return counts{}, fmt.Errorf("upsert translation: %w", err)
	}
	if tt.RowsAffected() > 0 {
		changed = true
	}

	if changed {
		return counts{updated: 1}, nil
	}
	return counts{}, nil // truly idempotent — no writes
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

func splitByParent(cats []CategorySeed) (roots, leaves []CategorySeed) {
	for _, c := range cats {
		if c.ParentSlug == nil {
			roots = append(roots, c)
		} else {
			leaves = append(leaves, c)
		}
	}
	return
}

func toBatches[T any](items []T, size int) [][]T {
	var batches [][]T
	for len(items) > 0 {
		end := size
		if end > len(items) {
			end = len(items)
		}
		batches = append(batches, items[:end])
		items = items[end:]
	}
	return batches
}

// ─── Main ─────────────────────────────────────────────────────────────────────

func main() {
	cfg := parseFlags()
	log := slog.New(slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))

	ctx := context.Background()
	pool, err := pgxpool.New(ctx, cfg.DBURL)
	if err != nil {
		log.Error("connect", "err", err)
		os.Exit(1)
	}
	defer pool.Close()

	if err := pool.Ping(ctx); err != nil {
		log.Error("ping", "err", err)
		os.Exit(1)
	}
	log.Info("connected", "dry_run", cfg.DryRun, "scope", cfg.Scope, "market", cfg.Market)

	s := &Seeder{pool: pool, cfg: cfg, log: log}

	if cfg.Scope == "all" || cfg.Scope == "categories" {
		if err := s.SeedCategories(ctx); err != nil {
			log.Error("seed categories", "err", err)
			os.Exit(1)
		}
	}
	if cfg.Scope == "all" || cfg.Scope == "products" {
		if err := s.SeedProducts(ctx); err != nil {
			log.Error("seed products", "err", err)
			os.Exit(1)
		}
	}
	log.Info("seed complete")
}
