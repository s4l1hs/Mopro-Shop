import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../_support/a11y_audit_harness.dart';
import 'screen_audit_support.dart';

/// §3 — measure-first baseline. Runs the audit across every configuration in
/// [auditConfigs] and writes a markdown report + prints a summary. It asserts
/// nothing; its only job is a recorded starting point. The strict guard lives in
/// screen_a11y_test.dart.
void main() {
  setUpAll(installA11yMocks);

  testWidgets('A11y baseline across screen configurations', (tester) async {
    final all = <String, A11yAuditReport>{};
    for (final config in auditConfigs) {
      await pumpAuditConfig(tester, config);
      all[config] = await A11yAuditHarness.audit(
        tester,
        find.byType(MaterialApp),
      );
    }

    final flat = all.values.expand((r) => r.violations).toList();
    int countSev(A11ySeverity s) =>
        flat.where((v) => v.severity == s).length;
    int countCheck(A11yCheck c) => flat.where((v) => v.check == c).length;

    final summary = StringBuffer()
      ..writeln('=== A11y Baseline Audit ===')
      ..writeln('Screens audited: ${auditConfigs.length}')
      ..writeln('Total violations: ${flat.length}')
      ..writeln('  Errors: ${countSev(A11ySeverity.error)}')
      ..writeln('  Warnings: ${countSev(A11ySeverity.warning)}')
      ..writeln('  Info: ${countSev(A11ySeverity.info)}')
      ..writeln()
      ..writeln('By category:');
    for (final c in A11yCheck.values) {
      summary.writeln('  ${c.name}: ${countCheck(c)}');
    }
    summary
      ..writeln()
      ..writeln('By config (errors):');
    for (final entry in all.entries) {
      summary.writeln('  ${entry.key}: ${entry.value.errorsOnly.length}');
    }

    // ignore: avoid_print
    print(summary);

    final md = StringBuffer()..writeln('# A11y Baseline Audit\n')
      ..writeln('```\n$summary```\n');
    for (final entry in all.entries) {
      md
        ..writeln('## ${entry.key}\n')
        ..writeln(entry.value.toMarkdown());
    }
    File('REPORT_BASELINE.md').writeAsStringSync(md.toString());
  });
}
