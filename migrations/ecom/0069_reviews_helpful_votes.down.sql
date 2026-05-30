-- 0069_reviews_helpful_votes.down.sql
-- Reverse ONLY what 0069 added. The review_helpful_votes table and the
-- product_reviews.helpful_count column belong to 0064_home_features and must
-- survive a down-migration of 0069 (dropping them here would corrupt the 0064
-- baseline). So we only drop the created_at column and clear the cache comment.

COMMENT ON COLUMN catalog_schema.product_reviews.helpful_count IS NULL;

ALTER TABLE catalog_schema.review_helpful_votes
  DROP COLUMN IF EXISTS created_at;
