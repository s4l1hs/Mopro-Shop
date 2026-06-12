COMPOSE      := docker compose -f deploy/docker-compose.yml
COMPOSE_PROD := docker compose -f deploy/docker-compose.prod.yml

# Image tag for local builds (docker-build). Production deploys are driven by
# the `deploy` GitHub workflow, not make — see docs/deploy.md (F-DH-RESIDUAL).
VERSION  ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)

OAPI_CODEGEN_VERSION  := v2.4.1
OPENAPI_GEN_VERSION   := v7.10.0
OPENAPI_GEN_IMAGE     := openapitools/openapi-generator-cli:$(OPENAPI_GEN_VERSION)

# `make` with no target prints help (TOOLING_AUDIT T-004). Was previously the
# first target (verify); nothing in CI/hooks/docs runs bare `make` (they call
# `make verify` explicitly), so this is a safe, friendlier default.
.DEFAULT_GOAL := help

.PHONY: help bootstrap verify verify-fast analyze soak fmt vet test lint govulncheck boundaries migration-check lint-discipline property-cashback property-payout property-ledger integration-wallet property-timex property-order \
        verify-image-manifest update-goldens audit audit-test i18n-check i18n-usage riverpod-check \
        pg-ledger-test-up pg-ledger-test-down \
        build-core build-fin build-jobs build-migrate build-mopro build-all run-local down-local \
        caddy-validate caddy-reload \
        test-integration-catalog integration-eventbus integration-outbox integration-order \
        integration-sellerpayout integration-apifin integration-reconcile integration-attachments integration-help \
        integration-inbox integration-idempotency \
        test-e2e integration-e2e integration-cart integration-identity integration-identity-race integration-payment e2e-test-up e2e-test-down \
        api-gen-models api-gen-core api-gen-fin api-gen-dart api-gen api-lint contract-test \
        docker-build \
        seed-dry-run seed-staging seed-prod build-seed \
        smoke loadtest grafana-deploy

# Self-documenting help (TOOLING_AUDIT T-004): lists every target carrying a
# `## ` description. Internal orchestration sub-targets (property-*, integration-*,
# api-gen-* steps, *-test-up/down) intentionally omit `## ` so help stays scannable
# — run those via `make verify` / `make api-gen`.
help: ## Show this help.
	@echo "Mopro Shop — make targets:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_-]+:.*?## /{printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# verify chains all static checks + the full DB/integration/property suites.
# This is the CI gate (the required `verify` workflow). It needs the Postgres +
# Redis test clusters up, so it is NOT what the local pre-push hook runs — see
# `verify-fast` below.
verify: fmt vet test lint boundaries migration-check lint-discipline property-cashback property-payout property-ledger integration-wallet property-timex property-order integration-e2e integration-cart integration-identity integration-identity-race integration-payment integration-analytics integration-shipping integration-order integration-sellerpayout integration-outbox integration-eventbus integration-apifin integration-reconcile integration-attachments integration-help integration-inbox integration-idempotency test-integration-catalog verify-image-manifest verify-contrast ## Full verification gate (CI; needs DB clusters).

# verify-fast: the fast, DB-free subset wired into the LOCAL pre-push hook.
# Everything here runs WITHOUT the Postgres/Redis test clusters or Docker, so it
# finishes in a couple of minutes and never hangs — unlike the full `verify`,
# whose property + integration suites need the DB cluster up (that suite stays in
# CI, where the required `verify` workflow runs it). A fast hook that actually
# runs beats a heavy one that's always `--no-verify`'d.
verify-fast: fmt vet lint-discipline boundaries migration-check build-all test analyze i18n-check i18n-usage ## Fast DB-free pre-push gate (full verify runs in CI).

# flutter analyze over the app — mirrors CI (green-on-compile; infos non-fatal).
analyze: ## flutter analyze the mobile app (--no-fatal-infos, mirrors CI).
	cd mobile && flutter analyze --no-fatal-infos

# WCAG contrast check for the documented brand colour pairs. Fails if any
# non-Backlog pair regresses below threshold. See lib/design/a11y_contrast.dart.
verify-contrast: ## WCAG contrast check for brand colour pairs.
	cd mobile && flutter test test/design/contrast_test.dart

# Re-baseline Flutter goldens on the CURRENT platform and stamp each with a
# `.png.meta` platform sidecar (written by the guard in
# test/_support/golden_platform.dart). Goldens are baselined on Linux/CI — run
# this via the `golden-rebaseline` GitHub workflow (or on a Linux machine), not
# on macOS. See CONTRIBUTING.md.
update-goldens: ## Re-baseline Flutter goldens (run on Linux/CI).
	cd mobile && flutter test --update-goldens

