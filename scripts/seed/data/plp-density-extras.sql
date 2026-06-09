-- scripts/seed/data/plp-density-extras.sql — dev-only PLP filter-walk density (PLP-SEED).
--
-- The PLP scopes products by EXACT category_id (no subtree rollup —
-- internal/catalog/repository.go:373), and the base seed puts only 2–3 products
-- per leaf category, so no single category can exercise the filters. This
-- concentrates ~28 EXISTING seeded SKUs into one leaf — `elektr-kea`
-- ("Küçük Ev Aletleri") — so every PLP *filter* facet has selectable options:
--   • brand   — ~23 distinct brands (exercises the searchable list + show-more >8)
--   • price   — full ₺89 → ₺89,999 spread
--   • rating  — buckets 2+/3+/4+ (step 2 spreads a few down; base seed is all 3.9–4.9)
--   • free-shipping — step 3 (a fresh `make seed` leaves free_shipping FALSE)
-- (The card's bestseller / "Sepette %X" signals are NOT PLP filters; they're set
--  separately by merch-extras.sql and need migration 0087's merch columns.)
--
-- DELIBERATELY brand-incoherent (book/cosmetic/appliance mix under one leaf): a
-- dev test FIXTURE for filter mechanics, not a realistic catalog. Real-shaped —
-- only re-points / adjusts EXISTING SKUs, never fabricates. Idempotent (UPDATEs
-- keyed on the stable variants.sku; re-runnable). LOCAL ONLY — postgres-ecom.
-- Mirrors merch-extras.sql. `make seed` resets it.
--
-- Apply (after `make seed` populates the catalog + after merch-extras.sql):
--   docker exec -i postgres-ecom psql -v ON_ERROR_STOP=1 \
--     -U ecom_admin -d mopro_ecom < scripts/seed/data/plp-density-extras.sql
-- Then walk the `elektr-kea` PLP (/categories/<its id>) — ~28 dense products.

-- 1) Re-point a cross-brand / cross-price set into elektr-kea (joins existing
--    elektr-kea SKUs MP-E001/E002/E010 → ~28 total).
UPDATE catalog_schema.products p
   SET category_id = (SELECT id FROM ref_schema.categories WHERE slug = 'elektr-kea')
  FROM catalog_schema.variants v
 WHERE v.product_id = p.id
   AND v.sku IN (
     'MP-L001','MP-L002','MP-A001','MP-A002','MP-K001','MP-K002','MP-K004','MP-K005',
     'MP-M001','MP-M002','MP-M004','MP-M006','MP-S001','MP-S002','MP-S003','MP-S006',
     'MP-S008','MP-S009','MP-S010','MP-H001','MP-H004','MP-E003','MP-E004','MP-E005','MP-E008'
   );

-- 2) Spread ratings so the 2+/3+/4+ buckets each select a distinct subset.
UPDATE catalog_schema.products p
   SET rating_stars = m.r
  FROM (VALUES
          ('MP-A001', 2.4::real),
          ('MP-L002', 3.1),
          ('MP-S003', 3.6),
          ('MP-H001', 2.8),
          ('MP-K001', 3.4)
       ) AS m(sku, r)
  JOIN catalog_schema.variants v ON v.sku = m.sku
 WHERE p.id = v.product_id;

-- 3) Give the free-shipping filter options (base seed sets none).
UPDATE catalog_schema.products p
   SET free_shipping = TRUE
  FROM catalog_schema.variants v
 WHERE v.product_id = p.id
   AND v.sku IN (
     'MP-L001','MP-S001','MP-E003','MP-E008','MP-H001','MP-K002','MP-S009','MP-M002'
   );
