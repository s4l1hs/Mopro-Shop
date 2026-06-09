-- 0088_categories_parent_id_idx.up.sql
-- Index ref_schema.categories.parent_id to back the PLP-12 subtree-rollup
-- recursive CTE (ListProductsByCategory walks parent_id → children). The
-- categories tree is tiny today, but the index keeps the recursion an index
-- scan as the taxonomy grows. Additive + IF NOT EXISTS — safe to re-run.
CREATE INDEX IF NOT EXISTS categories_parent_id_idx
    ON ref_schema.categories (parent_id);
