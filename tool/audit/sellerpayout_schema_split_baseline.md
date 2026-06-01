# Audit — Sellerpayout Schema Split

Read-only baseline. Closes the PR #8 boundaries-guard exemption that let
`internal/sellerpayout/` read `commission_schema` by relocating the
sellerpayout-domain tables into a new `sellerpayout_schema`.

## Branch-point
- Stacked on `feat/recommendation-surfaces` (the open recommendation PR #35;
  `main` is still at #30, so "branch from main" per the prompt would conflict on
  the governing docs the stack edits). Decision: stack + full-correct scope
  (both confirmed with the owner).
- `make boundaries` baseline = `boundaries OK`. `go test ./...` green;
  sellerpayout unit + integration (real ledger DB :6434) green; 3 binaries build.

## §2.1 Tables to relocate (all exclusively sellerpayout-owned)

| Table | Readers / writers | Verdict |
|---|---|---|
| `seller_payouts` | `internal/sellerpayout` + `internal/e2e` (tests) + `reconcile_user` SELECT grant | **move** |
| `payout_batches` | `internal/sellerpayout` only | **move** |
| `seller_psp_accounts` | `internal/sellerpayout` only | **move** |
| `capture_postings` | commission-owned; sellerpayout reads via `commission.CaptureRecorder` in-process seam (no direct SQL) | **stays** in `commission_schema` |

No shared-ownership ambiguity; nothing outside `internal/sellerpayout/` reads or
writes the three tables directly. `internal/reconcile` has **no** Go references —
only the `reconcile_user` SELECT grant on `seller_payouts`.

Attached objects that travel with / around the move:
- Indexes on all three tables (follow the table automatically on `SET SCHEMA`).
- `BIGSERIAL` sequences (follow automatically).
- Immutable trigger `seller_payout_immutable_trg` on `seller_payouts` (follows
  the table) **but** its function `commission_schema.enforce_payout_immutable()`
  does **not** — functions need an explicit `ALTER FUNCTION … SET SCHEMA`.
- FK `seller_payouts.batch_id → payout_batches(id)` — both move together; the FK
  stays valid (constraint binds the table OID, not the qualified name). Becomes
  an intra-`sellerpayout_schema` FK.

## §2.2 Application-code references

`internal/sellerpayout/` — all refs are to the three moving tables (so **zero**
`commission_schema` refs remain after the move → boundary is genuinely clean):

| File | `commission_schema.` refs |
|---|---|
| `repository.go` | 13 |
| `domain.go` | 3 |
| `service.go` | 1 |
| `sellerpayout_integration_test.go` | 14 (test DDL + queries) |
| `sellerpayout_cron_property_test.go` | 7 |

Exact breakdown (non-test): 8× `seller_payouts`, 7× `payout_batches`,
2× `seller_psp_accounts`. No outside-module references anywhere in `internal/`
or `cmd/`.

## §2.3 Boundaries guard (`scripts/check-module-boundaries.sh`)

Three distinct spots reference this — all must change (the prompt implies one):

1. **`commission_schema` regression guard** — exempt list includes
   `^internal/sellerpayout/` with the comment "owns seller_payouts … consider
   splitting into sellerpayout_schema in a future refactor." → remove the
   sellerpayout exemption.
2. **Generic cross-schema `FROM` check** — `SCHEMAS` var lacks `sellerpayout`;
   path-exempt list already allows the `sellerpayout` module dir. → add
   `sellerpayout` to `SCHEMAS` so the new schema is guarded for everyone, with
   the sellerpayout module dir remaining the only allowed reader.
3. **Immutable-UPDATE guard** — regex `UPDATE\s+commission_schema\.seller_payouts`
   → retarget to `sellerpayout_schema.seller_payouts`.

`make boundaries` is the check command (`scripts/check-module-boundaries.sh`).

## §2.4 Schema source of truth — dual (key finding)

The ledger schema is built two ways:
- **Fresh DBs:** `deploy/postgres-ledger/init/*.sql` (numeric order; the guard
  calls this "schema source of truth").
- **Deployed DBs:** `migrations/ledger/NNNN_*.{up,down}.sql`. Latest = `0079` →
  this PR is **`0080`**.

A migration alone leaves fresh containers building the OLD schema. Both must
change in lockstep. Init files touched:

| File | Change |
|---|---|
| `20-schemas.sql` | add `CREATE SCHEMA sellerpayout_schema AUTHORIZATION sellerpayout_user` |
| `60-seller-payout-schema.sql` | `seller_payouts` DDL + indexes → `sellerpayout_schema` |
| `61-seller-payout-immutable-trigger.sql` | function + trigger → `sellerpayout_schema` |
| `62-payout-batches.sql` | `payout_batches` DDL + indexes → `sellerpayout_schema` |
| `63-seller-payouts-batch-id.sql` | ALTER + FK (both sides now `sellerpayout_schema`) |
| `64-seller-psp-accounts.sql` | `seller_psp_accounts` DDL + index → `sellerpayout_schema` |
| `30-grants.sql` | sellerpayout_user: drop commission_schema DML, add sellerpayout_schema USAGE+DML+default-privs; commission_user unchanged |
| `66-sellerpayout-grants.sql` | payout_batches + seller_psp_accounts grants + sequences → `sellerpayout_schema` |
| `69-reconcile-grants.sql` | reconcile_user seller_payouts SELECT + schema USAGE → `sellerpayout_schema` |
| `10-roles.sql` | comment-only (role purpose text) |

`65-ledger-alerts-batch-patch.sql` — **no change** (only patches
`wallet_schema.ledger_alerts` with a plain BIGINT `batch_id` soft ref; its
comment merely mentions payout_batches).

Runtime note: fin-svc connects with a single `LEDGER_DATABASE_URL` pool (+ a
separate reconcile pool); per-role grants are prod-hardening / defence-in-depth,
not the dev connection — so grant edits won't break the dev runtime, but are
updated for correctness.

## §2.5 Governing-doc references (reverses a documented decision)

This is **not** mere "historical naming" — it reverses a recorded decision:
- `DATA_DICTIONARY.md §2.2` table: `commission_schema | commission + sellerpayout`
  → split into a new `sellerpayout_schema | sellerpayout` row + trim the
  commission row.
- `DATA_DICTIONARY.md §9` ("Seller Payout Schema Tables … / commission_schema")
  + the immutability rules (lines ~399/419/420) → retarget to
  `sellerpayout_schema`.
- `CLAUDE.md §5` line 214 "commission_schema (seller payouts here)" → state the
  new boundary.
- Init headers in `60`/`61` cite "DATA_DICTIONARY.md §2.2 (not a separate
  schema)" → update.

The boundaries-guard comment itself anticipated the split, so intent is
established; owner confirmed amending `DATA_DICTIONARY` (beyond the prompt's §6
list) is in scope.

## Migration / down / round-trip plan (§3)

- **0080.up:** `CREATE SCHEMA sellerpayout_schema`; `ALTER TABLE … SET SCHEMA` ×3;
  `ALTER FUNCTION commission_schema.enforce_payout_immutable() SET SCHEMA
  sellerpayout_schema`; `GRANT USAGE ON SCHEMA sellerpayout_schema` to
  sellerpayout_user + reconcile_user (+ commission_user not needed). Table-level
  grants persist with the table objects.
- **0080.down:** reverse `SET SCHEMA` ×3 + function back to commission_schema;
  `DROP SCHEMA sellerpayout_schema`.
- Round-trip: up → (seed via integration test) → down → re-up clean.

## No parity change
Operational/architectural cleanup. No endpoints, no DTOs, no user surface, no
parity movement.
