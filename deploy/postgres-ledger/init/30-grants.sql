-- 30-grants.sql — per-module schema grants on postgres-ledger.
-- Key cross-role concern: sellerpayout_user writes commission_schema.seller_payouts,
-- so it receives USAGE + DML on commission_schema even though that schema is owned by commission_user.

-- wallet_user — full DML on wallet_schema (accounts, transactions, ledger_entries, outbox, balances, ledger_alerts)
GRANT USAGE ON SCHEMA wallet_schema TO wallet_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA wallet_schema
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO wallet_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA wallet_schema
  GRANT USAGE, SELECT ON SEQUENCES TO wallet_user;

-- commission_user — full DML on commission_schema
GRANT USAGE ON SCHEMA commission_schema TO commission_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA commission_schema
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO commission_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA commission_schema
  GRANT USAGE, SELECT ON SEQUENCES TO commission_user;

-- treasury_user — full DML on treasury_schema
GRANT USAGE ON SCHEMA treasury_schema TO treasury_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA treasury_schema
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO treasury_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA treasury_schema
  GRANT USAGE, SELECT ON SEQUENCES TO treasury_user;

-- cashback_user — full DML on cashback_schema
GRANT USAGE ON SCHEMA cashback_schema TO cashback_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA cashback_schema
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO cashback_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA cashback_schema
  GRANT USAGE, SELECT ON SEQUENCES TO cashback_user;

-- sellerpayout_user — DML on commission_schema (seller_payouts lives here, not in a separate schema)
GRANT USAGE ON SCHEMA commission_schema TO sellerpayout_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA commission_schema
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO sellerpayout_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA commission_schema
  GRANT USAGE, SELECT ON SEQUENCES TO sellerpayout_user;

-- Belt-and-suspenders: retroactive grants on any commission_schema tables already created
-- before ALTER DEFAULT PRIVILEGES was evaluated (safe no-op on clean DB).
DO $$
DECLARE tbl RECORD;
BEGIN
  FOR tbl IN SELECT tablename FROM pg_tables WHERE schemaname = 'commission_schema' LOOP
    EXECUTE format(
      'GRANT SELECT, INSERT, UPDATE, DELETE ON commission_schema.%I TO sellerpayout_user',
      tbl.tablename
    );
    EXECUTE format(
      'GRANT SELECT, INSERT, UPDATE, DELETE ON commission_schema.%I TO commission_user',
      tbl.tablename
    );
  END LOOP;
END;
$$;
