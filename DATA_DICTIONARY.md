# DATA_DICTIONARY.md — Database Boundaries & Schemas

This file defines what data lives where and what code is allowed to read it. Crossing boundaries is forbidden.

## 1. Two Postgres Clusters

| Cluster | Container | Network | Used by |
|---|---|---|---|
| postgres-ecom | `postgres-ecom` | `mopro-net` | core-svc, jobs-svc |
| postgres-ledger | `postgres-ledger` | `mopro-fin-net` | fin-svc only |

NEVER:
- Connect core-svc or jobs-svc to postgres-ledger.
- Connect fin-svc to postgres-ecom.
- Open a TCP path from mopro-net to postgres-ledger.
- Run cross-cluster `dblink` or foreign-data-wrapper queries.

If core-svc needs ledger data: it asks fin-svc via Redis Streams (publish event, listen for response event) or a thin HTTP read API exposed by fin-svc.

## 2. Schema-per-Module Rule

Every module owns ONE Postgres schema. Tables, types, functions belonging to the module live there.

### 2.1 postgres-ecom

| Schema | Owner module | Service binary |
|---|---|---|
| `identity_schema` | identity | core-svc |
| `catalog_schema` | catalog | core-svc |
| `cart_schema` | cart | core-svc |
| `order_schema` | order | core-svc |
| `payment_schema` | payment | core-svc |
| `seller_schema` | seller | core-svc |
| `search_schema` | search | core-svc |
| `notification_schema` | notification | jobs-svc |
| `support_schema` | support | jobs-svc |
| `media_schema` | media | jobs-svc |
| `sizefinder_schema` | sizefinder | jobs-svc |

### 2.2 postgres-ledger

| Schema | Owner module | Service binary |
|---|---|---|
| `wallet_schema` | wallet | fin-svc |
| `commission_schema` | commission | fin-svc |
| `treasury_schema` | treasury | fin-svc |

### 2.3 Schema permissions

```sql
-- One PostgreSQL ROLE per module, with USAGE/SELECT/INSERT/UPDATE/DELETE only on its own schema.
-- INSERT only on append-only ledger; UPDATE/DELETE blocked by RULES (see LEDGER_GUIDE).

REVOKE ALL ON SCHEMA public FROM PUBLIC;

CREATE ROLE identity_user LOGIN PASSWORD 'changeme';
GRANT USAGE ON SCHEMA identity_schema TO identity_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA identity_schema TO identity_user;

-- Repeat per module. Production passwords come from .env via init scripts.
```

## 3. Cross-Schema Query Ban

The most important rule in this file:

> **No SQL JOIN across schemas. No `FROM other_schema.table`. No FOREIGN KEY across schemas.**

### 3.1 Allowed

```sql
-- order code reads its own schema only
SELECT * FROM order_schema.orders WHERE id = $1;
```

### 3.2 Forbidden

```sql
-- ❌ Cross-schema JOIN
SELECT o.*, p.title
FROM order_schema.orders o
JOIN catalog_schema.products p ON p.id = o.product_id;

-- ❌ Cross-schema lookup
SELECT title FROM catalog_schema.products WHERE id = ?
-- (when called from order code)

-- ❌ Cross-schema FK
ALTER TABLE order_schema.orders
    ADD CONSTRAINT fk_product
    FOREIGN KEY (product_id) REFERENCES catalog_schema.products(id);
```

### 3.3 The right way

If `order` needs the product title, it calls `catalog.GetByID(ctx, id)` (in-memory function call inside core-svc), or stores a denormalized snapshot at order creation time.

### 3.4 Enforcement

- `golangci-lint` with `depguard`: `internal/order/*.go` cannot import `internal/catalog/repository`. It can only import `internal/catalog` (the public interface).
- `scripts/check-module-boundaries.sh` greps for `FROM <other>_schema.` patterns in raw SQL files and fails the build.

## 4. PII Handling — AES-GCM Envelope Encryption

### 4.1 PII fields (must be encrypted at rest)

- `identity_schema.users.tc_no` (Türkiye Kimlik No)
- `identity_schema.users.phone_e164`
- `identity_schema.users.email`
- `support_schema.tickets.user_message` (free-text from users)

### 4.2 Mechanism

