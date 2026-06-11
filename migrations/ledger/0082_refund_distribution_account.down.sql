-- 0082_refund_distribution_account.down.sql — reverse 0082.
-- Safe only because the account is new; ledger_entries are append-only, so if any
-- refund has posted against it this DELETE will fail the FK (intended — never drop
-- an account with history). NULLIF guard keeps it scoped to the platform account.
DELETE FROM wallet_schema.accounts
WHERE type = 'equity:refund_distribution' AND owner_type = 'platform' AND currency = 'TRY_COIN';
