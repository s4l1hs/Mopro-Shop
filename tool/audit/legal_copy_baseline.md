# Legal-copy DRAFT artifacts baseline (read-only)

Every DRAFT marker the analytics arc (PRs #27/#28/#29) shipped, to be retired by
`chore/analytics-legal-copy-finalized`. Date: 2026-05-31. Base: `main` @ #29 merged.

| Artifact | Location | What's DRAFT |
|---|---|---|
| Legal-review header | `mobile/lib/features/analytics/consent_copy_DRAFT.dart:5` | `// PRIVACY COPY — REQUIRES LEGAL REVIEW…` block + `ignore_for_file: file_names` (line 1) for the intentional DRAFT suffix. |
| Pending-keys index | same file:29 | `kConsentCopyKeysPendingLegalReview` — a *list of `consent.*` keys* pending sign-off (the file holds **no copy text itself**). **No importers** in `lib/` or `test/` (standalone index). |
| Consent copy strings | `mobile/assets/translations/{tr-TR,en-US,de-DE,ar-AE}.json` → `consent.*` | The actual banner/settings/RTBF strings (tr + en real; de/ar = en fallback). Live + used by `ConsentBanner` / `PrivacySettingsScreen`. |
| Privacy article body | `migrations/ecom/0076_privacy_article.up.sql:14,23` (slug `privacy-and-tracking`) | First body line is the DRAFT blockquote (`> ⚠️ Bu makale hukuki inceleme bekliyor…` / `…pending legal review…`). Rendered as plain markdown by `HelpArticleScreen` — **no conditional widget** gating it. Migration 0076 is **shipped/immutable** → editing the body needs a NEW migration (`0077`), not a 0076 edit (CLAUDE.md §10.6). |
| Build flag | `mobile/lib/core/feature_flags.dart:13` | `kAnalyticsConsentEnabled = bool.fromEnvironment('ANALYTICS_CONSENT_ENABLED', defaultValue: true)`. Doc comment (line 6) says "flip to false for prod via env override until legal approves." Default is already `true`. |
| Env overrides | — | **None found.** `grep ANALYTICS_CONSENT_ENABLED` across `deploy/`, `.github/`, `Makefile`, `mobile/` matches only `feature_flags.dart` + the DRAFT file's comment. The prod "flip to false" was documented guidance but **never wired** into any `.env`/CI/Dockerfile — so §6's override-removal is a no-op (only the doc comment changes). |
| REPORT pending-review | `REPORT.md` Tranche 4a/4b/4c sections ("Pending legal review") | To be marked closed pointing at this PR. |

## Implications for the plan
- File rename is import-safe (no importers).
- Article DRAFT line removal = new migration `0077` (UPDATE the body), not a 0076 edit.
- Flag: doc-comment update only; `defaultValue` stays `true`; no env override to remove.
- §3 `AskUserQuestion` decides whether the `consent.*` strings + article body change
  (Option A/C) or are accepted as-is (Option B). The mechanical retirement
  (rename, header/DRAFT-line removal, flag doc, REPORT closure) happens regardless.
