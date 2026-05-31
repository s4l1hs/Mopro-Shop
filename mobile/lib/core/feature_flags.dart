/// Compile-time feature flags.
///
/// [kAnalyticsConsentEnabled] enables the analytics consent surface (banner +
/// settings) and the instrumentation layer (Tranche 4a/4b/4c).
///
/// Default `true` **everywhere** (dev, staging, prod) as of
/// `chore/analytics-legal-copy-finalized` — legal review of the consent +
/// privacy copy is complete, so production launch is unblocked. No env override
/// is needed for prod.
///
/// Retained as a runtime **kill-switch**: ops can pass
/// `--dart-define=ANALYTICS_CONSENT_ENABLED=false` for incident response (e.g. a
/// data-handling issue requiring an immediate tracking pause). Removing the flag
/// entirely is Backlog once the kill-switch is no longer needed.
///
/// When `false`: the consent banner does not render, the privacy settings row is
/// hidden, and `AnalyticsService.track()` no-ops (no queue, no network). The
/// privacy help article stays readable (it is just content).
const bool kAnalyticsConsentEnabled = bool.fromEnvironment(
  'ANALYTICS_CONSENT_ENABLED',
  defaultValue: true,
);
