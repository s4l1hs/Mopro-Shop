//go:build integration

package catalog_test

// Integration test for the catalog repository against an ephemeral PG16.
//
// Start the ephemeral container before running:
//
//	docker run --rm -d --name pg-ecom-test -p 6433:5432 \
//	  -e POSTGRES_USER=ecom_admin -e POSTGRES_PASSWORD=test123 \
//	  -e POSTGRES_DB=mopro_ecom postgres:16-alpine
//
// Then:
//
//	go test -tags=integration -v ./internal/catalog/...
//
// Override DSN with CATALOG_TEST_DSN if running against another endpoint.

import (
	"context"
	"errors"
	"fmt"
	"os"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/mopro/platform/internal/catalog"
)

const (
	defaultTestDSN = "postgres://ecom_admin:test123@localhost:6433/mopro_ecom"
)

var integPool *pgxpool.Pool

func TestMain(m *testing.M) {
	dsn := os.Getenv("CATALOG_TEST_DSN")
	if dsn == "" {
		dsn = defaultTestDSN
	}

	ctx := context.Background()
	var err error
	integPool, err = pgxpool.New(ctx, dsn)
	if err != nil {
		fmt.Fprintf(os.Stderr, "catalog integration: cannot create pool (%s): %v\n", dsn, err)
		os.Exit(1)
	}
	if err := integPool.Ping(ctx); err != nil {
		fmt.Fprintf(os.Stderr, "catalog integration: postgres ping failed: %v\n", err)
		os.Exit(1)
	}

	if err := setupSchema(ctx, integPool); err != nil {
		fmt.Fprintf(os.Stderr, "catalog integration: schema setup failed: %v\n", err)
		os.Exit(1)
	}

	code := m.Run()
	integPool.Close()
	os.Exit(code)
}

