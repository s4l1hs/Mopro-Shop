import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/design/widgets/mopro_share_button.dart';
import 'package:mopro/features/growth/share_service.dart';

import '../../_support/a11y_audit_harness.dart';
import '../../_support/test_harness.dart';

class _FakeShareService extends ShareService {
  _FakeShareService(this.outcome)
      : super(shareFn: (_, __) async {}, copyFn: (_) async {});

  final ShareOutcome outcome;
  String? lastText;
  String? lastSubject;

  @override
  Future<ShareOutcome> share({required String text, String? subject}) async {
    lastText = text;
    lastSubject = subject;
    return outcome;
  }
}

Future<void> _pump(WidgetTester tester, _FakeShareService fake) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [shareServiceProvider.overrideWithValue(fake)],
      child: MaterialApp(
        theme: buildLightTheme(),
        home: const Scaffold(
          body: MoproShareButton(
            url: 'https://mopro.shop/products/7',
            title: 'Süper Ürün',
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUpAll(initTestEnv);

  testWidgets('renders the share icon', (tester) async {
    await _pump(tester, _FakeShareService(ShareOutcome.shared));
    expect(find.byIcon(Icons.share_outlined), findsOneWidget);
  });

  testWidgets('tap invokes ShareService with "{title} — {url}"', (tester) async {
    final fake = _FakeShareService(ShareOutcome.shared);
    await _pump(tester, fake);
    await tester.tap(find.byType(MoproShareButton));
    await tester.pump();
    expect(fake.lastText, 'Süper Ürün — https://mopro.shop/products/7');
    expect(fake.lastSubject, 'Süper Ürün');
  });

  testWidgets('clipboard fallback outcome shows the copied snackbar',
      (tester) async {
    await _pump(tester, _FakeShareService(ShareOutcome.copiedToClipboard));
    await tester.tap(find.byType(MoproShareButton));
    await tester.pump(); // let the snackbar appear
    // Raw i18n key (translations not loaded in widget tests).
    expect(find.text('share.link_copied'), findsOneWidget);
  });

  testWidgets('shared outcome shows no snackbar', (tester) async {
    await _pump(tester, _FakeShareService(ShareOutcome.shared));
    await tester.tap(find.byType(MoproShareButton));
    await tester.pump();
    expect(find.text('share.link_copied'), findsNothing);
  });

  testWidgets('carries an accessible semantic label', (tester) async {
    await _pump(tester, _FakeShareService(ShareOutcome.shared));
    expect(find.bySemanticsLabel('share.share_a11y'), findsOneWidget);
  });

  testWidgets('a11y guard: zero error-severity violations', (tester) async {
    await _pump(tester, _FakeShareService(ShareOutcome.shared));
    final report =
        await A11yAuditHarness.audit(tester, find.byType(MoproShareButton));
    expect(
      report.errorsOnly,
      isEmpty,
      reason: report.toMarkdown(),
    );
  });
}
