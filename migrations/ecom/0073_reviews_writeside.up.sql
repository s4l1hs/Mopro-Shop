-- 0073_reviews_writeside.up.sql — reviews write-side (additive).
--
-- product_reviews (0064) already has UNIQUE(product_id, user_id) + title +
-- updated_at, so this migration only adds status + submitted_locale and the
-- revisions table. The storage-layer idempotency (one review per product per
-- user) is the existing unique constraint — no backfill.

ALTER TABLE catalog_schema.product_reviews
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'published';
ALTER TABLE catalog_schema.product_reviews
  ADD COLUMN IF NOT EXISTS submitted_locale TEXT NOT NULL DEFAULT 'tr';

-- Edit revisions (forward-compatible; surfacing prior versions is Backlog).
CREATE TABLE IF NOT EXISTS catalog_schema.product_review_revisions (
    id         BIGSERIAL   PRIMARY KEY,
    review_id  BIGINT      NOT NULL REFERENCES catalog_schema.product_reviews(id) ON DELETE CASCADE,
    rating     SMALLINT    NOT NULL CHECK (rating BETWEEN 1 AND 5),
    title      TEXT,
    body       TEXT        NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_review_revisions_review
    ON catalog_schema.product_review_revisions (review_id, created_at DESC);
