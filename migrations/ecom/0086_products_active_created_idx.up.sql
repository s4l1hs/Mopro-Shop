-- 0086_products_active_created_idx.up.sql — F-020.
-- The global (no-category) product list added for the server-driven Home rails
-- serves `sort=newest` as `ORDER BY p.created_at DESC, p.id DESC` over
-- `WHERE status='active'` across the whole catalog. Without an index that is a
-- full sort of every active product per request. This partial index makes the
-- bounded (LIMIT 6) rail an index scan. Partial on status='active' keeps it
-- small and matches the query predicate. (recommended → p.id DESC uses the PK;
-- bestseller → array_position over a capped popular-id list.)
CREATE INDEX IF NOT EXISTS products_active_created_idx
    ON catalog_schema.products (created_at DESC, id DESC)
    WHERE status = 'active';
