COMPOSE := docker compose -f deploy/docker-compose.yml

.PHONY: verify fmt vet test lint boundaries property-cashback property-payout property-ledger \
        build-core build-fin build-jobs build-migrate build-mopro run-local down-local

# verify chains all static checks; must pass before every push.
verify: fmt vet test lint boundaries property-cashback property-payout property-ledger

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
