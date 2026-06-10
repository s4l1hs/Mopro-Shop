-- 0090_seller_is_official.up.sql — PLP-17 / PD-04: official-seller flag.
-- Trendyol's "Resmi satıcı rozeti" — a verified/official badge on the PLP card +
-- the PDP seller card. The flag is a seller property (seller_schema); the catalog
-- card/product resolves it §5-safely (in-process seller.Service call + handler
-- app-merge — NEVER a cross-schema JOIN).
--
-- Which sellers are official is business/content data: seeded deterministically
-- here against the migration-seeded sellers (0078) so the walk shows a mix of
-- official + non-official cards. Idempotent.

ALTER TABLE seller_schema.sellers
  ADD COLUMN IF NOT EXISTS is_official BOOLEAN NOT NULL DEFAULT FALSE;

-- Mark a couple of the seeded sellers official (acme-store, teknoloji-dunyasi).
-- moda-evi (2) stays non-official so the badge difference is visible on the walk.
UPDATE seller_schema.sellers SET is_official = TRUE WHERE id IN (1, 3);