# Regenerate the image manifest and fail if the committed copy is stale.
# Build-time tool: requires ImageMagick (see tool/audit-images.sh).
verify-image-manifest: ## Regenerate + verify the image manifest.
	@./tool/audit-images.sh
	@git diff --quiet -- mobile/assets/images/MANIFEST.md || { \
	    echo "" >&2 ; \
	    echo "ERROR: mobile/assets/images/MANIFEST.md is stale." >&2 ; \
	    echo "Run ./tool/audit-images.sh and commit the result." >&2 ; \
	    git --no-pager diff -- mobile/assets/images/MANIFEST.md >&2 ; \
	    exit 1 ; }

# Regenerate the autogenerated inventory blocks of SYSTEM_AUDIT.md from the
# deterministic audit scripts under tool/audit/. Re-running on an unchanged tree
# produces no diff. See tool/audit/regen.sh.
audit: ## Regenerate SYSTEM_AUDIT.md inventory blocks.
	@bash tool/audit/regen.sh

# Smoke-test the audit scripts (run/non-empty/deterministic) + assert
# SYSTEM_AUDIT.md generated blocks are up to date.
audit-test: ## Smoke-test the audit scripts.
	@bash tool/audit/smoke_test.sh

# Translation completeness gate (TOOLING_AUDIT T-010). Fails on EXTRA keys
# (orphan/typo keys absent from the tr-TR master); missing keys stay
# informational (unlaunched markets are partial by design — see the script
# header). Wired into the Flutter CI workflow.
i18n-check: ## Translation completeness gate (fails on extra keys).
	@bash tool/audit/check_i18n.sh --strict

# i18n dead-key + missing-key ratchet (TOOLING_AUDIT T-001). Orthogonal to
# i18n-check (completeness): this checks USAGE against the baselines in
# tool/audit/i18n_*_baseline.txt. Zero-dep Dart. See docs/internal/i18n-analyzer.md.
i18n-usage: ## i18n dead-key / missing-key gate (ratchet vs baseline).
	@dart run tool/audit/check_i18n_usage.dart --check

# Riverpod inferred-type-provider ratchet (TOOLING_AUDIT T3-5). Notifier build()
# shapes are inventoried (informational); only inferred-type drift is gated.
# Zero-dep Dart. See docs/internal/riverpod-analyzer.md.
riverpod-check: ## Riverpod inferred-type-provider gate (ratchet vs baseline).
	@dart run tool/audit/riverpod_check.dart --check

# One-command local setup for a fresh checkout (TOOLING_AUDIT T3-3): env file,
# go mod download, git hooks, flutter pub get. Idempotent; detects (never installs)
# toolchains. See scripts/bootstrap.sh / docs/internal/bootstrap.md.
bootstrap: ## Set up a fresh checkout (deps + hooks + env), then run `make verify`.
	@bash scripts/bootstrap.sh

# Wire `.githooks/` into this clone (run once per machine, or after pulling
# a new hook). Refuses commits on main/master and runs the api-gen sync check.
hooks: ## Install .githooks into this clone (run once).
	@sh tool/setup-hooks.sh

fmt: ## Check gofmt; fail if any file is unformatted.
	gofmt -l . | tee /tmp/gofmt.out
	test ! -s /tmp/gofmt.out

vet: ## go vet over all packages.
	go vet ./...

test: ## Run all unit tests with the race detector.
	go test -race ./...

lint: ## Run golangci-lint.
	golangci-lint run

# Dependency-CVE scan of the Go module (TOOLING_AUDIT T-003). Mirrors the
# .github/workflows/govulncheck.yml gate. Run before bumping deps. NOT in
# `verify` yet — main has called stdlib vulns tracked as T-014 (Go 1.26.4 bump).
govulncheck: ## Scan the Go module for known CVEs (T-003).
	go run golang.org/x/vuln/cmd/govulncheck@latest ./...

# Whole-program dead-code scan (exported-unreachable funcs that golangci's
# `unused` can't see — it treats exported library symbols as used-externally).
# On-demand, NOT in `verify`: deadcode's results are build-tag-config sensitive
# (a symbol used only by //go:build integration tests reads as dead in the default
# config), so it is FP-prone as a hard gate. Run it during cleanup audits with the
# tags that match the symbols you're checking, e.g.:
#   make deadcode                      # default build config
#   make deadcode TAGS=integration     # include integration-tagged test roots
deadcode: ## Whole-program dead-code scan (on-demand; see comment).
	go run golang.org/x/tools/cmd/deadcode@v0.45.0 -test $(if $(TAGS),-tags=$(TAGS)) ./cmd/... ./internal/... ./pkg/...

boundaries: ## Enforce module-boundary import rules.
	./scripts/check-module-boundaries.sh

