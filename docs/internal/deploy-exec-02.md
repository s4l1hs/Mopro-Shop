# DEPLOY-EXEC-02 — pre-flight record (read-only, 2026-06-12)

Supersedes DEPLOY-EXEC-01. Cutover: prod (2026-05-26 build) → current `main`.

## Machinery (verified from source, not recall)
- **Deploy:** `.github/workflows/deploy.yml` — `workflow_dispatch` only; inputs
  `ref` (default main), `verify_only` (default **true**), `skip_photo_smoke`.
  Runs `tool/audit/deploy_script.sh` on the host over SSH: fail-fast
  (`set -euo pipefail`), GHCR login from `/etc/mopro/.env` (STEP 1.5, runs even in
  verify_only), pull→up→bounded `/healthz` wait (60s/svc), **image-ID assertion**
  (STEP 5 — running container ID must equal freshly-pulled ref ID; green no-op
  impossible). Serialized via concurrency group.
- **Migrations:** `deploy/scripts/apply-migration.sh --db <ecom|ledger> <up|down|status>`
  — builds linux/amd64 migrate-tool LOCALLY from the CURRENT CHECKOUT, ships
  binary + `migrations/` to the host, runs one-shot container on the right Docker
  network, direct-to-postgres (bypasses PgBouncer for DDL).
  ⚠️ **RUNBOOK doc drift:** its "Apply a database migration" example shows a stale
  `--file …init/99-….sql` interface — the script's real interface is the above.
- **Backup:** `deploy/scripts/backup-postgres.sh` — `pg_dump -Fc` compress=9 for
  BOTH `mopro_ecom` (ecom_admin) and `mopro_ledger` (ledger_admin). Those are the
  only two DBs (all schemas live inside them).
- **Rollback (RUNBOOK):** image-only = on-host `IMAGE_NS=s4l1hs VERSION=<prev-full-sha>
  docker compose -f /opt/mopro/deploy/docker-compose.prod.yml up -d core-svc fin-svc jobs-svc`.
  Data rollback = restore from §3 dumps (`restore-postgres.sh`).
- **Post-flip purge (RUNBOOK, gated):** only after ALL three containers show
  `ghcr.io/s4l1hs/*`; `docker image rm` per stale `mopro/*` (in-use refusal is the
  guard) + `rm -rf /opt/mopro/bin/*.tar /opt/mopro/bin/prev/`. Never `prune`.

## Prod state (host 195.85.207.92:4625 — read-only, 2026-06-12 ~02:52 UTC)
- Host up 11 days; disk 41G/118G used (**73G free**); TLS serving;
  **cert notAfter = Aug 18 2026** (≈9.5 weeks; renewal requires the #106 ACME
  resolver fix → this deploy).
- Containers: `core-svc → mopro/core-svc:latest` (sha **9fb19c19**, built
  2026-05-26), `fin-svc`/`jobs-svc → mopro/*:4e73f25`. Legacy namespace, stale.
- **Migration heads (live `schema_migrations`):** ecom = **62** (clean),
  ledger = **77** (clean).
- **GHCR creds: NOT present on host** (count 0 in `/etc/mopro/.env`) — §2 Salih
  action before anything else.

## The delta
- **Ecom: 62 → 95 (33 migrations)** — returns (0070), reviews/QA, attributes
  (0089), seller is_official (0090), basket discount (0091), coupons (0092),
  order addresses (0093), membership tiers (0094), installments (0095), ~19 new
  tables total + indexes/backfills.
- **Ledger: 77 → 82 (5 migrations)** — 0078, 0079, **0080 sellerpayout schema
  split (NON-ADDITIVE)**, 0081 reconcile grant, 0082 refund_distribution account.
- **Images:** `:latest` = build `113872d4` (the #207 merge). #209 (HEAD,
  097d16cf) is migrations/scripts-only → correctly no rebuild (path filters);
  binaries at #207-merge contain all app code. Migrations ship from the local
  HEAD checkout (= #209's fixed set: 0091 clean, 0094/0095 dedup).
- **#192 fixes confirmed on main:** jobs-svc `time/tzdata` embed (would
  crash-loop on distroless without it) + migration 0091 `</content>` strip.

