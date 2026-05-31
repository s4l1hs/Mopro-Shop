# Tranche 4b — merge-blocker status

Continues `tranche4a_blockers.md`. 4b ships consent UX + instrumentation
(consent surface now user-visible behind the build flag); the recently-viewed
consumer + merge/RTBF closing flows are carried to 4c (§1.6 split, user-chosen).

## Blocker #1 — privacy copy + legal review — **IN PROGRESS**

The consent copy now ships (behind `kAnalyticsConsentEnabled`, dev-default-on):
- Banner + settings strings: `consent.*` keys (`assets/translations/*.json`);
  index of keys pending review in `lib/features/analytics/consent_copy_DRAFT.dart`.
- Privacy help article: slug `privacy-and-tracking` (migration `0076`), body
  carries a DRAFT notice.
- Build flag: `lib/core/feature_flags.dart` — production must set
  `--dart-define=ANALYTICS_CONSENT_ENABLED=false` until legal approves.

**Next step — focused follow-up PR `chore/analytics-legal-copy-finalized`:**
1. Remove the `DRAFT` suffix from `consent_copy_DRAFT.dart` (+ its header).
2. Remove the DRAFT notice line from the privacy article body (new migration).
3. Flip the prod default of `kAnalyticsConsentEnabled` (env override removed).
4. Apply any legal-requested copy edits.

Owner: product/legal. Tracked in REPORT.md "Pending legal review".

## Blockers #2 (raw search text) and #3 (account deletion) — **RESOLVED**

Resolved in 4a (`tranche4a_blockers.md`): raw search = Option A (normalized
intent only, stripped server-side); account deletion = synchronous `onUserDeleted`
cascade in the `DELETE /me` handler. No further action this turn.