// setupSchema creates the minimal schema required for catalog tests.
func setupSchema(ctx context.Context, pool *pgxpool.Pool) error {
	ddl := `
CREATE SCHEMA IF NOT EXISTS ref_schema;
CREATE SCHEMA IF NOT EXISTS catalog_schema;

CREATE TABLE IF NOT EXISTS ref_schema.currencies (
    code             TEXT NOT NULL,
    kind             TEXT NOT NULL,
    minor_unit_scale INT  NOT NULL DEFAULT 2,
    symbol           TEXT NOT NULL,
    name_en          TEXT NOT NULL,
    active           BOOL NOT NULL DEFAULT FALSE,
    PRIMARY KEY (code)
);
INSERT INTO ref_schema.currencies (code, kind, symbol, name_en, active)
VALUES ('TRY','fiat','₺','Turkish Lira',TRUE),
       ('USD','fiat','$','US Dollar',FALSE),
       ('TRY_COIN','coin','₮','Mopro Coin',TRUE)
ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS ref_schema.categories (
    id        BIGINT NOT NULL,
    slug      TEXT   NOT NULL,
    name_tr   TEXT   NOT NULL,
    name_en   TEXT   NOT NULL,
    parent_id BIGINT REFERENCES ref_schema.categories(id),
    active    BOOL   NOT NULL DEFAULT TRUE,
    PRIMARY KEY (id),
    UNIQUE (slug)
);
INSERT INTO ref_schema.categories (id, slug, name_tr, name_en)
VALUES (30, 'akilli-telefon', 'Akıllı Cep Telefonu', 'Smartphones')
ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS ref_schema.commission_rules (
    id                 BIGSERIAL   NOT NULL,
    market             TEXT        NOT NULL,
    category_id        BIGINT      NOT NULL REFERENCES ref_schema.categories(id),
    commission_pct_bps INT         NOT NULL,
    kdv_pct_bps        INT         NOT NULL,
    effective_from     TIMESTAMPTZ NOT NULL DEFAULT now(),
    effective_to       TIMESTAMPTZ,
    active             BOOL        NOT NULL DEFAULT TRUE,
    PRIMARY KEY (id),
    UNIQUE (market, category_id, effective_from)
);
INSERT INTO ref_schema.commission_rules (market, category_id, commission_pct_bps, kdv_pct_bps)
VALUES ('TR', 30, 700, 2000)
ON CONFLICT DO NOTHING;

DROP TABLE IF EXISTS catalog_schema.variants CASCADE;
DROP TABLE IF EXISTS catalog_schema.product_translations CASCADE;
DROP TABLE IF EXISTS catalog_schema.products CASCADE;

CREATE TABLE catalog_schema.products (
    id               BIGSERIAL    PRIMARY KEY,
    seller_id        BIGINT       NOT NULL,
    category_id      BIGINT       NOT NULL,
    brand            TEXT         NOT NULL DEFAULT '',
    default_currency TEXT         NOT NULL DEFAULT 'TRY',
    default_locale   TEXT         NOT NULL DEFAULT 'tr-TR',
    status           TEXT         NOT NULL DEFAULT 'draft',
    -- additive display/filter columns (migrations 0065 + 0081)
    rating_avg       NUMERIC(2,1),
    rating_count     INT          NOT NULL DEFAULT 0,
    free_shipping    BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE catalog_schema.product_translations (
    product_id  BIGINT NOT NULL REFERENCES catalog_schema.products(id),
    locale      TEXT   NOT NULL,
    title       TEXT   NOT NULL,
    description TEXT   NOT NULL DEFAULT '',
    -- generated FTS column (migration 0057) so SearchProductsSummary works
    search_vector TSVECTOR GENERATED ALWAYS AS (
        to_tsvector('simple', coalesce(title, '') || ' ' || coalesce(description, ''))
    ) STORED,
    PRIMARY KEY (product_id, locale)
);

CREATE TABLE catalog_schema.variants (
    id                   BIGSERIAL PRIMARY KEY,
    product_id           BIGINT    NOT NULL REFERENCES catalog_schema.products(id),
    sku                  TEXT      NOT NULL,
    color                TEXT      NOT NULL DEFAULT '',
    size                 TEXT      NOT NULL DEFAULT '',
    price_minor          BIGINT    NOT NULL,
    price_currency       TEXT      NOT NULL DEFAULT 'TRY',
    stock                INTEGER   NOT NULL DEFAULT 0,
    original_price_minor BIGINT,
    image_keys           TEXT[]    NOT NULL DEFAULT '{}'::text[]
);

CREATE UNIQUE INDEX variants_product_sku_uq ON catalog_schema.variants(product_id, sku);

-- Reviews + helpful votes (mirrors migration 0064 + the additive 0069 created_at).
DROP TABLE IF EXISTS catalog_schema.review_helpful_votes CASCADE;
DROP TABLE IF EXISTS catalog_schema.product_reviews CASCADE;

CREATE TABLE catalog_schema.product_reviews (
    id            BIGSERIAL   PRIMARY KEY,
    product_id    BIGINT      NOT NULL,
    user_id       BIGINT      NOT NULL,
    rating        SMALLINT    NOT NULL CHECK (rating BETWEEN 1 AND 5),
    title         TEXT,
    body          TEXT,
    helpful_count INT         NOT NULL DEFAULT 0,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (product_id, user_id)
);

CREATE TABLE catalog_schema.review_helpful_votes (
    review_id  BIGINT      NOT NULL REFERENCES catalog_schema.product_reviews(id) ON DELETE CASCADE,
    user_id    BIGINT      NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (review_id, user_id)
);
`
	_, err := pool.Exec(ctx, ddl)
	return err
}

