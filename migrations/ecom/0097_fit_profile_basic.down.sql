-- 0097_fit_profile_basic.down.sql
ALTER TABLE sizefinder_schema.fit_profiles
    DROP COLUMN IF EXISTS weight_enc,
    DROP COLUMN IF EXISTS gender;
