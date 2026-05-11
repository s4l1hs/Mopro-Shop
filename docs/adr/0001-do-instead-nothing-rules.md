# ADR 0001: Append-Only Enforcement via DO INSTEAD NOTHING

- **Status:** Accepted
- **Date:** 2026-05-11
- **Phase introduced:** Phase 0 (Prompt 0.3)
- **Decided by:** Mopro architecture
- **Related:** LEDGER_GUIDE.md § 3, DATA_DICTIONARY.md § 5.5

## Context
Append-only enforcement on `wallet_schema.ledger_entries` and `wallet_schema.transactions` is a core financial invariant: ledger rows must never be UPDATEd or DELETEd. PostgreSQL offers two ways to enforce this: (a) `CREATE RULE ... DO INSTEAD NOTHING` (silently discards the operation) or (b) a BEFORE trigger that `RAISE EXCEPTION`s.

LEDGER_GUIDE.md § 3 specifies DO INSTEAD NOTHING verbatim.

## Decision
Use DO INSTEAD NOTHING (4 RULES total: ledger_entries × {UPDATE,DELETE}, transactions × {UPDATE,DELETE}).

## Consequences

### Positive
- Spec-verbatim implementation; lowest deviation from documented design
- Simple PG-native primitive; no PL/pgSQL function to maintain
- Negligible performance overhead (rule rewrite happens at parse time)

### Negative
- Silent rejection: a misdirected UPDATE returns success status with 0 rows affected. Application code might interpret this as a successful write
- Auditors will see no error log entry on attempted invalid writes
- Debugging accidental UPDATE attempts requires close attention to rows-affected counts in code review

### Mitigations
- No application code path issues UPDATE/DELETE on these tables (depguard rules + code review)
- Hourly per-currency reconcile (LEDGER_GUIDE.md § 9.2) catches any actual ledger corruption regardless of how it occurred
- Property-based tests (DEVELOPMENT.md § 7.2) verify no random sequence of valid operations breaks the invariant

## Alternatives Considered
1. **BEFORE trigger with RAISE EXCEPTION** — rejected because spec is explicit on DO INSTEAD NOTHING; revisit at Phase 6 audit prep when explicit failure feedback may be required
2. **REVOKE UPDATE/DELETE on the role** — rejected because module roles need INSERT and SELECT, and granular column/operation revocation patterns conflict with ALTER DEFAULT PRIVILEGES seeding

## Revisit
Phase 6 (audit preparation). If external auditors require explicit-rejection feedback, replace with BEFORE triggers raising sqlstate 25000 (read-only transaction) or a custom errcode.