func TestIntegration_CatalogCRUD(t *testing.T) {
	ctx := context.Background()
	repo := catalog.NewRepository(integPool)
	svc := catalog.NewService(repo, "TRY", "tr-TR")

	// 1. Create product
	p, err := svc.CreateProduct(ctx, catalog.CreateProductRequest{
		SellerID:   100,
		CategoryID: 30,
		Brand:      "TestBrand",
	})
	if err != nil {
		t.Fatalf("CreateProduct: %v", err)
	}
	if p.ID == 0 {
		t.Fatal("product ID is zero after insert")
	}
	if p.Status != "draft" {
		t.Errorf("expected draft, got %q", p.Status)
	}

	// 2. Add Turkish translation
	err = svc.UpdateTranslation(ctx, p.ID, "tr-TR", "Test Başlığı", "Test açıklaması")
	if err != nil {
		t.Fatalf("UpdateTranslation: %v", err)
	}

	// 3. Upsert same translation (idempotent)
	err = svc.UpdateTranslation(ctx, p.ID, "tr-TR", "Yeni Başlık", "Yeni açıklama")
	if err != nil {
		t.Fatalf("UpdateTranslation upsert: %v", err)
	}

	// 4. Add a variant with valid currency
	v1, err := svc.AddVariant(ctx, p.ID, catalog.AddVariantRequest{
		SKU:        "MODEL-BLACK-M",
		Color:      "Siyah",
		Size:       "M",
		PriceMinor: 75000,
		ImageKeys:  []string{"img/prod1.jpg"},
	})
	if err != nil {
		t.Fatalf("AddVariant: %v", err)
	}
	if v1.ID == 0 {
		t.Fatal("variant ID is zero after insert")
	}

	// 5. Duplicate SKU must fail
	_, err = svc.AddVariant(ctx, p.ID, catalog.AddVariantRequest{
		SKU:        "MODEL-BLACK-M",
		PriceMinor: 80000,
	})
	if !errors.Is(err, catalog.ErrDuplicateSKU) {
		t.Fatalf("expected ErrDuplicateSKU, got %v", err)
	}

	// 6. Invalid currency must fail
	_, err = svc.AddVariant(ctx, p.ID, catalog.AddVariantRequest{
		SKU:           "MODEL-FAKE",
		PriceCurrency: "NOTEXIST",
		PriceMinor:    1000,
	})
	if !errors.Is(err, catalog.ErrInvalidCurrency) {
		t.Fatalf("expected ErrInvalidCurrency, got %v", err)
	}

	// 7. GetByID returns product + variant + translation
	gotP, gotVariants, gotTranslations, err := svc.GetByID(ctx, p.ID)
	if err != nil {
		t.Fatalf("GetByID: %v", err)
	}
	if gotP.ID != p.ID {
		t.Errorf("product ID mismatch: want %d got %d", p.ID, gotP.ID)
	}
	if len(gotVariants) != 1 {
		t.Errorf("expected 1 variant, got %d", len(gotVariants))
	}
	if gotVariants[0].SKU != "MODEL-BLACK-M" {
		t.Errorf("variant SKU mismatch: %q", gotVariants[0].SKU)
	}
	if len(gotTranslations) != 1 {
		t.Errorf("expected 1 translation, got %d", len(gotTranslations))
	}
	if gotTranslations[0].Title != "Yeni Başlık" {
		t.Errorf("translation title mismatch: %q", gotTranslations[0].Title)
	}

	// 8. GetByID for non-existent product returns ErrNotFound
	_, _, _, err = svc.GetByID(ctx, 999999)
	if !errors.Is(err, catalog.ErrNotFound) {
		t.Fatalf("expected ErrNotFound, got %v", err)
	}

	// 9. Commission lookup for category 30 in TR market
	cc, err := svc.GetCommissionForCategory(ctx, "TR", 30)
	if err != nil {
		t.Fatalf("GetCommissionForCategory: %v", err)
	}
	if cc.CommissionPctBps != 700 {
		t.Errorf("expected 700 bps, got %d", cc.CommissionPctBps)
	}
	if cc.KdvPctBps != 2000 {
		t.Errorf("expected 2000 bps, got %d", cc.KdvPctBps)
	}

	t.Logf("integration CRUD passed: productID=%d variantID=%d", p.ID, v1.ID)
}

