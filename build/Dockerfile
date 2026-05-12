# Multi-stage build for all three Mopro binaries.
# Build: docker buildx build --build-arg SERVICE=core-svc -t ghcr.io/mopro/core-svc .
# Runtime base: gcr.io/distroless/static-debian12:nonroot (CLAUDE.md §6)

ARG SERVICE=core-svc
# RUNTIME_BASE default: distroless for production (CLAUDE.md § 6).
# Phase 0.5 stubs set RUNTIME_BASE=alpine:3.19 so nc/wget are available for
# network isolation verification.
#
# TODO(Phase 1): Switch RUNTIME_BASE back to distroless.
# VIOLATION: alpine:3.19 violates CLAUDE.md § 6 (distroless ONLY at runtime).
# Fix: add a --health subcommand to each binary that does:
#   resp, err := http.Get("http://localhost:8080/healthz"); exit 0 if 200, else exit 1
# Then in docker-compose.yml use:
#   healthcheck: { test: ["CMD", "/svc", "--health"], ... }
# The binary runs its own healthcheck — no shell or nc needed → distroless works.
ARG RUNTIME_BASE=gcr.io/distroless/static-debian12:nonroot

# ── Build stage ──────────────────────────────────────────────────────────────
FROM golang:1.25-alpine AS builder

ARG SERVICE
WORKDIR /build

# Cache module downloads before copying source
COPY go.mod go.sum ./
RUN go mod download

# Copy source
COPY . .

# Build the requested binary; CGO disabled for static binary + distroless
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -trimpath -ldflags="-s -w" \
    -o /out/svc ./cmd/${SERVICE}

# ── Runtime stage ─────────────────────────────────────────────────────────────
FROM ${RUNTIME_BASE}

COPY --from=builder /out/svc /svc

EXPOSE 8080 9090

ENTRYPOINT ["/svc"]
