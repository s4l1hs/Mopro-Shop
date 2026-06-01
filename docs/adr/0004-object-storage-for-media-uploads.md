# ADR 0004: Object Storage for User Media Uploads

- **Status:** Accepted
- **Date:** 2026-06-01
- **Phase introduced:** Photo upload shared infra (reviews + returns)
- **Decided by:** Human owner (storage-backend AskUserQuestion → Option A)
- **Related:** CLAUDE.md § 8 (Tech Stack Lock), CLAUDE.md § 5 (DB rules), ADR-0001,
  `internal/storage`, `internal/attachments`, `internal/media` (jobs-svc stub, unchanged), `pkg/mediaurl`

## Context

User-generated photo uploads (review photos, return photos) have been a Backlog
item since Tranche 1 (returns) and Tranche 3 (reviews). They need durable object
storage. The audit (`tool/audit/photo_upload_baseline.md`) found:

- `internal/media` was an empty stub (`Service interface{}`); no upload pipeline.
- No S3/B2/MinIO SDK in `go.mod`; no storage container in
  `deploy/docker-compose.yml`.
- Backblaze B2 is **already in the locked stack** (CLAUDE.md § 8: "Backup: Restic
  + Backblaze B2"), but its creds (`B2_*`) are used only by the Restic backup
  service — there is no app-facing media bucket.
- `pkg/mediaurl.CDNUrl(key)` already resolves storage keys → CDN URLs.

CLAUDE.md § 8 / § 2.2 require an ADR + human approval to add a new tool. Adding a
local dev object-storage service (MinIO) and an S3 SDK is such an addition.

## Decision

**App media uploads use S3-compatible object storage — Backblaze B2 in
production (the already-locked stack), MinIO for local dev/CI.**

- New Go dependency: `aws-sdk-go-v2` (S3 client). Justification: the ecosystem-
  standard S3 API client; B2 and MinIO both speak the S3 API, so one client code
  path serves dev, CI, and prod. (CLAUDE.md § 10 dependency justification.)
- New local-dev tool: a **MinIO** service in `deploy/docker-compose.yml`
  (dev/CI only; production uses B2, no MinIO). This is the new tool this ADR
  authorizes.
- New packages `internal/storage` (S3 client, shared) + `internal/attachments`
  (core-svc; owns attachments_schema, the consumer-UGC photo store for reviews +
  return items — distinct from the jobs-svc `media` product-image pipeline per
  CLAUDE.md §2.3) expose a `PhotoStorage` interface
  (`Put`/`Get`/`Delete`/`PublicURL`) with an S3 implementation. A filesystem
  implementation backs tests + dev-without-creds.
- **Gated by `STORAGE_ENABLED` (default false).** Until an app B2 bucket + app
  creds are provisioned (ops follow-up), the upload endpoint returns 503 and the
  consumer surfaces (review/return photo pickers) stay dormant. This follows the
  PR #28 `kAnalyticsConsentEnabled` flag precedent and the §1.6 escape-hatch #1
  of the photo-upload prompt.

### Storage layout & integrity
- Keys: `{entity_type}/{userId}/{uuid}.{ext}` — immutable, opaque.
- Public URLs via `pkg/mediaurl.CDNUrl` (CDN-fronted) or the bucket's public base.
- `photo_attachments` rows carry the storage key; cross-schema soft references
  only (no FK to reviews/returns), per CLAUDE.md § 5 / CONTRIBUTING.

### Not chosen
- **Local filesystem only (Option C):** simplest but not production-viable at
  scale; rejected because B2 is already the locked stack and the S3 path also
  covers dev via MinIO.
- **Presigned browser→bucket upload:** server-mediated chosen for v1 (single
  validation code path: magic-number MIME sniff + dimension decode + size cap).
  Presigned flow is Backlog if scale demands it.

## Consequences

- Ops must provision an app B2 bucket + app key (distinct from the backup bucket)
  and set `STORAGE_ENDPOINT/BUCKET/ACCESS_KEY/SECRET_KEY/REGION` +
  `STORAGE_ENABLED=true` before the consumer surfaces ship (carried to 4b).
- `aws-sdk-go-v2` enlarges the Go dependency tree (justified above).
- MinIO is dev/CI-only; it must never appear in `docker-compose.prod.yml`.
- Moderation + virus-scan remain Backlog (placeholder hooks at the upload path).
