-- 0099_seller_size_charts.up.sql
-- Seller-entered size charts (docs/internal/seller-size-charts.md). Sellers author
-- their own per-garment chart; the match prefers it over the EN 13402-3 standard
-- baseline (seller → standard → none). All in seller_schema (owned by
-- internal/seller) so resolution is a single-schema query — NO cross-schema JOIN
-- (§5). product_id / seller_id are plain BIGINT soft references (no cross-schema
-- FK), matching the sellers.id ↔ products.seller_id soft-ref pattern (0078).
--
-- Seller charts are PRODUCT data, NOT PII → plaintext integer millimetres (the
-- money-type discipline applied to lengths), unlike fit *profiles* which stay
-- AES-GCM encrypted (§6 unchanged). seller_schema has ALTER DEFAULT PRIVILEGES →
-- seller_user CRUD (30-grants.sql) → no grant block needed (the 0078/0096
-- precedent). IDEMPOTENT. Init lockstep: 80-seller-schema.sql.

CREATE TABLE IF NOT EXISTS seller_schema.seller_size_charts (
    id           BIGSERIAL   PRIMARY KEY,
    seller_id    BIGINT      NOT NULL,                       -- soft ref → sellers.id
    name         TEXT        NOT NULL,
    garment_type TEXT        NOT NULL
                 CHECK (garment_type IN ('top','bottom','dress','skirt','outerwear')),
    gender       TEXT        NOT NULL CHECK (gender IN ('female','male')),
    size_system  TEXT        NOT NULL DEFAULT 'alpha'
                 CHECK (size_system IN ('alpha','eu')),
    source       TEXT        NOT NULL DEFAULT 'seller',
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS seller_size_charts_seller_idx
    ON seller_schema.seller_size_charts(seller_id);

CREATE TABLE IF NOT EXISTS seller_schema.seller_size_chart_rows (
    chart_id     BIGINT NOT NULL
                 REFERENCES seller_schema.seller_size_charts(id) ON DELETE CASCADE,
    size_label   TEXT   NOT NULL,
    sort_rank    INT    NOT NULL,
    measurement  TEXT   NOT NULL CHECK (measurement IN ('chest','waist','hip')),
    min_mm       INT    NOT NULL CHECK (min_mm > 0),
    max_mm       INT    NOT NULL CHECK (max_mm > min_mm),
    PRIMARY KEY (chart_id, size_label, measurement)
);

-- One chart per product (v1). product_id is a soft ref → catalog product.
CREATE TABLE IF NOT EXISTS seller_schema.product_size_charts (
    product_id BIGINT      PRIMARY KEY,                      -- soft ref → products.id
    chart_id   BIGINT      NOT NULL
               REFERENCES seller_schema.seller_size_charts(id) ON DELETE CASCADE,
    seller_id  BIGINT      NOT NULL,                         -- soft ref → sellers.id
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS product_size_charts_chart_idx
    ON seller_schema.product_size_charts(chart_id);
