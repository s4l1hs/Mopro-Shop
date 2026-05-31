# Tranche 2b baseline — help/FAQ + contact form + support tickets (pre-PR)

Read-only §2 confirmation. `Exists — file:line` or `Missing`.

## Customer support surface

| Item | Finding |
|---|---|
| `help_categories` / `help_articles` tables | **Missing** — no help schema/tables anywhere. |
| `support_tickets` table | **Missing** — `support_schema` exists (`deploy/postgres-ecom/init/20-schemas.sql:17`, role `support_user` + grants `30-grants.sql:60`) but has **no tables**. |
| `internal/support` module | **Placeholder** — empty `Service`/`Repository` interfaces (`internal/support/api.go`); `domain.go`/`service.go`/`repository.go` are bare `package support`. |
| `internal/help` module | **Missing** — does not exist. |
| Help content endpoint | **Missing** |
| Support submission endpoint | **Missing** |
| `/help` route | **Placeholder** — `AccountPlaceholderScreen` (PR #19), `app_router.dart:351`; rail "Yardım" row → `/help`. |
| Contact-form widget | **Missing** |
| Markdown rendering | **Exists** — `flutter_markdown ^0.7.0` already in `pubspec.yaml` and used in `product_detail_screen.dart`. **No new package needed** (§3.6 adapts). |
| `url_launcher` | **Missing** — external markdown links render as styled text (no launching), per §3.6 fallback. |
| Rate-limit middleware | **None located** for HTTP handlers — guest/authed submission rate-limiting surfaced as Backlog (validation still enforced). |

## §2.2 module placement — decided via AskUserQuestion

Help is **public content** (guest-readable, cacheable); support tickets are
**private per-user records**. `support_schema` already exists; a help schema is
greenfield. Two shapes:
- **A — single `internal/support`** owns both help + tickets in `support_schema`
  (less surface; support_schema/role/grants already exist).
- **B — separate `internal/help` + `internal/support`** (`help_schema` +
  `support_schema`); cleanest separation, matches the Tranche 2a inbox precedent;
  adds a help_schema bootstrap (role + grants).

**Decision: B — separate `internal/help` + `internal/support`.** Help content
lives in a new `help_schema` (public, guest-readable) owned by a new
`internal/help` module; support tickets live in the existing `support_schema`
owned by `internal/support`. Migration 0072 bootstraps `help_schema`
(role/schema/grants + create-if-not-exists) and creates the three tables.

## Adaptations
1. **No new package:** `flutter_markdown` is already present + used — reuse it.
2. **External links:** no `url_launcher` → markdown external links render as
   styled (non-launching) text; internal app-path links route via go_router.
3. **Rate limiting:** no HTTP rate-limit middleware found → ticket validation
   ships; per-IP/per-user throttling is Backlog (noted in REPORT risks).
