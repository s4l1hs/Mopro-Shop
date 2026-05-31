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

**Chosen: Standard (~20 events).**

**Rationale.** The product intent is a *real recommendation surface* (the
`GET /recommendations` stub is already on the roadmap to be backed), not just a
recently-viewed rail — but not a heatmap/ML lab either. Minimal (8) cannot
express category affinity or facet intent, so backing the recommender later would
force a taxonomy migration — exactly the six-month rewrite this PR exists to
avoid. Rich (40+) buys per-pixel fidelity nobody has asked for, at a privacy and
maintenance cost that is wrong for the current stage. Standard is the smallest
taxonomy that still carries the *intent* signals (filter/sort/category/variant +
binned dwell) a recommender needs, while keeping every field coarse enough to
stay defensible under KVKK/GDPR. It is the "decision the choice resolves":
recommendation-capable without becoming surveillance-grade.

**Concrete event list (the locked v1 taxonomy).** All names are
`snake_case`; payloads are small typed JSON. Binning (not raw values) is a
deliberate privacy choice carried into Decision 5.

| Event | Key payload fields | Notes |
|---|---|---|
| `page_view` | `route`, `referrer?` | Every navigated route (auto-emitted, Decision 6). |
| `product_view` | `product_id`, `variant_id?`, `source?` | PDP open; `source` = where the click came from. |
| `category_view` | `category_id` | Category/PLP landing. |
| `search` | `query_hash`, `result_count` | Query is **hashed**, not stored raw (privacy). |
| `filter_applied` | `facet`, `value` | PLP filter (size/color/price-bucket/brand). |
| `sort_changed` | `sort_key` | PLP/reviews/Q&A sort. |
| `mega_menu_opened` | `menu_id` | Desktop discovery signal. |
| `pdp_variant_selected` | `product_id`, `variant_id` | Variant intent. |
| `scroll_depth` | `route`, `bucket` (10/25/50/75/100) | Binned; one event per bucket crossed. |
| `time_on_page` | `route`, `bucket` (e.g. <5s/5-30s/30-120s/>120s) | Binned on page-leave. |
| `add_to_cart` | `variant_id`, `qty` | Business event (manual, Decision 6). |
| `remove_from_cart` | `variant_id`, `qty` | Business event. |
| `purchase` | `order_id`, `item_count`, `total_minor`, `currency` | Business event; amounts in minor units. |
| `login` | `method?` | Auth lifecycle. |
| `logout` | — | Auth lifecycle. |
| `session_start` | `session_id`, `platform` | Emitted on first event of a session. |
| `session_end` | `session_id`, `duration_bucket` | Emitted on session timeout/close. |

That is 17 named events; the `scroll_depth` buckets and a small reserve
(`favorite_added`, `favorite_removed`, `notification_opened`) bring it to the
~20 envelope. New events append to this table; **renames are migrations** and
must be justified in a follow-up ADR.

## 3. Decision 2 — Storage shape

**Chosen: Append-only log + derived projection tables.**

**Rationale.** This is the shape the codebase is already built for. The
denormalized-cache discipline (`helpful_count`, `answer_count` refreshed in-tx,
documented in CONTRIBUTING "Storage-layer idempotency") is the same idea applied
to analytics: an immutable source of truth plus cheap-to-read derived state.
Option A (log-only) ships a day sooner but makes every personalization read a
live scan/aggregate over an unbounded table — the `GET /recommendations` query
would get slower every week. Option C (external broker) is the right shape *only*
if real-time recommendations or BI tooling were imminent; they are not, and a
Kafka/Redpanda container does not fit the 6-vCPU / 24 GB single-VDS budget
(`CLAUDE.md §7` — "the headroom IS the design"). Standard volume at this stage is
comfortably served by Postgres + a scheduled aggregator on the existing jobs-svc.
The decision the choice resolves: **cheap, bounded-cost reads for every
personalization surface, without new infrastructure.**

**Schema sketch.** Lives in its own `analytics_schema` in `postgres-ecom`
(jobs-svc owns the aggregator; writes arrive via the existing outbox → Redis
Streams path so no module reaches across a boundary). Cross-schema JOINs stay
forbidden — projections store denormalized display fields, like `UserReview` does.

```sql
-- Source of truth: append-only, never UPDATE/DELETE except retention prune.
CREATE TABLE analytics_schema.analytics_events (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  event_id    UUID        NOT NULL UNIQUE,         -- producer-supplied, idempotent
  user_id     BIGINT,                              -- NULL for guests
  session_id  TEXT        NOT NULL,                -- guest+authed both carry one
  type        TEXT        NOT NULL,                -- one of the locked taxonomy
  payload     JSONB       NOT NULL DEFAULT '{}',
  market      TEXT        NOT NULL,
  occurred_at TIMESTAMPTZ NOT NULL,                -- client/event time
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()   -- ingest time (retention anchor)
);
CREATE INDEX ON analytics_schema.analytics_events (user_id, occurred_at DESC);
CREATE INDEX ON analytics_schema.analytics_events (session_id, occurred_at);
CREATE INDEX ON analytics_schema.analytics_events (type, created_at);

-- Derived projections (refreshed by the jobs-svc aggregator; cheap to read).
CREATE TABLE analytics_schema.user_browsing_history (
  user_id      BIGINT NOT NULL,
  product_id   BIGINT NOT NULL,
  last_viewed  TIMESTAMPTZ NOT NULL,
  view_count   INT NOT NULL DEFAULT 1,
  PRIMARY KEY (user_id, product_id)
);
CREATE TABLE analytics_schema.user_search_history (
  user_id      BIGINT NOT NULL,
  query_hash   TEXT NOT NULL,
  query_sample TEXT,                               -- last raw query, only if consent allows
  last_searched TIMESTAMPTZ NOT NULL,
  search_count INT NOT NULL DEFAULT 1,
  PRIMARY KEY (user_id, query_hash)
);
CREATE TABLE analytics_schema.user_category_affinity (
  user_id     BIGINT NOT NULL,
  category_id BIGINT NOT NULL,
  score       NUMERIC NOT NULL,                    -- decayed interaction weight
  updated_at  TIMESTAMPTZ NOT NULL,
  PRIMARY KEY (user_id, category_id)
);
```

**Event flow.**

```mermaid
flowchart LR
  subgraph client[Flutter app]
    OBS[Riverpod observer<br/>+ manual call sites]
    GATE{consent<br/>gate}
    OBS --> GATE
  end
  GATE -- allowed --> ING["POST /events (batch)<br/>core-svc ingest"]
  GATE -- denied --> DROP[(dropped<br/>client-side)]
  ING --> OUT[(outbox<br/>same tx)]
  OUT --> XADD[Redis Stream<br/>analytics.events.v1]
  XADD --> CONS[jobs-svc<br/>analytics consumer]
  CONS --> EVT[(analytics_events<br/>append-only)]
  CONS --> AGG[scheduled aggregator]
  AGG --> PROJ[(projection tables:<br/>browsing / search / affinity)]
  PROJ --> REC["GET /recommendations<br/>+ history reads"]
```

The ingest endpoint writes to `analytics_events` and the outbox in one
transaction (the §4.5 outbox rule), so a consumer crash never loses events and
re-delivery is idempotent on `event_id`.

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
