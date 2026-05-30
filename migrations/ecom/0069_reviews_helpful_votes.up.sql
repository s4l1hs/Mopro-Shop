-- 0069_reviews_helpful_votes.up.sql
-- Reviews helpful-vote feature.
--
-- NOTE: the vote table (catalog_schema.review_helpful_votes) and the
-- product_reviews.helpful_count cache column ALREADY exist (created in
-- 0064_home_features). This migration is therefore additive only:
--   (a) adds created_at to review_helpful_votes so vote recency is auditable;
--   (b) backfills helpful_count from the authoritative vote rows (no-op when
--       counts already match, but handles any pre-existing drift);
--   (c) documents helpful_count as a denormalized cache whose source of truth is
--       review_helpful_votes — mirroring 0079_payments_made_cache_comment.
--
-- review_helpful_votes already carries PRIMARY KEY (review_id, user_id), which is
-- the storage-layer idempotency that prevents double-voting at the database (same
-- discipline as the PR #10 cashback fix).

ALTER TABLE catalog_schema.review_helpful_votes
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT now();

-- Backfill the denormalized cache from the authoritative vote rows.
UPDATE catalog_schema.product_reviews p
   SET helpful_count = (
     SELECT COUNT(*) FROM catalog_schema.review_helpful_votes v
      WHERE v.review_id = p.id
   );

COMMENT ON COLUMN catalog_schema.product_reviews.helpful_count IS
  'Denormalized cache of COUNT(*) FROM catalog_schema.review_helpful_votes for this review. NOT authoritative; review_helpful_votes is the source of truth. Refreshed inside the same SERIALIZABLE tx as every vote insert/delete (see catalog.RefreshHelpfulCountCache).';
