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
