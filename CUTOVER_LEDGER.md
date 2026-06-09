# CUTOVER_LEDGER.md

> Single source of truth for everything parked while production deploys are deferred (Phase B + C). Nothing here is lost; every item must be reconciled at the eventual cutover. Last updated: 2026-06-08.

---

## 0. Headline state

- **Production is still on the 2026-05-26 build.** Everything from #105 onward is merged to `main` but **not live** (deploys deliberately deferred until after Phase B+C).
- All deploy machinery is fixed and staged; the cutover is a known, rehearsed sequence — see §1.

---

## 1. Deferred production deploy (the staged runway)

**Trigger:** when Phase B+C are done, execute DEPLOY-EXEC-01 (host-prep → backup → dry-run → migrations → deploy → health → purge).

| Step | Detail |
|---|---|
| Host-prep | Add `GHCR_USER` + `GHCR_PAT` (read:packages) to `/etc/mopro/.env` (via the `/opt/mopro/deploy/.env` symlink). |
| Backup | `pg_dump -Fc` ecom + ledger before migrating (tiny DBs). The §3-era backups are stale — re-take fresh at cutover. |
| Dry-run | Dispatch deploy `verify_only=true` (login-only; proves GHCR auth). |
| Migrations | `apply-migration.sh --db ecom up` then `--db ledger up`. Count is large now (ecom 62→0087+, ledger 77→0081) — apply, then deploy promptly (tight window). |
| Deploy | Dispatch `verify_only=false`; #105 fail-fast + image-ID assertion guards a no-op. |
| Health | Re-run the #104 diagnosis; expect GREEN + smoke 5/5. |
| Post-flip purge | RUNBOOK "Post-flip cleanup": stale `mopro/*` images + `bin/*.tar` tarballs (gated on prod confirmed on `ghcr.io/s4l1hs/*`). |

**Rollback (if deploy fails after migrations):** ecom image-only; **ledger leads with `pg_restore`** of the pre-migration dump (0078.down is suspect), `ledger down` secondary. Data covered by the §backup dumps.

---

## 2. TLS / ACME — the Aug-18 hard clock ⏰

