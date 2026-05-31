import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/core/feature_flags.dart';

void main() {
  test('kAnalyticsConsentEnabled defaults true (prod launch unblocked)', () {
    // Post legal-copy finalization the analytics consent surface is on by
    // default everywhere. The kill-switch path
    // (--dart-define=ANALYTICS_CONSENT_ENABLED=false) is compile-time and so is
    // exercised by a separate build configuration, not a runtime toggle here.
    expect(kAnalyticsConsentEnabled, isTrue);
  });
}
