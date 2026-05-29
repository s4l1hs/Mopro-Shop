-- 0068_home_flash_deals.up.sql
-- Flash-deals for the home screen: a countdown-headed product rail. Multiple
-- collections are keyed by id; the endpoint serves the single active collection
-- within its [starts_at, ends_at] window. Generic placeholder copy — nothing
-- brand-specific is copied.

CREATE TABLE IF NOT EXISTS catalog_schema.home_flash_deals_collections (
  id         BIGSERIAL   PRIMARY KEY,
  title      TEXT        NOT NULL,
  starts_at  TIMESTAMPTZ NOT NULL,
  ends_at    TIMESTAMPTZ NOT NULL,
  is_active  BOOLEAN     NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Supports the "active collection within window" lookup.
CREATE INDEX IF NOT EXISTS home_flash_deals_active_idx
  ON catalog_schema.home_flash_deals_collections (starts_at, ends_at)
  WHERE is_active = TRUE;

CREATE TABLE IF NOT EXISTS catalog_schema.home_flash_deals_items (
  collection_id     BIGINT  NOT NULL
    REFERENCES catalog_schema.home_flash_deals_collections(id) ON DELETE CASCADE,
  product_id        BIGINT  NOT NULL REFERENCES catalog_schema.products(id),
  flash_price_minor BIGINT  NOT NULL,
  sort_order        INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (collection_id, product_id)
);

CREATE INDEX IF NOT EXISTS home_flash_deals_items_sort_idx
  ON catalog_schema.home_flash_deals_items (collection_id, sort_order);

-- Seed one active collection. Items are attached from the first 8 seeded
-- products (a no-op until products exist — product rows come from the seed
-- tool). Replace via admin in prod.
INSERT INTO catalog_schema.home_flash_deals_collections (title, starts_at, ends_at, is_active)
VALUES ('Bugünün Fırsatları', NOW() - INTERVAL '1 hour', NOW() + INTERVAL '6 hours', TRUE)
ON CONFLICT DO NOTHING;

INSERT INTO catalog_schema.home_flash_deals_items (collection_id, product_id, flash_price_minor, sort_order)
SELECT c.id, p.id, 9999, p.rn
FROM (
  SELECT id FROM catalog_schema.home_flash_deals_collections
  WHERE is_active = TRUE ORDER BY id LIMIT 1
) c
CROSS JOIN (
  SELECT id, (row_number() OVER (ORDER BY id))::int AS rn
  FROM catalog_schema.products ORDER BY id LIMIT 8
) p
ON CONFLICT DO NOTHING;

GRANT SELECT ON catalog_schema.home_flash_deals_collections TO catalog_user;
GRANT SELECT ON catalog_schema.home_flash_deals_items TO catalog_user;