- Production TLS cert **hard-expires 2026-08-18**; Caddy auto-renew attempt ~**Jul 19**.
- The #106 ACME resolver fix is **merged but not live** (deploy deferred) → renewal will still SERVFAIL until a deploy lands it.
- **Backstop schedule:** `mopro-cert-renewal-backstop` (Sundays in Jul/Aug, gated 2026-07-19 → 08-17) — reminds + emits an on-host check-prompt.
- **Decision required before ~Jul 19** (one of):
  1. Deploy before the window (lands #106 — cleanest).
  2. One-off host hotfix: add resolvers to the host Caddy config + `caddy validate && docker compose -f docker-compose.prod.yml up -d caddy` (recreate, ~2–5s blip; certs persist).
  3. Accept lapse (only if prod isn't serving — it self-heals at the eventual deploy).

---

## 3. F-019 — reconcile grant (live prod defect, fix pending deploy)

- `reconcile_user` lacked `SELECT` on `event_delivery_attempts` → the weekly reconcile cron throws `42501` + the table grows unbounded.
- **Fixed in #111** (ledger migration 0081 `GRANT SELECT` + init/73 converged) — but the fix only takes effect in prod **when ledger migrations apply at cutover**. Until then the live error + slow growth continue (tolerable pre-launch).
- **Resolves automatically at deploy** (§1 ledger migrations).

---

## 4. PLP-12 — subtree rollup (CONFIRMED-HIGH backend debt)

- `internal/catalog/repository.go:373` scopes products by **exact `category_id`**; no recursive subtree rollup.
- Walk- **and markup-confirmed**: Trendyol browsing a parent category aggregates all nested subcategory products (multi-brand under one category, subcats as filters).
- **Fix:** recursive CTE in `repository.go` (server-side; **no client wrapper**). Not built; tracked here for a dedicated backend PR.
- Canonical ID **PLP-12** (CONFIRMED-HIGH) — see the PLP registry `docs/audits/TRENDYOL_PARITY_PLP_AUDIT.md` §3/§8.

## 4b. PLP-13 — attribute facets (CONFIRMED-HIGH backend debt — DEFER'd)

- Trendyol's deep, **category-aware** attribute stack (storage/RAM/screen/colour/condition/camera…). Mopro has **no normalized attribute/facet model**: only `catalog_schema.variants.color/size` (structured but **not** filter params + sparse) and `catalog_schema.products.specs` (**opaque per-category JSONB**, no facet schema/index). No facet-aggregation (values+counts) surface.
- **Verdict: Outcome C — DEFER** (per the batch discovery). Building JSONB-key faceting on opaque `specs` = a fragile attribute store (anti-goal). The real fix is a **schema/data-modeling track**: a normalized product-attribute model + per-category facet config + an aggregation endpoint (mirror brand/rating) + filter params + accordion UI.
- Not built. Tracked for a dedicated backend design + PR. See `docs/internal/plp-batch.md`.

---

## 4c. PLP-14 — price-history filter ("Fiyat Geçmişi") — DEFER (feasible, design-ready)

- **Feasible** — `catalog_schema.variant_price_history` (0083, indexed) supports a §5-safe `price_dropped` predicate (`EXISTS … vph.price_minor > current`). The P-028 `free_shipping`/`in_stock` params prove the full path.
- **Deferred** as its own **OpenAPI-codegen vertical** (spec `price_dropped` param → `make api-gen` Go+Dart regen → backend WHERE → `PlpFilters`/codec + toggle UI on both surfaces + chip → i18n → tests → 8 `plp_sidebar_*` golden flips). Ready-to-build; not bundled into the multi-track batch to avoid a noisy/partial codegen landing. Design: `docs/internal/plp-14-price-history.md`.

---

## 5. CI / branch-protection

- **F-022b (#138)** made `flutter analyze` green-on-compile (`--no-fatal-infos`; errors/warnings still fatal).
- **Branch-protection PATCH** — the actual gate-close. Required contexts: `verify`, `flutter analyze`, `flutter test`, `build_runner (verify generated files up-to-date)`, `i18n completeness (extras gate)`, `i18n dead-key gate`, `riverpod inference gate`, `dart analyze (mopro_api generated client)`. Status: **[ ] apply** (or **[x] applied <date>**).
- **Rebaseline bot quirk:** `golden-rebaseline.yml` commits with `GITHUB_TOKEN` → won't trigger the now-required checks → PRs ending on a rebaseline commit hang "waiting for status." Mitigation: close/reopen, or switch that workflow to a PAT. **[ ] PAT fix (low priority, more relevant once checks are required).**

---

## 6. DEFER pile (lower priority, no clock)

| Item | Note |
|---|---|
| riverpod 2.x → 3.x migration | Deliberate task; Dependabot now ignores majors. |
| very_good_analysis ~199 analyze infos | Clear over time, then drop `--no-fatal-infos`. |
| mood-strip golden | Needs a network-image mock harness (CachedNetworkImage fires real HttpClient). |
| Footer `about` / `terms` pages | HP-09 DEFER — currently routed to `/help`. |
| Dead legacy columns | `discount_price_minor`, `rating_stars` — API no longer reads them. |
| init vs migration 0078 (`sellers`) | Provisioning-snapshot drift; prod already provisioned. |
| `local-phaseb.sh` orchestrator | Dev tooling, never merged to main. |

---

## 7. Phase B surface progress

| Surface | Status |
|---|---|
| Home | ✅ Parity-complete (IA-01/02, Sprints A/B, closeout #135–#137) within the Deliberately-Lean IA. |
| PLP / category browse | **UI parity ~done** — canonical registry `docs/audits/TRENDYOL_PARITY_PLP_AUDIT.md`. **RESOLVED:** PLP-01/03 (#142), PLP-04/05 (count+breadcrumb), **PLP-15/18/19/20** (numbered pages / sticky sidebar [already-matched] / ultra-wide breakpoints / sticky mobile bar, `feat/plp-layout-closeout`). **DEFER'd (backend):** **PLP-13** attribute facets (§4b), **PLP-12** rollup (§4). **Open CONFIRMED:** PLP-14 price-history (backend), PLP-09 fast-delivery. Remaining = MED/LOW polish + PROBABLE visual items awaiting Salih's live walk (§9). **ID re-map:** contract `PLP-02/05/07` (sticky sidebar / ultra-wide grid / sticky mobile bar) = **PLP-18/19/20**. |
| Search | Pending (inherits PLP grid/filter patterns). |
| PDP | Pending (own walk; may need seed extension: reviews/variants/gallery). |
| Phase C (divergences) | After parity surfaces — coin redeem (deferred), etc. |
