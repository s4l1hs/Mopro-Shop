# Audit — Photo Upload Shared Infra (reviews + returns)

Read-only baseline. file:line + observation.

## Branch-point (§1.1)
- PR #33 merged into `feat/seller-facing-and-platform-growth` (tip `72347c7f`) =
  5a+slug+5b+dashboard, **not on main** (main `3234ac92`). Branched
  `feat/photo-upload-shared-infra` off it (stacking precedent). `make verify`
  green → no §1.1 hygiene commit.

## §2.2 Storage backend — UNPROVISIONED for app uploads (gates §3)
- `internal/media` is an **empty stub**: `api.go` has `Service interface{}` /
  `Repository interface{}`; domain/service/repository/errors are bare `package
  media`. Doc says "image upload, resize, Backblaze B2 (jobs-svc)" — intent, not
  implementation.
- **No S3/B2/MinIO SDK** in `go.mod`. No upload endpoint, no multipart handler.
- **No storage container** in `deploy/docker-compose.yml` (no MinIO/seaweed).
- B2 creds (`B2_KEY_ID/APP_KEY/BUCKET`) exist **only for Restic backups**
  (`deploy/systemd/mopro-backup.service`, `install-backup.sh`) — a backup bucket,
  not an app media bucket.
- READ side exists: `pkg/mediaurl.CDNUrl(key)` → prepends `CDN_BASE_URL`
  (key unchanged when unset). Products/sellers store keys + resolve via CDNUrl.
- **CLAUDE.md §8 locks the stack** (Backup: Restic + Backblaze B2). §2.2/§8:
  adding a **new tool requires an ADR + human approval**; §10: never add deps
  casually. ⇒ Option A's MinIO-for-dev is a new tool (ADR); an S3 SDK is a new
  Go dep (justify). This is an ESCALATION-class decision (CLAUDE.md §12) — hence
  the §2.1 AskUserQuestion gates §3.

## §2.3 Image-handling utilities (frontend)
- `cached_network_image: ^3.4.1` + **`photo_view: ^0.15.0`** already in pubspec
  (photo_view gives the lightbox pinch-zoom for free).
- `lib/design/widgets/responsive_network_image.dart` (ResponsiveNetworkImage, `?w=`).
- **No `image_picker`/`file_picker`** → §4 adds `image_picker` (justify).

## §2.4 Review / Return DTOs — no photo fields
- No `photo`/`attachment` field on review or return wire shapes. Reviews + returns
  are **hand-written endpoints** (catalog `ugc.go` / order `returns.go`), not
  generated DTOs → §3.7 OpenAPI regen NOT needed for these (the response maps are
  built by hand in the handlers). The new `photo_attachments` array is added to
  the hand-built JSON.

## §2.5 Volume + limits (defaults adopted — seed-scale, low volume)
- Max 5 MB/photo; 5 photos/review; 3 photos/return-item.
- Accept `image/jpeg`, `image/png`, `image/webp` (magic-number sniff, not the
  client header). Dimensions 200×200 … 4096×4096. Rate limit 50 uploads/user/hr.

## §2.1 Storage backend decision — surfaced via AskUserQuestion
Reality-grounded options:
- **A — S3-compatible (Backblaze B2).** Matches CLAUDE.md's locked stack + the
  media stub's intent. Needs: an app B2 bucket + app creds (ops provisioning), an
  S3 Go SDK (dep, justify), and MinIO in compose for local dev (**new tool → ADR
  per CLAUDE.md §8**). Production-grade. Per §1.6 #1, until provisioned the
  endpoint ships behind a flag and consumers stay dormant.
- **B — Reuse existing.** Not viable: `internal/media` is an empty stub; nothing
  functional to reuse.
- **C — Local filesystem** (`PHOTO_STORAGE_PATH` + a static/Caddy handler +
  `CDN_BASE_URL`/served path for `PublicURL`). No new tool/infra, **no ADR**,
  simplest; prod must later provision B2. Behind a flag; viable at the audited
  low volume for dev/staging.

## Baselines (§1.3)
- `go test ./...` green; `flutter analyze` clean; `flutter build web` ~4.56 MB
  (dashboard); `flutter test` Linux-baselined goldens. Parity ~60%.
