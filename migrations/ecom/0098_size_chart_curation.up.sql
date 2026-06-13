-- 0098_size_chart_curation.up.sql
-- Size-Fit chart curation (docs/internal/size-fit.md §curation): replace the
-- phase-1 REPRESENTATIVE seed (0096) with the EN 13402-3 STANDARD-REFERENCE
-- dataset, and widen the chart model so it can hold the two axes EN needs:
--   • gender       — EN bust (women) ≠ chest (men); women's bottoms add hip.
--   • size_system  — alpha (S…XXL, what the match returns) AND EU numeric
--                    (32…58) as a parallel reference set.
--   • source       — provenance per row (EN 13402-3 standard reference).
--
-- HONESTY UNCHANGED: this is a STANDARD baseline, not per-brand truth — the API
-- still flags every response chart_approximate=true; the basic-mode warning is
-- untouched. Seller-entered charts (the next item) override this baseline later.
--
-- Measurements stay INTEGER MILLIMETRES (no floats). The match consumes only the
-- alpha rows (repository filters size_system='alpha'); EU rows are reference data
-- proving the numeric axis is representable. Charts key on GARMENT TYPE + gender,
-- NOT category (§5 — ref_schema is the allowed shared read). IDEMPOTENT.
-- Init lockstep: deploy/postgres-ecom/init/40-ref-schema.sql + 50-ref-seed.sql.

-- ── 1. Widen the model (additive columns) ──────────────────────────────────
ALTER TABLE ref_schema.size_charts
    ADD COLUMN IF NOT EXISTS gender      TEXT NOT NULL DEFAULT 'female'
        CHECK (gender IN ('female','male')),
    ADD COLUMN IF NOT EXISTS size_system TEXT NOT NULL DEFAULT 'alpha'
        CHECK (size_system IN ('alpha','eu')),
    ADD COLUMN IF NOT EXISTS source      TEXT NOT NULL DEFAULT 'EN 13402-3 (standard reference)';

-- ── 2. Widen the primary key to (garment_type, gender, size_system, size_label, measurement)
ALTER TABLE ref_schema.size_charts DROP CONSTRAINT IF EXISTS size_charts_pkey;

-- ── 3. Drop the representative phase-1 seed; load the EN 13402-3 dataset ─────
DELETE FROM ref_schema.size_charts;

ALTER TABLE ref_schema.size_charts
    ADD CONSTRAINT size_charts_pkey
    PRIMARY KEY (garment_type, gender, size_system, size_label, measurement);

-- ── 4a. WOMEN — alpha (EN 13402-3 bust/waist/hip letter codes) ──────────────
INSERT INTO ref_schema.size_charts
  (garment_type, gender, size_system, size_label, sort_rank, measurement, min_mm, max_mm, source)