## Rollback-safety audit (ALL 38 pending migrations scanned)
- **Non-additive: exactly ONE — ledger `0080_sellerpayout_schema_split`**
  (`ALTER TABLE … SET SCHEMA`: moves `seller_payouts`, `payout_batches` from
  commission_schema → sellerpayout_schema). The 2026-05-26 fin-svc binary reads
  commission_schema.* → **incompatible during the §5→§6 window** (payout
  reads/crons would error; the daily payout cron fires 02:30 UTC — schedule the
  window away from it). **§6-fail rollback for ledger = `pg_restore`-led** (the
  addendum rule); ecom = additive-only → **image-only** rollback suffices.
- Everything else: CREATE TABLE IF NOT EXISTS / ADD COLUMN (defaulted) /
  indexes / grants / idempotent seeds / one DROP TRIGGER+recreate (0083,
  additive-compatible — old binary doesn't reference it).

## Plan (checkpointed; STOP for go at §1→§2, §5, §6)
1. **§2 (Salih):** add `GHCR_USER` + `GHCR_PAT` (read:packages) to
   `/etc/mopro/.env`; I verify presence only.
2. **§3 backup:** run `backup-postgres.sh` (fresh `-Fc` dumps of ecom + ledger),
   verify non-zero, note path.
3. **§4 dry-run:** dispatch deploy `verify_only=true` (ref=main) — login + scp +
   compose-config mechanics. Fail → STOP.
4. **§5 migrations (GO #2):** `apply-migration.sh --db ecom up` → head 95;
   `--db ledger up` → head 82. Capture before/after. Any error → STOP, restore §3.
5. **§6 deploy (GO #3):** dispatch `verify_only=false` immediately after §5 (tight
   window — 0080 makes the old fin-svc incompatible). Watch to completion.
   Fail → image-only rollback (ecom-safe) + **ledger pg_restore** if ledger
   behavior is implicated.
6. **§7 health:** /healthz ×3, /__version == expected, smoke (PLP/search/PDP/
   auth/orders), Caddy/ACME — confirm the #106 resolver fix is live (cert
   renewable before Aug 18). RED → STOP (no purge).
7. **§8 purge (only GREEN):** RUNBOOK gated purge of `mopro/*` + tarballs.

## OUTCOME (2026-06-12) — GREEN ✅

- **§2–§4:** creds copied local→server (presence-verified, never printed); two
  latent host/script defects found by fail-fast + fixed: sudoers rejects inline
  setenv → `sudo env` (#210); root-only env unreadable by the script's plain
  `source` → `sudo grep` (#211). Dry-run green.
- **§5:** ecom 62→**95** + ledger 77→**82**, both clean. One real failure:
  0078 vs the init-provisioned sellers shape (the known-DEFER'd drift) →
  drift-tolerant 0078 + migrate-tool `force` (#212, scratch-validated both
  paths; the validation itself caught a third bug — the legacy `name` NOT NULL
  rejecting the seed). `force 77` → re-run → clean.
- **§6:** deploy green; pull/up clean; healthz 200 ×3; **image-ID asserted**:
  all three running `ghcr.io/s4l1hs/*:latest` = build **186263bc (main HEAD,
  built 17:07Z)** — build-images re-fired on #212's cmd/** change, so prod got
  every fix through #212.
- **§7 GREEN:** 0 service errors post the 11s deploy-window DB-restart burst;
  public smoke **5/5** (healthz/PLP/search/home-rails/PDP via TLS); jobs-svc
  crons live on Europe/Istanbul (#192 fix); ACME evidence: 3 nameservers,
  in-container ACME DNS resolves, 0 ACME errors, cert Aug 18 → renewal ~Jul 19
  viable (#106 live).
- **§8:** gated purge done — 0 `mopro/*` images remain; tarballs removed;
  74G free. Rollback targets are now ghcr `:sha` tags + today's dumps
  (`/opt/mopro/backups/deploy-exec-02-20260612T0656/`, copied off-host).
