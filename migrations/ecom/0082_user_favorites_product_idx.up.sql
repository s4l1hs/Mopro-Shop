-- 0082_user_favorites_product_idx.up.sql
-- Index for the ProductSummary favorites_count subquery (P-004 enrichment).
-- 0064 created user_fav_user_idx(user_id) for per-user favorite lookups; the
-- count-by-product aggregate (one correlated subquery per listed product) needs
-- the reverse access path. Additive, non-destructive.

CREATE INDEX IF NOT EXISTS user_fav_product_idx
  ON catalog_schema.user_favorites(product_id);
