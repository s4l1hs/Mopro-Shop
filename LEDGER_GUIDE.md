# LEDGER_GUIDE.md — Financial Code Rules

> **WARNING:** Code in this domain controls real seller money. A bug here is not a UX issue — it is a business-ending event. Treat every change with paranoia.

## 1. Mental Model

Mopro Coin uses **double-entry accounting**, append-only, denominated in TRY-pegged minor units (`amount_minor BIGINT`).

Every transaction touches at least two accounts: one debited (D), one credited (C). The sum of debits within a transaction MUST equal the sum of credits. Violations are blocked at the database level by a `DEFERRABLE INITIALLY DEFERRED` constraint trigger.

## 2. Chart of Accounts

| Account name | Type | Owner | Purpose |
|---|---|---|---|
| `asset:bank:escrow` | asset | platform | Real TRY in PSP/escrow account |
| `liability:platform_pool` | liability | platform | Commission pool owed to sellers |
| `liability:wallet:seller_<id>` | liability | seller | Seller's Mopro Coin wallet |
| `liability:bank_outbound` | liability | platform | Withdrawals reserved but not yet paid |
| `equity:retained_float_income` | equity | platform | Float yield reclassified to company income |

Currency is always `TRY_COIN`. Multi-currency is out of scope.

## 3. Schema (postgres-ledger / wallet_schema)

```sql
CREATE SCHEMA wallet_schema AUTHORIZATION wallet_user;

CREATE TABLE wallet_schema.accounts (
    id          BIGSERIAL PRIMARY KEY,
    type        TEXT NOT NULL,
    owner_type  TEXT,
    owner_id    BIGINT,
    currency    TEXT NOT NULL DEFAULT 'TRY_COIN',
    status      TEXT NOT NULL DEFAULT 'active',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE wallet_schema.transactions (
    id              BIGSERIAL PRIMARY KEY,
    type            TEXT NOT NULL,
    reference       TEXT,
    idempotency_key TEXT NOT NULL UNIQUE,
    status          TEXT NOT NULL DEFAULT 'posted',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

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

-- Append-only enforcement
CREATE RULE no_update_ledger AS
    ON UPDATE TO wallet_schema.ledger_entries DO INSTEAD NOTHING;
CREATE RULE no_delete_ledger AS
    ON DELETE FROM wallet_schema.ledger_entries DO INSTEAD NOTHING;
CREATE RULE no_update_transactions AS
    ON UPDATE TO wallet_schema.transactions DO INSTEAD NOTHING;
CREATE RULE no_delete_transactions AS
    ON DELETE FROM wallet_schema.transactions DO INSTEAD NOTHING;
```

## 4. Transaction-Level D=C Trigger

```sql
CREATE OR REPLACE FUNCTION wallet_schema.enforce_double_entry()
RETURNS TRIGGER AS $$
DECLARE
    debit_total  BIGINT;
    credit_total BIGINT;
BEGIN
    SELECT
        COALESCE(SUM(amount_minor) FILTER (WHERE direction='D'), 0),
        COALESCE(SUM(amount_minor) FILTER (WHERE direction='C'), 0)
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

CREATE CONSTRAINT TRIGGER ledger_balance_check
AFTER INSERT ON wallet_schema.ledger_entries
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION wallet_schema.enforce_double_entry();
```

### 4.1 How `DEFERRABLE INITIALLY DEFERRED` works

Within a transaction you can `INSERT` multiple `ledger_entries` rows that temporarily violate the invariant; the trigger evaluates **at COMMIT**. If the invariant holds at commit, the transaction commits. If not, the WHOLE transaction is rolled back.

This means agent code MUST insert all D and C rows for a transaction inside a single SQL transaction. Splitting across SQL transactions = guaranteed ROLLBACK at commit time.

## 5. Outbox Table (Same DB as Ledger)

```sql
CREATE TABLE wallet_schema.outbox (
    id              BIGSERIAL PRIMARY KEY,
    aggregate       TEXT NOT NULL,
    event_type      TEXT NOT NULL,
    payload         JSONB NOT NULL,
    idempotency_key TEXT NOT NULL UNIQUE,
    trace_id        TEXT,
    span_id         TEXT,
    published_at    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX outbox_unpublished_idx
    ON wallet_schema.outbox(created_at) WHERE published_at IS NULL;
```

## 6. Mandatory Write Pattern

EVERY ledger-touching code path MUST follow this template:

```go
func (s *walletService) Apply(ctx context.Context, in Input) error {
    // 1. Validate
    if in.IdempotencyKey == "" { return ErrIdempotencyKeyRequired }
    if in.AmountMinor <= 0    { return ErrInvalidAmount }

    // 2. Single SQL tx with SERIALIZABLE
    return s.repo.WithTx(ctx, sql.LevelSerializable, func(tx *sql.Tx) error {
        // 2a. Insert transaction (UNIQUE on idempotency_key handles double-apply)
        txnID, err := s.repo.InsertTransaction(ctx, tx, ledger.Transaction{
            Type:           in.Type,
            Reference:      in.Reference,
            IdempotencyKey: in.IdempotencyKey,
        })
        if errors.Is(err, ledger.ErrDuplicateIdempotency) {
            return nil // idempotent no-op
        }
        if err != nil { return err }

        // 2b. Insert all D and C entries (BOTH MUST BE PRESENT)
        for _, e := range in.Entries {
            if err := s.repo.InsertEntry(ctx, tx, ledger.Entry{
                TransactionID: txnID,
                AccountID:     e.AccountID,
                Direction:     e.Direction,
                AmountMinor:   e.AmountMinor,
            }); err != nil { return err }
        }

        // 2c. Insert outbox row in SAME tx
        return s.outbox.Insert(ctx, tx, outbox.Row{
            Aggregate:      in.Aggregate,
            EventType:      in.EventType,
            Payload:        marshal(in),
            IdempotencyKey: in.IdempotencyKey,
            TraceID:        traceIDFromCtx(ctx),
            SpanID:         spanIDFromCtx(ctx),
        })
        // Trigger validates D=C at COMMIT. If invalid: full rollback.
    })
}
```

