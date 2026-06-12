-- 85-sizefinder-schema.sql — sizefinder module tables (lockstep with migration
-- 0096; see its header for the §6/§5 notes). Measurements stored ONLY as
-- AES-GCM EncryptPII ciphertext.
CREATE TABLE IF NOT EXISTS sizefinder_schema.fit_profiles (
    user_id    BIGINT      PRIMARY KEY,
    chest_enc  TEXT,
    waist_enc  TEXT,
    hip_enc    TEXT,
    inseam_enc TEXT,
    height_enc TEXT,
    fit_pref   TEXT        NOT NULL DEFAULT 'regular'
               CHECK (fit_pref IN ('regular','loose','tight')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
