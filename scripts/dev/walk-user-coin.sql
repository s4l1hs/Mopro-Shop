-- walk-user-coin.sql — idempotent dev coin balance for the walk user (ledger DB).
-- Applied via: docker exec -i postgres-ledger psql -U ledger_admin -d mopro_ledger < this
--
-- Posts a single balanced double-entry move so the Wallet/Coin surface shows a
-- non-zero TRY_COIN balance + a transaction:
--   D equity:cashback_distribution:TRY_COIN  ←→  C liability:wallet:user_1:TRY_COIN
-- (the exact shape the cashback engine uses). Idempotent via a sentinel
-- idempotency_key; the DEFERRABLE balance trigger checks D==C at COMMIT.

\set ON_ERROR_STOP on

DO $$
DECLARE
  txid       BIGINT;
  acct_user  BIGINT;
  acct_equity BIGINT;
  amt        BIGINT := 4250;   -- ₿42.50 illustrative cashback coin
BEGIN
  IF EXISTS (SELECT 1 FROM wallet_schema.transactions WHERE idempotency_key = 'walk-seed-coin-1') THEN
    RAISE NOTICE 'coin already seeded'; RETURN;
  END IF;
  SELECT id INTO acct_user   FROM wallet_schema.accounts
    WHERE type = 'liability:wallet:user' AND owner_id = 1 AND currency = 'TRY_COIN';
  SELECT id INTO acct_equity FROM wallet_schema.accounts
    WHERE type = 'equity:cashback_distribution' AND currency = 'TRY_COIN';
  IF acct_user IS NULL OR acct_equity IS NULL THEN
    RAISE NOTICE 'wallet/equity coin account missing; skipping coin seed';
    RETURN;
  END IF;

  INSERT INTO wallet_schema.transactions (type, reference, idempotency_key, status, created_at)
  VALUES ('cashback_payment', 'walk-seed', 'walk-seed-coin-1', 'posted', now())
  RETURNING id INTO txid;

  INSERT INTO wallet_schema.ledger_entries (transaction_id, account_id, direction, amount_minor)
  VALUES (txid, acct_equity, 'D', amt),
         (txid, acct_user,   'C', amt);
END $$;
