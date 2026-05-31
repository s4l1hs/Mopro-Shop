-- 0078_sellers.up.sql — Tranche 5a: seller profiles + seller-user role binding.
-- Lives in seller_schema (owned by seller_user, created in bootstrap). Storefronts
-- read sellers; role gating reads seller_users. `products.seller_id`
-- (catalog_schema) is a plain BIGINT soft reference to sellers.id — NO
-- cross-schema FK (CONTRIBUTING soft-reference pattern); `seller_users.user_id`
-- is likewise a soft reference to identity_schema.users.

CREATE SCHEMA IF NOT EXISTS seller_schema;

CREATE TABLE IF NOT EXISTS seller_schema.sellers (
    id               BIGSERIAL   PRIMARY KEY,
    slug             TEXT        NOT NULL UNIQUE,
    display_name     TEXT        NOT NULL,
    bio_translations JSONB       NOT NULL DEFAULT '{}'::jsonb,
    logo_image_url   TEXT,
    banner_image_url TEXT,
    contact_email    TEXT,
    status           TEXT        NOT NULL DEFAULT 'active',  -- 'active' | 'suspended'
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_sellers_slug_active
    ON seller_schema.sellers (slug) WHERE status = 'active';

-- A user is a seller iff a row binds them here. `is_seller` on Q&A answers
-- (catalog_schema, Tranche 3) is derived from this table at answer time.
CREATE TABLE IF NOT EXISTS seller_schema.seller_users (
    seller_id  BIGINT      NOT NULL REFERENCES seller_schema.sellers(id) ON DELETE CASCADE,
    user_id    BIGINT      NOT NULL,                  -- soft reference (identity_schema.users)
    role       TEXT        NOT NULL DEFAULT 'owner',  -- 'owner' | 'staff' (future)
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (seller_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_seller_users_user ON seller_schema.seller_users (user_id);

-- Seed example sellers (idempotent) so storefronts have content on fresh DBs.
INSERT INTO seller_schema.sellers (id, slug, display_name, bio_translations, contact_email)
VALUES
  (1, 'acme-store', 'Acme Store',
     '{"tr":"Acme Store — kaliteli ürünler, hızlı kargo.","en":"Acme Store — quality goods, fast shipping."}'::jsonb,
     'destek@acme.example'),
  (2, 'moda-evi', 'Moda Evi',
     '{"tr":"Moda Evi — sezonun en yeni parçaları.","en":"Moda Evi — the season''s newest pieces."}'::jsonb,
     'iletisim@modaevi.example'),
  (3, 'teknoloji-dunyasi', 'Teknoloji Dünyası',
     '{"tr":"Teknoloji Dünyası — en yeni elektronik.","en":"Teknoloji Dünyası — the latest electronics."}'::jsonb,
     'destek@teknoloji.example')
ON CONFLICT (id) DO NOTHING;
SELECT setval(pg_get_serial_sequence('seller_schema.sellers','id'), GREATEST((SELECT max(id) FROM seller_schema.sellers), 1));

-- Bind user 1 as owner of seller 1 (test fixture; real binding is administrative).
INSERT INTO seller_schema.seller_users (seller_id, user_id, role)
VALUES (1, 1, 'owner') ON CONFLICT (seller_id, user_id) DO NOTHING;
