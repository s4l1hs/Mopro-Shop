-- 0065_product_display_fields.up.sql
-- Adds display fields to support Trendyol-style ProductCard:
--   * original_price_minor: optional MSRP (strikethrough when > current price)
--   * rating_avg, rating_count: aggregated review stats for the rating chip
--
-- Defaults keep existing rows visible without populated review data; the
-- product card simply hides the badge/chip when these are null/zero.

ALTER TABLE catalog_schema.products
  ADD COLUMN IF NOT EXISTS rating_avg   NUMERIC(2,1),  -- 0.0 .. 5.0
  ADD COLUMN IF NOT EXISTS rating_count INT NOT NULL DEFAULT 0;

ALTER TABLE catalog_schema.variants
  ADD COLUMN IF NOT EXISTS original_price_minor BIGINT;  -- null = no discount

-- Index for "top-rated" sort and rating-based discovery.
CREATE INDEX IF NOT EXISTS products_rating_idx
  ON catalog_schema.products(rating_avg DESC NULLS LAST)
  WHERE rating_count > 0;
