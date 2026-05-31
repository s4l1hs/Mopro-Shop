-- 0073_reviews_writeside.down.sql — reverse 0073.
DROP TABLE IF EXISTS catalog_schema.product_review_revisions;
ALTER TABLE catalog_schema.product_reviews DROP COLUMN IF EXISTS submitted_locale;
ALTER TABLE catalog_schema.product_reviews DROP COLUMN IF EXISTS status;
