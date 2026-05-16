-- 67-system-state.sql — singleton read-only flag for wallet.Service.
-- Phase 2.4: written by reconcile cron and mopro CLI; read by wallet.PostInTx.

CREATE TABLE wallet_schema.system_state (
    id               INTEGER PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    read_only        BOOLEAN NOT NULL DEFAULT FALSE,
    read_only_reason TEXT,
    read_only_since  TIMESTAMPTZ,
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO wallet_schema.system_state (id) VALUES (1);
