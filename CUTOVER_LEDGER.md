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
| Migrations | `apply-migration.sh --db ecom up` then `--db ledger up`. Count is large now (ecom 62→0088+, ledger 77→0081) — apply, then deploy promptly (tight window). |
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

## 4. PLP-12 — subtree rollup — ✅ RESOLVED (`feat/plp-subtree-rollup`)

- ~~`repository.go` scoped products by exact `category_id`~~ → **`ListProductsByCategory` now scopes via a `WITH RECURSIVE` subtree over `ref_schema.categories`** (parent_id walk): a parent aggregates all descendant products, a leaf resolves to itself. §5-safe (ref_schema is the cross-module-readable exception). Migration **0088** + init snapshot add `categories_parent_id_idx`. Integration test (parent→child→grandchild) + live-verified (root-elektronik 0→31, leaf elektr-kea 28).
- **Deploy note:** migration 0088 lands at the §1 cutover (`apply-migration.sh --db ecom up`); the index is additive (`IF NOT EXISTS`).

## 4b. PLP-13 — attribute facets — ✅ PHASE 1 COMPLETE for `renk` (user loop closed)

- **Phase 1, PR 1 (foundation) — landed:** migration **0089** creates the normalized model `attribute_keys` / `category_facets` / `product_attributes` (catalog_schema, §5-safe; aggregation + per-product indexes; fixed `renk` key). The per-product backfill is a **dev seed** `scripts/seed/data/attr-extras.sql` (migrations run pre-seed in dev) — normalizes `variants.color` → `product_attributes(renk)` + enables `category_facets(renk)` wherever colour exists. Migration-safe, idempotent, **live-verified** (product 15 → {Beyaz, Lacivert, Siyah}; category buckets aggregate). In prod the backfill runs as a one-off data step at cutover.
- **PR 2 (read-path) — landed (`feat/plp-13-readpath`):** `GET /categories/{id}/facets` (subtree aggregation — the first facet endpoint) + `attr=<slug>:<value>` filter (PLP + search) + `Product.attributes` + Go/Dart codegen + integration + live-handler contract tests.
- **PR 3 (PDP specs) — landed (`feat/plp-13-pdp-specs`):** the PDP specs tab renders `Product.attributes` (`_SpecsTab`, mobile + desktop; `_StubTab` gone) → **PD-01 resolved for the `renk` slice** + a specs-tab widget test + i18n.
- **PR 4 (FilterPanel accordion) — landed (`feat/plp-13-filterpanel-facet`):** `FilterPanel` renders a server-driven `renk` accordion (`PlpAttributeFacet`, mirror `PlpBrandFacet`, value+count, gated on `currentCategoryId>0` → **search inherits, category-gated**) + `PlpFilters.attrs` (Map<slug,values>) + codec round-trip (`attr_<slug>=…`) + `toggleAttr` + `attributeFacetsProvider` + `filteredProductsProvider` threads `attr` + removable chips. **No new i18n** (facet name/values are server-localized) + a codec/toggle/render test. **Phase-1 user loop is now closed for `renk`** (filter on PLP + search + PDP specs). `depolama`/other attrs + Phase 2/3 deferred per #149. Phase-1 plan: `docs/internal/plp-13-p1.md`; PR-4 discovery: `docs/internal/plp-13-pr4.md`.
- Protected by the gen-sync drift gate (§5) + the #158 live-handler contract test.

### (original design context — retained)

- Trendyol's deep, **category-aware** attribute stack (storage/RAM/screen/colour/condition/camera…). Mopro has **no normalized attribute/facet model**: only `catalog_schema.variants.color/size` (structured but **not** filter params + sparse) and `catalog_schema.products.specs` (**opaque per-category JSONB**, no facet schema/index). No facet-aggregation (values+counts) surface.
- **Verdict: Outcome C — DEFER** (per the batch discovery). Building JSONB-key faceting on opaque `specs` = a fragile attribute store (anti-goal). The real fix is a **schema/data-modeling track**: a normalized product-attribute model + per-category facet config + an aggregation endpoint (mirror brand/rating) + filter params + accordion UI.
- **Design (Track D) ready:** `docs/internal/plp-13-attribute-model.md` — `attribute_keys` / `category_facets` / `product_attributes` (catalog_schema, §5-safe), a brand/rating-style facet aggregation, accordion UI reusing `PlpBrandFacet`, and a **4-phase plan**. Even Phase 1 (schema + backfill `renk`/`depolama` + one facet + UI) is a full vertical → each phase is its own scoped PR. Build DEFER'd.

