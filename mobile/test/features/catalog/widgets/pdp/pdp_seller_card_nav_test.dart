import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/features/catalog/widgets/pdp/pdp_seller_card.dart';

import '../../../../_support/a11y_audit_harness.dart';
import '../../../../_support/test_harness.dart';

// Translations aren't loaded in widget tests (initTestEnv), so `.tr()` renders
// raw keys — assert on the key for the a11y semantic label.

GoRouter _router({required String? slug}) => GoRouter(
      initialLocation: '/pdp',
      routes: [
        GoRoute(
          path: '/pdp',
          builder: (context, _) => Scaffold(
            body: PdpSellerCard(
              sellerName: 'Acme Store',
              // Mirrors product_detail_screen's wiring: navigate only when the
              // slug resolved, else no link.
              onTap: (slug != null && slug.isNotEmpty)
                  ? () => context.push('/sellers/$slug')
                  : null,
            ),
          ),
        ),
        GoRoute(
          path: '/sellers/:slug',
          builder: (_, state) => Scaffold(
            body: Text('STOREFRONT ${state.pathParameters['slug']}'),
          ),
        ),
      ],
    );

Future<void> _pump(WidgetTester tester, {required String? slug}) async {
  await tester.pumpWidget(
    MaterialApp.router(
      theme: buildLightTheme(),
      routerConfig: _router(slug: slug),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(initTestEnv);

  testWidgets('tapping the store link routes to /sellers/:slug', (tester) async {
    await _pump(tester, slug: 'acme-store');
    expect(find.byType(TextButton), findsOneWidget);

    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();

    expect(find.text('STOREFRONT acme-store'), findsOneWidget);
  });

  testWidgets('null slug → no store link rendered', (tester) async {
    await _pump(tester, slug: null);
    expect(find.byType(TextButton), findsNothing);
    expect(find.text('Acme Store'), findsOneWidget); // name still shown
  });

  testWidgets('store link carries an accessible semantic label', (tester) async {
    await _pump(tester, slug: 'acme-store');
    // Raw key (translations not loaded in widget tests).
    expect(find.bySemanticsLabel('product.go_to_store_a11y'), findsOneWidget);
  });

  testWidgets('a11y guard: zero error-severity violations on the card',
      (tester) async {
    await _pump(tester, slug: 'acme-store');
    final report = await A11yAuditHarness.audit(
      tester,
      find.byType(PdpSellerCard),
    );
    expect(
      report.errorsOnly,
      isEmpty,
      reason: 'a11y errors on PdpSellerCard:\n${report.toMarkdown()}',
    );
  });
}
