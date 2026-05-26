# Multi-stage build for all three Mopro binaries.
# Build: docker buildx build --build-arg SERVICE=core-svc -t ghcr.io/mopro/core-svc .
# Runtime base: gcr.io/distroless/static-debian12:nonroot (CLAUDE.md §6)

ARG SERVICE=core-svc
ARG RUNTIME_BASE=gcr.io/distroless/static-debian12:nonroot
# BUILD_SHA: full 40-char git commit SHA. Injected by CI / make docker-build.
# When absent (local docker build without --build-arg), falls back to "dev".
ARG BUILD_SHA=dev
# BUILT_AT: RFC-3339 UTC timestamp. Set by make docker-build via $(shell date -u +%FT%TZ).
ARG BUILT_AT=

# ── Build stage ──────────────────────────────────────────────────────────────
FROM golang:1.25-alpine AS builder

# Re-declare ARGs after FROM so they are visible inside this stage.
ARG SERVICE
ARG BUILD_SHA
ARG BUILT_AT
WORKDIR /build

# Cache module downloads before copying source
COPY go.mod go.sum ./
RUN go mod download

# Copy source
COPY . .

# Build the requested binary; CGO disabled for static binary + distroless.
# BUILD_SHA and BUILT_AT are injected into internal/buildinfo via ldflags so
# that /__version returns the real commit SHA even when .git is absent (tarball builds).
RUN GOWORK=off CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -trimpath \
    -ldflags="-s -w \
      -X github.com/mopro/platform/internal/buildinfo.SHA=${BUILD_SHA} \
      -X github.com/mopro/platform/internal/buildinfo.BuiltAt=${BUILT_AT}" \
    -o /out/svc ./cmd/${SERVICE}

# ── Runtime stage ─────────────────────────────────────────────────────────────
FROM ${RUNTIME_BASE}

COPY --from=builder /out/svc /svc

EXPOSE 8080 9090

ENTRYPOINT ["/svc"]
