-- 0064_home_features.up.sql
-- Adds tables for product reviews, user favorites, and home screen content.

-- ── User favorites ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS catalog_schema.user_favorites (
  user_id    BIGINT      NOT NULL,
  product_id BIGINT      NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, product_id)
);
CREATE INDEX IF NOT EXISTS user_fav_user_idx ON catalog_schema.user_favorites(user_id);

-- ── Product reviews ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS catalog_schema.product_reviews (
  id            BIGSERIAL   PRIMARY KEY,
  product_id    BIGINT      NOT NULL,
  user_id       BIGINT      NOT NULL,
  rating        SMALLINT    NOT NULL CHECK (rating BETWEEN 1 AND 5),
  title         TEXT,
  body          TEXT,
  helpful_count INT         NOT NULL DEFAULT 0,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (product_id, user_id)
);
CREATE INDEX IF NOT EXISTS reviews_product_idx ON catalog_schema.product_reviews(product_id, created_at DESC);

-- ── Review helpful votes ──────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS catalog_schema.review_helpful_votes (
  review_id  BIGINT NOT NULL REFERENCES catalog_schema.product_reviews(id) ON DELETE CASCADE,
  user_id    BIGINT NOT NULL,
  PRIMARY KEY (review_id, user_id)
);

-- ── Home banners (editable via admin; seeded below) ───────────────────────────
CREATE TABLE IF NOT EXISTS catalog_schema.home_banners (
  id         BIGSERIAL   PRIMARY KEY,
  image_url  TEXT        NOT NULL,
  deep_link  TEXT        NOT NULL DEFAULT '/',
  sort_order INT         NOT NULL DEFAULT 0,
  active     BOOLEAN     NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Seed 3 sample banners (easily replaced in production).
INSERT INTO catalog_schema.home_banners (image_url, deep_link, sort_order) VALUES
  ('https://placehold.co/800x300/CA4E00/FFFFFF/png?text=Mopro+Kampanya', '/categories', 1),
  ('https://placehold.co/800x300/333333/FFFFFF/png?text=Yeni+Sezon', '/categories', 2),
  ('https://placehold.co/800x300/E36925/FFFFFF/png?text=Fırsatlar', '/categories', 3)
ON CONFLICT DO NOTHING;

-- ── Home rails config (server-driven composition) ─────────────────────────────
CREATE TABLE IF NOT EXISTS catalog_schema.home_rails (
  id         BIGSERIAL   PRIMARY KEY,
  rail_key   TEXT        NOT NULL UNIQUE,  -- 'recommended' | 'bestseller' | 'newest' | etc.
  title_tr   TEXT        NOT NULL,
  title_en   TEXT        NOT NULL,
  sort_order INT         NOT NULL DEFAULT 0,
  active     BOOLEAN     NOT NULL DEFAULT TRUE
);

INSERT INTO catalog_schema.home_rails (rail_key, title_tr, title_en, sort_order) VALUES
  ('recommended', 'Sizin için seçtiklerimiz', 'Recommended for you', 1),
  ('bestseller',  'Çok satanlar',              'Best Sellers',        2),
  ('newest',      'Yeni gelenler',              'New Arrivals',        3)
ON CONFLICT (rail_key) DO NOTHING;

-- ── Grants ────────────────────────────────────────────────────────────────────
GRANT SELECT, INSERT, DELETE ON catalog_schema.user_favorites TO catalog_user;
GRANT SELECT, INSERT, UPDATE ON catalog_schema.product_reviews TO catalog_user;
GRANT SELECT, INSERT, DELETE ON catalog_schema.review_helpful_votes TO catalog_user;
GRANT SELECT ON catalog_schema.home_banners TO catalog_user;
GRANT SELECT ON catalog_schema.home_rails TO catalog_user;
