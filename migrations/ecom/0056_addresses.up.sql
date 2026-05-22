-- 0056_addresses.up.sql — identity_schema.addresses: user shipping addresses with PII encryption.
-- All personally-identifying fields stored as AES-GCM encrypted TEXT (pkg/crypto.EncryptPII).

CREATE TABLE IF NOT EXISTS identity_schema.addresses (
  id               BIGSERIAL    NOT NULL,
  user_id          BIGINT       NOT NULL REFERENCES identity_schema.users(id) ON DELETE CASCADE,
  label            TEXT         NOT NULL,
  name_enc         TEXT         NOT NULL,
  phone_enc        TEXT         NOT NULL,
  full_address_enc TEXT         NOT NULL,
  neighborhood_enc TEXT,
  district         TEXT         NOT NULL,
  city             TEXT         NOT NULL,
  postal_code      TEXT,
  is_default       BOOLEAN      NOT NULL DEFAULT FALSE,
  created_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
  PRIMARY KEY (id)
);

CREATE INDEX ON identity_schema.addresses(user_id);
