-- 41-trigger-d-equals-c.sql — multi-currency-aware double-entry invariant.
-- Source: LEDGER_GUIDE.md § 4 verbatim.
--
-- CONSTRAINT TRIGGER with DEFERRABLE INITIALLY DEFERRED fires at COMMIT, not per-row.
-- This allows a transaction to INSERT both D and C entries before validation runs.
-- All D and C entries for a ledger transaction MUST be in ONE SQL transaction.

CREATE OR REPLACE FUNCTION wallet_schema.enforce_double_entry()
RETURNS TRIGGER AS $$
DECLARE
    txn_currencies TEXT[];
    debit_total    BIGINT;
    credit_total   BIGINT;
BEGIN
    -- (1) Multi-currency safety: all entries in this transaction must share one currency.
    --     Joining ledger_entries back to accounts reads the currency of every account
    --     touched by this transaction_id (including the just-inserted NEW row).
    SELECT array_agg(DISTINCT a.currency)
    INTO txn_currencies
    FROM wallet_schema.ledger_entries le
    JOIN wallet_schema.accounts a ON a.id = le.account_id
    WHERE le.transaction_id = NEW.transaction_id;

    IF array_length(txn_currencies, 1) > 1 THEN
        RAISE EXCEPTION
            'Mixed currencies in transaction %: %',
            NEW.transaction_id, txn_currencies
            USING ERRCODE = 'check_violation';
    END IF;

    -- (2) D=C check (single-currency guaranteed at this point).
    SELECT
        COALESCE(SUM(amount_minor) FILTER (WHERE direction = 'D'), 0),
        COALESCE(SUM(amount_minor) FILTER (WHERE direction = 'C'), 0)
    INTO debit_total, credit_total
    FROM wallet_schema.ledger_entries
    WHERE transaction_id = NEW.transaction_id;

    IF debit_total != credit_total THEN
        RAISE EXCEPTION
            'Double-entry violation: txn=% debit=% credit=%',
            NEW.transaction_id, debit_total, credit_total
            USING ERRCODE = 'check_violation';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- DEFERRABLE INITIALLY DEFERRED: trigger evaluates at COMMIT, not after each INSERT.
-- At COMMIT all entries are present → D=C invariant can be correctly evaluated.
-- If violated at COMMIT → entire transaction is atomically rolled back.
CREATE CONSTRAINT TRIGGER ledger_balance_check
AFTER INSERT ON wallet_schema.ledger_entries
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION wallet_schema.enforce_double_entry();
