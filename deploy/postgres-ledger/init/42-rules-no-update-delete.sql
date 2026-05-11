-- 42-rules-no-update-delete.sql — append-only enforcement for ledger tables.
-- Source: LEDGER_GUIDE.md § 3 verbatim.
-- DO INSTEAD NOTHING silently discards UPDATE/DELETE rather than raising.
-- Corrections to ledger entries happen ONLY via reversal transactions (new rows).

CREATE RULE no_update_ledger AS
    ON UPDATE TO wallet_schema.ledger_entries DO INSTEAD NOTHING;

CREATE RULE no_delete_ledger AS
    ON DELETE TO wallet_schema.ledger_entries DO INSTEAD NOTHING;

CREATE RULE no_update_transactions AS
    ON UPDATE TO wallet_schema.transactions DO INSTEAD NOTHING;

CREATE RULE no_delete_transactions AS
    ON DELETE TO wallet_schema.transactions DO INSTEAD NOTHING;
