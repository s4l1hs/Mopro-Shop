# Tranche 2 baseline — notifications + customer support surface (pre-PR)

Read-only §2 confirmation. `Exists — file:line` or `Missing`.

## Notifications

| Item | Finding |
|---|---|
| User-facing `notifications` table | **Missing** — `notification_schema` exists but holds only `slack_sent` (jobs-svc reconcile-drift dedup, `deploy/postgres-ecom/init/90-notification-schema.sql`). No user-targeted message table. |
| `internal/notification` module | **Placeholder** — `Service`/`Repository` are empty interfaces (`internal/notification/api.go`); real content is the Slack drift consumer (`reconcile_consumer.go`), not user notifications. |
| List endpoint for user messages | **Missing** |
| Unread-count / badge widget | **Missing** — no `NotificationBadge`; `AccountLeftRail` "Bildirimler" row routes to the `/account/notifications` placeholder (`account_left_rail.dart:65`). |
| Push-token persistence | **Partial** — `identity_schema.devices` (`fcm_token`, `device_model`, `os_version`) via `identity.RegisterDevice` + `POST /me/devices` (`internal/identity/api.go:43`). Mobile-FCM oriented; no generic web/ios token table. |
| Notification preferences | **Missing** |
| Email/SMS templating | **Missing** (transactional email/OTP send exists in identity, no template system) |

## Customer support

| Item | Finding |
|---|---|
| `help_categories` / `help_articles` | **Missing** |
| `support_tickets` table | **Missing** — `support_schema` exists (`20-schemas.sql`, grants) but has no tables. |
| `internal/support` module | **Placeholder** — empty `Service`/`Repository` interfaces (`internal/support/api.go`). |
| Help content endpoint | **Missing** |
| `/help` route | **Placeholder** — `AccountPlaceholderScreen` (PR #19); rail "Yardım" row → `/help` (`account_left_rail.dart:68`). |
| Contact-form widget | **Missing** |

## Account rail integration points

- `AccountRailItem` enum has `notifications` + `help` (`account_rail_item.dart:11-12`).
- `accountRailItemFor`: `/account/notifications*` → notifications; `/help*` → help (sub-routes already inherit highlight — `/account/notifications/preferences`, `/help/contact` will highlight correctly).
- Rows: Bildirimler at `account_left_rail.dart:65` (→ `/account/notifications`), Yardım at `:68` (→ `/help`).

## Scope assessment (§1.6) — SPLIT INVOKED

**Both domains are greenfield** (no tables, empty modules, placeholder routes). Concrete scope, compared to Tranche 1 (one backend domain + ~6 frontend components + 3 flows + 8 goldens — which consumed a full session):

| | Notifications (2a) | Customer support (2b) |
|---|---|---|
| Migrations | 0071 (3 tables) | 0072 (3 tables + **32-article × 4-locale seed**) |
| Endpoints | 8 | 7 |
| Leaf widgets | 2 (badge, row) | 2 (category card, contact form) |
| Screens | 2 (list, preferences) + rail/header badge wiring | 5 (index, category, article, search, contact) + markdown package |
| Flows | Y | Z |
| Goldens | ~7 | ~9 |

Two greenfield domains ≈ **2× Tranche 1**. Per §1.6, **partial-and-green beats full-and-red**: this PR ships **2a (notifications)** in full; **2b (customer support)** is carried forward to a fresh `feat/customer-support` PR. Notifications lands first per §1.6 (it provides the `NotificationBadge` surface that support's future "your ticket has a reply" notification will use). The §3.2/§3.4/§3.5 (help + tickets) backend, §4.3/§4.4 + §6 (help screens + contact form), and flow Z are deferred to 2b.

## Adaptations (2a)

1. **Push tokens:** add `notification_schema.push_tokens` (generic web/android/ios) per the prompt; note the existing `identity_schema.devices` (mobile FCM) as the precedent — registration was already Partial, now extended for web.
2. **Schema placement:** notifications tables go in `notification_schema` (consistent with the existing bootstrap), not the unqualified `notifications` the prompt sketches.
