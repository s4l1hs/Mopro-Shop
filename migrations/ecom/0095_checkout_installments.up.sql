-- 0095_checkout_installments.up.sql
-- PD-05: record the buyer's chosen card-installment count (taksit) on the
-- checkout session — the as-initiated record written in the same tx as the
-- per-seller orders. INTEREST-FREE model (Salih-confirmed): the charged
-- total_amount is UNCHANGED; the bank slices the buyer's payments. No money-math
-- change anywhere (display==charge invariant intact); the count is passed to
-- Sipay paySmart3D as installments_number and recorded here.
--
-- The payments row is NOT the recording point: it is born at webhook time from
-- webhook fields, which do not echo the installment count. The session (same
-- invoice_id) is the §5-safe order-schema record.
--
-- Additive + backward-compatible: DEFAULT 1 = single charge (tek çekim) for all
-- existing and non-card sessions. Allowed counts mirror the Sipay-documented set.

ALTER TABLE order_schema.checkout_sessions
  ADD COLUMN IF NOT EXISTS installments SMALLINT NOT NULL DEFAULT 1
      CHECK (installments IN (1, 3, 6, 9, 12));