### 6.1 FORBIDDEN patterns

```go
// ❌ Single-direction write
db.Exec("INSERT INTO ledger_entries ...")  // only D, no C — will rollback

// ❌ Update existing entry
db.Exec("UPDATE ledger_entries SET amount_minor = ?")  // rule blocks

// ❌ Float for money
type BadEntry struct { Amount float64 }  // ALWAYS BIGINT

// ❌ Skipping idempotency
if err := repo.Insert(...); err != nil { /* ignore */ }

// ❌ Direct Redis publish without outbox
redis.XAdd(ctx, &redis.XAddArgs{Stream: "fin.wallet.credited.v1", ...})

// ❌ Splitting across SQL transactions
tx1 := beginTx(); writeD(tx1); tx1.Commit()
tx2 := beginTx(); writeC(tx2); tx2.Commit()  // first commit will rollback
```

## 7. Reversal — the only correction mechanism

To undo transaction `T_orig`:
- Create `T_reversal` with `type='reversal'`, `reference=T_orig.id`, fresh idempotency key.
- For each original entry, write the OPPOSITE direction with the same amount.
- Sum stays balanced; original entries remain in place; audit trail preserved.

NEVER edit `T_orig`. NEVER delete `T_orig`.

## 8. Continuous Reconciliation (Three Layers)

### 8.1 Transaction-level (every commit)

The trigger above. Already running. DO NOT disable, DO NOT mark `DEFERRABLE INITIALLY IMMEDIATE`.

### 8.2 Hourly full reconcile

`/opt/mopro/scripts/ledger-reconcile.sh`, cron `5 * * * *`:

```bash
#!/usr/bin/env bash
set -euo pipefail

DIFF=$(docker exec postgres-ledger psql -U ledger_admin -d mopro_ledger -tAc \
  "SELECT COALESCE(SUM(CASE WHEN direction='D' THEN amount_minor ELSE -amount_minor END), 0)
   FROM wallet_schema.ledger_entries")

if [ "$DIFF" -ne "0" ]; then
    docker exec postgres-ledger psql -U ledger_admin -d mopro_ledger -c \
      "INSERT INTO wallet_schema.ledger_alerts(severity, message, detected_at)
       VALUES ('CRITICAL', 'Sum D-C != 0 (delta=$DIFF)', now())"

    curl -X POST "$PAGERDUTY_API" -H "Content-Type: application/json" \
      -d "{\"event_action\":\"trigger\",\"payload\":{\"summary\":\"LEDGER INVARIANT VIOLATION delta=$DIFF\",\"severity\":\"critical\"}}"

    docker exec fin-svc /app/app set-read-only --reason "ledger-invariant"
fi

curl -sf "https://hc-ping.com/$HEALTHCHECK_LEDGER_RECONCILE_UUID"
```

When the hourly reconcile sees a delta ≠ 0, fin-svc is forced into read-only and on-call is paged. No new financial writes happen until a human signs off.

### 8.3 Daily audit

A daily job exports per-account balances + treasury bank movements to `/opt/mopro/audit/<date>.csv`. The accountant compares against bank statements.

## 9. Property-Based Tests Are Mandatory

Every change to `wallet`, `commission`, or `treasury` MUST include or extend property-based tests using `github.com/leanovate/gopter`.

The single property to never break:

> **For any random sequence of valid operations, after applying them all, `Sum(D) - Sum(C) = 0`.**

See `PROMPTS.md` § 6 for the test skeleton.

## 10. Common Failure Modes

| Symptom | Likely cause | Action |
|---|---|---|
| `Double-entry violation` exception | Forgot a C for a D, or amounts mismatch | Fix the code; add a property test reproducing the case |
| Hourly reconcile delta ≠ 0 | Outbox replay applied wrong, schema bypass via raw SQL | Page on-call; fin-svc to read-only; investigate |
| Outbox unpublished count growing | Worker crashed or Redis Streams down | `mopro outbox replay --since "1 hour ago"` |
| `ErrDuplicateIdempotency` | Same operation retried | Treat as success; do nothing |

## 11. Wallet Read API Rules

- Reading a wallet balance MUST query the materialized view (or compute from ledger_entries on the fly).
- Withdraw flow: query balance with `SELECT ... FOR UPDATE` on a row representing the seller wallet within the SAME transaction that creates the withdraw `transactions` record. This serializes concurrent withdraws.
- Cache balances in Redis with TTL ≤ 10 seconds for read endpoints. NEVER cache for the withdrawal critical path.

## 12. mopro CLI Commands

```bash
mopro outbox list [--aggregate <name>] [--unpublished]
mopro outbox replay <event_id>
mopro outbox replay --since "2 hours ago" --dry-run

mopro saga inspect <order_id>
mopro saga timeline <order_id>

mopro ledger reconcile --dry-run
mopro ledger reconcile --confirm
mopro ledger lock-account <id> --reason "<text>"
mopro ledger unlock-account <id>
```

The CLI is the ONLY supported way to do operator interventions. Direct SQL on production ledger is prohibited.
