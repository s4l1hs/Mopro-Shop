-- 0083_variant_price_history.down.sql — reverse P-030 price-history tracking.
DROP TRIGGER IF EXISTS variants_price_history_trg ON catalog_schema.variants;
DROP FUNCTION IF EXISTS catalog_schema.track_variant_price();
DROP TABLE IF EXISTS catalog_schema.variant_price_history;  -- drops vph_product_effective_idx too
