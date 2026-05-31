// ignore_for_file: file_names — the DRAFT suffix is intentional so a repo
// search for "DRAFT" surfaces this legal-review-gated file (removed when legal
// finalizes the copy; see header below).

// PRIVACY COPY — REQUIRES LEGAL REVIEW BEFORE PRODUCTION LAUNCH.
//
// Drafted by engineering for Tranche 4b. Before this consent flow ships to
// real users:
//
//   1. KVKK (Turkey) compliance review of Turkish copy.
//   2. GDPR compliance review if any EU users.
//   3. Privacy policy update at /help category if needed.
//   4. Replace the DRAFT suffix on the file name + remove this header.
//
// Until reviewed, the consent banner is gated behind kAnalyticsConsentEnabled
// (default true in dev/staging, must flip to false for prod via
// --dart-define=ANALYTICS_CONSENT_ENABLED=false until legal approves).
//
// The user-facing strings themselves live in the easy_localization files
// (assets/translations/*.json) under the `consent.*` namespace — per the
// project's all-strings-via-i18n rule — so a search for "DRAFT" lands here and
// this file is the canonical index of which keys are pending legal sign-off.
// The privacy help article body (slug `privacy-and-tracking`, migration 0076)
// carries its own DRAFT notice and is part of the same review.

/// The `consent.*` localization keys that require legal review before the
/// production flip of `kAnalyticsConsentEnabled`. Listed here (not consumed) so
/// the legal-finalization PR has an authoritative checklist.
const List<String> kConsentCopyKeysPendingLegalReview = <String>[
  'consent.banner_headline',
  'consent.banner_body_1',
  'consent.banner_body_2',
  'consent.banner_body_3',
  'consent.accept',
  'consent.decline',
  'consent.more_info',
  'consent.setting_title',
  'consent.setting_desc',
  'consent.setting_on_help',
  'consent.setting_off_help',
  'consent.delete_all',
  'consent.delete_confirm_title',
  'consent.delete_confirm_body',
  'consent.read_policy',
  // Plus the help article body: slug `privacy-and-tracking` (migration 0076).
];
