-- 0093_order_delivery_address.up.sql
-- OR-02: capture the delivery address as an immutable snapshot on the order.
--
-- The order must record its ship-to as an AS-OF-PURCHASE fact. The saved address in
-- identity_schema.addresses is MUTABLE (the user can edit/delete it) and lives in a
-- different schema, so an FK/JOIN would be both wrong (history would drift) and a §5
-- violation. Instead the order owns a denormalized 1:1 snapshot in its OWN schema:
-- the order build resolves the address via identity.Service.GetAddress (in-process,
-- §3.1) and copies the fields here, inside the same tx as the order rows.
--
-- PII parity (§6): recipient name, phone, full address and neighborhood are the same
-- PII as the source table, so they are AES-GCM encrypted at rest (pkg/crypto.*),
-- exactly as identity_schema.addresses stores them. district/city/postal_code/label
-- stay plaintext for logistics routing, matching the source.
--
-- Additive + backward-compatible: legacy orders simply have no row → the order detail
-- omits the delivery-address card. order_id is the PK (one snapshot per order).

CREATE TABLE IF NOT EXISTS order_schema.order_addresses (
  order_id          BIGINT       NOT NULL
                      REFERENCES order_schema.orders(id) ON DELETE CASCADE,
  label             TEXT         NOT NULL DEFAULT '',
  recipient_name_enc TEXT        NOT NULL,
  phone_enc         TEXT         NOT NULL,
  full_address_enc  TEXT         NOT NULL,
  neighborhood_enc  TEXT,
  district          TEXT         NOT NULL DEFAULT '',
  city              TEXT         NOT NULL DEFAULT '',
  postal_code       TEXT,
  created_at        TIMESTAMPTZ  NOT NULL DEFAULT now(),
  PRIMARY KEY (order_id)
);
