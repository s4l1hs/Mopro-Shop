/// Compile-time feature flags.
///
/// [kAnalyticsConsentEnabled] is the **launch gate** for the analytics consent
/// surface (banner + settings) and the instrumentation layer (Tranche 4a/4b).
/// It defaults to `true` for dev/staging so the flow is exercisable, and MUST be
/// flipped to `false` for production via `--dart-define=ANALYTICS_CONSENT_ENABLED=false`
/// until the privacy copy passes legal review (KVKK + GDPR — see
/// `TRANCHE_4_DESIGN.md` §11, blocker #1, and REPORT.md "Pending legal review").
///
/// When `false`: the consent banner does not render, the privacy settings row is
/// hidden, and `AnalyticsService.track()` no-ops (no queue, no network). The
/// privacy help article stays readable (it is just content).
const bool kAnalyticsConsentEnabled = bool.fromEnvironment(
  'ANALYTICS_CONSENT_ENABLED',
  defaultValue: true,
);
