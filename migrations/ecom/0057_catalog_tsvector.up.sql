-- 0057_catalog_tsvector.up.sql — OQ-3 resolution: 'simple' tsvector for stemless FTS.
-- Turkish morphology deferred to Phase 5 (Meilisearch). 'simple' handles exact-word
-- and prefix matches reliably without requiring pg_catalog.turkish.

ALTER TABLE catalog_schema.product_translations
  ADD COLUMN IF NOT EXISTS search_vector TSVECTOR
    GENERATED ALWAYS AS (
      to_tsvector('simple', coalesce(title, '') || ' ' || coalesce(description, ''))
    ) STORED;

CREATE INDEX IF NOT EXISTS product_translations_search_vector_idx
  ON catalog_schema.product_translations
  USING GIN(search_vector);
