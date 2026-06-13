# Contributing to Mopro Shop

## Pre-requisites

- Go 1.25+
- Docker + Docker Compose (for `make run-local`)
- `golangci-lint` — `go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest`
- `govulncheck` — `go install golang.org/x/vuln/cmd/govulncheck@latest`

## Local setup

```bash
make bootstrap   # .env + go mod download + git hooks + flutter pub get
make verify      # full gate (needs Docker for the integration suites)
```

`make bootstrap` (→ `scripts/bootstrap.sh`) is idempotent and repo-local — no
sudo, no system packages. It **detects** but does not install toolchains
(Go / Flutter / Docker), and does not fill secrets in `.env`; it lists
those as remaining manual steps in its summary. See `docs/internal/bootstrap.md`.

### Git hooks (`.githooks/`)

`make hooks` runs `tool/setup-hooks.sh`, which sets `core.hooksPath = .githooks`
and makes the hook scripts executable. After this, three hooks are active:

- **`pre-commit`** — refuses commits when `HEAD` is `main`/`master` (added after
  the Session 4a turn produced an orphan commit on local `main`), then runs the
  api-gen sync check (fails if `api/openapi.yaml` is staged but the generated
  Go + Dart files aren't).
- **`prepare-commit-msg`** — same protected-branch guard, fired earlier so
  editors that bypass `pre-commit` still surface the error.
- **`pre-push`** — runs `make verify` (gofmt + vet + race tests + golangci-lint
  + module boundary checks + property tests). Skips can be bypassed with
  `git push --no-verify` for emergencies only.

The legacy `scripts/install-hooks.sh` writes to `.git/hooks/`, which `git`
ignores once `core.hooksPath` is set. The `.githooks/pre-push` above preserves
its behavior; no need to run both.

CI safety net: `.github/workflows/branch-guard.yml` refuses any PR whose source
branch is `main` or `master` — protects against the same foot-gun at the
remote layer.

### Convention: echo `pwd` before chained `git` operations

Any multi-step shell command that chains `git` operations (especially `git
checkout`, `git branch`, `git reset`, or anything creating files in the working
tree) MUST run `echo "pwd=$(pwd)"` as its first step. Rationale: Session 4b
created an empty `mobile/.githooks/pre-commit` because the agent's cwd had
drifted into `mobile/` mid-chain — the `.githooks/pre-commit` empty-file guard
catches the result, but knowing `pwd` upfront catches the cause.

This is a documented convention, not a code check today. TODO: a future session
may add `tool/lint-shell.sh` that scans long-form scripts in the repo for
multi-`git` chains without a `pwd` echo.

## Core rules

Before writing any code, read **CLAUDE.md** fully. It is the constitution.
Key points that trips contributors:

1. No microservices. Three binaries only. New binary = ADR + explicit approval.
2. No floats for money. Integer minor units (`BIGINT`) everywhere.
3. `core-svc` ↔ `fin-svc`: Redis Streams only. No HTTP, no shared DB.
4. Every financial write uses the outbox pattern.
5. Never modify an existing cashback plan or seller payout. Reversals only.
6. Never hardcode `TRY`, `TR`, commission percentages, or locale strings.

## Development workflow

```bash
make help                    # list all developer-facing make targets
make run-local               # start all services
make verify                  # full verification suite (must pass before PR)
```

`make verify` runs: `gofmt`, `go vet`, `go test -race ./...`, `golangci-lint run`,
`./scripts/check-module-boundaries.sh`, and property tests.

## Tooling audit cadence

Tooling work follows the same **audit-then-build** shape as the testing arc (the read-only
`TESTING_AUDIT.md` → focused fix PRs #58–#61): a read-only audit lands first, then build PRs
act on its findings by ID.

- **`docs/audits/TOOLING_AUDIT.md` is the source of truth** for what tooling to build and in what
  order. Read its §6 "Recommended build sequence" before proposing a new script, workflow, or
  analyzer — the gap may already be scoped (or may already exist; the audit lists what's
  EXISTS-FINE so we don't rebuild it).
- **Build PRs reference the `T-ID`** they close (e.g. `feat/i18n-deadkey-analyzer (closes
  TOOLING_AUDIT T-001)`), one finding per commit, mirroring the F-ID discipline.
- **Honest-zero is allowed.** A category with no gap is written up as `VERIFIED-COMPLETE` with the
  `git grep`/`ls`/`make -n` command that proves it — don't manufacture findings to look thorough
  (the PR #56 lesson). New gaps discovered while building are added to the audit, not silently fixed.
- **Re-verify at PR time.** A finding is only as good as its evidence on the current branch; the
  Step-3 audit caught two from-memory false positives (rollback, golden-diff) by reading the code.

## Architecture audit cadence

Architecture/modularity work follows the same **audit-then-refactor** shape (Step 4).

- **`docs/audits/ARCHITECTURE_AUDIT.md` is the source of truth** for refactor work. Read its §6
  "Recommended refactor sequence" before proposing a structural change — the issue may already be
  scoped, or the area may be VERIFIED-COMPLETE (don't "fix" a gated-clean boundary).
- **Refactor PRs reference the `A-ID`** they close (e.g. `feat/payment-test-adapter (closes
  ARCHITECTURE_AUDIT A-001)`).
- **Honest-zero is allowed** (§1.3): a clean category is `VERIFIED-COMPLETE` with the
  `go list -deps`/`git grep` command that proves it — don't pad.
- **First-read architecture intuitions are recall-prone** (§2.3): trace BOUNDARY/TANGLED findings
  with `go list -deps`/`git grep`, not memory; a MISSING-ABSTRACTION is only real if a useful test
  would exist against the proposed interface. The arc has caught such misreads twice (#59→#60, #71→#72).

## Parity audit cadence

UI/UX parity work (Step 5) follows the same **audit-then-build** shape — adapted for visual evidence.

- **`docs/audits/TRENDYOL_PARITY_AUDIT.md` is the source of truth** for what to build. Read its §6
  "Recommended parity-PR sequence" before proposing a UI change — the surface may already be
  `VERIFIED-COMPLETE` (don't re-skin a surface that already matches; e.g. design tokens and the
  auth-gate are done — don't "systematize" them again).
- **Parity PRs reference the `P-ID`** they close (e.g. `feat/pdp-delivery-eta (closes
  TRENDYOL_PARITY_AUDIT P-007)`).
- **CONFIRMED needs visual evidence on BOTH sides** (§2.1): a widget read (`file:line`) or golden
  *and* a Trendyol fetch/screenshot. Mopro-read-only + Trendyol-from-memory = the gap is **PROBABLE**,
  not CONFIRMED — even when the Mopro side is certain.
- **Visual audits are the most recall-prone** (§2.5): "I remember Trendyol has X" → fetch the page;
  "Mopro probably looks like Y" → read the widget; "a golden probably exists" → `ls .../goldens/`.
  This audit already caught the prompt's own false sample finding (a "missing" sticky buy box that
  exists) by reading, not trusting recall.
- **Trendyol is a dated snapshot, not gospel** (§2.4): the audit records Trendyol as of its fetch
  date. Build against that snapshot; if Trendyol changes dramatically, that's a follow-up audit.
- **Intentional divergences are documented, not closed as gaps** (§1.3/§10): Mopro's cashback model
  (Mopro Coin where Trendyol shows discounts, no discount-tier nav, wallet/seller-transparency
  surfaces) is a product decision — see the audit's "Intentional divergences" section. Don't file
  these as parity gaps.
- **Coverage-constrained is an honest outcome** (§12): when Trendyol bot-blocks a surface (403 on
  `/sr`, PDP, login-gated pages), the finding is PROBABLE and gets re-confirmed in its build PR's
  discovery phase. Don't manufacture CONFIRMED gaps to look thorough.
- **Honest-zero applies**: a surface that already matches is `VERIFIED-COMPLETE` with the
  widget/golden evidence that proves it — no padding.

## Commit conventions

Follow conventional commits: `feat:`, `fix:`, `chore:`, `docs:`, `test:`, `refactor:`.

Examples:
- `feat(cashback): add partial-refund CLI command`
- `fix(idempotency): handle Redis Nil on first request`
- `chore(deps): bump x/crypto to patch CVE-XXXX`

## Pull request checklist

- [ ] `make verify` passes locally
- [ ] No new `//nolint:` directives without a comment explaining why
- [ ] No `go.mod` changes without justification in the PR description
- [ ] No new migration files — if you need schema changes, create a new migration file
  and never modify an existing one that has been applied to any environment
- [ ] Financial changes: run `go test -tags=integration -run Property ./internal/...`
  and verify all property tests pass

## Merging & branch protection

`main` requires a set of status checks (incl. `verify`, `build_runner (verify
generated files up-to-date)`, `Generated files in sync`, `flutter test`). Admin
override exists (`enforce_admins=false`) **only as an escape hatch for confirmed
infra flakes** — a runner that died, a transient network/registry failure, a known
upstream outage.

**NEVER override a red `verify`/`gofmt`, `build_runner`/gen-sync, or `flutter
test`.** These are **deterministic**: red means the branch is wrong (unformatted
code, stale generated `.g.dart`, a failing test), not that the runner is flaky.
Overriding them lands broken code on `main`. This actually happened across
#217/#218/#221/#223 (stale `.g.dart` + a gofmt misalignment merged over red
required checks) — see `docs/internal/main-drift-forensics.md`. If a required check
is red, **fix the branch**; if you genuinely believe it is a flake, re-run it and
get a second opinion before any override.

### Mandatory post-batch main-green check

After **any wave of parallel-lane merges**, immediately verify `main` on a clean
checkout of `origin/main`:

```bash
make verify
( cd mobile/packages/mopro_api && dart run build_runner build --delete-conflicting-outputs ) && git status --short  # must be EMPTY
gofmt -l .   # must be EMPTY
```

Two lanes can each be green alone yet break `main` when combined — a *combined-test*
interaction (precedent #208) or a *combined-codegen / gofmt* drift (precedent
#217/#218/#221/#223). Red here means a cross-lane interaction: **fix forward
immediately**, never leave `main` red. Coordinate migration version numbers and
codegen-touching lanes across parallel branches (only one lane regenerates at a
time; the second to merge rebases + regenerates).

## Module boundary enforcement

`./scripts/check-module-boundaries.sh` verifies that:
- `internal/identity|catalog|cart|order|payment|seller|search` do not import `fin-svc` internals
- `internal/wallet|commission|treasury|cashback|sellerpayout` do not import `core-svc` internals
- No direct imports of `*/repository` outside the owning module

`golangci-lint` (depguard rules in `.golangci.yml`) enforces the same rules at lint time.

### Discipline analyzers (`make lint-discipline`)

`make lint-discipline` (in `make verify`) runs `cmd/lint-discipline`, a go/analysis
multichecker that gates the repo-discipline patterns Steps 1–2 enforced by hand:
**pool-acquire-inside-tx** (a `*pgxpool.Pool` call while a tx is open — PR #42/#47) and
**soft-deleted-user-consumer** (a `*Repository` user read with no `StatusDeleted` guard —
PR #49). Both are at 0 findings, so the gate fails on any *new* violation. Suppress an
intentional case with `//nolint:soft-deleted-user-consumer`. See `docs/internal/lint-discipline.md`.

### Relocating tables across schemas to fix a boundary debt

When a table lives in the "wrong" schema and the boundaries guard carries an
exemption for it, the workflow to pay down that debt is:

1. Audit which tables genuinely belong to the destination domain (some may
   legitimately live where they are — confirm ownership by who reads/writes
   them, not by name).
2. Write an `ALTER TABLE … SET SCHEMA` migration with a reversible `.down.sql`.
   Make it **idempotent** (guarded `IF EXISTS` moves) when the same DB also runs
   the init scripts — the test harness applies init **and** migrations to a
   fresh DB, so the migration must no-op once the init already builds the new
   layout. Remember the trigger **function** does not travel with the table on
   `SET SCHEMA` — relocate it with `ALTER FUNCTION … SET SCHEMA`.
3. Update the **dual** schema source of truth in lockstep: the migration (for
   deployed DBs) **and** `deploy/postgres-ledger/init/` (for fresh DBs), plus
   the per-role grants (the new schema needs `USAGE` granted; table-level grants
   persist with the table object across `SET SCHEMA`).
4. Update application SQL references + any governing-doc decision that pinned the
   old location (`CLAUDE.md`, `DATA_DICTIONARY.md`).
5. Update the boundaries guard to enforce the new boundary and smoke-test it by
   injecting a violation and confirming it fires.

Cross-schema foreign keys can stay when they cross between domains owned by the
same migration namespace; cross-schema reads from application code go through
interface seams (per PR #8's commission/orderledger `CaptureRecorder` pattern).

Precedent: `chore/sellerpayout-schema-split`.

## Photo upload integration pattern

Photo uploads are a **two-phase commit**: (1) `POST /uploads/photos` validates +
stores the bytes and returns an orphan attachment row (`entity_id = NULL`); (2)
the entity submission endpoint (review POST, return POST) accepts `photo_ids` and
atomically attaches them inside its transaction (ownership-scoped, orphan-state
+ per-entity-limit checked). Orphans older than 24h are deleted by a cleanup job
(Backlog). Form abandonment is clean — abandoned uploads disappear within the
window.

Server-side validation **never trusts the client `Content-Type`** — MIME is
determined by magic-number sniffing (`http.DetectContentType`); dimensions by
decoding the image header; size is capped before any storage write. Moderation +
virus-scan are documented placeholder no-ops at the upload path; integrations
slot in there without changing the upload contract.

Storage is S3-compatible (`internal/storage`, B2 in prod / MinIO in dev) behind
`STORAGE_ENABLED`. **Placement:** consumer-UGC photos for core-svc entities live
in `internal/attachments` (core-svc, owns `attachments_schema`) — NOT
`internal/media` (jobs-svc-only per CLAUDE.md §2.3, the product-image-resize
pipeline). When a new upload concern appears, match the module to the binary that
owns the entity, and give it its own schema (the boundary script keys on
module↔schema). Precedent + rationale: ADR-0004.

## Two-phase commit for cross-entity attachments

Broader than photos: when an entity (review, return, support ticket) must
reference data uploaded *before the entity exists*, use two-phase commit —
(1) upload to an orphan table keyed by the uploading user, (2) atomically attach
via the entity's submission endpoint (verify ownership + unattached state inside
the tx), (3) clean up orphans on a schedule. The pattern survives form
abandonment and avoids dangling references. Attach happens via the owning
module's repository inside the submission tx (a `pgx.Tx` is threaded in), never a
cross-schema write from the consumer module.

## Role-gated routes via redirect + snackbar

Routes gated by a user role (seller, admin, moderator, …) follow one shape: a
`go_router` `redirect` callback reads the role provider via `ref`, returns the
redirect target when the user lacks the role, and sets a one-shot
`pendingSnackbarProvider` (an i18n key) that an app-root listener shows once via
`rootNavigatorKey` then clears (mirrors `sessionRevokedProvider`).

The role provider **derives from `currentUserProvider`** — auth state is the
source of truth; role bindings are facts about that state, never their own
network call. Keep the gate decision in a **pure function**
(`computeXRedirect(location, hasRole, roleKnown)`) so it's unit-testable, and
**defer while the role is still loading** (`roleKnown == false` → return null) so
a legitimate user isn't bounced mid-`/me`-fetch; add `currentUserProvider` to the
router's `refreshListenable` so the deferred gate re-runs on resolve.

Precedent: `feat/seller-dashboard-ui` — `userIsSellerProvider` +
`computeSellerRedirect` gate the `/seller/*` panel; non-sellers get
`seller.access_denied`. Future role surfaces follow the same shape.

## Runtime DOM mutation for Flutter web head content

Flutter web ships as an SPA; per-route head content (titles, meta tags, JSON-LD)
is set at runtime via DOM mutation rather than build-time templating. Modern
crawlers execute JavaScript and pick up the updates; the trade-off (JS-less
crawlers see only the initial `web/index.html` shell) is documented per-PR.

Services follow a consistent shape: an abstract interface with `setX(...)`
methods, behind a **conditional import** (`import 'x_noop.dart' if
(dart.library.html) 'x_web.dart'`) so the web build gets a `package:web`
(not deprecated `dart:html`) DOM impl and every other target (mobile, desktop,
VM tests) gets a no-op. The web impl is **idempotent** (update existing tags in
place, create when absent) and **fails closed** — a DOM error never propagates to
the user surface (try/catch + optional dev log). Keep the input→tags mapping in a
**pure function** so it's unit-testable without a DOM; the per-route invocation is
tested by overriding the service provider with a recorder.

Precedent: Tranche 5b `MetaTagsService` + `StructuredDataService`, applied via the
`SeoHead` wrapper in a post-frame callback (never blocks first paint).

## Backend-served paths that bypass the Flutter router

Some routes are served entirely by the backend without entering Flutter's router:
`/sitemap.xml`, `/robots.txt`, OAuth callbacks, raw asset proxies. When adding
such routes, verify the Flutter web `go_router` config doesn't catch them — they
should fall through to the backend / static asset serving (Caddy routes the path
prefix to the service before the SPA loads). The verification is a backend
integration smoke test that fetches the route and asserts the content type;
frontend-side, confirm `go_router` has no matching entry (only the `errorBuilder`
would see it, and these never reach the SPA in production).

Precedent: Tranche 5b sitemap + robots (core-svc handlers; the web origin is
injected via `WEB_BASE_URL`, and a Caddy route to core-svc exposes them at the
public origin — a deploy config item).

## Generated DTOs are source-of-truth

When frontend code needs a field that exists conceptually in the backend but is
absent from the generated DTO, the fix is in the OpenAPI spec + codegen regen,
never by hand-editing generated code. Hand-edits get clobbered on the next regen
and create invisible drift between the spec and the actual DTO.

The workflow: (1) add or change the field in `api/openapi.yaml`, (2) update the
backend handler to populate it, (3) run codegen, (4) commit the regenerated files
alongside the spec change. CI's `api-check-sync` gate catches missed
regenerations.

Codegen has **two** stages — miss either and the field won't (de)serialize:
- `make api-gen` — `oapi-codegen` (Go types under `internal/api/gen/`) +
  `openapi-generator` via Docker (Dart `*.dart` models with `@JsonKey`
  annotations under `mobile/packages/mopro_api/`).
- `dart run build_runner build` in `mobile/packages/mopro_api/` — regenerates the
  `*.g.dart` files that hold the actual `fromJson`/`toJson`. The Dart `.dart`
  model alone only declares the field; the `.g.dart` is what serializes it.
  CI's flutter-ci `build_runner` job fails if these are stale.

Precedent: Tranche 5a left a documented carry because `Product.sellerSlug` was
needed for PDP→storefront navigation but absent from the generated DTO; the
`chore/seller-slug-in-product-dto` PR closes it via spec + regen rather than
hand-edit. That same regen surfaced a latent `build_runner` miss
(`product_summary.g.dart` lacked `flash_price_minor` serialization) — exactly the
drift this gate exists to prevent.

## Adding a new dependency

1. Check if it already exists in `go.mod`.
2. If not, evaluate: is there a stdlib equivalent? Is the licence compatible (Apache 2 / MIT)?
3. Add with `go get <module>@<version>` and `go mod tidy`.
4. Run `govulncheck ./...` to verify no new vulnerabilities are introduced.
5. Justify the new dependency in the PR description.

## Financial code

> **Source of truth:** `docs/internal/financial-core.md` consolidates the 7
> financial-path conventions (SERIALIZABLE retry, pool-acquire-inside-tx,
> soft-deleted-user-consumer, idempotency, outbox, rate-limiter zset-member, soft
> refs) with code sketches, gating, and a PR-time review checklist. Read it once.

Any change to cashback calculation, seller payout, or ledger entries requires:

1. Reading `LEDGER_GUIDE.md` and `CLAUDE.md §4` fully.
2. Property tests in `*_property_test.go` covering the invariants.
3. Explicit review from the platform engineering lead.

Do **not** change:
- `internal/cashback/calculator.go` formula without a new constitution version.
- `reference_interest_rate_bps` on existing plans.
- The 3-business-day delay for cashback or seller payout.

## Goldens (Flutter)

Flutter goldens render differently per platform (fonts/subpixel), so this repo
**baselines them on Linux** — the same `ubuntu-latest` the `flutter test` CI
gate runs on. macOS-generated goldens will not match CI.

A platform guard (`mobile/test/_support/golden_platform.dart`, installed via
`mobile/test/flutter_test_config.dart`) stamps every golden with a
`<name>.png.meta` sidecar recording its platform. When you run goldens on a
platform that doesn't match a golden's sidecar, the test fails with a clear
message pointing here — instead of a cryptic pixel diff.

To (re-)baseline goldens:

- **Preferred — CI:** open the **Actions** tab → **golden-rebaseline** → **Run
  workflow** on your branch. It runs `flutter test --update-goldens` on
  `ubuntu-latest`, writes the `.png` + `.png.meta` files, and commits them back
  to the branch.
- **Local (Linux only):** `make update-goldens`.

Do **not** commit macOS-generated goldens. New golden tests are added without a
baseline; trigger the workflow to produce it.

## Adding a Notifier (Riverpod)

A `Notifier` / `AsyncNotifier` / `FamilyNotifier`'s `build()` runs **before the
notifier is mounted**, so mutating `state` from inside `build()` — directly or
via a helper — throws `Bad state: Tried to read the state of an uninitialized
provider` on the very first read. Every notifier `build()` must match one of
these three safe shapes:

1. **Return a const/default state; mutate only in event handlers.**
   ```dart
   SearchState build() => const SearchState();
   void setQuery(String q) => state = state.copyWith(query: q); // later, fine
   ```
2. **Defer the initial fetch with `Future.microtask`** (runs after `build()`
   returns and the notifier is mounted).
   ```dart
   CartState build() { Future.microtask(_load); return const CartState(); }
   ```
3. **Touch `state` only after the first `await`** in the loader you call.
   ```dart
   Future<void> _load() async {
     final api = ref.read(apiProvider);   // no state write yet
     final r = await api.fetch();          // first await
     state = AsyncData(r.data);            // safe — mounted by now
   }
   ```

**Synchronous-reachability rule:** no `state` mutation may be reachable
*synchronously* from `build()` before its first `await` — **including via helpers
called with `unawaited(...)` or inside `Future.wait([...])`. Both invoke the
function synchronously up to its first `await`**, so a pre-`await` `state =` in
that helper still runs during `build()`. Only `Future.microtask` (shape 2) or
returning state and waiting for an event (shape 1) actually defers.

The full audit that produced this taxonomy is recorded in `REPORT.md` §8.8
(Session 5a notifier sweep).

## Writing a Regression Test

**A regression test must fail when the original buggy code is restored.** If you
revert the fix and the test still passes, the test isn't guarding the
regression — it's documenting some unrelated behavior. Always confirm by
reverting the fix locally and watching the test go red before you commit.

Example: `mobile/test/features/catalog/products_by_category_provider_test.dart`
(PR #15) asserts the first read builds without throwing and resolves to data; it
was verified to throw the "uninitialized provider" `StateError` when the
`Future.microtask` deferral is reverted — proving it guards the build-time
state-mutation bug rather than passing vacuously.

## URL state

When mirroring widget state into the URL, **do not clear query parameters with
`Uri.replace(queryParameters: null)` — it is a no-op in Dart** (a null
`queryParameters` means "leave unchanged", so the existing query is kept). This
shipped as a real bug in Session 5b: clearing all PLP filters never cleared the
URL.

To clear the query, navigate to the bare path (`context.go(uri.path)`) or use the
safe helper `uri.clearQueryParameters()` from `lib/core/utils/uri_ext.dart`
(`Uri.replace(queryParameters: const {})`). The extension prevents the recurrence
by API shape; `test/core/utils/uri_ext_test.dart` includes a contrast test
asserting the `null` form does NOT clear.

## Storage-layer idempotency

Several domains now follow this pattern (cashback `payments_made`, reviews
`helpful_count`, and Q&A `answer_count`). The reviews write-side adds a second
flavour of storage-layer idempotency: the `product_reviews (product_id, user_id)`
unique constraint guarantees one review per user per product, so a concurrent or
retried submit surfaces as a 23505 mapped to `ErrReviewExists` (the HTTP layer
returns 409 + the existing review id) rather than a duplicate row.

1. A junction table with `PRIMARY KEY (parent_id, user_id)` (or equivalent
   composite key) catches concurrent inserts at the database via 23505
   unique-constraint violation.
2. A denormalized count column on the parent table, refreshed inside the same
   SERIALIZABLE transaction as the junction-table write. Doc comment on the column
   flags it as "denormalized cache, do not treat as authoritative."
3. A `Refresh<Domain>Cache` function with a doc comment naming the junction table
   as authoritative.
4. A concurrent-write integration test that asserts N goroutines converge to the
   expected row count.
5. A property test that asserts the cache column matches `COUNT(*)` across a random
   sequence of operations.

Implementations: `internal/cashback/RefreshPaymentsMadeCache`,
`internal/catalog/RefreshHelpfulCountCache`, and (Q&A) `internal/catalog`'s
`InsertAnswerAndRefresh` (refreshes `product_questions.answer_count` in the same
tx as the answer insert; covered by `TestProperty_AnswerCountMatchesRows` +
`TestIntegration_ConcurrentReviewConverges`). The unique-constraint flavour lives
in `internal/catalog`'s `InsertReview` (23505 → `ErrReviewExists`). Add new domains
to this list as they land.

## Append-only event log + derived projections

Source-of-truth events live in an append-only table (`analytics_schema.analytics_events`);
reads are served from derived **projection** tables (`user_recently_viewed`, and
future `user_search_history` / affinity). Projections refresh incrementally on
ingest (the cheap path — upsert inside the ingest write) plus a periodic full
rebuild safety net (jobs-svc cron) that backstops drift. Same denormalized-cache
discipline as `helpful_count` / `answer_count`: refresh as close to the producing
write as practical; the cron rebuild is the backstop, not the primary path.

Raw events are bounded by a retention prune (90 days); projections persist (and
are user-erasable for RTBF). The log is never UPDATEd — the only deletes are the
retention prune and per-user erasure.

Cross-schema soft references: `analytics_events.user_id` / `user_recently_viewed.*`
are plain BIGINT columns with **no** FK to `identity_schema.users` /
`catalog_schema.products` (same convention as `inbox_schema.notifications.user_id`,
`product_questions.user_id`). Integrity is enforced at the application layer;
account-deletion erasure is wired explicitly (a `DELETE /me` handler hook), not via
`ON DELETE CASCADE` — which would not fire anyway, since `DELETE /me` is a soft delete.

Implementation: `internal/analytics` (shared by core-svc ingest + jobs-svc
crons), Tranche 4a.

## Source-tagged recommendations + daily projection rebuild

Recommendation surfaces (home "Senin için seçtiklerimiz" rail, PDP "Benzer
ürünler" rail) read two derived projections in `analytics_schema`:
`popular_products` (global view-count ranking) and `product_co_views`
(co-occurrence). Unlike `user_recently_viewed` — which refreshes **incrementally
on ingest** — these are **truncate-and-rebuild** projections: a single jobs-svc
cron (05:00 Europe/Istanbul, alongside the prune/rebuild crons) recomputes both
from scratch each day (`RefreshRecommendations`). Co-occurrence has no cheap
incremental form, and recs tolerate up-to-24h staleness, so a full daily rebuild
is the right cost trade — no on-ingest path. The co-view rebuild is a
self-join over a session/time window; it carries a 30-min context timeout.

`product_id` columns are **plain BIGINT soft references** (no cross-schema FK),
same convention as the rest of `analytics_schema`. Reads return **ranked IDs
only**; the HTTP handler hydrates them via `catalog.ListProductsByIDs`
(read→hydrate, order-preserving) — never a cross-schema JOIN. Per-category
popularity is **deliberately not built**: the product→category map lives in
`catalog_schema`, which the jobs-svc refresh cannot read; the `scope` column is
retained for that future tier (Backlog) and the PDP fallback is therefore
co-view → global-popular.

**Source tagging:** recommendation responses carry a `source` field so the
client picks the right presentation without re-deriving server logic — home is
`"personalized"` (co-view over the user's recently-viewed seeds, for an
authed+consented user with history) or `"popular"` (the fallback for guests,
non-consenting users, and cold-start); the PDP is `"co_view"` or `"popular"`.
The fallback chain lives **server-side** (the handler decides + tags); the
client only reads the tag. Combined with defensive layering (below), a sparse
co-view table or a fetch error degrades to popularity or an empty (hidden) rail,
never an error.

Implementation: `internal/analytics` (refresh + reads) + the
`/recommendations/home` and `/products/{id}/similar` handlers
(`feat/recommendation-surfaces`).

## Build-flag gating for legal-review surfaces

Production surfaces that depend on legal review (privacy copy, consent flows,
regulatory disclaimers) ship behind a build-time constant defaulting to
dev/staging-on, prod-configurable-off; the flag is the gate, and legal sign-off
triggers the prod-default flip in a focused follow-up PR (which also removes any
`DRAFT`-suffixed files). When the flag is off the surface must fully no-op (no
render, no network). Tracked in REPORT.md "Pending legal review".

Precedent: `kAnalyticsConsentEnabled` (`lib/core/feature_flags.dart`, Tranche
4a/4b) gates the analytics consent banner + settings + the instrumentation layer.

## Seller storefront + role-gated dashboard (Tranche 5a)

Seller surfaces span three modules without widening their core interfaces:

- **Separate read interfaces, not `Service` widening.** Storefront reads live on
  `catalog.SellerStorefrontReader` and seller-side returns on
  `order.ReturnService` — distinct from `catalog.Service` / `order.Service` so
  existing mocks don't churn (same rationale as the Tranche 3 UGC interfaces and
  the checkout-session repo). Prefer a new narrow interface over a method on a
  widely-mocked one.
- **Cross-schema stays soft + JOIN-free.** `products.seller_id` (catalog_schema)
  and `seller_users.user_id` (seller_schema) are plain BIGINT soft references —
  **no** FK (same convention as `analytics_events.user_id`,
  `product_questions.user_id`). Seller-scoped reads/writes get the seller's
  product-id set from catalog, then scope **within** order_schema
  (`ReturnProductIDs` ∩ `sellerProductIDs`); there is no cross-schema JOIN.
- **Never trust the path id for seller writes.** `SellerApprove`/`SellerReject`
  verify the target return references one of the caller's products and return
  `ErrReturnNotOwned` (mapped to 404, not 403, so a seller can't probe another
  seller's return ids) before the pending-state guard. The `seller_id` comes from
  `RequireSellerRole` (ctx), never the request body.
- **is_seller is computed at answer time**, in the handler, from
  `seller.ResolveSellerForUser(user)` ∩ `catalog.ProductSellerID(question→product)`
  — not stored on the user. The service layer just threads `AnswerInput.IsSeller`.

Mobile: the storefront products tab reuses the shared `buildProductSummaryJSON`
shape, so it hits the **same cashback field-name trap** as the recently-viewed
rail — the wire key is `cashback_preview.monthly_amount_minor` but the generated
`ProductSummary.fromJson` expects `monthly_coin_minor`. Map explicitly
(`sellerProductFromApi`); do **not** call `ProductSummary.fromJson` on these
hand-written endpoints. The generated `Product`/`ProductSummary` models carry
`sellerId`/`sellerName` but **no slug**, so PDP→storefront deep-linking needs the
slug added to the product-detail payload (an OpenAPI codegen change) — carried.

## PostgreSQL serialization retries

`SERIALIZABLE` isolation can return `40001` (`serialization_failure`) when
transactions conflict. This is normal under contention, not an error condition —
the application is expected to retry. The reviews `ToggleHelpfulVote`
implementation uses a savepoint + retry loop. If a third domain needs this pattern,
extract `WithRetryOnSerialization(ctx, tx, fn, maxRetries int)` into
`internal/shared/db` rather than copy the loop again. Tracked as backlog.

## Formatting

The `require_trailing_commas` lint and `dart format`'s output disagree on
multi-argument calls when the line would fit without a trailing comma. Hand-format
the trailing comma in — do not rely on `dart format` to add it. Pre-commit hook
does not auto-fix this; CI lint catches it.

## Project patterns (index)

These are "the project's way" — established across 2+ implementations and
expected in new work. The full system inventory and gap analysis live in
[`SYSTEM_AUDIT.md`](SYSTEM_AUDIT.md).

- [Storage-layer idempotency](#storage-layer-idempotency)
- [Append-only event log + derived projections](#append-only-event-log--derived-projections)
- [Source-tagged recommendations + daily projection rebuild](#source-tagged-recommendations--daily-projection-rebuild)
- [PostgreSQL serialization retries](#postgresql-serialization-retries)
- [URL state](#url-state)
- [Adding a Notifier (Riverpod)](#adding-a-notifier-riverpod)
- [Writing a Regression Test](#writing-a-regression-test)
- [Goldens (Flutter)](#goldens-flutter)
- [Formatting](#formatting)
- [Audit-before-code](#audit-before-code)
- [Adaptive presenter](#adaptive-presenter)
$1
- [Module placement decisions](#module-placement-decisions)
- [Goldens on authed state](#goldens-on-authed-state)
- [Background polling vs. on-demand refresh](#background-polling-vs-on-demand-refresh)

## Audit-before-code

Before changing a surface that spans many files, **inventory it first** and post
the baseline, then change against that baseline. This has paid off repeatedly:
the PDP component extraction measured the widget tree before splitting it, the
account two-pane PR audited every `go_router` route before adding the shell, and
the A11y sweep built an audit harness + baseline before fixing a single label.
`SYSTEM_AUDIT.md` and the `tool/audit/` scripts are the largest instance — they
generate the inventory deterministically so the "before" is reproducible. For a
non-trivial change, prefer a measured baseline over a guess.

**Re-verify referenced foundations.** When a task references prior-session
deliverables as foundation (widgets, providers, schema, endpoints), the
audit-first step explicitly re-verifies each one (`file:line`) before
implementation proceeds. Earlier reports occasionally describe surfaces that were
never fully wired through — Session 5a's "Son baktıkların" rail was referenced
but only a placeholder column existed; Tranche 4a's prompt assumed a
`recentlyViewedProvider` that did not exist; the 4b prompt's auto-observer
allowlist contradicted the locked design doc's manual-event decision. Catching
these in the audit (and reconciling toward the locked design, not the prompt's
incidental wording) prevents wrong assumptions from cascading into implementation.

## Cleanup audits

Periodically (every ~6 months or ~20 PRs, whichever first), run a cleanup audit
producing `CLEANUP_AUDIT.md` at repo root. It inventories dead code, unused assets,
orphan dependencies, stale docs, and duplicate utilities across all stacks. **Output
is read-only**; subsequent focused PRs act on its §10 roadmap. Run via the
`chore/cleanup-audit` pattern; each domain (backend / frontend / docs / tooling) gets
its own section so removal PRs target one domain cleanly. Findings carry severity
(high/med/low) + effort (XS/S/M/L); raw analyzer outputs are committed under
`tool/audit/cleanup_raw_outputs/` as evidence. Future audits supersede prior ones —
keep only the most recent in repo root.

Hard-won lessons from the first audit (`main@ca739bf4`):
- **Know what the gates already enforce.** `flutter analyze` (very_good_analysis) and
  `go test`/`go build` pre-empt whole classes of deadness, so don't re-report them.
  Conversely, `.golangci.yml` does **not** enable `unused`/`deadcode` — that is exactly
  where Go dead code hides. Check the config before trusting "clean."
- **Grep cross-file deadness is false-positive-heavy.** Riverpod Notifier/State/provider
  classes (referenced via their provider, by type inference, or composed file-internally)
  read as "0 references" but are live. easy_localization i18n keys and interpolated golden
  names (`'goldens/refund_card_${status}.png'`) defeat literal grep. **Label these as
  candidate pools requiring manual review or a real usage tool — never as a dead list a
  removal PR can act on blindly.** Verify a sample before classifying.
- **The right tool beats grep:** `staticcheck -checks=U1000` (unexported) +
  `deadcode -test ./...` (whole-program reachability) are reliable for Go; spot-check that
  a flagged symbol isn't reachable only behind a build tag.

Lessons from the first cleanup *execution* (`chore/project-cleanup-confirmed`):
- **Pair removal with the regression guard.** That PR enabled golangci `unused` (it was
  missing — the root cause that let 37 dead symbols accumulate) in the same change that
  removed them. Without the gate, the next audit finds the same class again. `unused` is in
  `make verify` via `lint`. Caveat: golangci v2 `unused` only catches **unexported** dead
  code (it treats exported library symbols as used-externally); the exported-unreachable
  class is covered by on-demand `make deadcode`, **not** a hard gate — deadcode is
  build-tag-config sensitive (a symbol used only by `//go:build integration` tests reads as
  dead in the default config), so it would be a flaky gate.
- **`deadcode -test` (default config) misses build-tagged test callers → false positives.**
  `RefreshWorker` and the sipay `Sign*` funcs were flagged "dead" by the audit but are used
  by `//go:build integration` tests; removing them would have broken `make verify`'s
  integration run. **Before removing any "confirmed dead" symbol, grep ALL `*_test.go`
  (build-tag-agnostic) and run `go vet -tags=integration` on the package.**
- **`var _ = f` unused-suppression hides deadness.** `reconcile` kept two dead funcs alive
  only via blank assignments; the cleanup removed the funcs AND the suppression. Watch for
  `var _ =` when assessing whether something is really used. The codebase now has **zero**
  package-scope `var _ = expr` suppressions (`chore/cleanup-cheap-followup` swept and confirmed).
  If you add one for a legitimate reason (forcing an init-time side effect; a helper used only
  under a build tag), **add a comment saying why** — an undocumented `var _ =` reads as a
  dead-code mask and a future cleanup will remove it (and the symbol it points at). Typed
  interface assertions (`var _ Iface = (*T)(nil)`) are a different, fine idiom — not a mask.
- **`git add a b c` stages NOTHING if any path is already-deleted** (errors on the missing
  pathspec). After `git rm x`, don't re-`git add x` in a later grouped `git add`; commit the
  `git rm` separately or `git add -A` the survivors.

## Testing audit cadence

The same audit-first → focused-fix discipline used for cleanup applies to testing,
correctness, concurrency, and performance. The audit report is `docs/audits/TESTING_AUDIT.md`
— **it is the source of truth for what's broken/uncovered**. The audit PR fixes nothing;
fix PRs follow and **must reference the finding ID** (e.g. "closes TESTING_AUDIT F-001").

Rules (carried from the cleanup arc):
- **Re-verify at PR time.** Every finding carries the exact command + output that reproduced
  it on the PR branch. Confidence is graded CONFIRMED (reproduced) / PROBABLE (pattern only) /
  UNKNOWN (flagged for follow-up). Don't promote PROBABLE to CONFIRMED without reproduction.
- **Enumerate build tags** before any absence-of-caller claim (`integration`, `contract`,
  `sipay_sandbox`, `tools`) — the #54 `RefreshWorker`/`Sign*` lesson generalizes.
- **Escape hatch (honest zero):** if a section genuinely has nothing, write it
  "verified-not-actionable" with the command used — don't manufacture findings to look
  thorough. PR #56 (net-zero cleanup) and this audit's verified-not-actionable sections
  (§3.2/§3.4/§4.2/§5.1) are the precedent.
- Audits supersede prior ones; `docs/audits/ROADMAP.md` tracks step status (audited vs. fixed).

## Adaptive presenter

One content widget, two presenters chosen by breakpoint. `LoginRequired`
(`mobile/lib/features/auth/widgets/login_required.dart`) is the canonical case:
the same presenter-agnostic content renders inside a bottom sheet on mobile
(`showLoginRequiredSheet`) and a centered `Dialog` on desktop, and both honour
the `requireAuth(ctx, ref, onAuthed: …)` resume-once contract. When a flow needs
a modal that differs only in chrome between form factors, write the content once
and add a presenter — do not fork the widget.

## In-component composition over `Overlay` routing

Prefer composing transient UI **in the widget tree** over pushing it through the
global `Overlay`/route stack. The PDP hover-zoom and the login dialog both
compose in-tree, and `AnchoredOverlayPanel`
(`mobile/lib/design/responsive/anchored_overlay_panel.dart`) anchors dropdowns
(search pill, account menu, mega-menu) to their trigger rather than routing a new
page. This keeps focus management, dismissal, and lifecycle local to the
component and avoids route-stack surprises.

## Module placement decisions

When backend gap-fill could plausibly live in two existing modules, surface the
choice with the trade-offs **before** implementing. Use `AskUserQuestion` with
named options + a one-line rationale for each. The wrong module assignment is
cheap now and expensive to refactor later. Precedent: Tranche 2a inbox vs.
`notification_schema` (PR #23, chose a new `internal/inbox`); Tranche 2b help
vs. support (chose separate `internal/help` + `internal/support`).

## Goldens on authed state

Authed-state goldens have a higher risk of revealing platform-specific
timer/async behavior. When adding goldens for screens that consume providers
with timers (`Timer.periodic`, polling intervals, `FutureProvider.autoDispose`
with `keepAlive`) or that fire a network request on build, prefer **stubbing the
provider in the test harness** over letting the real provider's timer/request
fire during golden capture. The macOS platform-guard sometimes masks Linux
failures of this class — a golden that "passes" locally can fail CI with a
pending-timer error once the golden assertion passes on Linux. Precedent: the
notification-badge poller leaked into account goldens until stubbed (PR #23).

## Background polling vs. on-demand refresh

Background polls are a top source of test-suite timer leaks and a non-trivial
source of mobile battery drain. Prefer **on-demand refresh** — after user
actions, on screen open, on auth-state changes — over `Timer.periodic`. When
real-time updates matter for a specific surface, the path is WebSockets or
server-sent events, not faster polling. Precedent: the Tranche 2a notification
badge dropped its 60s poll for on-demand refresh (PR #23).

## Decision precedence — locked design > CONTRIBUTING > prompt specifics

When a task prompt conflicts with a locked architectural decision
(`TRANCHE_*_DESIGN.md`) or an established CONTRIBUTING pattern, the
higher-precedence source wins:

> **locked design > CONTRIBUTING patterns > per-task-prompt specifics**

Each level may override the next when they conflict; the override is auditable
because it cites the higher-precedence source. Precedents:
- PR #28 followed design §7 (auto `page_view` + **manual** business events) over
  the prompt's auto-ProviderObserver allowlist.
- PR #27 followed the CONTRIBUTING cross-schema soft-reference pattern over the
  prompt's `REFERENCES … ON DELETE CASCADE` SQL.
- Tranche 4c shipped a sibling `ProductListRail` rather than contorting the
  provider-coupled `ProductRail` the prompt named `MoproProductRail`.

## Defensive layering — cross-cutting infra fails closed

Cross-cutting infrastructure (analytics, telemetry, observability) must **fail
closed for itself but open for the surfaces it instruments**. An analytics
failure must never propagate into the commerce path. Event emission, flush,
identify, and recently-viewed fetch resolve to silent no-ops or **empty** states —
never error states that the home/cart/checkout flows would render or crash on.
Precedents: PR #28 caught a `purchase_flow` regression during instrumentation
(resilient session-id + guarded lifecycle observer); Tranche 4c's
`recentlyViewedProvider` treats fetch errors as empty data (rail hides), not error
data (rail shows an error).

## User-state-consumer discipline (`internal/identity`)

Soft-delete is a **service-layer policy, not a storage filter**. `repo.GetUser`
(and the `Find*ByEmailHash`/`Find*` repository methods) deliberately return
soft-deleted rows with no `deleted_at` predicate — admin, audit, and account-
recovery flows need to read deleted users. The store stays dumb; **every
service function that returns or acts on user state owns the deleted-user
check itself.**

Because auth is stateless JWT (`RequireAuth` trusts the access-token claims and
does not re-hit the DB per request), a user soft-deleted mid-session keeps a
valid access token until its TTL expires. Refresh is revoked at deletion
(`SoftDeleteWithRevoke`), so the exposure is TTL-bounded — *except* for any path
that **mints a new session** for a deleted user, which escapes the TTL window
entirely. `VerifyEmail` was exactly such a gap (it issued tokens on the
already-verified branch with no state check — an effective login bypass); see
`fix/identity-getme-deleted-user-guard` and the sweep in
`tool/audit/identity_user_state_consumers.md`.

**Decision tree for any new `internal/identity` function that loads a user:**

1. Does it return user state, issue a session/step-up token, or perform an
   authenticated action on the user? → it is a user-state consumer.
2. Can a soft-deleted user reach it (directly, or via a token/challenge they
   could still hold)? If a strictly-upstream consumer already rejects deleted
   users before this one is reachable (e.g. `VerifyMFAChallenge` is gated by
   `LoginEmail`), add a **doc comment** stating the upstream gate and stop.
   Otherwise:
3. Apply the guard immediately after loading the row, before any return or
   side-effect:
   ```go
   if user.Status == StatusDeleted {
       return <zero>, ErrUserDeleted
   }
   ```
4. **Exception — enumeration-safe endpoints.** `ForgotPassword`,
   `ResendVerification`, and peers return `nil` silently on unknown email so
   they don't leak account existence. For these, a deleted user must also
   `return nil` silently — returning `ErrUserDeleted` would leak deleted status.
   Never branch the response in a way an attacker can distinguish.

The established guard sites are `VerifyOTP`, `RefreshTokens`, `LoginEmail`
(session issuers); mirror them. The repository layer must **never** grow a
`deleted_at` filter to "fix" a missing service guard — that would break the
admin/audit/recovery readers that depend on seeing deleted rows.

This is a TTL-bounded confidentiality/integrity concern, not an incident: fix
it at normal cadence with the rest of the consumer sweep, don't hotfix a single
function in isolation (the value is the *uniform* discipline). A token denylist
/ per-request user-state revocation would close the TTL window structurally but
is a deliberate non-goal here (stateless-JWT tradeoff); it lives in the backlog.

## Test-suite CI gating discipline

A test suite that isn't in `make verify` is one refactor away from silent rot.
The `internal/e2e` suite drifted across multiple refactors (cashback v6→v8
rewrite, `cart.Service`/`catalog.Service` interface growth, `RunMonth`/
`CreatePlanForOrder` entry-point removal, plus the v8 `plans`/`orders` schema
columns) **without anyone noticing**, because nothing made the build break
loudly — `make verify`'s `test` target runs `go test ./...` *without*
`-tags=integration`, so the entire build-tagged suite was invisible.

Discipline: every test suite intended to enforce a contract MUST be gated by
`make verify` (or a CI workflow that runs on every PR). Suites that exist only
as documentation or developer-iteration tools should be labelled as such — but
if they exercise behavior production depends on, they belong in the gate.

When adding a new test surface (integration-tagged, build-tagged, etc.), the
**same PR that adds the tests must add the gate**. Adding tests without gating
them is filing for future silent breakage. For suites needing infrastructure,
follow the idempotent self-bootstrap precedent (`pg-ledger-test-up`,
`e2e-test-up`): apply the **real** init + migration SQL — never a hand-rolled
DDL snapshot, which silently drifts from production schema (it's what rotted the
e2e ledger schema here).

Precedent: `chore/revive-internal-e2e-suite` (this PR) gated the suite after it
had rotted; `chore/cashback-reference-rate-constant-fix` (PR #37) first surfaced
the rot. `go build` does NOT compile `_test.go` files — use
`go test`/`go vet -tags=integration` to detect test rot.

## Migration discipline for test fixtures

When refactoring a service interface or removing a public entry point, grep for
usage across **both production code AND test code** (including build-tagged or
`_test.go` files). Test files don't appear in `go build` without the right tags,
so the compiler won't catch them. Use `gofmt -r` for renames; use explicit grep
for signature changes. The Go compiler reports only the *first* missing
interface method — a single "missing method X" error can hide a dozen more (the
e2e catalog mock was missing 13 methods, surfaced one at a time).

When a test references a deleted constant or function, the question is "what
does the test actually need to assert?" Restoring the symbol is rarely right
(PR #37's analysis); migrating the test to the current engine functions usually
is — e.g. `cashback.ComputePlanTerms(price, bps).MonthlyAmountMinor` rather than
a hardcoded monthly amount that silently encodes the old (v6) math.

## Image-build workflow + manual rollout

Backend service images (`core-svc`, `fin-svc`, `jobs-svc`) build automatically on
`main` push via `.github/workflows/build-images.yml` — each from the single
parameterized `build/Dockerfile` (`--build-arg SERVICE=<svc>`, mirroring
`make docker-build`), tagged `latest`, full-sha, and short-sha at
`ghcr.io/<repo-owner>/<service>:<tag>` — **owner-relative**: it resolves to
`ghcr.io/s4l1hs/*` on the current fork, and `ghcr.io/mopro/*` if/when the repo
migrates to the `mopro` org.

**Image namespace parameterization.** `deploy/docker-compose.yml` pulls
`ghcr.io/${IMAGE_NS:-mopro}/<service>`, so the puller can be pointed at the actual
push owner without editing the file: set `IMAGE_NS` in the host's `.env` (e.g.
`IMAGE_NS=s4l1hs`). The default `mopro` exists for the eventual org migration —
until then, hosts set `IMAGE_NS` to the current owner; after a move to `mopro`,
they clear the override. A PR that touches deploy config must verify
`docker compose config` resolves correctly under **both** the default and the
override (both paths must work). `docker-compose.prod.yml` uses the identical
`ghcr.io/${IMAGE_NS:-mopro}/<service>` form — both compose files now resolve to the
same registry and namespace as the CI push target.

Building ≠ deploying. Rolling a new image onto a host is a manual
`docker compose pull <svc> && docker compose up -d <svc>` step (or automatic if a
watchtower-style auto-pull agent is configured). When merging a backend PR that
needs to reach production, confirm the build workflow ran after merge, then trigger
the host pull. See `docs/deploy.md`.

## Architectural decisions retired

When an explored approach is abandoned, **delete the dead code but record why**, so
a future contributor doesn't recreate the same dead path.

- **core-svc HTTP routing uses the stdlib mux, NOT the generated `gen/core`
  StrictServerInterface.** `internal/api/core_impl.go` (a `CoreServer` with 41
  methods returning 501 Not Implemented) was scaffolded in session-3 (2026-05-29) to
  migrate core-svc onto the oapi-codegen strict server — but core-svc never adopted
  it; the live routing is the stdlib `http.ServeMux` in `cmd/core-svc/main.go`. The
  stub was wired to nothing and removed in `chore/project-cleanup-confirmed`. The
  parallel `internal/api/fin_impl.go` (`FinServer`) **does** use the generated server
  — so the pattern lives for fin-svc but is deliberately not used for core-svc. The
  `gen/core` types are still regenerated from `api/openapi.yaml` by `openapi-ci.yml`
  (used for client/model generation); they just have no server implementer. If a
  future PR is tempted to re-add a `CoreServer`: this was a deliberate choice, not an
  oversight — core-svc's mux is the contract.

## Operational-file drift discipline

When the same operational concern lives in two or more files, drift is the
default: one file evolves while its sibling stays frozen, and the mismatch
surfaces as a deploy failure (or worse, a silent production incident) months
later. The CI↔deploy registry arc is the canonical example — the build workflow
(`build-images.yml`) and the deploy compose files (`docker-compose.yml`,
`docker-compose.prod.yml`) each encode the image registry/namespace independently,
and they drifted twice in two PRs: PR #51 caught the dev compose pinning a
nonexistent org namespace, and the prod compose was still on a *different
registry* entirely (Docker Hub vs GHCR) until the follow-up. The same class
recurs elsewhere — e.g. a module's hand-rolled test-schema setup (identity's
`TestMain` DDL) drifting from the real migrations it's supposed to mirror.

Discipline: when modifying a file that has an operational sibling — a compose
dev/prod pair, a migration + init-script pair, a test-setup + production-schema
pair, a CI push target + a deploy pull target — **verify the sibling matches in
the same PR.** Fix both, or document the divergence as deliberate. The audit-first
step of an operational PR should explicitly grep for the siblings of any file it
touches (e.g. `grep -rn '<registry-or-namespace>' deploy/ .github/`). The check is
cheap; skipping it is how the registry mismatch survived three PRs before anyone
pulled on the deploy host.

## `make verify` as the canonical CI gate

`make verify` runs on every PR to `main` via `.github/workflows/make-verify.yml`.
It orchestrates `go test ./...` (incl. `-tags=integration` for the e2e + property
suites, with Docker-bootstrapped postgres/redis), `golangci-lint` (v2), module
boundary checks, and the Flutter WCAG contrast test.

Anything that should block a PR from merging belongs in `make verify` — the CI
workflow inherits it for free. Local-only gates that aren't wired into `make verify`
silently rot: see PR #40's `internal/e2e/` revival, where a build-tagged suite went
uncompilable across several refactors because nothing in CI ran it. The gate is
now a **required** status check on `main` (PR #50): the required-check context is
`verify` (the *job* name), not `make-verify` (the *workflow* name) — branch
protection keys on the job. `enforce_admins=false` keeps the solo owner from being
locked out by a gate flake while still blocking non-admins on a red/missing `verify`.

## Manual image build for hotfixes / out-of-band deploys

If a backend change must reach production without a `main` merge (hotfix, debug
build), build + push manually:

```sh
docker build --platform=linux/amd64 --build-arg SERVICE=core-svc \
  -t ghcr.io/<owner>/core-svc:hotfix-<short_sha> -f build/Dockerfile .
docker push ghcr.io/<owner>/core-svc:hotfix-<short_sha>
```

Then `docker compose pull` + `up -d` on the host. Keep `:latest` reserved for the
`main`-built image — don't push custom tags to `:latest`.

## Deploy via workflow_dispatch

Deploys run through `.github/workflows/deploy.yml`, triggered manually:

```sh
gh workflow run deploy.yml --ref main                      # real deploy
gh workflow run deploy.yml --ref main -f verify_only=true  # non-destructive check
gh run watch
```

The workflow SSHes to the deploy host (stored SSH key), `scp`s
`tool/audit/deploy_script.sh`, and runs it — full output streams into the run log,
same as a manual SSH session, but nobody types commands into production. Inputs:

- `ref` — branch/tag/SHA to deploy from (default `main`). Lets a feature branch's
  deploy be exercised before merge.
- `verify_only` (**default `true`**) — non-destructive: SSH + scp + compose-dir
  discovery + `docker compose config`, **no** `pull`/`up`/restart and no upload POST.
  Set `verify_only=false` for an actual deploy.
- `skip_photo_smoke` — skip STEP 8 (photo-upload smoke) when host test creds absent.

Required secrets (Settings → Secrets and variables → Actions): `DEPLOY_SSH_KEY`
(ed25519 private key; public half in the host's `authorized_keys`), `DEPLOY_HOST`,
`DEPLOY_PORT`. The deploy user needs **passwordless sudo** for `docker`/`tee` —
the workflow runs the script over a non-interactive SSH session, so a sudo password
prompt would hang the job.

Trigger is `workflow_dispatch` only — no auto-deploy on push (a wrong merge auto-
shipping to prod is a different risk profile; Backlog). **A newly-added or renamed
deploy workflow can't be dispatched until it's merged to the default branch** —
GitHub only registers `workflow_dispatch` workflows from the default branch, so the
first run of any change to `deploy.yml` is necessarily post-merge (same constraint
that gated build-images in PR #41).

## Compose-path discovery (deploy script)

`tool/audit/deploy_script.sh` discovers the compose directory rather than assuming
one (a hard-coded `cd /opt/mopro` failed when the host kept compose in a
subdirectory). Order: `COMPOSE_DIR` env override → `/opt/mopro/deploy` →
`/opt/mopro` → `find / -maxdepth 4 -name 'docker-compose*.yml'`. Override when the
host differs:

```sh
COMPOSE_DIR=/srv/mopro bash deploy_script.sh
```

`IMAGE_NS` is written to `$COMPOSE_DIR/.env` (where Compose actually reads it), not
an assumed `/opt/mopro/.env`.

## Connection acquisition inside transactions

A function called from within an active `pgx.Tx` block must use that tx for its
database reads. Reading via the pool (`pool.Query`/`QueryRow`) inside a tx-bearing
call chain makes the function acquire a **second** pool connection while the first
(the tx) is still held — which **deadlocks** when the pool budget is saturated by
concurrent goroutines each holding one connection and waiting for a second.

Pattern: repository functions that may be called from inside a tx take an optional
`pgx.Tx` parameter — non-nil → read on the tx; nil → fall back to the pool (correct
for callers outside a tx). Precedents: `wallet.GetAccountCurrencies`,
`wallet.GetSystemState`, `wallet.SetSystemState`.

**Correctness caveat — not every read can be tx-routed.** A read that must observe
rows committed by a *concurrent* transaction (e.g. `wallet.GetTransactionByIdempotencyKey`
on the idempotent-replay path, looking up a txn another worker just committed) must
stay on the pool: a SERIALIZABLE tx's snapshot was frozen at tx start and would
return *not-found*. Tx-route a read only when the rows it needs are already committed
before the tx opens (account/config lookups), not when it must see concurrent commits.

This deadlock surfaced in PR #41's `make-verify` CI: `TestCronProperty_ConcurrentIdempotency`
on a 2-vCPU runner with pgx's default `MaxConns=4` × 8 concurrent payments. Local
6-core machines masked it (pool default is `max(4, NumCPU)`). Fix:
`fix/cashback-pgxpool-deadlock`.

### Three patterns + a decision tree (`fix/financial-domain-pool-discipline`)

The in-tx read above resolves to one of three patterns:

1. **`tx-routing`** — the read interleaves with writes in the same tx and the rows it
   needs are committed before the tx opens. Take an optional `pgx.Tx`; read on it when
   non-nil. Precedents: `wallet.GetAccountCurrencies`, `wallet.GetSystemState`.

2. **`read-snapshot-before-tx`** — the read is a single check-once condition. Read it on
   the pool **before** opening the tx and pass the value in, rather than reading inside
   the tx (which both risks the second-connection deadlock and observes the tx's frozen
   snapshot). Precedent: `sellerpayout.run_daily.go` reads `FindBatchByKey` as a
   pre-check before its `WithTx`. Use when the read can't interleave with in-tx writes
   and doesn't need to see concurrent commits.

3. **`documented-pool-access`** — the read **must** observe rows committed by *concurrent*
   transactions (idempotency lookups on a replay path), so it stays on the pool by
   design. It gets a doc comment naming the failure mode if "fixed" via tx-routing, and
   a regression test that depends on the pool access (so the naive fix fails loudly).
   Precedent: `wallet.GetTransactionByIdempotencyKey`.

**Decision tree** for a read reachable from inside a `WithTx`:

1. Must it observe *concurrent* commits (sibling goroutines racing on the same key)?
   → **`documented-pool-access`** (stays on pool; add the contract test).
2. Is it a single check that can run *before* the tx opens? → **`read-snapshot-before-tx`**.
3. Does it interleave with writes in the tx, on rows committed before tx-open?
   → **`tx-routing`** (optional `pgx.Tx`, read on it).
4. Ambiguous? Default to **`tx-routing`** — it's the safest when requirements are unclear.

Every financial ledger write funnels through `wallet.PostInTx`, so this single function
is the whole in-tx-pool-read surface; `TestProperty_FinancialWritePathDoesNotDeadlock`
(MaxConns=4, N concurrent, context-timeout deadlock-detection, `pgxpool.Stat` leak check)
is the non-fragile regression guard for it.

## Financial-domain change discipline (CLAUDE.md §12)

When changing financial-domain code (`internal/wallet`, `internal/cashback`,
`internal/sellerpayout`, `internal/orderledger`):

- **Audit pool-vs-tx in every call path.** Grep tx-bearing functions for pool reads
  (the deadlock pattern above). Document the inventory before changing code.
- **Pin pool budget in concurrency tests** (`MaxConns=4`, or `=1` for a
  single-connection contract guard) so behavior is reproducible across runner CPU
  counts — never rely on the CPU-derived default.
- **Guard the contract with a concurrency test.** A new tx-bearing function on the
  financial write path gets a pinned-pool concurrency test (`MaxConns=4`, more
  goroutines than connections) that deadlocks if it acquires a second connection
  under contention — like `TestCronProperty_ConcurrentIdempotency`. (A `MaxConns=1`
  "exactly one connection" assertion is tempting but fragile on shared-CPU CI
  runners — a legit single op can exceed a wall-clock deadline under load; prefer a
  counting-pool decorator if you need a precise per-op assertion.) Don't widen the
  pool to silence such a test.
- **Confirm singleton/concurrency invariants** and document the production pool size
  (set an explicit `DB_MAX_CONNS` rather than the implicit default).
