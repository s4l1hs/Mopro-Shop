-- 0067_category_promo_slot.down.sql
--
-- Reverses 0067. Drops the column unconditionally (the seeded promo rows
-- are deleted as a side effect; they are placeholder data not relied on
-- by anything outside the desktop mega menu's 3+1 layout, which falls
-- back to the 4-column layout when no promo is present).

ALTER TABLE ref_schema.categories
  DROP COLUMN IF EXISTS promo_slot;