VALUES
  -- women top: bust
  ('top','female','alpha','XS',1,'chest', 740, 820,'EN 13402-3 (standard reference)'),
  ('top','female','alpha','S', 2,'chest', 820, 900,'EN 13402-3 (standard reference)'),
  ('top','female','alpha','M', 3,'chest', 900, 980,'EN 13402-3 (standard reference)'),
  ('top','female','alpha','L', 4,'chest', 980,1060,'EN 13402-3 (standard reference)'),
  ('top','female','alpha','XL',5,'chest',1070,1190,'EN 13402-3 (standard reference)'),
  ('top','female','alpha','XXL',6,'chest',1190,1310,'EN 13402-3 (standard reference)'),
  -- women outerwear: bust (jacket primary = bust, EN 13402-2)
  ('outerwear','female','alpha','XS',1,'chest', 740, 820,'EN 13402-3 (standard reference)'),
  ('outerwear','female','alpha','S', 2,'chest', 820, 900,'EN 13402-3 (standard reference)'),
  ('outerwear','female','alpha','M', 3,'chest', 900, 980,'EN 13402-3 (standard reference)'),
  ('outerwear','female','alpha','L', 4,'chest', 980,1060,'EN 13402-3 (standard reference)'),
  ('outerwear','female','alpha','XL',5,'chest',1070,1190,'EN 13402-3 (standard reference)'),
  ('outerwear','female','alpha','XXL',6,'chest',1190,1310,'EN 13402-3 (standard reference)'),
  -- women bottom: waist + hip (waist primary, hip strong secondary)
  ('bottom','female','alpha','XS',1,'waist', 580, 660,'EN 13402-3 (standard reference)'),
  ('bottom','female','alpha','S', 2,'waist', 660, 740,'EN 13402-3 (standard reference)'),
  ('bottom','female','alpha','M', 3,'waist', 740, 820,'EN 13402-3 (standard reference)'),
  ('bottom','female','alpha','L', 4,'waist', 820, 910,'EN 13402-3 (standard reference)'),
  ('bottom','female','alpha','XL',5,'waist', 910,1030,'EN 13402-3 (standard reference)'),
  ('bottom','female','alpha','XXL',6,'waist',1030,1150,'EN 13402-3 (standard reference)'),
  ('bottom','female','alpha','XS',1,'hip', 820, 900,'EN 13402-3 (standard reference)'),
  ('bottom','female','alpha','S', 2,'hip', 900, 980,'EN 13402-3 (standard reference)'),
  ('bottom','female','alpha','M', 3,'hip', 980,1060,'EN 13402-3 (standard reference)'),
  ('bottom','female','alpha','L', 4,'hip',1060,1150,'EN 13402-3 (standard reference)'),
  ('bottom','female','alpha','XL',5,'hip',1150,1250,'EN 13402-3 (standard reference)'),
  ('bottom','female','alpha','XXL',6,'hip',1250,1350,'EN 13402-3 (standard reference)'),
  -- women skirt: waist + hip
  ('skirt','female','alpha','XS',1,'waist', 580, 660,'EN 13402-3 (standard reference)'),
  ('skirt','female','alpha','S', 2,'waist', 660, 740,'EN 13402-3 (standard reference)'),
  ('skirt','female','alpha','M', 3,'waist', 740, 820,'EN 13402-3 (standard reference)'),
  ('skirt','female','alpha','L', 4,'waist', 820, 910,'EN 13402-3 (standard reference)'),
  ('skirt','female','alpha','XL',5,'waist', 910,1030,'EN 13402-3 (standard reference)'),
  ('skirt','female','alpha','XXL',6,'waist',1030,1150,'EN 13402-3 (standard reference)'),
  ('skirt','female','alpha','XS',1,'hip', 820, 900,'EN 13402-3 (standard reference)'),
  ('skirt','female','alpha','S', 2,'hip', 900, 980,'EN 13402-3 (standard reference)'),
  ('skirt','female','alpha','M', 3,'hip', 980,1060,'EN 13402-3 (standard reference)'),
  ('skirt','female','alpha','L', 4,'hip',1060,1150,'EN 13402-3 (standard reference)'),
  ('skirt','female','alpha','XL',5,'hip',1150,1250,'EN 13402-3 (standard reference)'),
  ('skirt','female','alpha','XXL',6,'hip',1250,1350,'EN 13402-3 (standard reference)'),
  -- women dress: bust + waist + hip
  ('dress','female','alpha','XS',1,'chest', 740, 820,'EN 13402-3 (standard reference)'),
  ('dress','female','alpha','S', 2,'chest', 820, 900,'EN 13402-3 (standard reference)'),
  ('dress','female','alpha','M', 3,'chest', 900, 980,'EN 13402-3 (standard reference)'),
  ('dress','female','alpha','L', 4,'chest', 980,1060,'EN 13402-3 (standard reference)'),
  ('dress','female','alpha','XL',5,'chest',1070,1190,'EN 13402-3 (standard reference)'),
  ('dress','female','alpha','XXL',6,'chest',1190,1310,'EN 13402-3 (standard reference)'),
  ('dress','female','alpha','XS',1,'waist', 580, 660,'EN 13402-3 (standard reference)'),
  ('dress','female','alpha','S', 2,'waist', 660, 740,'EN 13402-3 (standard reference)'),
  ('dress','female','alpha','M', 3,'waist', 740, 820,'EN 13402-3 (standard reference)'),
  ('dress','female','alpha','L', 4,'waist', 820, 910,'EN 13402-3 (standard reference)'),
  ('dress','female','alpha','XL',5,'waist', 910,1030,'EN 13402-3 (standard reference)'),
  ('dress','female','alpha','XXL',6,'waist',1030,1150,'EN 13402-3 (standard reference)'),
  ('dress','female','alpha','XS',1,'hip', 820, 900,'EN 13402-3 (standard reference)'),
  ('dress','female','alpha','S', 2,'hip', 900, 980,'EN 13402-3 (standard reference)'),
  ('dress','female','alpha','M', 3,'hip', 980,1060,'EN 13402-3 (standard reference)'),
  ('dress','female','alpha','L', 4,'hip',1060,1150,'EN 13402-3 (standard reference)'),
  ('dress','female','alpha','XL',5,'hip',1150,1250,'EN 13402-3 (standard reference)'),
  ('dress','female','alpha','XXL',6,'hip',1250,1350,'EN 13402-3 (standard reference)'),
  -- ── 4b. MEN — alpha (EN 13402-3 chest letter codes; waist drop ≈ −12) ──────
  ('top','male','alpha','XS',1,'chest', 780, 860,'EN 13402-3 (standard reference)'),
  ('top','male','alpha','S', 2,'chest', 860, 940,'EN 13402-3 (standard reference)'),
  ('top','male','alpha','M', 3,'chest', 940,1020,'EN 13402-3 (standard reference)'),
  ('top','male','alpha','L', 4,'chest',1020,1100,'EN 13402-3 (standard reference)'),
  ('top','male','alpha','XL',5,'chest',1100,1180,'EN 13402-3 (standard reference)'),
  ('top','male','alpha','XXL',6,'chest',1180,1290,'EN 13402-3 (standard reference)'),
  ('outerwear','male','alpha','XS',1,'chest', 780, 860,'EN 13402-3 (standard reference)'),
  ('outerwear','male','alpha','S', 2,'chest', 860, 940,'EN 13402-3 (standard reference)'),
  ('outerwear','male','alpha','M', 3,'chest', 940,1020,'EN 13402-3 (standard reference)'),
  ('outerwear','male','alpha','L', 4,'chest',1020,1100,'EN 13402-3 (standard reference)'),
  ('outerwear','male','alpha','XL',5,'chest',1100,1180,'EN 13402-3 (standard reference)'),
  ('outerwear','male','alpha','XXL',6,'chest',1180,1290,'EN 13402-3 (standard reference)'),
  -- men bottom: waist only (EN sizes men's trousers on waist + inside-leg)
  ('bottom','male','alpha','XS',1,'waist', 660, 740,'EN 13402-3 (standard reference)'),
  ('bottom','male','alpha','S', 2,'waist', 740, 820,'EN 13402-3 (standard reference)'),
  ('bottom','male','alpha','M', 3,'waist', 820, 900,'EN 13402-3 (standard reference)'),
  ('bottom','male','alpha','L', 4,'waist', 900, 980,'EN 13402-3 (standard reference)'),
  ('bottom','male','alpha','XL',5,'waist', 980,1060,'EN 13402-3 (standard reference)'),
  ('bottom','male','alpha','XXL',6,'waist',1060,1170,'EN 13402-3 (standard reference)'),
  -- ── 4c. EU NUMERIC reference set (parallel axis; not consumed by the match) ─
  -- women dress EU (EN 13402-3 dress table, bust/waist/hip)
  ('dress','female','eu','36',36,'chest', 820, 860,'EN 13402-3 (standard reference)'),
  ('dress','female','eu','38',38,'chest', 860, 900,'EN 13402-3 (standard reference)'),
  ('dress','female','eu','40',40,'chest', 900, 940,'EN 13402-3 (standard reference)'),
  ('dress','female','eu','42',42,'chest', 940, 980,'EN 13402-3 (standard reference)'),
  ('dress','female','eu','44',44,'chest', 980,1020,'EN 13402-3 (standard reference)'),
  ('dress','female','eu','46',46,'chest',1020,1070,'EN 13402-3 (standard reference)'),
  ('dress','female','eu','36',36,'waist', 660, 700,'EN 13402-3 (standard reference)'),
  ('dress','female','eu','38',38,'waist', 700, 740,'EN 13402-3 (standard reference)'),
  ('dress','female','eu','40',40,'waist', 740, 780,'EN 13402-3 (standard reference)'),
  ('dress','female','eu','42',42,'waist', 780, 820,'EN 13402-3 (standard reference)'),
  ('dress','female','eu','44',44,'waist', 820, 860,'EN 13402-3 (standard reference)'),
  ('dress','female','eu','46',46,'waist', 860, 910,'EN 13402-3 (standard reference)'),
  ('dress','female','eu','36',36,'hip', 900, 940,'EN 13402-3 (standard reference)'),
  ('dress','female','eu','38',38,'hip', 940, 980,'EN 13402-3 (standard reference)'),
  ('dress','female','eu','40',40,'hip', 980,1020,'EN 13402-3 (standard reference)'),
  ('dress','female','eu','42',42,'hip',1020,1060,'EN 13402-3 (standard reference)'),
  ('dress','female','eu','44',44,'hip',1060,1100,'EN 13402-3 (standard reference)'),
  ('dress','female','eu','46',46,'hip',1100,1150,'EN 13402-3 (standard reference)'),
  -- men top EU (EN 13402-3 men's chest table; EU = chest/2)
  ('top','male','eu','48',48,'chest', 940, 980,'EN 13402-3 (standard reference)'),
  ('top','male','eu','50',50,'chest', 980,1020,'EN 13402-3 (standard reference)'),
  ('top','male','eu','52',52,'chest',1020,1060,'EN 13402-3 (standard reference)'),
  ('top','male','eu','54',54,'chest',1060,1100,'EN 13402-3 (standard reference)'),
  ('top','male','eu','56',56,'chest',1100,1140,'EN 13402-3 (standard reference)')
ON CONFLICT (garment_type, gender, size_system, size_label, measurement) DO NOTHING;
