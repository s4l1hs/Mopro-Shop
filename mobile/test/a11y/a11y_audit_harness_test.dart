import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../_support/a11y_audit_harness.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: Center(child: child))),
  );
}

void main() {
  testWidgets('icon-only button with no label → exactly one error', (tester) async {
    await _pump(
      tester,
      IconButton(onPressed: () {}, icon: const Icon(Icons.add)),
    );
    final report = await A11yAuditHarness.audit(
      tester,
      find.byType(MaterialApp),
      checks: const {A11yCheck.missingSemanticLabel},
    );
    expect(report.violations.length, 1);
    expect(report.violations.single.check, A11yCheck.missingSemanticLabel);
    expect(report.violations.single.severity, A11ySeverity.error);
    expect(report.isClean, isFalse);
  });

  testWidgets('labelled button → clean (zero errors)', (tester) async {
    await _pump(
      tester,
      IconButton(
        onPressed: () {},
        tooltip: 'Ekle',
        icon: const Icon(Icons.add),
      ),
    );
    final report =
        await A11yAuditHarness.audit(tester, find.byType(MaterialApp));
    expect(report.isClean, isTrue);
  });

  testWidgets('hit-target check flags a 32×32 tap surface', (tester) async {
    await _pump(
      tester,
      GestureDetector(
        onTap: () {},
        child: const SizedBox(width: 32, height: 32),
      ),
    );
    final report = await A11yAuditHarness.audit(
      tester,
      find.byType(MaterialApp),
      checks: const {A11yCheck.smallHitTarget},
    );
    expect(report.violations.length, 1);
    expect(report.violations.single.check, A11yCheck.smallHitTarget);
    expect(report.violations.single.severity, A11ySeverity.warning);
  });

  testWidgets('ignoreKeys suppresses matching widgets', (tester) async {
    const key = ValueKey('skip-me');
    await _pump(
      tester,
      InkWell(
        key: key,
        onTap: () {},
        child: const SizedBox(width: 24, height: 24),
      ),
    );
    final without =
        await A11yAuditHarness.audit(tester, find.byType(MaterialApp));
    expect(without.violations, isNotEmpty);

    final with_ = await A11yAuditHarness.audit(
      tester,
      find.byType(MaterialApp),
      ignoreKeys: {key.toString()},
    );
    expect(with_.violations, isEmpty);
  });

  testWidgets('toMarkdown produces a per-category table', (tester) async {
    await _pump(
      tester,
      IconButton(onPressed: () {}, icon: const Icon(Icons.add)),
    );
    final report = await A11yAuditHarness.audit(
      tester,
      find.byType(MaterialApp),
      checks: const {A11yCheck.missingSemanticLabel},
    );
    final md = report.toMarkdown();
    expect(md, contains('### missingSemanticLabel'));
    expect(md, contains('| Severity | Widget | Key | Bounds | Detail |'));
    expect(md, contains('error'));
  });
}
