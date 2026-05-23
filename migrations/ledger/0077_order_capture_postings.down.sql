-- 0077_order_capture_postings.down.sql
-- Rolls back the capture_postings table and the two new platform accounts.
-- WARNING: dropping capture_postings discards all audit rows — use only in dev/test.

DROP TABLE IF EXISTS commission_schema.capture_postings;

DELETE FROM wallet_schema.accounts
WHERE type IN ('asset:psp_receivable', 'liability:shipping_payable')
  AND owner_type = 'platform'
  AND owner_id IS NULL;
