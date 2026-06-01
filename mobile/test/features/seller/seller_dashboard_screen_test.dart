import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mopro/design/theme.dart';
import 'package:mopro/features/seller/providers/seller_dashboard_provider.dart';
import 'package:mopro/features/seller/screens/seller_dashboard_screen.dart';
import 'package:mopro/features/seller/user_is_seller_provider.dart';
import 'package:mopro_api/mopro_api.dart';

import '../../_support/a11y_audit_harness.dart';
import '../../_support/test_harness.dart';

SellerBinding _binding() => SellerBinding(
      sellerId: 1,
      sellerSlug: 'acme-store',
      sellerName: 'Acme Store',
      role: SellerBindingRoleEnum.owner,
    );

String? lastRoute;

Future<void> _pump(WidgetTester tester, SellerDashboardSummary summary) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/seller/dashboard',
    routes: [
      GoRoute(
        path: '/seller/dashboard',
        builder: (_, __) => const SellerDashboardScreen(),
      ),
      GoRoute(
        path: '/seller/returns',
        builder: (_, state) {
          lastRoute = state.uri.toString();
          return const Scaffold();
        },
      ),
      GoRoute(
        path: '/seller/questions',
        builder: (_, state) {
          lastRoute = state.uri.toString();
          return const Scaffold();
        },
      ),
      GoRoute(path: '/sellers/:slug', builder: (_, __) => const Scaffold()),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentSellerBindingProvider.overrideWithValue(_binding()),
        sellerDashboardSummaryProvider.overrideWith((ref) async => summary),
      ],
      child: MaterialApp.router(theme: buildLightTheme(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(initTestEnv);
  tearDown(() => lastRoute = null);

  testWidgets('renders overview cards with counts', (tester) async {
    await _pump(
      tester,
      const SellerDashboardSummary(
        pendingReturns: 3,
        pendingReturnsHasMore: false,
        unansweredQuestions: 5,
      ),
    );
    expect(find.text('Acme Store'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('seller.card_pending_returns'), findsOneWidget);
    expect(find.text('seller.card_unanswered_questions'), findsOneWidget);
  });

  testWidgets('hasMore renders the "+" affordance', (tester) async {
    await _pump(
      tester,
      const SellerDashboardSummary(
        pendingReturns: 20,
        pendingReturnsHasMore: true,
        unansweredQuestions: 0,
      ),
    );
    expect(find.text('20+'), findsOneWidget);
  });

  testWidgets('empty (all clear) shows the all-done state, no cards',
      (tester) async {
    await _pump(
      tester,
      const SellerDashboardSummary(
        pendingReturns: 0,
        pendingReturnsHasMore: false,
        unansweredQuestions: 0,
      ),
    );
    expect(find.text('seller.all_done_title'), findsOneWidget);
    expect(find.text('seller.card_pending_returns'), findsNothing);
  });

  testWidgets('quick action routes to returns', (tester) async {
    await _pump(
      tester,
      const SellerDashboardSummary(
        pendingReturns: 1,
        pendingReturnsHasMore: false,
        unansweredQuestions: 1,
      ),
    );
    await tester.tap(find.text('seller.go_to_returns'));
    await tester.pumpAndSettle();
    expect(lastRoute, '/seller/returns');
  });

  testWidgets('a11y guard: zero errors', (tester) async {
    await _pump(
      tester,
      const SellerDashboardSummary(
        pendingReturns: 2,
        pendingReturnsHasMore: false,
        unansweredQuestions: 0,
      ),
    );
    final report = await A11yAuditHarness.audit(
      tester,
      find.byType(SellerDashboardScreen),
    );
    expect(report.errorsOnly, isEmpty, reason: report.toMarkdown());
  });
}