- A master key (KEK) lives in `.env` (`PII_KEK_BASE64`). Rotated every 90 days.
- Each row gets a fresh 256-bit DEK (data encryption key), AES-GCM, 96-bit nonce.
- Stored format: `<nonce>:<ciphertext>:<dek_encrypted_with_kek>`.
- Hashed lookup column: `<column>_hash = SHA256(value || pepper)`.

### 4.3 Code helper (mandatory)

```go
// /pkg/crypto/pii.go
package crypto

func EncryptPII(kek []byte, plaintext []byte) (string, error) { /* AES-GCM envelope */ }
func DecryptPII(kek []byte, ciphertext string) ([]byte, error) { /* AES-GCM envelope */ }
func HashLookup(value string, pepper []byte) string { /* SHA256(value || pepper) */ }
```

NEVER write plaintext PII to logs. NEVER `SELECT *` PII columns to display.

## 5. Migration Rules

### 5.1 File path

`/migrations/<ecom|ledger>/<NNNN>_<verb>_<noun>.sql`

Numeric prefix is monotonically increasing. Never re-use numbers.

### 5.2 Allowed operations

- `CREATE TABLE`
- `ALTER TABLE ADD COLUMN` (nullable or with DEFAULT that does not require rewrite)
- `CREATE INDEX CONCURRENTLY`
- `CREATE OR REPLACE VIEW`
- `CREATE FUNCTION`
- `INSERT` (seeding reference data only, idempotent with `ON CONFLICT DO NOTHING`)

### 5.3 FORBIDDEN destructive operations

```sql
-- ❌ DROP TABLE
DROP TABLE catalog_schema.deprecated_table;

-- ❌ DROP COLUMN
ALTER TABLE order_schema.orders DROP COLUMN legacy_status;

-- ❌ ALTER COLUMN TYPE (rewrites the table)
ALTER TABLE catalog_schema.products ALTER COLUMN price_minor TYPE BIGINT;

-- ❌ ALTER ... SET NOT NULL on populated table
ALTER TABLE catalog_schema.products ALTER COLUMN brand_id SET NOT NULL;

-- ❌ DROP INDEX without CONCURRENTLY (on production-grade table)
DROP INDEX order_schema.orders_status_idx;

-- ❌ Renames
ALTER TABLE order_schema.orders RENAME COLUMN status TO order_status;
```

### 5.4 Expand-and-Contract

To replace a column without DROP:

1. **Expand:** add the new column. Both writers populate old + new.
2. **Backfill:** a job copies old → new for historical rows.
3. **Switch:** readers read from new. Old column becomes unused.
4. **Contract:** ONLY after ≥ 30 days, with explicit human approval, schedule a `DROP COLUMN` in a staged maintenance window.

The Contract step is OUT OF SCOPE for autonomous agent action. Agents propose, humans execute.

### 5.5 Ledger has STRICTER rules

In `postgres-ledger`:
- NEVER drop or rename anything.
- NEVER alter a column type once it carries production data.
- New tables/columns are append-only.

If a ledger schema change is genuinely needed, write a NEW schema/table in parallel; never mutate existing.

## 6. Seed and Reference Data

Static reference tables (countries, currencies, payment method codes, etc.) are seeded via `/migrations/ecom/seed_*.sql`. These ARE allowed to use `INSERT ... ON CONFLICT DO NOTHING` to be idempotent.

## 7. Backups

Backup behavior is defined in `DISASTER_RECOVERY.md`. Note: a snapshot of `postgres-ecom` is INSUFFICIENT to recover the system. ALWAYS take both clusters together with the same logical timestamp; restic snapshots are atomic per run.

## 8. Quick Reference for Agents

When generating SQL or migrations:

| Question | Answer |
|---|---|
| Which DB? | The one matching the module's binary (see § 1) |
| Which schema? | The one belonging to the module |
| Cross-schema JOIN? | NEVER |
| Drop or rename? | NEVER (use expand-and-contract) |
| Money type? | `BIGINT` minor units |
| PII column? | Encrypted via `crypto.EncryptPII`; add `_hash` column for lookups |
| Idempotency? | UNIQUE constraint on the natural key |
| Index? | `CREATE INDEX CONCURRENTLY` always |
| Connection? | Through PgBouncer; never direct to Postgres |
| FK across schemas? | NEVER |
