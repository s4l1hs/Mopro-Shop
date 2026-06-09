-- scripts/seed/data/merch-extras.sql — dev-only merchandising-signals seed (HOME-POP-01).
--
-- Sets the two G-3 / migration-0087 merch columns on a representative subset so the
-- "Çok Satan" stamp + "Sepette %X İndirim" pill actually render in rails / PLP / search
-- locally. Dark by default per #133 (is_bestseller=FALSE, basket_discount_pct=NULL for
-- every row); this flips a handful. Real-shaped — only flags existing seeded SKUs, never
-- fabricates products. Idempotent (plain UPDATEs keyed on the stable variants.sku).
-- Mirrors the coin-extras.sql dev-seed pattern. LOCAL ONLY — postgres-ecom.
--
-- Apply (after `make seed` has populated the catalog against local):
--   docker exec -i postgres-ecom psql -v ON_ERROR_STOP=1 \
--     -U ecom_admin -d mopro_ecom < scripts/seed/data/merch-extras.sql

-- "Çok Satan" bestseller stamp on a cross-category subset (book / fashion /
-- electronics / sport / cosmetics).
UPDATE catalog_schema.products p
   SET is_bestseller = TRUE
  FROM catalog_schema.variants v
 WHERE v.product_id = p.id
   AND v.sku IN ('MP-L001', 'MP-M001', 'MP-E003', 'MP-S002', 'MP-K004', 'MP-M002');

-- "Sepette %X İndirim" basket-discount pill on discounted SKUs — overlaps the
-- bestsellers above, so those cards show strikethrough + stamp + pill together.
UPDATE catalog_schema.products p
   SET basket_discount_pct = m.pct
  FROM (VALUES
          ('MP-M002', 10::smallint),
          ('MP-S002', 15),
          ('MP-E003', 12),
          ('MP-K004', 8),
          ('MP-M004', 10)
       ) AS m(sku, pct)
  JOIN catalog_schema.variants v ON v.sku = m.sku
 WHERE p.id = v.product_id;
