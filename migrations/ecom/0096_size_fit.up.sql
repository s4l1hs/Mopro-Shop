-- 0096_size_fit.up.sql
-- Size-Fit Recommendation phase 1 (Phase C; docs/internal/size-fit.md).
--
-- Two tables:
--   ref_schema.size_charts          — STANDARD garment-type size charts.
--   sizefinder_schema.fit_profiles  — per-user measurements, AES-GCM encrypted.
--
-- ⚠️ SEED CHARTS ARE REPRESENTATIVE, NOT AUTHORITATIVE. Values approximate
-- common TR/EU adult tables; curate before making returns-reduction claims
-- (the API flags every response chart_approximate=true). Charts key on GARMENT
-- TYPE, not category — the taxonomy is too coarse (a category holds tops AND
-- bottoms). Bottoms/skirts match on waist+hip; inseam is collected on the
-- profile for future length recommendations but no phase-1 chart uses it.
--
-- Measurements are INTEGER MILLIMETRES (the money-type discipline applied to
-- lengths — no floats). fit_profiles measurement columns hold
-- pkg/crypto.EncryptPII ciphertext (§6 — the 0093 order-address pattern);
-- plaintext mm values never touch disk. user_id is a soft reference to
-- identity_schema.users (no cross-schema FK, §5).
--
-- ref_schema has ALTER DEFAULT PRIVILEGES → SELECT TO PUBLIC (30-grants.sql);
-- sizefinder_schema has default CRUD grants to sizefinder_user. No grant block
-- needed. Fresh-DB init lockstep: 40-ref-schema.sql / 50-ref-seed.sql /
-- 85-sizefinder-schema.sql. IDEMPOTENT.

CREATE TABLE IF NOT EXISTS ref_schema.size_charts (
    garment_type TEXT NOT NULL,   -- top | bottom | dress | skirt | outerwear
    size_label   TEXT NOT NULL,   -- XS … XXL
    sort_rank    INT  NOT NULL,   -- ladder order (1 = smallest)
    measurement  TEXT NOT NULL,   -- chest | waist | hip
    min_mm       INT  NOT NULL CHECK (min_mm > 0),
    max_mm       INT  NOT NULL CHECK (max_mm > min_mm),
    PRIMARY KEY (garment_type, size_label, measurement)
);

CREATE TABLE IF NOT EXISTS sizefinder_schema.fit_profiles (
    user_id    BIGINT      PRIMARY KEY,    -- soft ref → identity_schema.users
    chest_enc  TEXT,                       -- AES-GCM EncryptPII(mm)
    waist_enc  TEXT,
    hip_enc    TEXT,
    inseam_enc TEXT,
    height_enc TEXT,
    fit_pref   TEXT        NOT NULL DEFAULT 'regular'
               CHECK (fit_pref IN ('regular','loose','tight')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── Representative standard charts (APPROXIMATE — see header) ───────────────
INSERT INTO ref_schema.size_charts
  (garment_type, size_label, sort_rank, measurement, min_mm, max_mm)
VALUES
  -- top: chest
  ('top','XS',1,'chest', 820, 880),('top','S',2,'chest', 880, 940),
  ('top','M',3,'chest', 940,1000),('top','L',4,'chest',1000,1080),
  ('top','XL',5,'chest',1080,1160),('top','XXL',6,'chest',1160,1260),
  -- bottom: waist + hip
  ('bottom','XS',1,'waist', 660, 720),('bottom','S',2,'waist', 720, 780),
  ('bottom','M',3,'waist', 780, 840),('bottom','L',4,'waist', 840, 920),
  ('bottom','XL',5,'waist', 920,1000),('bottom','XXL',6,'waist',1000,1100),
  ('bottom','XS',1,'hip', 860, 920),('bottom','S',2,'hip', 920, 980),
  ('bottom','M',3,'hip', 980,1040),('bottom','L',4,'hip',1040,1120),
  ('bottom','XL',5,'hip',1120,1200),('bottom','XXL',6,'hip',1200,1300),
  -- dress: chest + waist + hip
  ('dress','XS',1,'chest', 820, 880),('dress','S',2,'chest', 880, 940),
  ('dress','M',3,'chest', 940,1000),('dress','L',4,'chest',1000,1080),
  ('dress','XL',5,'chest',1080,1160),('dress','XXL',6,'chest',1160,1260),
  ('dress','XS',1,'waist', 660, 720),('dress','S',2,'waist', 720, 780),
  ('dress','M',3,'waist', 780, 840),('dress','L',4,'waist', 840, 920),
  ('dress','XL',5,'waist', 920,1000),('dress','XXL',6,'waist',1000,1100),
  ('dress','XS',1,'hip', 860, 920),('dress','S',2,'hip', 920, 980),
  ('dress','M',3,'hip', 980,1040),('dress','L',4,'hip',1040,1120),
  ('dress','XL',5,'hip',1120,1200),('dress','XXL',6,'hip',1200,1300),
  -- skirt: waist + hip
  ('skirt','XS',1,'waist', 660, 720),('skirt','S',2,'waist', 720, 780),
  ('skirt','M',3,'waist', 780, 840),('skirt','L',4,'waist', 840, 920),
  ('skirt','XL',5,'waist', 920,1000),('skirt','XXL',6,'waist',1000,1100),
  ('skirt','XS',1,'hip', 860, 920),('skirt','S',2,'hip', 920, 980),
  ('skirt','M',3,'hip', 980,1040),('skirt','L',4,'hip',1040,1120),
  ('skirt','XL',5,'hip',1120,1200),('skirt','XXL',6,'hip',1200,1300),
  -- outerwear: chest (cut roomier)
  ('outerwear','XS',1,'chest', 860, 920),('outerwear','S',2,'chest', 920, 980),
  ('outerwear','M',3,'chest', 980,1040),('outerwear','L',4,'chest',1040,1120),
  ('outerwear','XL',5,'chest',1120,1200),('outerwear','XXL',6,'chest',1200,1300)
ON CONFLICT (garment_type, size_label, measurement) DO NOTHING;
