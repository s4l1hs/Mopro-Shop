-- 0010_catalog_up.sql — catalog_schema tables (Prompt 1.1 / Phase 1)
-- Depends on: catalog_schema already created by postgres-ecom/init/20-schemas.sql
--             ref_schema already created by postgres-ecom/init/40-ref-schema.sql

CREATE TABLE IF NOT EXISTS catalog_schema.products (
    id               BIGSERIAL    PRIMARY KEY,
    seller_id        BIGINT       NOT NULL,
    category_id      BIGINT       NOT NULL,
    brand            TEXT         NOT NULL DEFAULT '',
    default_currency TEXT         NOT NULL DEFAULT 'TRY',
    default_locale   TEXT         NOT NULL DEFAULT 'tr-TR',
    status           TEXT         NOT NULL DEFAULT 'draft'
                       CHECK (status IN ('draft','active','inactive','deleted')),
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS products_seller_idx
    ON catalog_schema.products(seller_id, status);
CREATE INDEX IF NOT EXISTS products_category_idx
    ON catalog_schema.products(category_id, status);

CREATE TABLE IF NOT EXISTS catalog_schema.product_translations (
    product_id  BIGINT NOT NULL REFERENCES catalog_schema.products(id),
    locale      TEXT   NOT NULL,
    title       TEXT   NOT NULL,
    description TEXT   NOT NULL DEFAULT '',
    PRIMARY KEY (product_id, locale)
);

CREATE TABLE IF NOT EXISTS catalog_schema.variants (
    id             BIGSERIAL  PRIMARY KEY,
    product_id     BIGINT     NOT NULL REFERENCES catalog_schema.products(id),
    sku            TEXT       NOT NULL,
    color          TEXT       NOT NULL DEFAULT '',
    size           TEXT       NOT NULL DEFAULT '',
    price_minor    BIGINT     NOT NULL CHECK (price_minor >= 0),
    price_currency TEXT       NOT NULL DEFAULT 'TRY',
    stock          INTEGER    NOT NULL DEFAULT 0,
    image_keys     TEXT[]     NOT NULL DEFAULT '{}'::text[]
);

CREATE UNIQUE INDEX IF NOT EXISTS variants_product_sku_uq
    ON catalog_schema.variants(product_id, sku);
CREATE INDEX IF NOT EXISTS variants_product_idx
    ON catalog_schema.variants(product_id);
