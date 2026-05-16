-- 40-wallet-schema.sql — wallet_schema: core double-entry ledger tables.
-- Source: LEDGER_GUIDE.md § 3 verbatim, plus OQ1-resolved ledger_alerts table.
-- RULES (no_update_ledger, no_delete_ledger, etc.) live in 42-rules-no-update-delete.sql.
-- Trigger (enforce_double_entry) lives in 41-trigger-d-equals-c.sql.

-- ── accounts ─────────────────────────────────────────────────────────────────
-- Each account has exactly ONE currency. An account never holds mixed currencies.
-- type: the hierarchical account class, e.g. 'asset:bank:escrow' (without currency suffix).
-- owner_type: 'platform' | 'user' | 'seller' | 'fx'.
-- owner_id: NULL for platform accounts; user_id or seller_id for per-entity accounts.
CREATE TABLE wallet_schema.accounts (
    id          BIGSERIAL PRIMARY KEY,
    type        TEXT NOT NULL,
    owner_type  TEXT,
    owner_id    BIGINT,
    currency    TEXT NOT NULL,
    status      TEXT NOT NULL DEFAULT 'active',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX accounts_owner_idx          ON wallet_schema.accounts(owner_type, owner_id);
CREATE INDEX accounts_type_currency_idx  ON wallet_schema.accounts(type, currency);

-- Unique index for platform (non-per-entity) accounts to support idempotent seeding.
-- owner_type = 'platform', owner_id IS NULL → one account per (type, currency).
CREATE UNIQUE INDEX accounts_platform_type_currency_uq
    ON wallet_schema.accounts(type, currency)
    WHERE owner_type = 'platform' AND owner_id IS NULL;

-- Unique index for per-entity accounts (user wallets, seller payables).
-- Required by wallet.OpenOrFindUserWallet and wallet.FindOrOpenSellerPayable so that
-- ON CONFLICT (type, owner_type, owner_id, currency) WHERE owner_id IS NOT NULL
-- resolves correctly during concurrent lazy-create races.
-- owner_type = 'user'   → 'liability:wallet:user'    per user per coin currency
-- owner_type = 'seller' → 'liability:payable:seller' per seller per fiat currency
CREATE UNIQUE INDEX IF NOT EXISTS accounts_owner_currency_uq
    ON wallet_schema.accounts(type, owner_type, owner_id, currency)
    WHERE owner_id IS NOT NULL;

-- ── transactions ──────────────────────────────────────────────────────────────
CREATE TABLE wallet_schema.transactions (
    id              BIGSERIAL PRIMARY KEY,
    type            TEXT NOT NULL,
    reference       TEXT,
    fx_pair_id      TEXT,
    idempotency_key TEXT NOT NULL UNIQUE,
    status          TEXT NOT NULL DEFAULT 'posted',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── ledger_entries ────────────────────────────────────────────────────────────
-- Append-only. RULES (42-rules-no-update-delete.sql) block UPDATE/DELETE.
-- DEFERRABLE constraint trigger (41-trigger-d-equals-c.sql) enforces D=C at COMMIT.
CREATE TABLE wallet_schema.ledger_entries (
    id              BIGSERIAL PRIMARY KEY,
    transaction_id  BIGINT NOT NULL REFERENCES wallet_schema.transactions(id),
    account_id      BIGINT NOT NULL REFERENCES wallet_schema.accounts(id),
    direction       CHAR(1) NOT NULL CHECK (direction IN ('D','C')),
    amount_minor    BIGINT NOT NULL CHECK (amount_minor > 0),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX ledger_entries_account_idx ON wallet_schema.ledger_entries(account_id);
CREATE INDEX ledger_entries_txn_idx     ON wallet_schema.ledger_entries(transaction_id);
CREATE INDEX ledger_entries_created_idx ON wallet_schema.ledger_entries(created_at);

-- ── outbox ────────────────────────────────────────────────────────────────────
-- Financial events written here within the SAME DB transaction as the ledger write.
-- A separate outbox-publisher worker drains this to Redis Streams via XADD.
CREATE TABLE wallet_schema.outbox (
    id              BIGSERIAL PRIMARY KEY,
    aggregate       TEXT NOT NULL,
    event_type      TEXT NOT NULL,
    payload         JSONB NOT NULL,
    idempotency_key TEXT NOT NULL UNIQUE,
    trace_id        TEXT,
    span_id         TEXT,
    market          TEXT NOT NULL,
    currency        TEXT NOT NULL,
    published_at    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX outbox_unpublished_idx
    ON wallet_schema.outbox(created_at) WHERE published_at IS NULL;

-- ── balances (materialized view) ─────────────────────────────────────────────
-- Refreshed hourly by balance-mv-refresh worker in fin-svc (Phase 2.1).
-- READ-ONLY for display/reporting. NEVER used for financial decisions (withdrawal
-- critical path uses SELECT ... FOR UPDATE on live ledger_entries per LEDGER_GUIDE § 12).
CREATE MATERIALIZED VIEW wallet_schema.balances AS
  SELECT a.id AS account_id,
         a.currency,
         a.owner_type,
         a.owner_id,
         COALESCE(SUM(CASE WHEN le.direction = 'C' THEN le.amount_minor
                            ELSE -le.amount_minor END), 0) AS balance_minor
  FROM wallet_schema.accounts a
  LEFT JOIN wallet_schema.ledger_entries le ON le.account_id = a.id
  GROUP BY a.id;
CREATE UNIQUE INDEX balances_account_uq ON wallet_schema.balances(account_id);

-- ── ledger_alerts ─────────────────────────────────────────────────────────────
-- Written by ledger-reconcile.sh (LEDGER_GUIDE § 9.2) when per-currency delta ≠ 0.
-- On CRITICAL alert: fin-svc is forced to read-only and on-call is paged via PagerDuty.
CREATE TABLE wallet_schema.ledger_alerts (
    id                 BIGSERIAL PRIMARY KEY,
    severity           TEXT NOT NULL CHECK (severity IN ('CRITICAL','SEV1','SEV2','SEV3')),
    currency           TEXT,                   -- which currency; NULL if cross-currency event
    delta_amount_minor BIGINT,                 -- per-currency delta; NULL if not applicable
    message            TEXT NOT NULL,
    detected_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    acknowledged_at    TIMESTAMPTZ,
    acknowledged_by    TEXT
);
CREATE INDEX ledger_alerts_unack_idx
    ON wallet_schema.ledger_alerts(detected_at) WHERE acknowledged_at IS NULL;
