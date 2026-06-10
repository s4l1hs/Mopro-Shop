-- scripts/seed/data/attr-extras.sql — dev-only PLP-13 phase-1 attribute backfill.
--
-- Migration 0089 creates the attribute tables + the fixed `renk` key but does NOT
-- backfill (in dev, migrations run before the catalog seed populates variants).
-- This seed, applied AFTER `make seed`, normalizes the existing colour data into
-- product_attributes and lights up the renk facet wherever colour exists:
--   • product_attributes(renk) ← DISTINCT variants.color (one row per product×colour)
--   • category_facets(renk)    ← every category that has a coloured product
--
-- Real-shaped (derives from existing variants — never fabricates). Idempotent
-- (ON CONFLICT). §5-safe (catalog_schema only). LOCAL ONLY — postgres-ecom.
-- Mirrors pdp-walk-extras.sql / plp-density-extras.sql. In prod the same backfill
-- runs as a one-off data step at the deferred cutover.
--
-- Apply (after `make seed`):
--   docker exec -i postgres-ecom psql -v ON_ERROR_STOP=1 \
--     -U ecom_admin -d mopro_ecom < scripts/seed/data/attr-extras.sql

BEGIN;

-- 1) Normalize colour → product_attributes(renk). DISTINCT collapses a product's
--    repeated colour (across SKUs) into one row per (product, colour).
INSERT INTO catalog_schema.product_attributes (product_id, attribute_key_id, value_text)
SELECT DISTINCT v.product_id, ak.id, v.color
  FROM catalog_schema.variants v
  CROSS JOIN catalog_schema.attribute_keys ak
 WHERE ak.slug = 'renk'
   AND v.color <> ''
ON CONFLICT (product_id, attribute_key_id, value_text) DO NOTHING;

-- 2) Enable the renk facet for every category that has a coloured product (the
--    facet endpoint returns an attribute only when category_facets carries it).
INSERT INTO catalog_schema.category_facets (category_id, attribute_key_id, display_order, searchable)
SELECT DISTINCT p.category_id, ak.id, 1, TRUE
  FROM catalog_schema.products p
  JOIN catalog_schema.variants v ON v.product_id = p.id AND v.color <> ''
  CROSS JOIN catalog_schema.attribute_keys ak
 WHERE ak.slug = 'renk'
ON CONFLICT (category_id, attribute_key_id) DO NOTHING;

COMMIT;
