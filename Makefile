COMPOSE      := docker compose -f deploy/docker-compose.yml
COMPOSE_PROD := docker compose -f deploy/docker-compose.prod.yml

# Production deploy settings — override on CLI: make deploy SERVER=mopro@195.85.207.92
SERVER   ?= mopro@195.85.207.92
SSH_PORT ?= 4625
SSH_USER ?= mopro
VERSION  ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)

OAPI_CODEGEN_VERSION  := v2.4.1
OPENAPI_GEN_VERSION   := v7.10.0
OPENAPI_GEN_IMAGE     := openapitools/openapi-generator-cli:$(OPENAPI_GEN_VERSION)

.PHONY: verify fmt vet test lint boundaries property-cashback property-payout property-ledger property-timex property-order \
        build-core build-fin build-jobs build-migrate build-mopro run-local down-local \
        caddy-validate caddy-reload \
        test-integration-catalog test-integration-outbox test-integration-cart test-integration-order \
        test-integration-sellerpayout test-e2e \
        api-gen-models api-gen-core api-gen-fin api-gen-dart api-gen api-lint contract-test \
        docker-build release deploy rollback

# verify chains all static checks; must pass before every push.
verify: fmt vet test lint boundaries property-cashback property-payout property-ledger property-timex property-order

fmt:
	gofmt -l . | tee /tmp/gofmt.out
	test ! -s /tmp/gofmt.out

vet:
	go vet ./...

test:
	go test -race ./...

lint:
	golangci-lint run

boundaries:
	./scripts/check-module-boundaries.sh

property-cashback:
	go test -tags=integration -run Property ./internal/cashback/...

property-payout:
	go test -tags=integration -run Property ./internal/sellerpayout/...

property-ledger:
	go test -tags=integration -run Property ./internal/wallet/...

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

build-migrate:
	go build -o /tmp/migrate-tool ./cmd/migrate-tool

build-mopro:
	go build -o /tmp/mopro ./cmd/mopro

run-local:
	mkdir -p ./data/postgres-ecom ./data/postgres-ledger ./data/redis ./data/meili
	$(COMPOSE) --env-file .env.local up -d --build

down-local:
	$(COMPOSE) --env-file .env.local down

caddy-validate:
	$(COMPOSE) --env-file .env.local exec caddy caddy validate --config /etc/caddy/Caddyfile

caddy-reload:
	$(COMPOSE) --env-file .env.local exec caddy caddy reload --config /etc/caddy/Caddyfile

# ── Production build + deploy ─────────────────────────────────────────────────

# Build all three service images with VERSION tag.
docker-build:
	docker build --platform=linux/amd64 --build-arg SERVICE=core-svc \
	  -t mopro/core-svc:$(VERSION) -f build/Dockerfile .
	docker build --platform=linux/amd64 --build-arg SERVICE=fin-svc \
	  -t mopro/fin-svc:$(VERSION) -f build/Dockerfile .
	docker build --platform=linux/amd64 --build-arg SERVICE=jobs-svc \
	  -t mopro/jobs-svc:$(VERSION) -f build/Dockerfile .

# Save images as tarballs in bin/ ready for scp to VDS.
release: docker-build
	mkdir -p bin
	docker save mopro/core-svc:$(VERSION) -o bin/core-svc-$(VERSION).tar
	docker save mopro/fin-svc:$(VERSION)  -o bin/fin-svc-$(VERSION).tar
	docker save mopro/jobs-svc:$(VERSION) -o bin/jobs-svc-$(VERSION).tar
	@echo "Tarballs written to bin/ — run 'make deploy' to ship"

# Upload + rolling restart on VDS.
deploy: release
	VERSION=$(VERSION) SERVER=$(SERVER) SSH_PORT=$(SSH_PORT) \
	  ./deploy/scripts/deploy.sh $(VERSION)

# Restore previous image set on VDS.
rollback:
	SERVER=$(SERVER) SSH_PORT=$(SSH_PORT) ./deploy/scripts/rollback.sh

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

