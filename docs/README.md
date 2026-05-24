# docs/

Reference documents for Mopro Shop. All architecture and operational decisions live here.

## Architecture Decision Records

| File | Decision |
|---|---|
| `adr/0001-do-instead-nothing-rules.md` | Agent constitution and "do not" rules foundation |
| `adr/0002-per-seller-payable-accounts.md` | Per-seller payable ledger account design |
| `adr/0003-redis-streams-maxlen-policy.md` | Redis Streams retention and MAXLEN policy |

New ADRs go in `adr/` with the next sequential number. Required for: new binary, new
programming language, new database engine, new RPC framework, reference rate change.

## Runbooks

| File | When to use |
|---|---|
| `runbooks/launch-day.md` | Go/no-go checklist and launch sequence |
| `runbooks/disaster-recovery.md` | Full VDS recovery from backup |
| `runbooks/restore-from-backup.md` | Step-by-step restore procedure |
| `runbooks/backup-failure.md` | Responding to a failed backup job |
| `runbooks/disk-pressure.md` | Responding to low disk on the VDS |

## Audit Logs

| File | Contents |
|---|---|
| `dependency-audit-2026-05-24.md` | go mod tidy + govulncheck results, 2026-05-24 |

## PDFs

| File | Contents |
|---|---|
| `Mopro_Shop_PRD_PRODUCTION.pdf` | Product Requirements Document v6.0 |
| `Mopro_Shop_Kisa_Ozet.pdf` | Turkish business summary |
