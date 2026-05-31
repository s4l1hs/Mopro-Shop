import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../_support/a11y_audit_harness.dart';
import 'screen_audit_support.dart';

/// §10 — strict regression guard. Each audited configuration must have ZERO
/// error-severity violations (missing semantic labels on tappables). Warning /
/// info violations are logged for future cleanup but do not fail the suite.
///
/// If a future PR adds an interactive widget without an accessible label, the
/// matching config's test fails with the offending widget named in the report.
/// Truly-deferred items go in `ignoreKeys` (bounded ≤5, documented in IGNORED.md).
void main() {
  setUpAll(installA11yMocks);

  for (final config in auditConfigs) {
    testWidgets('$config — zero a11y errors', (tester) async {
      await pumpAuditConfig(tester, config);
      final report = await A11yAuditHarness.audit(
        tester,
        find.byType(MaterialApp),
      );
      expect(
        report.errorsOnly,
        isEmpty,
        reason: 'a11y errors in $config:\n${report.toMarkdown()}',
      );
    });
  }
}
