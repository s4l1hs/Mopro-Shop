-- 0080_recommendation_projections.up.sql — recommendation projections derived
-- from analytics_schema.analytics_events (Tranche 4 loop-closing). Live in
-- analytics_schema (owned by the analytics module; the refresh reads events
-- same-schema). product_id is a plain BIGINT soft reference to
-- catalog_schema.products — NO cross-schema FK (CLAUDE.md §5 + CONTRIBUTING
-- soft-reference pattern). Both tables are derived (never source-of-truth): the
-- daily refresh truncates + rebuilds; no incremental updates.

-- Popularity: per-scope ('global' | 'category:{id}') view-count ranking.
CREATE TABLE IF NOT EXISTS analytics_schema.popular_products (
    scope        TEXT        NOT NULL,            -- 'global' | 'category:{categoryId}'
    product_id   BIGINT      NOT NULL,            -- soft ref → catalog_schema.products
    view_count   INTEGER     NOT NULL,
    refreshed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (scope, product_id)
);
CREATE INDEX IF NOT EXISTS idx_popular_products_scope_rank
    ON analytics_schema.popular_products (scope, view_count DESC);

-- Co-view: "users who viewed product_a also viewed product_b" co-occurrence.
CREATE TABLE IF NOT EXISTS analytics_schema.product_co_views (
    product_a     BIGINT      NOT NULL,           -- soft refs → catalog_schema.products
    product_b     BIGINT      NOT NULL,
    co_view_count INTEGER     NOT NULL,
    refreshed_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (product_a, product_b)
);
CREATE INDEX IF NOT EXISTS idx_co_views_lookup
    ON analytics_schema.product_co_views (product_a, co_view_count DESC);