test-integration-outbox:
	docker rm -f pg-ledger-test redis-outbox-test 2>/dev/null || true
	docker run -d --name pg-ledger-test -p 6434:5432 \
	  -e POSTGRES_USER=ledger_admin -e POSTGRES_PASSWORD=test123 \
	  -e POSTGRES_DB=mopro_ledger postgres:16-alpine
	docker run -d --name redis-outbox-test -p 6380:6379 redis:7-alpine
	sleep 3
	for f in $$(ls deploy/postgres-ledger/init/*.sql | sort); do \
	  docker exec -i pg-ledger-test psql -U ledger_admin -d mopro_ledger < $$f || exit 1; \
	done
	go test -tags=integration -count=1 -race ./internal/eventbus/... ./internal/outbox/... ; \
	  STATUS=$$? ; docker rm -f pg-ledger-test redis-outbox-test ; exit $$STATUS

test-integration-cart:
	docker rm -f redis-cart-test 2>/dev/null || true
	docker run -d --name redis-cart-test -p 6380:6379 redis:7-alpine
	sleep 1
	CART_TEST_REDIS=localhost:6380 \
	  go test -tags=integration -count=1 -race ./internal/cart/... ; \
	  STATUS=$$? ; docker rm -f redis-cart-test ; exit $$STATUS

test-integration-order:
	docker rm -f pg-ecom-order-test 2>/dev/null || true
	docker run -d --name pg-ecom-order-test -p 6435:5432 \
	  -e POSTGRES_USER=ecom_admin -e POSTGRES_PASSWORD=test123 \
	  -e POSTGRES_DB=mopro_ecom postgres:16-alpine
	sleep 2
	ORDER_TEST_DSN=postgres://ecom_admin:test123@localhost:6435/mopro_ecom \
	  go test -tags=integration -count=1 -race ./internal/order/... ; \
	  STATUS=$$? ; docker rm -f pg-ecom-order-test ; exit $$STATUS

test-integration-sellerpayout:
	docker rm -f pg-ledger-sp-test 2>/dev/null || true
	docker run -d --name pg-ledger-sp-test -p 6434:5432 \
	  -e POSTGRES_USER=ledger_admin -e POSTGRES_PASSWORD=test123 \
	  -e POSTGRES_DB=mopro_ledger postgres:16-alpine
	sleep 3
	for f in $$(ls deploy/postgres-ledger/init/*.sql | sort); do \
	  docker exec -i pg-ledger-sp-test psql -U ledger_admin -d mopro_ledger < $$f || exit 1; \
	done
	SELLERPAYOUT_TEST_DSN=postgres://ledger_admin:test123@localhost:6434/mopro_ledger \
	  go test -tags=integration -count=1 -race ./internal/sellerpayout/... ; \
	  STATUS=$$? ; docker rm -f pg-ledger-sp-test ; exit $$STATUS

# ── OpenAPI codegen targets ────────────────────────────────────────────────────

api-lint:
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

api-gen: api-gen-models api-gen-core api-gen-fin api-gen-dart

contract-test:
	go test -tags=contract -v ./internal/api/...

# ── Diff enforcement (called by CI) ────────────────────────────────────────────

api-check-sync:
	@git diff --exit-code internal/api/gen/ mobile/packages/mopro_api/ || \
		(echo "\nERROR: Generated files out of sync with api/openapi.yaml. Run 'make api-gen' and commit." && exit 1)

# ── e2e ────────────────────────────────────────────────────────────────────────

test-e2e:
	docker rm -f pg-ecom-e2e pg-ledger-e2e redis-e2e 2>/dev/null || true
	docker run -d --name redis-e2e -p 6381:6379 redis:7-alpine
	docker run -d --name pg-ecom-e2e -p 6435:5432 \
	  -e POSTGRES_USER=ecom_admin -e POSTGRES_PASSWORD=test123 \
	  -e POSTGRES_DB=mopro_ecom postgres:16-alpine
	docker run -d --name pg-ledger-e2e -p 6436:5432 \
	  -e POSTGRES_USER=ledger_admin -e POSTGRES_PASSWORD=test123 \
	  -e POSTGRES_DB=mopro_ledger postgres:16-alpine
	sleep 3
	REDIS_E2E_ADDR=localhost:6381 \
	ORDER_E2E_DSN=postgres://ecom_admin:test123@localhost:6435/mopro_ecom \
	LEDGER_E2E_DSN=postgres://ledger_admin:test123@localhost:6436/mopro_ledger \
	  go test -tags=integration -count=1 -race -v ./internal/e2e/... ; \
	  STATUS=$$? ; docker rm -f pg-ecom-e2e pg-ledger-e2e redis-e2e ; exit $$STATUS
