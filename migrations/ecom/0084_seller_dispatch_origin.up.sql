-- 0084_seller_dispatch_origin.up.sql — P-034 (shipping-ETA infra, enabler for P-007).
-- A seller declares the city it dispatches from. This is the origin input to a cheap,
-- table-driven pre-purchase delivery estimate (shipping.EstimateETA) shown on the PDP —
-- NOT a live carrier call. dispatch_city is a normalized ASCII key (lower, ascii-folded)
-- so it joins ref_schema.shipping_zones without locale-dependent casing.
-- See docs/internal/p034-shipping-eta-architecture.md.
--
-- Nullable: legacy/un-onboarded sellers carry NULL → the estimator falls back to the
-- conservative national range (never a hard failure). Onboarding *capture* of this value
-- is a separate Tranche-5 surface; for now it is seeded / set administratively.

ALTER TABLE seller_schema.sellers
    ADD COLUMN IF NOT EXISTS dispatch_city TEXT;   -- normalized key, e.g. 'istanbul'; NULL = unknown origin

-- Seed the example sellers (0078) so fresh DBs render a PDP delivery estimate.
UPDATE seller_schema.sellers SET dispatch_city = 'istanbul' WHERE id = 1 AND dispatch_city IS NULL;
UPDATE seller_schema.sellers SET dispatch_city = 'izmir'    WHERE id = 2 AND dispatch_city IS NULL;
UPDATE seller_schema.sellers SET dispatch_city = 'ankara'   WHERE id = 3 AND dispatch_city IS NULL;