# Migration-safety gate (TOOLING_AUDIT T3-4): risky destructive DDL (DROP COLUMN/
# TABLE, SET NOT NULL) in forward *.up.sql migrations, ratcheted vs a baseline.
# Fast/text — wired into `verify`. See scripts/lint-migrations.sh + docs/internal/lint-discipline.md.
migration-check: ## Flag risky destructive DDL in forward migrations.
	@bash scripts/lint-migrations.sh --strict

# Repo-discipline static analyzers (TOOLING_AUDIT T-007): pool-acquire-inside-tx
# (PR #42/#47) + soft-deleted-user-consumer (PR #49). go/analysis multichecker;
# 0 findings today, so it's a required drift-gate (exits non-zero on any new one).
# See cmd/lint-discipline + docs/internal/lint-discipline.md.
lint-discipline: ## Run the repo-discipline go/analysis analyzers.
	@go run ./cmd/lint-discipline ./internal/... ./cmd/... ./pkg/...

# ── Test infrastructure: pg-ledger-test:6434 ────────────────────────────────
#
# Property-* tests for cashback, sellerpayout, and wallet hit a postgres
# instance at localhost:6434 with the full ledger schema applied. Before
# Session 4d these had to be provisioned manually; PRs #7 and #8 both
# used `--no-verify` because of it. This block lets `make verify` run
# end-to-end without that bypass.
#
# `pg-ledger-test-up` is idempotent: reuses an existing container if one
# is on the expected name, otherwise spins up fresh + waits for postgres
# ready + applies every deploy/postgres-ledger/init/*.sql migration.
# `pg-ledger-test-down` is a manual escape hatch when cross-run state
# drift needs a clean slate (the F-018 ledger suites also share :6434).
#
# Reuse caveat: state persists across `make verify` runs. Most property
# tests TRUNCATE / DROP what they need; if cross-run drift causes a
# flake, run `make pg-ledger-test-down && make verify`.
PG_LEDGER_TEST_CONTAINER := pg-ledger-test

