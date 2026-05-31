# Tranche 4a — merge-blocker status

The three merge-blockers from `TRANCHE_4_DESIGN.md` §11. 4a shipped as the
**backend pipeline** (§1.6 split — consent UX + instrumentation + recently-viewed
consumer carried to 4b).

## Blocker #1 — privacy copy + legal review

**Status: carried to 4b (no user-facing consent surface ships in 4a).**

The consent banner, settings UI, DRAFT privacy copy, privacy help article, and
the `kAnalyticsConsentEnabled` build flag are all part of the consent **UX**
(prompt §4/§5), which the §1.6 split moves to 4b. 4a ships no legal-review-gated
text.

Safety note: in 4a the pipeline is **dormant**. Consent defaults to *off*
server-side, there is no `PUT /me/consent` caller yet (the settings toggle is
4b), and there is no client instrumentation yet (also 4b). So no authed user can
opt in and no events are emitted by the app — the infrastructure exists and is
tested but collects nothing until 4b wires the consent UX + instrumentation. The
legal review remains a gate for **4b**, not 4a.

## Blocker #2 — raw-search-text stance

**Status: RESOLVED — Option A (normalized intent only).**

`search` events carry `{normalizedQuery, resultCount}` only. The service strips
raw-text keys (`query`/`rawQuery`/`q`/`text`) defensively before storage
(`stripRawSearchText`, unit-tested in `TestIngest_SearchRawTextStripped`), and
`NormalizeSearchQuery` defines the lowercase/strip/collapse/truncate-50 rule.
Backlog: raw search-text retention, if ever wanted, requires a user-level opt-in
toggle (recorded in REPORT §16).

## Blocker #3 — account-deletion wire-up

**Status: RESOLVED — synchronous cascade in the DELETE /me handler.**

Audit (§2.4) found `DELETE /me` is a **soft delete** (`identity.DeleteMe` →
`SoftDeleteWithRevoke`) that emits `ecom.user.soft_deleted.v1` only nominally —
no emit code actually exists, and a soft delete would never fire an
`ON DELETE CASCADE`. So an event-driven erasure consumer is not viable without
first building identity→outbox emit infra (out of 4a scope).

Resolution: the `DELETE /me` handler now runs an `onUserDeleted` hook
(`analyticsSvc.DeleteUserData`) after the soft-delete, erasing the user's rows
from `analytics_events`, `session_identity`, and `user_recently_viewed`
(best-effort; logged, never fails the deletion). Covered by
`TestIntegration_EraseUserData`. The `user_consent` row is intentionally left
(harmless orphan; the RTBF endpoint also leaves it so a user can re-opt-in).
Backlog: if identity ever emits a real `soft_deleted` event, the synchronous
hook can be replaced by a jobs-svc consumer.
