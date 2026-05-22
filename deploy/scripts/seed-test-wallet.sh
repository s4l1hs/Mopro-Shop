#!/usr/bin/env bash
# Seeds a deterministic test wallet + cashback data for Phase 4.3b visual QA.
# All rows use idempotency_key prefix "test_visual_qa_" for easy cleanup.
#
# Usage:
#   ./deploy/scripts/seed-test-wallet.sh [DSN]
#
# Defaults to postgres://ledger_admin:test123@localhost:6434/mopro_ledger
# Override with: LEDGER_DSN=<dsn> ./seed-test-wallet.sh
#                or pass DSN as $1

set -euo pipefail

DSN="${1:-${LEDGER_DSN:-postgres://ledger_admin:test123@localhost:6434/mopro_ledger}}"
TEST_USER_ID=3

echo "==> Seeding test wallet data for user_id=${TEST_USER_ID} ..."
echo "    DSN: ${DSN}"

psql "${DSN}" <<'SQL'

-- ── Wallet account (idempotent) ──────────────────────────────────────────────
INSERT INTO wallet_schema.accounts (owner_id, currency, status)
VALUES (3, 'TRY_COIN', 'active')
ON CONFLICT (owner_id, currency) DO NOTHING;

-- ── Seed balance via ledger entries ─────────────────────────────────────────
-- Only insert if transaction doesn't already exist (idempotency).
DO $$
DECLARE
  v_account_id BIGINT;
  v_txn_id     BIGINT;
  v_idem_key   TEXT := 'test_visual_qa_seed_balance_v1';
BEGIN
  -- Get account id
  SELECT id INTO v_account_id
    FROM wallet_schema.accounts
   WHERE owner_id = 3 AND currency = 'TRY_COIN';

  -- Skip if already seeded
  IF EXISTS (
    SELECT 1 FROM wallet_schema.transactions
     WHERE idempotency_key = v_idem_key
  ) THEN
    RAISE NOTICE 'Balance already seeded, skipping.';
    RETURN;
  END IF;

  INSERT INTO wallet_schema.transactions
    (type, reference, idempotency_key)
  VALUES
    ('cashback_payment', '0', v_idem_key)
  RETURNING id INTO v_txn_id;

  INSERT INTO wallet_schema.ledger_entries
    (transaction_id, account_id, amount_minor, direction, currency)
  VALUES
    (v_txn_id, v_account_id, 50000, 'C', 'TRY_COIN'),
    (v_txn_id,
     (SELECT id FROM wallet_schema.accounts
       WHERE owner_id = 0 AND currency = 'TRY_COIN'
       LIMIT 1),
     50000, 'D', 'TRY_COIN');

  RAISE NOTICE 'Seeded 500,00 MC balance for user 3.';
END;
$$;

-- ── Seed cashback plan ────────────────────────────────────────────────────────
INSERT INTO cashback_schema.plans
    (order_id, user_id, monthly_amount_minor, currency,
     reference_interest_rate_bps, start_date, status,
     delivered_at, market, commission_snapshot, idempotency_key)
SELECT
    90001, 3, 5000, 'TRY_COIN',
    5000, NOW() - INTERVAL '90 days', 'active',
    NOW() - INTERVAL '93 days', 'TR', '[]'::jsonb,
    'test_visual_qa_plan_v1'
WHERE NOT EXISTS (
    SELECT 1 FROM cashback_schema.plans
     WHERE idempotency_key = 'test_visual_qa_plan_v1'
);

-- ── Seed 3 paid + 3 scheduled payments ───────────────────────────────────────
DO $$
DECLARE
  v_plan_id BIGINT;
  v_month   TEXT;
  v_status  TEXT;
  i         INT;
BEGIN
  SELECT id INTO v_plan_id
    FROM cashback_schema.plans
   WHERE idempotency_key = 'test_visual_qa_plan_v1';

  FOR i IN 1..6 LOOP
    v_month  := TO_CHAR(NOW() - ((7 - i) || ' months')::INTERVAL, 'YYYYMM');
    v_status := CASE WHEN i <= 3 THEN 'paid' ELSE 'scheduled' END;

    INSERT INTO cashback_schema.payments
        (plan_id, period_yyyymm, amount_minor, currency, status,
         paid_at, idempotency_key)
    SELECT
        v_plan_id, v_month, 5000, 'TRY_COIN', v_status,
        CASE WHEN v_status = 'paid' THEN NOW() - ((7 - i) || ' months')::INTERVAL + INTERVAL '2 days' ELSE NULL END,
        'test_visual_qa_pay_' || v_month
    WHERE NOT EXISTS (
        SELECT 1 FROM cashback_schema.payments
         WHERE idempotency_key = 'test_visual_qa_pay_' || v_month
    );
  END LOOP;

  RAISE NOTICE 'Seeded 6 payments (3 paid + 3 scheduled) for plan %.', v_plan_id;
END;
$$;

SQL

echo "==> Done. Pull-to-refresh WalletScreen to see the seeded data."
echo "    To clean up: psql \$DSN -c \"DELETE FROM cashback_schema.payments WHERE idempotency_key LIKE 'test_visual_qa_%'; DELETE FROM cashback_schema.plans WHERE idempotency_key LIKE 'test_visual_qa_%';\""