pg-ledger-test-up:
	@if docker inspect $(PG_LEDGER_TEST_CONTAINER) > /dev/null 2>&1; then \
	    echo "[$(PG_LEDGER_TEST_CONTAINER)] already running, reusing" ; \
	else \
	    echo "[$(PG_LEDGER_TEST_CONTAINER)] starting fresh on port 6434..." ; \
	    docker run -d --name $(PG_LEDGER_TEST_CONTAINER) -p 6434:5432 \
	        -e POSTGRES_USER=ledger_admin -e POSTGRES_PASSWORD=test123 \
	        -e POSTGRES_DB=mopro_ledger postgres:16-alpine > /dev/null ; \
	    echo "[$(PG_LEDGER_TEST_CONTAINER)] waiting for postgres..." ; \
	    for i in $$(seq 1 30); do \
	        if docker exec $(PG_LEDGER_TEST_CONTAINER) psql -U ledger_admin -d mopro_ledger -c 'SELECT 1' > /dev/null 2>&1; then \
	            break ; \
	        fi ; \
	        sleep 1 ; \
	    done ; \
	    echo "[$(PG_LEDGER_TEST_CONTAINER)] applying init schema (deploy/postgres-ledger/init/*.sql)..." ; \
	    for f in $$(ls deploy/postgres-ledger/init/*.sql | sort); do \
	        docker exec -i $(PG_LEDGER_TEST_CONTAINER) psql -U ledger_admin -d mopro_ledger < $$f > /dev/null \
	            || { echo "init schema apply failed at $$f" >&2 ; exit 1 ; } ; \
	    done ; \
	    echo "[$(PG_LEDGER_TEST_CONTAINER)] applying ledger migrations (migrations/ledger/*.up.sql)..." ; \
	    for f in $$(ls migrations/ledger/*.up.sql | sort); do \
	        docker exec -i $(PG_LEDGER_TEST_CONTAINER) psql -U ledger_admin -d mopro_ledger < $$f > /dev/null \
	            || { echo "migration apply failed at $$f" >&2 ; exit 1 ; } ; \
	    done ; \
	    echo "[$(PG_LEDGER_TEST_CONTAINER)] ready" ; \
	fi

pg-ledger-test-down:
	-@docker rm -f $(PG_LEDGER_TEST_CONTAINER) > /dev/null 2>&1 ; \
	echo "[$(PG_LEDGER_TEST_CONTAINER)] torn down"

property-cashback: pg-ledger-test-up
	go test -tags=integration -run Property ./internal/cashback/...

property-payout: pg-ledger-test-up
	go test -tags=integration -run Property ./internal/sellerpayout/...

property-ledger: pg-ledger-test-up
	go test -tags=integration -run Property ./internal/wallet/...

# integration-wallet (Step 2 closure): runs the NON-Property wallet integration tests
# (TestIntegration_*) that property-ledger's `-run Property` filter left ungated — they ran
# on no CI job before this. `-skip Property` avoids double-running the property suite above.
# -race on: the F-003 RefreshWorker.Run loop test + the concurrent-open tests want it.
integration-wallet: pg-ledger-test-up
	go test -tags=integration -race -skip 'Property' ./internal/wallet/... -count=1 -timeout 8m

# property-timex and property-order are pure-math; no DB needed.
property-timex:
	go test -tags=integration -run Property ./pkg/timex/...

property-order:
	go test -run Property ./internal/order/...

build-core:
	go build -o /tmp/core-svc ./cmd/core-svc

build-fin:
	go build -o /tmp/fin-svc ./cmd/fin-svc

build-jobs:
	go build -o /tmp/jobs-svc ./cmd/jobs-svc

# Build all three Go binaries to /tmp/ (fast local verify, no Docker).
build-all: build-core build-fin build-jobs ## Build all three service binaries (to /tmp).

build-migrate:
	go build -o /tmp/migrate-tool ./cmd/migrate-tool

build-mopro:
	go build -o /tmp/mopro ./cmd/mopro

run-local: ## Start the full local stack (docker compose).
	mkdir -p ./data/postgres-ecom ./data/postgres-ledger ./data/redis ./data/meili
	$(COMPOSE) --env-file .env up -d --build

down-local: ## Stop the local stack.
	$(COMPOSE) --env-file .env down

caddy-validate:
	$(COMPOSE) --env-file .env exec caddy caddy validate --config /etc/caddy/Caddyfile

caddy-reload:
	$(COMPOSE) --env-file .env exec caddy caddy reload --config /etc/caddy/Caddyfile

# ── Production build (local mirror of build-images.yml) ──────────────────────
# F-DH-RESIDUAL: the tarball deploy path (release/deploy/deploy-staging/rollback
# targets + deploy/scripts/{deploy,rollback}.sh) is RETIRED. Canonical deploy is
# the `deploy` workflow (workflow_dispatch) → tool/audit/deploy_script.sh pulling
# ghcr.io/${IMAGE_NS}/* — see docs/deploy.md. Rollback = re-deploy a pinned
# previous :<full-sha> tag (deploy/RUNBOOK.md "Rollback").

# Build all three service images with VERSION tag.
# BUILD_SHA defaults to VERSION (the git SHA or tag); BUILT_AT is captured at make-time.
BUILD_SHA ?= $(VERSION)
BUILT_AT  ?= $(shell date -u +%FT%TZ)
IMAGE_NS  ?= s4l1hs

docker-build:
	docker build --platform=linux/amd64 \
	  --build-arg SERVICE=core-svc \
	  --build-arg BUILD_SHA=$(BUILD_SHA) \
	  --build-arg BUILT_AT=$(BUILT_AT) \
	  -t ghcr.io/$(IMAGE_NS)/core-svc:$(VERSION) -f build/Dockerfile .
	docker build --platform=linux/amd64 \
	  --build-arg SERVICE=fin-svc \
	  --build-arg BUILD_SHA=$(BUILD_SHA) \
	  --build-arg BUILT_AT=$(BUILT_AT) \
	  -t ghcr.io/$(IMAGE_NS)/fin-svc:$(VERSION) -f build/Dockerfile .
	docker build --platform=linux/amd64 \
	  --build-arg SERVICE=jobs-svc \
	  --build-arg BUILD_SHA=$(BUILD_SHA) \
	  --build-arg BUILT_AT=$(BUILT_AT) \
	  -t ghcr.io/$(IMAGE_NS)/jobs-svc:$(VERSION) -f build/Dockerfile .

# Integration test targets — each spins up an ephemeral container, runs tests, then tears down.

test-integration-catalog:
	docker rm -f pg-ecom-test 2>/dev/null || true
	docker run -d --name pg-ecom-test -p 6433:5432 \
	  -e POSTGRES_USER=ecom_admin -e POSTGRES_PASSWORD=test123 \
	  -e POSTGRES_DB=mopro_ecom postgres:16-alpine
	sleep 2
	CATALOG_TEST_DSN=postgres://ecom_admin:test123@localhost:6433/mopro_ecom \
	  go test -tags=integration -count=1 -race ./internal/catalog/... ; \
	  STATUS=$$? ; docker rm -f pg-ecom-test ; exit $$STATUS

# ── F-018 revived integration suites ──────────────────────────────────────────
# The legacy self-spinning targets (test-integration-{outbox,cart,order,
# sellerpayout}) are GONE — they bound :6434/:6435/:6380, colliding with the
# shared fixtures (pg-ledger-test / pg-ecom-e2e / each other), which is why
# these suites ran in no gate (TESTING_AUDIT F-018). Revived as env-pointer
# targets on the idempotent-reuse fixtures — the cart/identity pattern.
# See docs/internal/f018-integration-suites.md for the per-suite triage.

# eventbus (autoclaim + DLQ) — pg-ledger schema + Redis streams.
integration-eventbus: pg-ledger-test-up e2e-test-up
	REDIS_TEST_ADDR=localhost:6381 \
	LEDGER_TEST_DSN=postgres://ledger_admin:test123@localhost:6434/mopro_ledger \
	  go test -tags=integration -count=1 -race -timeout 8m ./internal/eventbus/...

# outbox publisher properties + chaos — wallet_schema.outbox + Redis.
integration-outbox: pg-ledger-test-up e2e-test-up
	REDIS_TEST_ADDR=localhost:6381 \
	LEDGER_TEST_DSN=postgres://ledger_admin:test123@localhost:6434/mopro_ledger \
	  go test -tags=integration -count=1 -race -timeout 8m ./internal/outbox/...

# order full integration (TestMain self-bootstraps order_schema with DROP+CREATE;
# sequenced after the rest of the chain — verify runs targets serially).
integration-order: e2e-test-up
	ORDER_TEST_DSN=postgres://ecom_admin:test123@localhost:6435/mopro_ecom \
	  go test -tags=integration -count=1 -race -timeout 5m ./internal/order/...

# sellerpayout full integration (-skip Property: the Property suite already runs
# under property-payout — same split as integration-wallet vs property-ledger).
integration-sellerpayout: pg-ledger-test-up
	SELLERPAYOUT_TEST_DSN=postgres://ledger_admin:test123@localhost:6434/mopro_ledger \
	  go test -tags=integration -count=1 -race -skip Property -timeout 8m ./internal/sellerpayout/...

# fin HTTP API IDOR suite (real wallet/cashback schemas + JWT middleware).
integration-apifin: pg-ledger-test-up
	LEDGER_TEST_DSN=postgres://ledger_admin:test123@localhost:6434/mopro_ledger \
	  go test -tags=integration -count=1 -race -timeout 5m ./internal/api/...

# reconcile cross-schema invariant suite (F-018 batch 2). Needs both the admin
# DSN and the reconcile_user DSN — the suite asserts least-privilege behavior,
# incl. CleanupOldAttempts, which requires the SELECT grant from migration 0081
# (F-019). pg-ledger-test-up applies init/* + migrations, so the fixture carries
# the grant. No legacy target to delete (reconcile was "no target", not colliding).
integration-reconcile: pg-ledger-test-up
	LEDGER_TEST_DSN=postgres://ledger_admin:test123@localhost:6434/mopro_ledger \
	RECONCILE_TEST_DSN=postgres://reconcile_user:reconcile_password@localhost:6434/mopro_ledger \
	  go test -tags=integration -count=1 -race -timeout 8m ./internal/reconcile/...

# attachments (applies 0079 itself), help, inbox: self-contained on pg-ecom-e2e.
integration-attachments: e2e-test-up
	MEDIA_TEST_DSN=postgres://ecom_admin:test123@localhost:6435/mopro_ecom \
	  go test -tags=integration -count=1 -race -timeout 5m ./internal/attachments/...

integration-help: e2e-test-up
	HELP_TEST_DSN=postgres://ecom_admin:test123@localhost:6435/mopro_ecom \
	  go test -tags=integration -count=1 -race -timeout 5m ./internal/help/...

integration-inbox: e2e-test-up
	INBOX_TEST_DSN=postgres://ecom_admin:test123@localhost:6435/mopro_ecom \
	  go test -tags=integration -count=1 -race -timeout 5m ./internal/inbox/...

# idempotency middleware — Redis only (DB 15 keeps keys scoped).
integration-idempotency: e2e-test-up
	REDIS_URL=redis://localhost:6381/15 \
	  go test -tags=integration -count=1 -race -timeout 5m ./internal/idempotency/...

# ── OpenAPI codegen targets ────────────────────────────────────────────────────

api-lint: ## Lint the OpenAPI spec (spectral).
	npx --yes @stoplight/spectral-cli@6 lint api/openapi.yaml --ruleset api/.spectral.yaml

api-gen-models:
	go run github.com/oapi-codegen/oapi-codegen/v2/cmd/oapi-codegen@$(OAPI_CODEGEN_VERSION) \
		--config api/oapi-codegen-models.yaml api/openapi.yaml

api-gen-core:
	go run github.com/oapi-codegen/oapi-codegen/v2/cmd/oapi-codegen@$(OAPI_CODEGEN_VERSION) \
		--config api/oapi-codegen-core.yaml api/openapi.yaml

api-gen-fin:
	go run github.com/oapi-codegen/oapi-codegen/v2/cmd/oapi-codegen@$(OAPI_CODEGEN_VERSION) \
		--config api/oapi-codegen-fin.yaml api/openapi.yaml

api-gen-dart:
	docker run --rm \
		-v $$(pwd):/local \
		$(OPENAPI_GEN_IMAGE) generate \
		-i /local/api/openapi.yaml \
		-g dart-dio \
		-o /local/mobile/packages/mopro_api \
		--additional-properties=pubName=mopro_api,nullSafe=true,serializationLibrary=json_serializable,hideGenerationTimestamp=true \
		--skip-validate-spec

api-gen: api-gen-models api-gen-core api-gen-fin api-gen-dart ## Regenerate all OpenAPI models + clients.

contract-test: ## Run API contract tests (spec fixtures + live-handler conformance).
	go test -tags=contract -v -run TestContract ./internal/api/... ./cmd/core-svc/...

# ── Diff enforcement (called by CI) ────────────────────────────────────────────

api-check-sync:
	@git diff --exit-code internal/api/gen/ mobile/packages/mopro_api/ || \
		(echo "\nERROR: Generated files out of sync with api/openapi.yaml. Run 'make api-gen' and commit." && exit 1)

# ── e2e ────────────────────────────────────────────────────────────────────────

# test-e2e: throwaway fresh-container run (tears down first, then the gated run,
# then tears down). Use `make integration-e2e` for the fast reuse-containers loop.
test-e2e: e2e-test-down integration-e2e
	@$(MAKE) e2e-test-down

# ── E2e suite infra (gated by `make verify` via integration-e2e) ─────────────
# Idempotent self-bootstrap, mirroring pg-ledger-test-up: reuse running
# containers, start fresh otherwise, LEAVE running for dev iteration.
# Unlike test-e2e (throwaway containers, torn down each run), these persist so
# `make verify` is fast on repeat. The suite's TestMain applies its own schema
# (setupEcomSchema/setupLedgerSchema), so these are plain empty postgres + redis
# — no init/migration files applied here.
# `make verify` already requires docker (property-* use pg-ledger-test-up), so
# hard-requiring these three containers is consistent; TestMain os.Exit(1)s if
# postgres is absent, which is why bootstrap-as-dependency (not skip) is correct.
e2e-test-up:
	@if docker inspect redis-e2e > /dev/null 2>&1; then echo "[redis-e2e] reusing" ; else \
	    echo "[redis-e2e] starting on 6381..." ; \
	    docker run -d --name redis-e2e -p 6381:6379 redis:7-alpine > /dev/null ; fi
	@if docker inspect pg-ecom-e2e > /dev/null 2>&1; then echo "[pg-ecom-e2e] reusing" ; else \
	    echo "[pg-ecom-e2e] starting on 6435..." ; \
	    docker run -d --name pg-ecom-e2e -p 6435:5432 \
	        -e POSTGRES_USER=ecom_admin -e POSTGRES_PASSWORD=test123 \
	        -e POSTGRES_DB=mopro_ecom postgres:16-alpine > /dev/null ; fi
	@if docker inspect pg-ledger-e2e > /dev/null 2>&1; then echo "[pg-ledger-e2e] reusing" ; else \
	    echo "[pg-ledger-e2e] starting on 6436..." ; \
	    docker run -d --name pg-ledger-e2e -p 6436:5432 \
	        -e POSTGRES_USER=ledger_admin -e POSTGRES_PASSWORD=test123 \
	        -e POSTGRES_DB=mopro_ledger postgres:16-alpine > /dev/null ; \
	    echo "[pg-ledger-e2e] waiting for postgres..." ; \
	    for i in $$(seq 1 30); do \
	        if docker exec pg-ledger-e2e psql -U ledger_admin -d mopro_ledger -c 'SELECT 1' > /dev/null 2>&1; then break ; fi ; \
	        sleep 1 ; \
	    done ; \
	    echo "[pg-ledger-e2e] applying init schema (deploy/postgres-ledger/init/*.sql)..." ; \
	    for f in $$(ls deploy/postgres-ledger/init/*.sql | sort); do \
	        docker exec -i pg-ledger-e2e psql -U ledger_admin -d mopro_ledger < $$f > /dev/null \
	            || { echo "ledger init apply failed at $$f" >&2 ; exit 1 ; } ; \
	    done ; \
	    echo "[pg-ledger-e2e] applying ledger migrations (migrations/ledger/*.up.sql)..." ; \
	    for f in $$(ls migrations/ledger/*.up.sql | sort); do \
	        docker exec -i pg-ledger-e2e psql -U ledger_admin -d mopro_ledger < $$f > /dev/null \
	            || { echo "ledger migration apply failed at $$f" >&2 ; exit 1 ; } ; \
	    done ; \
	    echo "[pg-ledger-e2e] ready (real schema applied)" ; fi
	@echo "[e2e] waiting for postgres readiness..." ; \
	for i in $$(seq 1 30); do \
	    if docker exec pg-ecom-e2e psql -U ecom_admin -d mopro_ecom -c 'SELECT 1' > /dev/null 2>&1 \
	       && docker exec pg-ledger-e2e psql -U ledger_admin -d mopro_ledger -c 'SELECT 1' > /dev/null 2>&1; then \
	        echo "[e2e] postgres ready" ; break ; fi ; \
	    sleep 1 ; \
	done

e2e-test-down:
	-@docker rm -f redis-e2e pg-ecom-e2e pg-ledger-e2e > /dev/null 2>&1 ; echo "[e2e] containers torn down"

# integration-e2e is the load-bearing gate: it runs the build-tagged internal/e2e
# suite (invisible to `go test ./...` / `go build`) so refactors break it loudly.
integration-e2e: e2e-test-up
	REDIS_E2E_ADDR=localhost:6381 \
	ORDER_E2E_DSN=postgres://ecom_admin:test123@localhost:6435/mopro_ecom \
	LEDGER_E2E_DSN=postgres://ledger_admin:test123@localhost:6436/mopro_ledger \
	  go test -tags=integration ./internal/e2e/... -count=1 -race -timeout 5m

# Cart + identity integration suites reuse e2e-test-up's containers (no new infra):
# cart needs Redis; identity needs postgres-ecom (its TestMain applies identity_schema)
# + Redis. Both gated so the suites can't silently rot again (revived in
# chore/revive-cart-identity-integration-tests; precedent: integration-e2e / PR #40).
integration-cart: e2e-test-up
	CART_TEST_REDIS=localhost:6381 \
	  go test -tags=integration ./internal/cart/... -count=1 -race -timeout 5m

# NOTE: no -race here (unlike the other suites) — kept off the main path for speed
# (bcrypt-heavy RequestOTP flows). The -race coverage of the identity concurrency tests
# (token rotation / family revoke / rate-limiter / step-up) runs in integration-identity-race.
integration-identity: e2e-test-up
	IDENTITY_TEST_DSN=postgres://ecom_admin:test123@localhost:6435/mopro_ecom \
	IDENTITY_TEST_REDIS=localhost:6381 \
	  go test -tags=integration ./internal/identity/... -count=1 -timeout 5m

# integration-identity-race (TESTING_AUDIT F-006): the targeted -race run the no-race
# integration-identity comment promised — the whole identity integration suite
# (refresh-token rotation, family-revoke, OTP rate-limiter, step-up) under the detector.
# (The old `-skip OTPCodeDistribution` is gone: that slow chi-square test was replaced by
# a deterministic format test — closes flake TestProperty_OTPCodeDistribution.)
integration-identity-race: e2e-test-up
	IDENTITY_TEST_DSN=postgres://ecom_admin:test123@localhost:6435/mopro_ecom \
	IDENTITY_TEST_REDIS=localhost:6381 \
	  go test -tags=integration -race ./internal/identity/... -count=1 -timeout 8m

# payment reconciler integration suite (TESTING_AUDIT F-001). Reuses e2e-test-up's
# pg-ecom-e2e (its TestMain self-bootstraps order_schema.payments+outbox). -race is on:
# the suite is small + DB-bound, and the concurrency case exists specifically to be
# race-checked (addresses TESTING_AUDIT F-006's "reconciler not exercised under -race").
integration-payment: e2e-test-up
	ORDER_TEST_DSN=postgres://ecom_admin:test123@localhost:6435/mopro_ecom \
	  go test -tags=integration ./internal/payment/... -count=1 -race -timeout 5m

# analytics integration suite (post-audit wiring; was on no CI job — see
# docs/internal/integration-tests-wiring.md). Reuses e2e-test-up's pg-ecom-e2e:
# its TestMain self-bootstraps analytics_schema on empty postgres-ecom (no migrations,
# no new container). Covers ingest/consent/identify/recently-viewed/prune/erase/
# recommendations + the #100 per-category popularity (TestIntegration_PopularPerCategory).
integration-analytics: e2e-test-up
	ANALYTICS_TEST_DSN=postgres://ecom_admin:test123@localhost:6435/mopro_ecom \
	  go test -tags=integration ./internal/analytics/... -count=1 -race -timeout 5m

# shipping ref_schema integration suite (P-034 live-PG, post-audit wiring; was on
# no CI job — see docs/internal/integration-tests-wiring.md). Reuses e2e-test-up's
# pg-ecom-e2e; the suite applies migrations/ecom/0085_shipping_zones.up.sql itself
# (verifying the seed). Non-recursive (./internal/shipping/ not /...) so the carrier
# adapter sub-packages — already unit-tested by `go test ./...` — aren't pulled in.
integration-shipping: e2e-test-up
	SHIPPING_TEST_DSN=postgres://ecom_admin:test123@localhost:6435/mopro_ecom \
	  go test -tags=integration ./internal/shipping/ -count=1 -race -timeout 5m

# Nightly soak (TOOLING_AUDIT T3-6): the concurrency-sensitive suites Step 2
# flagged for repeated -race stress (§6.3) — wallet RefreshWorker/reconcile (F-003),
# payment reconciler (F-001/F-006), identity rate-limiter (F-017). Run nightly by
# .github/workflows/nightly.yml; locally: `make soak SOAK_COUNT=10`.
SOAK_COUNT ?= 50
soak: pg-ledger-test-up e2e-test-up ## Stress concurrency suites (-race -count=$(SOAK_COUNT)).
	go test -tags=integration -race -skip 'Property' ./internal/wallet/... -count=$(SOAK_COUNT) -timeout 45m
	ORDER_TEST_DSN=postgres://ecom_admin:test123@localhost:6435/mopro_ecom \
	  go test -tags=integration -race ./internal/payment/... -count=$(SOAK_COUNT) -timeout 45m
	IDENTITY_TEST_DSN=postgres://ecom_admin:test123@localhost:6435/mopro_ecom \
	IDENTITY_TEST_REDIS=localhost:6381 \
	  go test -tags=integration -race ./internal/identity/... -count=$(SOAK_COUNT) -timeout 60m

# ── Catalog seed ───────────────────────────────────────────────────────────────

SEED_DATA_DIR ?= scripts/seed/data
SEED_BIN      := /tmp/mopro-seed

build-seed: ## Build the catalog seed CLI.
	go build -o $(SEED_BIN) ./scripts/seed/cmd/seed

# Dry-run against local stack (prints what would change, writes nothing).
seed-dry-run: build-seed ## Seed: dry run against local (no writes).
	$(SEED_BIN) \
	  --db-url="$${DATABASE_URL:-postgres://ecom_app:ecom_pass@localhost:5432/mopro_ecom?sslmode=disable}" \
	  --data-dir=$(SEED_DATA_DIR) \
	  --dry-run

# Full seed against staging (scope=all).
# Use FORCE=1 for a fresh reseed: make seed-staging FORCE=1
seed-staging: build-seed
	@test -n "$$STAGING_DATABASE_URL" || (echo "ERROR: STAGING_DATABASE_URL is not set"; exit 1)
	$(SEED_BIN) \
	  --db-url="$$STAGING_DATABASE_URL" \
	  --data-dir=$(SEED_DATA_DIR) \
	  --scope=all \
	  $(if $(filter 1,$(FORCE)),--force,)

# Full seed against production — requires explicit SEED_PROD=yes env guard.
seed-prod: build-seed
	@test "$$SEED_PROD" = "yes" || \
	  (echo "ERROR: set SEED_PROD=yes to confirm production seeding"; exit 1)
	@test -n "$$PROD_DATABASE_URL" || (echo "ERROR: PROD_DATABASE_URL is not set"; exit 1)
	$(SEED_BIN) \
	  --db-url="$$PROD_DATABASE_URL" \
	  --data-dir=$(SEED_DATA_DIR) \
	  --scope=all

# ── L9 Smoke + Load test ───────────────────────────────────────────────────
# Backend smoke: ~25 endpoint checks against a running stack.
# BASE defaults to staging; override: make smoke BASE=https://api.moproshop.com
BASE ?= https://api-staging.moproshop.com

smoke: ## Backend smoke test against a running stack.
	@echo "Running backend smoke against $(BASE)"
	BASE=$(BASE) bash scripts/smoke/run.sh | tee /tmp/smoke-backend.log
	@echo "Smoke log written to /tmp/smoke-backend.log"

# Load test: k6 ramping-VU scenario (requires k6 installed — https://k6.io/docs/get-started/installation/).
loadtest: ## Run the k6 load test.
	@command -v k6 >/dev/null 2>&1 || { echo "k6 not found. Install: brew install k6 or https://k6.io"; exit 1; }
	k6 run --env BASE=$(BASE) scripts/loadtest/k6-smoke.js | tee /tmp/k6-smoke.log
	@echo "k6 log written to /tmp/k6-smoke.log"

# ── Observability ──────────────────────────────────────────────────────────
# Push Grafana dashboards, alert rules, and notification policy to Grafana Cloud.
# Requires: GRAFANA_API_URL, GRAFANA_API_TOKEN env vars.
# Optional:  MIMIR_RULER_URL, GRAFANA_PROM_USER, GRAFANA_PROM_PASS for mimirtool alert push.
grafana-deploy: ## Push Grafana dashboards + alert rules to Grafana Cloud.
	@deploy/grafana/provision.sh