---

## 4c. PLP-14 — price-history filter ("Fiyatı düşenler") — ✅ RESOLVED (`feat/catalog-backend-vertical`, PR 2)

- **Built** as the OpenAPI-codegen vertical: `price_dropped` boolean param on `listProducts`+`search` → `ProductFilter.PriceDropped` → §5-safe `EXISTS` over `catalog_schema.variant_price_history` (0083, index-served `vph.price_minor > v.price_minor` within 30d) → `make api-gen` Go+Dart regen → `PlpFilters.priceDropped` + codec (`drop=down`) + `FilterPanel` & `PlpFilterSheet` toggle + removable chip + i18n (`plp.filter_price_dropped`/`plp.filter_price_history`).
- **Tests:** `TestIntegration_PriceDroppedFilter` (backend, fresh-PG), filter-wiring + codec/model round-trips (Dart). 15 generated-client fakes updated for the new method param.
- **Goldens:** `plp_sidebar_*` + `search_sidebar_*` flip (a new sidebar toggle row) — **not regenerated locally** (anti-goal); the Linux golden-rebaseline job rebaselines on the PR. Design: `docs/internal/plp-14-price-history.md`.

## 4d. SE-08 / SE-03 — search relevance + result count — ✅ RESOLVED (`feat/catalog-backend-vertical`, PR 1)

- **SE-08** — `SearchProductsSummary` now ranks by `ts_rank(search_vector, plainto_tsquery('simple', q))` for the default (`recommended`) sort via `appendSearchOrderBy`; explicit sort tokens (price/newest/cashback) and bestseller `PopularIDs` still win. Backend-only — relevance is the implicit default, so **no contract/token change, no codegen**. Reuses the 0057 GIN `search_vector` + the already-bound `$1` query (no new index/placeholder). Integration test `TestIntegration_SearchRelevance`. Discovery: `docs/internal/be-vert.md`.
- **SE-03** — already satisfied: the `Search` 200 envelope returns `pagination.total` (required `PaginationMeta`, populated by `handleSearch`→`buildProductListResponse`). No backend change; the search UI (Session 1) reads it.

## 4e. PD-06 — PDP read-path conformance + contract guard — ✅ RESOLVED (`fix/pdp-readpath-contract`)

- **PD-06** — `GET /products/{id}` returned a legacy `{product, variants, translations, cashback_preview, delivery_eta}` envelope with variant `image_keys`/`cover_image_url`, matching neither the OpenAPI flat `Product` (variants[] = `Variant`, `image_urls` required) nor the generated mobile client (also flat) — so the strict parse failed and the PDP never rendered end-to-end (the walk was blocked). The handler now emits the flat spec `Product`: top-level `id/seller_*/category_id/brand/status/created_at`, locale-resolved `title`/`description` (drops the unused `translations` array), and each `Variant` with **`image_urls`** = `image_keys` mapped through `mediaurl.CDNUrl`. **No codegen** (spec + client already flat).
- **Contract guard (the systemic catch):** the F-021 test (`internal/api`) is fixture-only and never calls a handler — which is why PD-06 shipped. Added a **live-handler conformance test** (`cmd/core-svc/contract_test.go`, `//go:build contract`): calls the real handler, `VisitJSON`s the response against the `Product` schema (+ guards `image_urls` present / no envelope leak). Extended `make contract-test` + `openapi-ci.yml` to run it. Discovery: `docs/internal/pdp-readpath.md`.
- **PD-07 (DEFER → scoped follow-up):** reviews return no reviewer name or photos. Plan: add `reviewer_name` (`identity.Service.GetUser`, masked) + `photos` (`attachments.Service.ListByEntity`, CDN-mapped) to the reviews response — spec + codegen, §5-safe (in-process service calls, no cross-schema JOIN) — render in `PdpReviewsTab`, + a reviews conformance test. Its own codegen+UI vertical (per §5 split-bailout: PD-06 first, PD-07 second).

---

## 5. CI / branch-protection

