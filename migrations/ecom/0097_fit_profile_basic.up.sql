-- 0097_fit_profile_basic.up.sql
-- Size-fit BASIC mode (docs/internal/size-fit-basic.md): height+weight+gender
-- estimation for users without detailed measurements.
--
-- weight is sensitive body data → stored in GRAMS (integer) as AES-GCM
-- EncryptPII ciphertext, exactly like the existing measurement columns (§6).
-- gender is a categorical preference (not a measurement), stored plaintext like
-- fit_pref; 'unspecified' = basic estimation unavailable for that user.
-- Additive; idempotent. Init lockstep: 85-sizefinder-schema.sql.

ALTER TABLE sizefinder_schema.fit_profiles
    ADD COLUMN IF NOT EXISTS weight_enc TEXT,
    ADD COLUMN IF NOT EXISTS gender     TEXT NOT NULL DEFAULT 'unspecified'
        CHECK (gender IN ('female','male','unspecified'));
