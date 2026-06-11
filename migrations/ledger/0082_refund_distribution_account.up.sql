-- 0082_refund_distribution_account.up.sql
-- RT-01 refund settlement (refund-as-coin). Add the counter-equity account debited
-- each time an approved return is settled by minting Mopro Coin to the buyer's
-- wallet: D equity:refund_distribution:TRY_COIN ↔ C liability:wallet:user_<id>:TRY_COIN.
--
-- This is the exact analogue of equity:cashback_distribution (a TRY_COIN platform
-- counter-equity, recognized per-settlement with no upfront provision) — it follows
-- every §4 invariant (double-entry, single-currency, append-only, idempotent,
-- outbox) and is NOT a §12 change. The fresh-DB source
-- (deploy/postgres-ledger/init/70-chart-of-accounts-seed.sql) is updated in
-- lockstep; this migration carries already-deployed ledgers across the same change.
--
-- IDEMPOTENT: ON CONFLICT DO NOTHING (partial unique index
-- accounts_platform_type_currency_uq, init/40-wallet-schema.sql).

INSERT INTO wallet_schema.accounts (type, owner_type, owner_id, currency, status)
VALUES ('equity:refund_distribution', 'platform', NULL, 'TRY_COIN', 'active')
ON CONFLICT DO NOTHING;
