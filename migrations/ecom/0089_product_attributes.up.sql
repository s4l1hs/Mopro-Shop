-- 0089_product_attributes.up.sql — PLP-13 phase 1: normalized attribute model.
-- Trendyol's category-aware attribute/facet stack. Replaces faceting on the
-- opaque products.specs JSONB (a fragile per-category hack) with three normalized
-- catalog_schema tables (§5-safe — single schema). Phase 1 lights up ONE
-- attribute (renk / colour); later attributes + the seller write-path are Phase 2
-- (docs/internal/plp-13-attribute-model.md).
--
-- The per-product backfill (from variants.color) + the category_facets seeding
-- are NOT here: in dev, migrations run on an empty DB and the catalog seed
-- populates variants afterwards, so a migration-time INSERT…SELECT FROM variants
-- captures nothing. They live in scripts/seed/data/attr-extras.sql (dev) / a
-- one-off data step at cutover (prod). This migration carries only the tables,
-- indexes, grants, and the fixed `renk` reference key.

-- attribute_keys: the catalogue of facetable attributes. data_type drives later
-- numeric/range facets; unit_slug is for number types (e.g. GB) — Phase 3.
CREATE TABLE IF NOT EXISTS catalog_schema.attribute_keys (
    id        BIGSERIAL PRIMARY KEY,
    slug      TEXT NOT NULL UNIQUE,                 -- 'renk','depolama','ekran_boyutu'…
    name_tr   TEXT NOT NULL,
    name_en   TEXT NOT NULL,
    data_type TEXT NOT NULL DEFAULT 'text' CHECK (data_type IN ('text','number','bool')),
    unit_slug TEXT
);

-- category_facets: which attributes are facetable per category (Trendyol's
-- category-aware stack). category_id is a soft ref to ref_schema.categories
-- (CLAUDE.md §5 — no cross-schema FK). Facets inherit down the PLP-12 subtree at
-- query time (the aggregation unions over the category's descendants).
CREATE TABLE IF NOT EXISTS catalog_schema.category_facets (
    category_id      BIGINT  NOT NULL,
    attribute_key_id BIGINT  NOT NULL REFERENCES catalog_schema.attribute_keys(id) ON DELETE CASCADE,
    display_order    INT     NOT NULL DEFAULT 0,
    searchable       BOOLEAN NOT NULL DEFAULT TRUE,  -- render the in-facet search box when long
    PRIMARY KEY (category_id, attribute_key_id)
);

-- product_attributes: normalized per-product values — one row per
-- (product, key, value). A product may carry several values for one key (e.g. a
-- shirt sold in three colours → three renk rows). product_id is a soft ref.
CREATE TABLE IF NOT EXISTS catalog_schema.product_attributes (
    id               BIGSERIAL PRIMARY KEY,
    product_id       BIGINT  NOT NULL,
    attribute_key_id BIGINT  NOT NULL REFERENCES catalog_schema.attribute_keys(id) ON DELETE CASCADE,
    value_text       TEXT,                           -- set for text attrs (renk); the facet bucket key
    value_num        NUMERIC,                         -- set for number attrs (Phase 2/3)
    UNIQUE (product_id, attribute_key_id, value_text)
);

-- Facet aggregation: GROUP BY (attribute_key_id, value_text) over a product set.
CREATE INDEX IF NOT EXISTS product_attributes_key_value_idx
    ON catalog_schema.product_attributes (attribute_key_id, value_text);
-- Per-product lookup (the PDP specs tab).
CREATE INDEX IF NOT EXISTS product_attributes_product_idx
    ON catalog_schema.product_attributes (product_id);

-- Fixed reference attribute: renk (colour). Deterministic — safe in the migration.
INSERT INTO catalog_schema.attribute_keys (slug, name_tr, name_en, data_type)
VALUES ('renk', 'Renk', 'Colour', 'text')
ON CONFLICT (slug) DO NOTHING;

GRANT SELECT ON catalog_schema.attribute_keys   TO catalog_user;
GRANT SELECT ON catalog_schema.category_facets  TO catalog_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON catalog_schema.product_attributes TO catalog_user;
GRANT USAGE, SELECT ON SEQUENCE catalog_schema.product_attributes_id_seq TO catalog_user;
GRANT USAGE, SELECT ON SEQUENCE catalog_schema.attribute_keys_id_seq     TO catalog_user;
