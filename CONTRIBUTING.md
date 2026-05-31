# Contributing to Mopro Shop

## Pre-requisites

- Go 1.25+
- Docker + Docker Compose (for `make run-local`)
- `golangci-lint` — `go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest`
- `govulncheck` — `go install golang.org/x/vuln/cmd/govulncheck@latest`

## Local setup

```bash
cp .env.example .env.local
chmod 600 .env.local
make hooks                   # points core.hooksPath at .githooks/
go mod download
make verify
```

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
# Start all services
make run-local

# Run the full verification suite (must pass before PR)
make verify
```

`make verify` runs: `gofmt`, `go vet`, `go test -race ./...`, `golangci-lint run`,
`./scripts/check-module-boundaries.sh`, and property tests.

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

## Module boundary enforcement

`./scripts/check-module-boundaries.sh` verifies that:
- `internal/identity|catalog|cart|order|payment|seller|search` do not import `fin-svc` internals
- `internal/wallet|commission|treasury|cashback|sellerpayout` do not import `core-svc` internals
- No direct imports of `*/repository` outside the owning module

`golangci-lint` (depguard rules in `.golangci.yml`) enforces the same rules at lint time.

## Adding a new dependency

1. Check if it already exists in `go.mod`.
2. If not, evaluate: is there a stdlib equivalent? Is the licence compatible (Apache 2 / MIT)?
3. Add with `go get <module>@<version>` and `go mod tidy`.
4. Run `govulncheck ./...` to verify no new vulnerabilities are introduced.
5. Justify the new dependency in the PR description.

## Financial code

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

Two domains now follow this pattern (cashback `payments_made` and reviews
`helpful_count`):

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
`internal/catalog/RefreshHelpfulCountCache`. Add new domains to this list as they
land.

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
