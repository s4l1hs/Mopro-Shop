-- 0087_products_merch_signals.up.sql
-- Adds the two merchandising signals that back the G-3 product-card props:
--   * is_bestseller       → the "Çok Satan" image stamp
--   * basket_discount_pct → the "Sepette %X İndirim" pill
--
-- Additive, safe defaults: is_bestseller defaults FALSE and basket_discount_pct
-- is NULL, so every existing row stays valid and the card renders exactly as
-- today until a value is set. The card UI + DTO + filter are wired now; data
-- lands later via seller/admin tooling — the established "UI ready, data SOON"
-- pattern (cf. free_shipping in 0081, rating_avg/original_price_minor in 0065).
-- is_bestseller may later be driven by the popularity engine (P-029/P-031)
-- instead of a manual flag; the column keeps that an internal detail.

ALTER TABLE catalog_schema.products
  ADD COLUMN IF NOT EXISTS is_bestseller BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS basket_discount_pct SMALLINT;