- **F-022b (#138)** made `flutter analyze` green-on-compile (`--no-fatal-infos`; errors/warnings still fatal).
- **Branch-protection PATCH** — the actual gate-close. Required contexts: `verify`, `flutter analyze`, `flutter test`, `build_runner (verify generated files up-to-date)`, `i18n completeness (extras gate)`, `i18n dead-key gate`, `riverpod inference gate`, `dart analyze (mopro_api generated client)`. Status: **[ ] apply** (or **[x] applied <date>**).
- **Rebaseline bot quirk — ✅ FIXED (`chore/ci-cleanup`):** `golden-rebaseline.yml` now checks out with `token: ${{ secrets.GOLDEN_REBASELINE_PAT }}`, so its re-baseline push is authenticated as the PAT and **fires the required checks** (a `GITHUB_TOKEN` push does not — GitHub's recursion guard — which is what hung golden PRs). **One-time secret setup for Salih** (fine-grained PAT, repo `contents:write`): `gh secret set GOLDEN_REBASELINE_PAT --repo s4l1hs/Mopro-Shop --body '<PAT>'`. Until the secret is added the workflow has no token to push with.
- **Vuln scanner consolidated — ✅ (`chore/ci-cleanup`):** `govulncheck.yml` and `security-scan.yml` ran the identical `govulncheck ./...` scan. Merged to one canonical scanner: `govulncheck.yml` now triggers on **push:[main] + path-filtered PR + weekly + dispatch** (fail-on-vuln exit-3 unchanged); `security-scan.yml` deleted. Required context `govulncheck ./...` unchanged.
- **Stale PLP-14 toggle goldens — ✅ re-baselined (`chore/ci-cleanup`):** the `golden-rebaseline` workflow regenerated the 9 `*_sidebar_*` baselines (#153 added the price-drop toggle row but left them un-rebaselined). Only `*_sidebar_*` flipped. (Also unblocked a main red: 2 search-UI test fakes missing the `priceDropped` param — `search_ports_test`/`search_recovery_test` — threaded through.)
- **Codegen-drift gate — ✅ closed (`fix/mopro-api-gen-sync`):** the `build_runner (verify generated files up-to-date)` job ran build_runner only with `working-directory: mobile` (the app) → the **`mopro_api` path-dependency package's `.g.dart` was never regenerated/checked** and drifted. Live impact: `product_summary.g.dart` dropped `isBestseller`/`basketDiscountPct` deserialization, so the shipped "Çok Satan" stamp + "Sepette %X" pill **silently didn't render on the real API path** (widget tests bypass `fromJson`). Regenerated 2 stale files (product_summary + delivery_eta), added a package `build_runner` + `git diff --exit-code` step to the same job, and a `ProductSummary.fromJson` regression test. Required context name unchanged. Protects the upcoming PLP-13/17 codegen verticals. See `docs/internal/gen-sync.md`.

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
| PLP-16 bestseller rank (backend-surface) | Rank exists in `analytics_schema.popular_products`; surface as `ProductSummary.bestseller_rank` (handler app-merge, §5-safe) + spec/codegen + ranked card badge ("Çok Satan N"). Own task. |
| PLP-09 fast-delivery flag (backend) | No `fast_delivery`/delivery-SLA column or API param — add the flag first, then a badge/filter. |
| PLP-17 official-seller flag (backend) | No seller `is_official`/verified flag — add it, then the "Resmi satıcı" badge. |

---

## 7. Phase B surface progress

| Surface | Status |
|---|---|
| Home | ✅ Parity-complete (IA-01/02, Sprints A/B, closeout #135–#137) within the Deliberately-Lean IA. |
| PLP / category browse | **UI parity ~done** — canonical registry `docs/audits/TRENDYOL_PARITY_PLP_AUDIT.md`. **RESOLVED:** PLP-01/03 (#142), PLP-04/05 (count+breadcrumb), **PLP-15/18/19/20** (numbered pages / sticky sidebar [already-matched] / ultra-wide breakpoints / sticky mobile bar, `feat/plp-layout-closeout`). **DEFER'd (backend):** **PLP-13** attribute facets (§4b), **PLP-12** rollup (§4). **Open CONFIRMED:** PLP-14 price-history (backend), PLP-09 fast-delivery. Remaining = MED/LOW polish + PROBABLE visual items awaiting Salih's live walk (§9). **ID re-map:** contract `PLP-02/05/07` (sticky sidebar / ultra-wide grid / sticky mobile bar) = **PLP-18/19/20**. |
| Search | Pending (inherits PLP grid/filter patterns). |
| PDP | Pending (own walk; may need seed extension: reviews/variants/gallery). |
| Phase C (divergences) | After parity surfaces — coin redeem (deferred), etc. |