func TestIntegration_CommissionNotFound(t *testing.T) {
	ctx := context.Background()
	repo := catalog.NewRepository(integPool)
	svc := catalog.NewService(repo, "TRY", "tr-TR")

	_, err := svc.GetCommissionForCategory(ctx, "TR", 99999)
	if !errors.Is(err, catalog.ErrCommissionNotFound) {
		t.Fatalf("expected ErrCommissionNotFound, got %v", err)
	}
}

func TestIntegration_InactiveCurrencyReject(t *testing.T) {
	ctx := context.Background()
	repo := catalog.NewRepository(integPool)
	svc := catalog.NewService(repo, "TRY", "tr-TR")

	// USD is seeded as active=FALSE in setupSchema
	_, err := svc.CreateProduct(ctx, catalog.CreateProductRequest{
		SellerID:        1,
		CategoryID:      30,
		DefaultCurrency: "USD",
	})
	if !errors.Is(err, catalog.ErrInvalidCurrency) {
		t.Fatalf("expected ErrInvalidCurrency for inactive USD, got %v", err)
	}
}

func TestIntegration_GetVariantByIDPopulatesCategoryAndSeller(t *testing.T) {
	ctx := context.Background()
	repo := catalog.NewRepository(integPool)
	svc := catalog.NewService(repo, "TRY", "tr-TR")

	p, err := svc.CreateProduct(ctx, catalog.CreateProductRequest{
		SellerID: 77, CategoryID: 30, Brand: "VarLookupTest",
	})
	if err != nil {
		t.Fatalf("CreateProduct: %v", err)
	}

	v, err := svc.AddVariant(ctx, p.ID, catalog.AddVariantRequest{
		SKU: "VLT-001", PriceMinor: 5000,
	})
	if err != nil {
		t.Fatalf("AddVariant: %v", err)
	}

	got, err := svc.GetVariantByID(ctx, v.ID)
	if err != nil {
		t.Fatalf("GetVariantByID: %v", err)
	}
	if got.CategoryID != 30 {
		t.Errorf("CategoryID: want 30, got %d", got.CategoryID)
	}
	if got.SellerID != 77 {
		t.Errorf("SellerID: want 77, got %d", got.SellerID)
	}
}

// TestIntegration_VariantImageKeys verifies TEXT[] roundtrip.
func TestIntegration_VariantImageKeys(t *testing.T) {
	ctx := context.Background()
	repo := catalog.NewRepository(integPool)
	svc := catalog.NewService(repo, "TRY", "tr-TR")

	p, err := svc.CreateProduct(ctx, catalog.CreateProductRequest{
		SellerID: 1, CategoryID: 30, Brand: "ImgTest",
	})
	if err != nil {
		t.Fatalf("CreateProduct: %v", err)
	}

	keys := []string{"img/a.jpg", "img/b.jpg", "img/c.jpg"}
	v, err := svc.AddVariant(ctx, p.ID, catalog.AddVariantRequest{
		SKU:        "IMG-SKU-1",
		PriceMinor: 1000,
		ImageKeys:  keys,
	})
	if err != nil {
		t.Fatalf("AddVariant: %v", err)
	}

	_, variants, _, err := svc.GetByID(ctx, p.ID)
	if err != nil {
		t.Fatalf("GetByID: %v", err)
	}
	if len(variants) == 0 {
		t.Fatal("no variants returned")
	}
	got := variants[0]
	if got.ID != v.ID {
		t.Errorf("variant ID mismatch")
	}
	if len(got.ImageKeys) != len(keys) {
		t.Errorf("image_keys length: want %d got %d", len(keys), len(got.ImageKeys))
	}
	for i, k := range keys {
		if got.ImageKeys[i] != k {
			t.Errorf("image_keys[%d]: want %q got %q", i, k, got.ImageKeys[i])
		}
	}
}
