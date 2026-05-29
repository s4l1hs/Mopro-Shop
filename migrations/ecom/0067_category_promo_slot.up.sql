-- 0067_category_promo_slot.up.sql
--
-- Adds an optional `promo_slot` JSONB column on ref_schema.categories.
-- Application layer only surfaces this on top-level categories
-- (parent_id IS NULL); the column physically exists on every row but
-- subcategories and leaves leave it NULL.
--
-- Expected JSON shape: { "imageUrl": string, "title": string, "deepLink": string }
-- Validation is enforced in the Go repository layer (not via CHECK
-- constraint) so a malformed row can be returned as a logged warning
-- + null instead of 500ing the categories endpoint.
--
-- Seeds two example top-level categories with realistic placeholder
-- values so the desktop mega menu's 3+1 layout can be exercised in
-- dev / staging without manual admin work.

ALTER TABLE ref_schema.categories
  ADD COLUMN IF NOT EXISTS promo_slot JSONB;

-- Seed two top-level categories with promo data. Categories 1 and 2 are
-- "Kadın" and "Erkek" per the existing seed in 50-ref-seed.sql; we use
-- their IDs directly. Idempotent via WHERE clause.
UPDATE ref_schema.categories
SET promo_slot = jsonb_build_object(
    'imageUrl', 'https://cdn.example.com/promos/kadin-spring.png',
    'title',    'Yeni Sezon Kadın',
    'deepLink', '/categories/1?campaign=spring'
)
WHERE id = 1 AND parent_id IS NULL AND promo_slot IS NULL;

UPDATE ref_schema.categories
SET promo_slot = jsonb_build_object(
    'imageUrl', 'https://cdn.example.com/promos/erkek-sport.png',
    'title',    'Spor Koleksiyonu',
    'deepLink', '/categories/2?campaign=sport'
)
WHERE id = 2 AND parent_id IS NULL AND promo_slot IS NULL;
