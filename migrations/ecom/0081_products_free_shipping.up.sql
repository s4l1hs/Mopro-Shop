-- 0081_products_free_shipping.up.sql
-- Adds the free_shipping flag to catalog_schema.products to back the new
-- catalog/search free_shipping filter (P-028).
--
-- Additive + DEFAULT FALSE: existing rows stay valid and visible. The filter
-- simply matches nothing until products are flagged — population via seller
-- onboarding / admin tooling is a follow-up. The filter is wired now; data
-- lands later (the established "UI/filter ready, data SOON" pattern, cf. the
-- rating_avg / original_price_minor display fields in 0065).

ALTER TABLE catalog_schema.products
  ADD COLUMN IF NOT EXISTS free_shipping BOOLEAN NOT NULL DEFAULT FALSE;
