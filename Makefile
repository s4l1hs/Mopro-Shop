COMPOSE := docker compose -f deploy/docker-compose.yml

.PHONY: verify fmt vet test lint boundaries property-cashback property-payout property-ledger property-timex \
        build-core build-fin build-jobs build-migrate build-mopro run-local down-local \
        caddy-validate caddy-reload \
        test-integration-catalog test-integration-outbox test-integration-cart

# verify chains all static checks; must pass before every push.
verify: fmt vet test lint boundaries property-cashback property-payout property-ledger property-timex

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
