# Tranche 4 Design — Personalization + Analytics Foundation

> **Status:** design document (no production code). This is the input contract
> for the Tranche 4 implementation PRs (4a, 4b, …). It locks seven architectural
> decisions so the implementation PRs consume them instead of relitigating them
> mid-build. Wrong taxonomy → migration in six months; wrong consent model →
> regulatory exposure; wrong storage shape → recommendation-infra rewrite. One
> deliberate design PR is cheap insurance.

## Table of contents

1. [Current state](#1-current-state)
2. [Decision 1 — Event taxonomy](#2-decision-1--event-taxonomy)
3. [Decision 2 — Storage shape](#3-decision-2--storage-shape)
4. [Decision 3 — Consent model](#4-decision-3--consent-model)
5. [Decision 4 — Identity model](#5-decision-4--identity-model)
6. [Decision 5 — Retention policy](#6-decision-5--retention-policy)
7. [Decision 6 — Instrumentation pattern](#7-decision-6--instrumentation-pattern)
8. [Decision 7 — Bundle shape](#8-decision-7--bundle-shape)
9. [Implementation tranche split](#9-implementation-tranche-split)
10. [Open questions](#10-open-questions)
11. [Risk notes](#11-risk-notes)
12. [Glossary](#12-glossary)

---

## 1. Current state

Evidence-based baseline (read-only audit, 2026-05-31). Each row is what exists
*today* on `main` after Tranche 3 (#25) merged.

| Capability | Current state (evidence) |
|---|---|
| Flutter analytics SDK | **None** — no analytics/telemetry dependency in `mobile/pubspec.yaml` (no firebase/sentry/mixpanel/amplitude/posthog/segment). |
| Search history (client) | **Partial** — `RecentSearchesNotifier` (`mobile/lib/features/catalog/providers/recent_searches_provider.dart`): local `SharedPreferences` only, max 5, key `mopro_recent_searches`; never leaves the device. |
| Browsing / recently-viewed history | **Missing** — no `recentlyViewedProvider`; the home "Son baktıkların" rail is unbuilt (REPORT backlog, "hide-when-empty"). |
| Backend analytics events | **None** — `internal/eventbus/registry.go` carries *business* events only (`ecom.order.delivered.v1`, `ecom.payment.captured.v1`, `ecom.user.created.v1`, …). No `analytics_events` / `audit_log` / `event_log` table anywhere. |
| Event transport | **Redis Streams + outbox** — `internal/eventbus/redis_bus.go` + `internal/outbox` (transactional outbox → XADD). The established async path. |
| External event broker | **Absent** — `deploy/docker-compose.yml` runs postgres-ecom, postgres-ledger, pgbouncer ×2, redis, meilisearch, caddy, core/fin/jobs-svc, grafana-agent. No Kafka/Redpanda/NATS/Pulsar. |
| Recommendations API | **Stubbed** — `GET /recommendations` returns 501 (`internal/api/core_impl.go:74`); endpoint exists, no data behind it. |
| Aggregation host (cron) | **jobs-svc exists** (notification/support/media/sizefinder); fin-svc owns the cashback/payout crons. No analytics aggregator yet. |
| Object storage | **Referenced, not provisioned** — `internal/media/api.go` names Backblaze B2 (external), but no MinIO/S3 container in compose; not on the analytics critical path. |
| Guest→user merge precedent | **Present** — `mergeGuestCart` POSTs `/cart/merge` on login, then clears the local guest cart (`mobile/lib/features/cart/application/cart_merge_service.dart`); favorites follow the same shape. |
| Guest personalization hook | **Present** — `OptionalAuth` middleware (`internal/identity/middleware/auth.go:61`) exposes the user id to public reads when a token is present, else treats the caller as a guest. |
| Consent / cookie / tracking UX | **None for analytics** — only checkout *legal* checkboxes (`consent_sales`, `consent_distance_contract`) and a `privacy` label in the locale files. No tracking-consent surface. |
| Consent category system | **None** — the only preference system is the theme (light/dark); no precedent for toggle-by-category. |
| Regulatory posture | **Documented, not enforced** — `CLAUDE.md §6`: KVKK (TR launch) / GDPR (EU) / PDPL (UAE), deferred to jurisdiction; no consent gating in code today. |
| Denormalized-projection discipline | **Established** — `helpful_count`, `answer_count` refreshed in-tx (CONTRIBUTING "Storage-layer idempotency"); the precedent for derived analytics projection tables. |

**Reading of the baseline.** The async plumbing (Redis Streams + outbox) and the
derived-cache discipline already exist; an analytics pipeline is a *new consumer
of established patterns*, not new infrastructure. The two genuinely new surfaces
are (a) an analytics event store and (b) a tracking-consent UX — and the consent
surface is greenfield with real regulatory weight. The decisions below resolve
those tradeoffs before code lands.

---

## 2. Decision 1 — Event taxonomy

_(pending decision)_

## 3. Decision 2 — Storage shape

_(pending decision)_

## 4. Decision 3 — Consent model

_(pending decision)_

## 5. Decision 4 — Identity model

_(pending decision)_

## 6. Decision 5 — Retention policy

_(pending decision)_

## 7. Decision 6 — Instrumentation pattern

_(pending decision)_

## 8. Decision 7 — Bundle shape

_(pending decision)_

## 9. Implementation tranche split

_(derived from Decision 7)_

## 10. Open questions

_(populated during synthesis)_

## 11. Risk notes

_(populated during synthesis)_

## 12. Glossary

_(populated during synthesis)_
