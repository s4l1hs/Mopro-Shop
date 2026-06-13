-- 0098_size_chart_curation.down.sql
-- Revert to the 0096 representative seed: narrow the PK back to
-- (garment_type, size_label, measurement), drop the gender/size_system/source
-- columns, and restore the phase-1 approximate rows. IDEMPOTENT.

DELETE FROM ref_schema.size_charts;

ALTER TABLE ref_schema.size_charts DROP CONSTRAINT IF EXISTS size_charts_pkey;

ALTER TABLE ref_schema.size_charts
    DROP COLUMN IF EXISTS gender,
    DROP COLUMN IF EXISTS size_system,
    DROP COLUMN IF EXISTS source;

ALTER TABLE ref_schema.size_charts
    ADD CONSTRAINT size_charts_pkey
    PRIMARY KEY (garment_type, size_label, measurement);

INSERT INTO ref_schema.size_charts
  (garment_type, size_label, sort_rank, measurement, min_mm, max_mm)
VALUES
  ('top','XS',1,'chest', 820, 880),('top','S',2,'chest', 880, 940),
  ('top','M',3,'chest', 940,1000),('top','L',4,'chest',1000,1080),
  ('top','XL',5,'chest',1080,1160),('top','XXL',6,'chest',1160,1260),
  ('bottom','XS',1,'waist', 660, 720),('bottom','S',2,'waist', 720, 780),
  ('bottom','M',3,'waist', 780, 840),('bottom','L',4,'waist', 840, 920),
  ('bottom','XL',5,'waist', 920,1000),('bottom','XXL',6,'waist',1000,1100),
  ('bottom','XS',1,'hip', 860, 920),('bottom','S',2,'hip', 920, 980),
  ('bottom','M',3,'hip', 980,1040),('bottom','L',4,'hip',1040,1120),
  ('bottom','XL',5,'hip',1120,1200),('bottom','XXL',6,'hip',1200,1300),
  ('dress','XS',1,'chest', 820, 880),('dress','S',2,'chest', 880, 940),
  ('dress','M',3,'chest', 940,1000),('dress','L',4,'chest',1000,1080),
  ('dress','XL',5,'chest',1080,1160),('dress','XXL',6,'chest',1160,1260),
  ('dress','XS',1,'waist', 660, 720),('dress','S',2,'waist', 720, 780),
  ('dress','M',3,'waist', 780, 840),('dress','L',4,'waist', 840, 920),
  ('dress','XL',5,'waist', 920,1000),('dress','XXL',6,'waist',1000,1100),
  ('dress','XS',1,'hip', 860, 920),('dress','S',2,'hip', 920, 980),
  ('dress','M',3,'hip', 980,1040),('dress','L',4,'hip',1040,1120),
  ('dress','XL',5,'hip',1120,1200),('dress','XXL',6,'hip',1200,1300),
  ('skirt','XS',1,'waist', 660, 720),('skirt','S',2,'waist', 720, 780),
  ('skirt','M',3,'waist', 780, 840),('skirt','L',4,'waist', 840, 920),
  ('skirt','XL',5,'waist', 920,1000),('skirt','XXL',6,'waist',1000,1100),
  ('skirt','XS',1,'hip', 860, 920),('skirt','S',2,'hip', 920, 980),
  ('skirt','M',3,'hip', 980,1040),('skirt','L',4,'hip',1040,1120),
  ('skirt','XL',5,'hip',1120,1200),('skirt','XXL',6,'hip',1200,1300),
  ('outerwear','XS',1,'chest', 860, 920),('outerwear','S',2,'chest', 920, 980),
  ('outerwear','M',3,'chest', 980,1040),('outerwear','L',4,'chest',1040,1120),
  ('outerwear','XL',5,'chest',1120,1200),('outerwear','XXL',6,'chest',1200,1300)
ON CONFLICT (garment_type, size_label, measurement) DO NOTHING;
