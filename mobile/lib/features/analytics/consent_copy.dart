// User-facing consent + privacy copy for analytics surfaces.
//
// The actual strings live in the easy_localization files
// (assets/translations/*.json) under the `consent.*` namespace — per the
// project's all-strings-via-i18n rule. This file is the canonical index of
// those keys. Legal review of the consent + privacy copy completed in
// `chore/analytics-legal-copy-finalized`.

/// The `consent.*` localization keys backing the consent banner + privacy
/// settings + RTBF surfaces. (Index only — the text lives in the locale files;
/// the privacy article body lives in the `privacy-and-tracking` help article.)
const List<String> kConsentCopyKeys = <String>[
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
];
