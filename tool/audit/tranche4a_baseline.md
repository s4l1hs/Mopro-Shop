# Tranche 4a baseline audit (read-only)

Re-verification of `TRANCHE_4_DESIGN.md` §1 at implementation time, plus the
three merge-blocker resolutions. Date: 2026-05-31. Base: `main` @ PR #26 merged.

## 2.1 Analytics infrastructure surface

| Item | State | Evidence |
|---|---|---|
| `analytics_events` / `session_identity` / `user_consent` / `user_recently_viewed` | **Missing** | no such tables in `migrations/` or `internal/`. |
| Backend event-emit | **Business events only** | `internal/eventbus/registry.go` (`ecom.order.*`, `ecom.user.*`, …); no analytics events. |
| Flutter instrumentation (`track`/telemetry) | **Missing** | no `analyticsService`/`.track(`/`logEvent` anywhere in `mobile/lib/`. |
| `GET /recommendations` | **501-stubbed** | `internal/api/core_impl.go:74` returns `notImplemented501`; route at `cmd/core-svc/main.go:412`. |

## 2.2 Recently-viewed — **prompt premise is INCORRECT**

The 4a prompt §2.2/§7.1/§7.2 assume a Session-5a `recentlyViewedProvider`
exists (local-only) and a "Son baktıkların" home rail is already built, framing
§7 as a *refactor*. **Neither exists.**

- **Missing** — no `recentlyViewedProvider` / `recently_viewed` in `mobile/lib/`.
- The home rail is **explicitly omitted**: `home_screen.dart:109–130` documents
  the desktop "Editor's picks / Recently viewed" sub-section with the
  recently-viewed column *omitted* "while there is no local recently-viewed
  history provider (hide-when-empty)".
- What *does* exist is `RecentSearchesNotifier` (`recent_searches_provider.dart`)
  — **search** history, local `SharedPreferences`, not **browsing**/recently-viewed.

**Implication:** §7 is **build-from-scratch** (create `recentlyViewedProvider` +
build the home rail), not a refactor — larger than the prompt budgeted. This is
consistent with the design doc's own §1 ("Browsing / recently-viewed history —
Missing"). Drives the scope assessment below.

## 2.3 Guest merge precedent (mirror target for session_identity)

- `mobile/lib/features/cart/application/cart_merge_service.dart`: `mergeGuestCart`
  → `POST /cart/merge` (then clears local), and `mergeGuestFavorites`.
- Backend route `POST /cart/merge` at `cmd/core-svc/main.go:447`.
- Shape to mirror: post-auth hook calls a merge endpoint; idempotent server-side.

## 2.4 Account-deletion (merge-blocker #3) — **EXISTS; soft-delete + event**

- `DELETE /me` → `handleDeleteMe` (`cmd/core-svc/auth_handlers.go:238`) →
  `identity.DeleteMe` (`service.go:277`) → `repo.SoftDeleteWithRevoke` — a
  **soft delete** (sets `deleted_at`, revokes tokens; the `users` row is NOT
  removed).
- It emits **`ecom.user.soft_deleted.v1`** (`registry.go:202`,
  `StatusActiveEmittedNoConsumer`, Notes: *"Emitted on DELETE /me. Future: data
  erasure pipeline."*).

**Resolution for blocker #3:** analytics erasure is wired as a **jobs-svc
consumer of `ecom.user.soft_deleted.v1`** (the anticipated erasure pipeline) —
it `DELETE`s the user's rows from the four analytics tables. This keeps the
erasure event-driven and avoids any cross-module/cross-schema reach from
`internal/identity`. **Note:** because `DELETE /me` is a *soft* delete, an
`ON DELETE CASCADE` FK on `users(id)` would **never fire** — a second reason the
prompt's FK approach is wrong (see below).

## 2.5 Privacy / consent infrastructure

- **No tracking-consent UX.** Only checkout *legal* checkboxes
  (`consent_sales`, `consent_distance_contract`) + a `privacy` label.
- Settings analog: `NotificationPreferencesScreen`
  (`mobile/lib/features/notifications/notification_preferences_screen.dart`) —
  the closest pattern for the "Analitik İzleme" consent row.

## Cross-schema FK conflict (prompt §3.1 vs. constitution + locked design)

The prompt's §3.1 SQL declares `user_id BIGINT … REFERENCES users(id) ON DELETE
CASCADE` (and `product_id … REFERENCES products(id)`). `users` lives in
`identity_schema`, `products` in `catalog_schema`, so those are **cross-schema
FKs**. This conflicts with:

1. **Locked design** `TRANCHE_4_DESIGN.md` Decision 4 / §3 — "`user_id` as plain
   BIGINT — no cross-schema FK"; merge via `session_identity`.
2. **`CLAUDE.md §5`** — module-owns-schema; soft references the established way.
3. **Tranche 3 precedent** — `product_questions.user_id` is a plain BIGINT.
4. **The soft-delete fact** above — CASCADE would never fire anyway.

The prompt itself acknowledges the soft-reference pattern in its §3.1 comment
("`analytics_events.user_id` is NOT FK-constrained … per CONTRIBUTING") and §15
("Cross-schema soft references via plain BIGINT columns (no FK)").

**Resolution:** all four analytics tables use **plain BIGINT soft references**
(no FK) for `user_id` and `product_id`; integrity at the app layer; erasure via
the `ecom.user.soft_deleted.v1` consumer. This is the constitution-compliant,
design-doc-faithful reconciliation of the intra-prompt inconsistency.

## Schema / role placement

New `analytics_schema` (postgres-ecom). Ingest endpoint lives in core-svc; the
prune/rebuild jobs + erasure consumer live in jobs-svc — both connect to
postgres-ecom, so `analytics_schema` needs grants for both their DB roles (new
`analytics_user` + cross-grants, mirroring how `notification_schema` is set up
across init scripts).

## Scope assessment + §1.6 escape-hatch trigger

Concrete data (post-audit, pre-§3):
- **Backend §3 is a full large PR on its own:** new `analytics_schema` + role +
  grants (init scripts), migration `0075` (4 tables), `internal/analytics`
  (domain + 20-event enum/payload validation + repository + service), **6
  endpoints** (ingest, identify+backfill, GET/PUT/DELETE consent,
  recently-viewed read) wired into core-svc, **2 cron jobs** + the erasure
  **event consumer** wired into jobs-svc, and ~15 backend tests.
- **§7 is build-from-scratch, not a refactor** (2.2 above) — `recentlyViewedProvider`
  and the home rail do not exist — enlarging the frontend beyond the prompt's
  budget. The full Flutter half is *also* a large PR: consent banner + settings +
  privacy article + DRAFT legal copy + build flag + `analyticsService` + auto
  observers + manual call sites + provider + rail + 2 integration flows + ~8
  goldens.
- The design doc (`§9`) estimated 4a at **~2 sessions**.

Per `§1.6` trigger #1 (backend §3 ≥ ~40% of budget) and the design doc's
pre-authorized split, the recommendation is to **ship 4a as the backend
pipeline (pipeline-only), fully green + tested + docs**, and carry the Flutter
consent UX + instrumentation + the (build-from-scratch) recently-viewed consumer
to **4b**. Surfaced to the user before §3.
