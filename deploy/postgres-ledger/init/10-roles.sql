-- 10-roles.sql — create one LOGIN role per fin-svc module on postgres-ledger.
-- Placeholder password replaced at runtime by 99-set-passwords.sh from env vars.
-- All roles: NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT LOGIN.

DO $$
DECLARE
  roles TEXT[] := ARRAY[
    'wallet_user',       -- wallet_schema: accounts, transactions, ledger_entries, outbox, balances
    'commission_user',   -- commission_schema: (future) commission records
    'treasury_user',     -- treasury_schema: float yield tracking
    'cashback_user',     -- cashback_schema: plans, plans_history, payments
    'sellerpayout_user'  -- sellerpayout_schema: seller_payouts, payout_batches, seller_psp_accounts
  ];
  r TEXT;
BEGIN
  FOREACH r IN ARRAY roles LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
      EXECUTE format(
        'CREATE ROLE %I NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT LOGIN PASSWORD ''REPLACE_BY_INIT''',
        r
      );
    END IF;
  END LOOP;
END;
$$;
