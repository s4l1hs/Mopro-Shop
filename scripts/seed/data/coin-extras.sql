-- scripts/seed/data/coin-extras.sql — dev-only Coin hub ledger seed (IA-02).
--
-- Balanced double-entry (CLAUDE.md §4.1) TRY_COIN credits + one spend to the
-- first dev-OTP user's wallet (owner_id=1), so the Coin hub renders REAL ledger
-- data (balance MV + transactions) — not fabricated values. Each transaction is
-- D == C in the same currency, satisfying the DEFERRABLE ledger_balance_check.
-- Credits: D equity:cashback_distribution ↔ C the user wallet (= cashback earn,
-- per §4.7). The spend reverses it (D wallet ↔ C equity).
--
-- Idempotent: dev rows are tagged `seed-coin-%` and cleared before re-insert;
-- the wallet_schema.balances materialized view is refreshed at the end (balance
-- reads come from the MV). LOCAL ONLY — postgres-ledger.
--
-- Apply (after the user's wallet may or may not exist):
--   docker exec -i postgres-ledger psql -v ON_ERROR_STOP=1 \
--     -U ledger_admin -d mopro_ledger < scripts/seed/data/coin-extras.sql

DO $$
DECLARE
  wallet_acct bigint;
  equity_acct bigint;
  tx bigint;
  ts timestamptz;
  r  record;
BEGIN
  -- Ensure the dev user's coin wallet account (looked up by owner, §4.7 type).
  SELECT id INTO wallet_acct FROM wallet_schema.accounts
   WHERE owner_type = 'user' AND owner_id = 1 AND currency = 'TRY_COIN';
  IF wallet_acct IS NULL THEN
    INSERT INTO wallet_schema.accounts (type, owner_type, owner_id, currency, status)
    VALUES ('liability:wallet:user', 'user', 1, 'TRY_COIN', 'active')
    RETURNING id INTO wallet_acct;
  END IF;

  SELECT id INTO equity_acct FROM wallet_schema.accounts
   WHERE type = 'equity:cashback_distribution' AND currency = 'TRY_COIN';

  -- Idempotency: drop any prior dev coin seed.
  DELETE FROM wallet_schema.ledger_entries WHERE transaction_id IN
    (SELECT id FROM wallet_schema.transactions WHERE idempotency_key LIKE 'seed-coin-%');
  DELETE FROM wallet_schema.transactions WHERE idempotency_key LIKE 'seed-coin-%';

  -- amt minor | dir | months-ago | tx type | reference(plan id)
  FOR r IN SELECT * FROM (VALUES
      (15800::bigint, 'C', 1, 'cashback_payment', '101'),
      (15800::bigint, 'C', 2, 'cashback_payment', '101'),
      (18958::bigint, 'C', 3, 'cashback_payment', '102'),
      ( 7499::bigint, 'D', 0, 'adjustment',        '')
    ) AS v(amt, dir, ago, ttype, ref) LOOP
    ts := now() - (r.ago || ' months')::interval;
    INSERT INTO wallet_schema.transactions (type, reference, idempotency_key, status, created_at)
    VALUES (r.ttype, NULLIF(r.ref, ''), 'seed-coin-' || r.ago || '-' || r.dir, 'posted', ts)
    RETURNING id INTO tx;
    IF r.dir = 'C' THEN  -- earn: D equity ↔ C user wallet
      INSERT INTO wallet_schema.ledger_entries (transaction_id, account_id, direction, amount_minor, created_at)
      VALUES (tx, equity_acct, 'D', r.amt, ts), (tx, wallet_acct, 'C', r.amt, ts);
    ELSE                 -- spend: D user wallet ↔ C equity
      INSERT INTO wallet_schema.ledger_entries (transaction_id, account_id, direction, amount_minor, created_at)
      VALUES (tx, wallet_acct, 'D', r.amt, ts), (tx, equity_acct, 'C', r.amt, ts);
    END IF;
  END LOOP;
END $$;

REFRESH MATERIALIZED VIEW wallet_schema.balances;
